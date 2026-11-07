# Migrations of the database

This folder holds the schema of the app's SQLite database and its migrations. The OCaml backend applies the migrations at start (`backend/migrate`). The Prisma CLI only writes and checks them: there is no Prisma client, and the production image has no Node and no Prisma.

| Path | What |
| --- | --- |
| `schema.prisma` | The source of truth of the schema. |
| `migrations/<name>/migration.sql` | One migration each, applied in name order. `prisma migrate dev` writes them. |
| `migrations/migration_lock.toml` | Prisma's record of the provider. |
| `prisma.config.ts` | The settings of the CLI: `DATABASE_URL`. |
| `package.json`, `package-lock.json` | The pinned Prisma CLI. |

## How the backend applies the migrations

At each start, in one `BEGIN IMMEDIATE` transaction, the backend applies each migration that the database lacks and records it in Prisma's own table `_prisma_migrations`. It uses the same columns, checksum (the SHA-256 of `migration.sql`) and timestamps (Unix milliseconds) as `prisma migrate deploy`. So `prisma migrate status` tells the truth about a database that the app migrated.

The start stops, before any change, when:

- the file of an applied migration changed (its checksum differs);
- the database has a migration that the backend does not have, such as after a rollback to an older build;
- `_prisma_migrations` holds a failed migration that nobody resolved.

Never edit a migration that a database has applied. Write a new one.

## Change the schema

From the root of the repository:

1. Change `schema.prisma`.
2. Write the migration: `make db-new NAME=<what_it_does>`. Prisma names its folder `<YYYYMMDDHHMMSS>_<what_it_does>`, and applies it to the local database.
3. Read the new `migration.sql`.
4. Write the queries that use the change in the backend, with ppx_rapper. Table and column names are the model and field names, such as `"Team"."wins"`.

## Check a database

`make db-status` lists the migrations that the local database has and lacks.
