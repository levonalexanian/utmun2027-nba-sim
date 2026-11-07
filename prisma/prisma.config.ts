// The settings of the Prisma CLI (README.md). DATABASE_URL names the SQLite
// file (file:<path>); the Makefile sets it.
import { defineConfig } from "prisma/config";

export default defineConfig({
  schema: "schema.prisma",
  migrations: { path: "migrations" },
  datasource: {
    url: process.env.DATABASE_URL ?? "",
  },
});
