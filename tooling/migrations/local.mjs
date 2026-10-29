#!/usr/bin/env node
// Applies packages/db's migrations, in manifest order, to a LOCAL Postgres —
// the database `react-router dev` and `wrangler dev` reach through the
// HYPERDRIVE binding's localConnectionString (the Supabase CLI's default
// database, `supabase start`). Deployed environments never run this: the
// db-migrate component applies the same files to stage and prod over the
// Supabase Management API, before the Worker deploys.
//
//   pnpm --filter @app/web db:migrate:local
//   LOCAL_DATABASE_URL=postgres://… pnpm --filter @app/web db:migrate:local
//
// Every migration is written idempotently, so running it again is a no-op.
// Needs psql on PATH.
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const db = resolve(dirname(fileURLToPath(import.meta.url)), "../../packages/db/src");
const paths = [...readFileSync(resolve(db, "manifest.ts"), "utf8").matchAll(/path:\s*"([^"]+)"/g)].map((m) => m[1]);
if (paths.length === 0) {
  console.error("migrations: packages/db/src/manifest.ts lists no migrations");
  process.exit(1);
}
const url = process.env.LOCAL_DATABASE_URL ?? "postgres://postgres:postgres@localhost:54322/postgres";
for (const rel of paths) {
  console.log(`migrations: ${rel} → ${url.replace(/:[^:@/]*@/, ":***@")}`);
  const r = spawnSync("psql", [url, "-X", "-q", "-v", "ON_ERROR_STOP=1", "-f", resolve(db, "migrations", rel)], {
    stdio: "inherit",
  });
  if (r.status !== 0) {
    console.error(`migrations: ${rel} failed${r.error ? ` (${r.error.message})` : ""}`);
    process.exit(r.status ?? 1);
  }
}
console.log(`migrations: ${paths.length} applied to the local Postgres`);
