# The commands of the repository. Run them inside the devcontainer, which has
# every tool (Node, opam/dune, Terraform, tflint, AWS CLI).

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

TF := terraform -chdir=infra/terraform
# The tf-* targets read the deploy settings from infra/terraform/.env.local.
TF_ENV := source infra/terraform/.env.local &&
OPAM := opam exec --
PRISMA := npm --prefix db exec -- prisma

# One SQLite file, shared by Prisma (migrations) and the backend (queries).
export DB_PATH ?= $(CURDIR)/db/dev.db
export DATABASE_URL := file:$(DB_PATH)
# Dev-only token for /api/admin/dump; production sets its own.
export ADMIN_TOKEN ?= dev
# Where make db-dump downloads from.
APP_URL ?= http://localhost:8080

.DEFAULT_GOAL := help
.PHONY: help install dev dev-frontend dev-backend build check fmt clean db-migrate db-new db-reset db-studio db-dump tf-init tf-plan tf-apply tf-output

help:
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Setup
install: ## Install the frontend and backend dependencies
	npm --prefix frontend ci
	npm --prefix db ci
	$(OPAM) opam install ./backend --deps-only -y
	$(TF) init -backend=false -lockfile=readonly
	cd infra/terraform && tflint --init

##@ Run
dev: ## Run the backend and the frontend, until Ctrl-C
	$(MAKE) -j2 dev-backend dev-frontend

dev-frontend: ## Run the Vite dev server on :5173 (proxies /api to :8080)
	npm --prefix frontend run dev

dev-backend: db-migrate ## Run the backend on :8080, rebuilding on change
	cd backend && $(OPAM) dune exec --watch ./bin/main.exe

##@ Build and check
build: ## Build the frontend (frontend/dist) and the backend
	npm --prefix frontend run build
	cd backend && $(OPAM) dune build

check: ## Run every check: types, build, formatting, Terraform
	npm --prefix frontend run typecheck
	cd backend && $(OPAM) dune build @all @fmt
	cd backend && $(OPAM) dune test
	$(TF) fmt -check -recursive
	$(TF) validate
	cd infra/terraform && tflint

fmt: ## Format the backend and the Terraform
	cd backend && $(OPAM) dune fmt || true
	$(TF) fmt -recursive

clean: ## Remove build outputs
	rm -rf frontend/dist backend/_build

##@ Database (SQLite at $DB_PATH, default db/dev.db)
db-migrate: ## Apply the pending migrations (creates the database if needed)
	$(PRISMA) migrate deploy

db-new: ## Make a migration from schema.prisma changes: make db-new NAME=add_players
	$(PRISMA) migrate dev --name $(NAME)

db-reset: ## Drop the local database and apply every migration again
	$(PRISMA) migrate reset --force

db-studio: ## Browse and edit the data in Prisma Studio (:5555)
	$(PRISMA) studio --port 5555 --browser none

db-dump: ## Download a snapshot from APP_URL into local/dumps/ (set APP_URL, ADMIN_TOKEN)
	mkdir -p local/dumps
	cd local/dumps && curl -fsS -OJ -H "Authorization: Bearer $$ADMIN_TOKEN" "$(APP_URL)/api/admin/dump"
	@ls -lt local/dumps | head -2

##@ Infra (needs infra/terraform/.env.local, see .env.example)
tf-init: ## Point Terraform at the S3 state
	$(TF_ENV) $(TF) init -reconfigure \
	  -backend-config="bucket=$$TF_STATE_BUCKET" \
	  -backend-config="key=$$TF_STATE_KEY" \
	  -backend-config="region=$$TF_STATE_REGION" \
	  -backend-config="encrypt=true" \
	  -backend-config="use_lockfile=true"

tf-plan: ## Plan into infra/terraform/release.tfplan
	$(TF_ENV) $(TF) plan -out=release.tfplan

tf-apply: ## Apply infra/terraform/release.tfplan (read the plan first)
	$(TF_ENV) $(TF) apply release.tfplan

tf-output: ## Print the stack outputs (instance id, public IP)
	$(TF_ENV) $(TF) output
