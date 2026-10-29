# react-router-postgres — operating contract (for humans and agents)

This is the standing guide to how this product is deployed and operated.
Instance facts (live URLs, workspace, what the database check reports, the
secrets it uses) live in [deployment.md](deployment.md), rendered from
probed reality by the bootstrap's `02-docs` phase; this file is the contract
that stays true between deployments. It is written to give an agent with
repository read access enough context to reason about and operate the product
without any other source.

## What this system is

Cloudflare's React Router + Postgres SSR template — a books library
server-rendered by React Router v7, its page loaders calling the Worker's own
`BooksService` entrypoint over a service binding to itself — on Cloudflare
Workers, with its Postgres a Supabase project reached through Cloudflare
Hyperdrive, expressed as an Orun component-native desired-state repo. Seven
components:

- **`infra/terraform/supabase`** (`supabase`) — one Supabase project per
  environment. Its apply publishes `SUPABASE_PROJECT_REF`,
  `SUPABASE_DB_PASSWORD` and `SUPABASE_DB_URL` onto the environment's secret
  rung.
- **`infra/terraform/cloudflare-hyperdrive`** (`cloudflare-hyperdrive`) — one
  Hyperdrive config per environment over that database. Its apply publishes
  `WIRING_CLOUDFLARE_HYPERDRIVE` (the config's id and name).
- **`infra/db-migrate`** (`db-migrate`) — applies `packages/db`'s migrations
  to the environment's database through Supabase's Management API. Each
  migration is recorded with its checksum in `_migrations.applied`; only the
  missing ones apply.
- **`packages/db`** (`db`, the package `@saas/db` — the name the db-migrate
  composition builds) — the migrations and their runner.
- **`apps/web`** (`web`) — the app: React Router v7 and a Hono entry, built
  by the Cloudflare Vite plugin into one Worker plus Static Assets. Its
  loaders call `BooksService` through the `BOOKS_SERVICE` binding, which
  binds this same Worker (`<repo>-web-<env>`); the service reaches Postgres
  through the `HYPERDRIVE` binding, one client per call
  (`api/books-service.js`).
- **`tests/web`**, **`tests/db`** — vitest suites, verified on the `dev` rung.

Environments: **`stage`** and **`prod`** are deployed; **`dev` is
verify-only by design** — lanes build and test, nothing deploys.

## Identity and tenancy

Every remote operation runs against ONE Orun workspace, declared in
`intent.yaml` under `execution.state.workspace` — committed, enforced, and
what CI uses. Do not remove it; headless credentials depend on it. If it
reads `ws_SET_ME`, the bootstrap had no workspace to write: set the real one
before anything else.

## How deployment works

1. Merge (or push) to `main`.
2. CI (`.github/workflows/ci.yml`) runs `orun plan --changed` — only
   components whose files changed are planned — then runs each planned lane
   with `orun run --remote-state`, authenticated by GitHub OIDC (the
   exchange resolves this repository's linked workspace server-side).
3. Per environment, in this order — each edge `mode: enforced` on a push to
   main, advisory on a pull request (which deploys nothing):
   **`supabase` → `cloudflare-hyperdrive` → `db-migrate` → `web`.** A job
   resolves its secrets when it starts, so each one reads what the apply
   before it published. The app's deploy re-renders both wrangler configs
   (`apps/web/wrangler.jsonc`, what the Vite plugin builds from, and
   `wrangler.deploy.jsonc`, what deploys) from `WIRING_CLOUDFLARE_HYPERDRIVE`
   before it builds, deploys `react-router-postgres-web-<env>`, and
   smoke-tests it: the library renders to its end, and `/api/health` —
   asked through the self-binding — answers 200 only when the database is
   reachable through Hyperdrive and migrated.
4. `prod` deploys after `stage` has converged on the same commit
   (`environments.prod.promotion` in intent.yaml).
5. **The convergence run is the deployment.** A green run means every
   planned lane applied. Failed lanes are retried with
   `gh run rerun --failed`, which resumes the same execution.

Caveats that matter:

- A push that touches no component files plans zero lanes — that run is
  green and deployed nothing. Never treat "latest run green" as "product
  converged"; probe the URLs instead.
- Both wrangler configs are committed as the renders of their templates
  (`wrangler.template.jsonc`, `wrangler.deploy.template.jsonc`) from
  `wiring.fixture.json` (placeholder Hyperdrive ids): edit the templates —
  together; tests/web fails when they disagree — and run `pnpm run
  wire:fixture`. The deploy lanes render the real ones in their own job
  tree; never commit a real id.
- **The self-binding names the Worker's own per-environment name.** Both
  templates write `"name"` and `"service"` as
  `"react-router-postgres-web-__ENV__"`, and the render fills in the
  environment; the lanes deploy the same name (`<workerName>-<env>`).
  Rename the Worker and the service must follow, or every page's loader —
  and `/api/health` — calls nothing, deployed and under `wrangler dev`
  alike.
- **The schema and the books are the migrations'.** db-migrate creates
  `books` and writes the template's nine books (`ON CONFLICT (id) DO
  NOTHING`, the id sequence moved past them) before the Worker deploys. If
  the table is missing, `/api/health` answers 503 `schema: missing`.
- **Hyperdrive caches reads** for up to a minute (60 s, plus 15 s stale while
  it revalidates) and does not invalidate them on a write, so the library can
  show rows up to that old after you change them. `/api/health` is never
  cached (`to_regclass` is STABLE, and Hyperdrive caches only IMMUTABLE
  reads).
- Every table in `public` has row-level security and no policy. Supabase's
  Data API serves `public` to the anon key, so this is what keeps the table
  out of it; the app is unaffected because it connects as `postgres`, the
  table's owner. Enable RLS on a new table in the migration that creates it;
  never `FORCE` it, and never add a policy for `anon` without meaning to
  publish that table.
- A migration is immutable once applied: its checksum is in
  `packages/db/src/manifest.ts` and in the database's ledger. Change the
  schema with a NEW migration in `packages/db/src/migrations`.

## Secrets model

- **Brokered provider secrets**, minted per run from the workspace's
  connections — no long-lived values at rest, nothing to rotate by hand:
  `CLOUDFLARE_API_TOKEN` (Workers deploy), `CLOUDFLARE_HYPERDRIVE_TOKEN`
  (Hyperdrive — the deploy token deliberately cannot touch it),
  `CLOUDFLARE_ACCOUNT_ID`, `SUPABASE_ACCESS_TOKEN` (project create and
  migrations) and `SUPABASE_ORG_ID`.
- **Published by the applies** onto the stage and prod rungs:
  `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `SUPABASE_DB_URL`,
  `WIRING_CLOUDFLARE_HYPERDRIVE`.
- **No Worker secrets.** The app talks to Postgres through its binding and
  to no third party, so there is nothing for an owner to add.
- Inspect by NAME only: `orun secrets list --org <ws> --project` and
  `--env stage|prod`. No tooling in this repository prints a secret value,
  and no document in `ai/context/` may contain one.

## Verifying the system

```bash
# the library and its database path on each environment (also recorded, probed, in deployment.md)
curl -s -o /dev/null -w '%{http_code}\n' https://react-router-postgres-web-stage.your-workers-subdomain.workers.dev/
curl -s https://react-router-postgres-web-prod.your-workers-subdomain.workers.dev/api/health

# workspace readiness (integrations + repository link)
orun integrations list --org <ws> --json && orun cloud check --org <ws>
```

## Common operations

| task | how |
|---|---|
| deploy a change | merge to `main`; watch the run; failed lanes → `gh run rerun --failed` |
| deploy by hand | Orunbase's Deploy button, or `gh workflow run ci.yml --ref main -f environment=<env> [-f component=<a,b>]` — the named components (blank: every one) run in that environment as a merge runs them; started off `main` it is refused |
| change the schema or the books | a new `packages/db/src/migrations/<nnn>_<name>/up.sql` and its manifest entry (`pnpm --filter @saas/db run manifest:fix` for its checksum), merge — db-migrate applies it before the app deploys. `pnpm test` fails on a table in `public` without row-level security. Edits in the Supabase SQL editor work too, and are not recorded anywhere |
| try it locally | `supabase start`, `pnpm --filter @app/web db:migrate:local`, then `pnpm --filter @app/web dev` (or `pnpm build` and `pnpm --filter @app/web preview`) |
| redeploy without a change | edit the last line of the component's `component.yaml` (`# orun: redeploy <reason> <stamp>`) and merge — it is a deploy trigger, nothing reads it |
| serve a custom domain | attach it to the Worker in Cloudflare (README, "Custom domain"); replace the placeholder `react-router-postgres.example.com` in `intent.yaml`'s `BASE_DOMAIN` with it (a record; nothing builds a URL from it) |
| headless credentials | `ORUN_TOKEN` (workspace-scoped) + `GITHUB_TOKEN` |

The deployment record is the bootstrap's `02-docs` phase. Re-running it (the
Orun console's Retry on that phase, or `orun new … --phase 02-docs`)
re-probes the URLs and re-renders [deployment.md](deployment.md); it is
idempotent.

## Evolution

Structural changes (a second Worker, a queue, another data store) follow the
same contract that deployed the product: add a component under `apps/`,
`infra/` or `packages/` with a `component.yaml` — declaring `dependsOn` on
any infrastructure whose published secrets it reads, enforced on main — land
it as a pull request, and the convergence run applies it.
