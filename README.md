# UTMUN 2027 NBA Simulation

The NBA Simulation for the UTMUN 2027 NBA Committee. It handles the simulation logic of the committee's teams: their rosters, their drafts, their games, and the standings.

## Layout

| Folder | What it is |
|---|---|
| `frontend/` | The web app: React, TypeScript, Tailwind (Vite). |
| `backend/` | The OCaml server (Dream). `lib/sim.ml` holds the simulation logic. |
| `db/` | The SQLite schema and migrations (Prisma). |
| `infra/terraform/` | AWS: one small EC2, and an S3 bucket of database snapshots. |

## Getting started

Open the repository in its devcontainer (`.devcontainer/`), which has every tool. Then:

```sh
make help   # list the commands
make dev    # backend on :8080, frontend on :5173
```

After each session, `make db-dump` downloads a snapshot of the database into `local/dumps/`.
