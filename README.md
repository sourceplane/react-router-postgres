# react-router-postgres

Cloudflare's [React Router + Postgres SSR template](https://github.com/cloudflare/templates/tree/main/react-router-postgres-ssr-template)
— a books library server-rendered by **React Router v7**, its page loaders
calling a **Hono** Worker's own `BooksService` entrypoint over a service
binding to itself, the books in Postgres reached through **Cloudflare
Hyperdrive** — running on **Cloudflare Workers + Static Assets** through the
[Cloudflare Vite plugin](https://developers.cloudflare.com/workers/vite-plugin/),
with the database a **Supabase Postgres** project, both provisioned by
Terraform through [Orun](https://github.com/sourceplane/orun) and the schema
and its books applied by Orun's `db-migrate`, and packaged as an **Orun
baseline**: one command takes a new product from nothing to live on stage and
prod, in its own repository, under its own name, in ONE landing.

The template's code is the code: its routes, components, styles, covers and
`BooksService` are as upstream wrote them, JavaScript included. What the port
changes is what an unattended deployment forces: the database is a Supabase
project per environment instead of a Neon one created by hand, its
`init.sql` — the table and the nine books — is three migrations applied
before the Worker deploys instead of a script pasted into an SQL editor, and
every table in `public` has row-level security, so Supabase's Data API serves
none of it. The self-binding stays: the Worker binds its own per-environment
name, rendered into its config per lane. Two additions: the product's name in
one place (`apps/web/app/lib/site.ts`, the library's heading and the page's
`<title>`), and `/api/health`, which the deploy's smoke and the bootstrap's
probes read. What the baseline adds is everything needed to make a copy of it
somebody else's. See [`specs/epics/react-router-postgres`](specs/epics/react-router-postgres/README.md)
for the design, the milestones and the as-built status, including every
departure.

## Instantiating a product

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/react-router-postgres
cd react-router-postgres
orun new --blueprint repo-blueprint.yaml --out ~/products/acme-books --run-hooks --resume \
  --set reponame=acme-books --set productname="Acme Books" \
  --set githuborg=acme-inc --set subdomain=<workers-dev-subdomain>
```

Or, once the platform's registry lists it, from the Orun console (Baselines →
`react-router-postgres` → Build). Two phases: **`01-product`** creates the
repository, mints the five brokered credentials (Cloudflare and Supabase) and
lands the whole product as one pull request, whose convergence on `main`
provisions and deploys it per environment in a fixed order —

```
supabase ──▶ cloudflare-hyperdrive ──▶ db-migrate ──▶ web
```

— each edge `mode: enforced` on a push to main and advisory on a pull
request; then **`02-docs`** records the live deployment from probed facts.
**[BOOTSTRAP.md](BOOTSTRAP.md)** is the operator guide;
[docs/phases/](docs/phases/README.md) has a page per phase. The Supabase
organization needs room for two projects (stage and prod) — the free plan's
limit.

The new repository receives the **product only** — the app, the Terraform
roots, the migrations, the tests, its CI, its tooling, a README of its own
and its operating contract — renamed throughout to the product's name,
repository, Worker, Supabase project and Hyperdrive config. None of this
repository's machinery ships. The card asks for no third-party key: the app
uses none.

| What makes it a baseline | Where |
|---|---|
| The console card (inputs, secrets, programme) | `blueprint.yaml` |
| The build document (modules, phases, hooks) | `repo-blueprint.yaml` |
| This tree's identity, the product's README and the bootstrap's task contracts | `.baseline/` |
| The rename engine (product-name seam: `apps/web/app/lib/site.ts`) | `tooling/rebrand/rebrand.mjs` |
| The bootstrap's helpers (deferrals, redeploy marker, work-tree strip) | `tooling/bootstrap/` |
| The deployment-record renderer | `hooks/render-deployment-docs.sh` |
| The product's context pack | `ai/context/` |
| The baseline's tests: contract, leak, offline bootstrap and plans, end to end | `testing/`, `.github/workflows/baseline.yml` |
| Cutting a `baseline-vN` tag | `.github/workflows/tag.yml` |

## What is here (the product)

| Surface | Where |
|---|---|
| The product's name (the library's heading and the page's `<title>`) | `apps/web/app/lib/site.ts` |
| The routes, layout and components (React Router v7, SSR) | `apps/web/app` |
| The Worker: Hono's request handler, `/api/health`, the `BooksService` entrypoint (a `postgres` client per call over `env.HYPERDRIVE`; the template's mock data when no database is bound) | `apps/web/api` |
| The covers | `apps/web/public/images/books` |
| The build and the two wrangler configs: what the Vite plugin builds from, and what deploys | `apps/web/vite.config.js`, `wrangler.template.jsonc` → `wrangler.jsonc`, `wrangler.deploy.template.jsonc` → `wrangler.deploy.jsonc` (both committed), `component.yaml` |
| The schema, the nine books and row-level security, as migrations, and Lumen's runner | `packages/db` (`@saas/db` — the name the db-migrate composition builds) |
| The Supabase project, the Hyperdrive config, the migration step | `infra/terraform/supabase`, `infra/terraform/cloudflare-hyperdrive`, `infra/db-migrate` |
| Tests | `tests/web`, `tests/db` (vitest; `tests/db` runs the migrations in PGlite) |

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # re-render both wrangler configs from their templates (committed; this changes nothing)
pnpm typecheck
pnpm lint
pnpm test
pnpm build              # react-router build → apps/web/build/{server,client}
```

The build needs no database. Running it locally — a Postgres on
`localhost:54322` (`supabase start`), `pnpm --filter @app/web db:migrate:local`,
then `react-router dev` or the built Worker under `wrangler dev` — is in the
product's README (`.baseline/product/README.md`), which is what a product
built from here carries.

## How it maps to Cloudflare's template

| The template | Here |
|---|---|
| One Worker (`api/index.js`) built by the Cloudflare Vite plugin, its assets beside it | The same Worker. The lanes deploy `wrangler.deploy.jsonc` — the built entry, no re-bundling, as the plugin's own `build/server/wrangler.json` says — because they check the config exists before they build |
| A Neon (or any) Postgres you create, a Hyperdrive config you create with `wrangler hyperdrive create`, its id pasted into `wrangler.jsonc` | `infra/terraform/supabase` (one project per environment) + `infra/terraform/cloudflare-hyperdrive` (one config per environment); the id reaches both wrangler configs per lane through `tooling/wire` |
| `init.sql` loaded by hand (the table and nine books) | `packages/db`'s migrations `010_books` and `020_books_seed` (`ON CONFLICT DO NOTHING`, the id sequence moved past the seeded ids), then `030_row_level_security`, applied by `infra/db-migrate` before the Worker deploys |
| The `BOOKS_SERVICE` service binding to the Worker's own name | The same self-binding, to `<repo>-web-<env>`: each environment's Worker calls its own entrypoint |
| Demo mode on mock data when no database is bound | Kept as upstream wrote it; a deployed product always binds its database, and `/api/health` reports mock data as unhealthy |
| Smart Placement, observability, source maps | Kept |
| No `<title>` | `meta()` in `app/root.jsx` names the product (the seam in `app/lib/site.ts`) |
| "Deploy to Cloudflare" (clone the template) | `orun new --blueprint repo-blueprint.yaml` — a new repository, branded, provisioned, migrated, deployed |

## CI

| Workflow | What it runs | Ships to a product |
|---|---|---|
| `ci.yml` | the Orun pipeline, and the only workflow a product carries: `orun plan --changed`, then one job per lane. A pull request runs the verify lanes (the app built and dry-deployed per environment, both Terraform roots checked and planned, the migrations planned), except the bootstrap's own landings (`orun/BASE-*`), where `plan` alone runs and nothing waits for it — the landing was checked in the build box; a merge applies, migrates and deploys stage → prod. The lanes do not typecheck, lint or run the tests: `baseline.yml`'s e2e tier does, on the landing, before each tag. It plans nothing while `intent.yaml` names the placeholder workspace `ws_CHANGE_ME`, as this repository does. A manual run (Orunbase's Deploy button, or Run workflow on `main`) plans the environment and components it names under the push-to-main trigger, so they deploy as a merge deploys them | yes |
| `baseline.yml` | the baseline's own tiers: contract tests; the blueprint read by the pinned orun, the leak gate, the offline bootstrap and the product's own plans; the product built, migrated into a local Postgres, dry-deployed and served — its self-binding resolving to itself — and its table shut to the Data API's roles | no |
| `tag.yml` | cuts a `baseline-vN` tag (manual) | no |

## Credit

The app is Cloudflare's [`react-router-postgres-ssr-template`](https://github.com/cloudflare/templates/tree/main/react-router-postgres-ssr-template),
MIT-licensed; `apps/web/LICENSE` carries the licence.
