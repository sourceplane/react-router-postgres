# react-router-postgres — implementation plan

## RR0 — the spec (RR-1)

**Done when**
- the five documents and `epic.yaml` are on `main`, with `tasks/RR-1..RR-5.TaskContract.yaml`
- the repository's intent (`intent.yaml`, workspace `ws_CHANGE_ME` until it is linked), `ci.yml` (the plan job a green no-op until then), the workspace files and the shared tooling (`tooling/{eslint,tsconfig,wire,migrations}`) are on `main`

## RR1 — the app on Workers (RR-2)

**Done when**
- `apps/web` is upstream's files as written, plus `/api/health`, `SITE_NAME` and the two wrangler templates with their committed fixture renders
- `pnpm install && pnpm run wire:fixture && pnpm typecheck && pnpm lint && pnpm test && pnpm build` is green locally
- `wrangler deploy --dry-run --config wrangler.deploy.jsonc --name <reponame>-web-stage` lists `env.HYPERDRIVE` and `env.BOOKS_SERVICE (<reponame>-web-stage#BooksService)`
- `wrangler dev` with no database serves the mock library and its banner; with a local Postgres holding `init.sql`, the loaders read it through the self-binding

## RR2 — Supabase, Hyperdrive and the schema (RR-3)

**Done when**
- `terraform validate` passes on both roots, and `hyperdrive_id` is the key the templates' token names
- `packages/db` carries `010_books`, `020_books_seed` and `030_row_level_security` with their manifest checksums; `tests/db` holds the manifest, the seed (nine books, the next id 10) and row-level security on every table in `public`
- `infra/db-migrate` reads the project's three credentials and declares its edges on `supabase` and `cloudflare-hyperdrive`; `web` declares its edges on `cloudflare-hyperdrive` and `db-migrate`

## RR3 — ready to instantiate (RR-4)

**Done when**
- the README quick start works from a fresh clone: install, the local Postgres (`pnpm --filter @app/web run db:migrate:local`), dev, test, preview, deploy by hand
- the status file lists every PR and every departure from upstream

## RR4 — a baseline (RR-5)

The repository becomes an Orun baseline on the Lumen conventions, held to
the starter standard and built the way turso-starter builds a product — in
ONE landing:

- `blueprint.yaml` (the card: `requires [github, cloudflare, supabase]`, the
  five brokered secrets as a preview, the programme `01-product`, `02-docs`)
  and `repo-blueprint.yaml` (every module placed by `01-product` and landed as
  one pull request; `02-docs` hook-only);
- the components' edges `mode: enforced` on a push to main, advisory on a
  pull request, so one convergence runs supabase → cloudflare-hyperdrive →
  db-migrate → web per environment;
- `.baseline/`, the rename engine (`SITE_NAME`, the worker and service
  names, upstream's credit protected), the bootstrap helpers, the deployment
  record, `ai/context/`, the generated component docs, `testing/` and the
  `baseline.yml` / `tag.yml` lanes.

**Done when**
- orun reads the build document at the bootstrap floor and the lane pin, the
  card agrees with it, and `orun catalog validate` reports no errors
- the product's own `orun plan --trigger github-push-main` shows the order,
  enforced; a pull request's plan holds the same edges advisory
- the e2e tier migrates a local Postgres with the product's own runner
  (and re-applies nothing), builds in the job tree orun stages, dry-deploys
  both bindings, serves the built Worker under its own deployed name over
  that database — eight concurrent first requests, each loader reading the
  books through the self-binding — passes the deploy's own smoke, and shows
  the Data API's roles reading none of it
- tagged `baseline-v1` through `tag.yml`

## Sequencing note

RR1's component already names the Hyperdrive root's wiring secret and the
migrations lane; RR2 makes the names true. Applying RR2 needs a workspace
with Supabase and Cloudflare connections (the Hyperdrive token scope) and
room for two Supabase projects (risk RR-E).
