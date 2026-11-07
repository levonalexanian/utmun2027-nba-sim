import { defineConfig, env } from "prisma/config";

// The Makefile sets DATABASE_URL (file:<absolute path>) so Prisma and the
// OCaml backend always point at the same SQLite file.
export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: { path: "prisma/migrations" },
  datasource: { url: env("DATABASE_URL") },
});
