# react-router-postgres

Cloudflare's [React Router + Postgres SSR template](https://github.com/cloudflare/templates/tree/main/react-router-postgres-ssr-template)
— a books library server-rendered by **React Router v7**, its page loaders
calling a **Hono** Worker's own `BooksService` entrypoint over a service
binding to itself, the books in Postgres reached through **Cloudflare
Hyperdrive** — running on **Cloudflare Workers + Static Assets** through the
[Cloudflare Vite plugin](https://developers.cloudflare.com/workers/vite-plugin/),
with the database a **Supabase Postgres** project, both provisioned by
Terraform through [Orun](https://github.com/sourceplane/orun) and the schema
and its books applied by Orun's `db-migrate` — and, at its last milestone
(RR4), packaged as an **Orun baseline**: one command taking a new product
from nothing to live on stage and prod, in its own repository, under its own
name, in ONE landing.

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
probes read. See [`specs/epics/react-router-postgres`](specs/epics/react-router-postgres/README.md)
for the design, the milestones and the as-built status, including every
departure.

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

The build needs no database: the pages render per request.

## Running it locally

You need a Postgres on `localhost:54322` — the Supabase CLI's default
(`supabase start`) — or any Postgres whose URL you put in
`LOCAL_DATABASE_URL`, and `psql` on your PATH.

1. **Schema and books.** Apply `packages/db`'s migrations — the same files CI
   applies to the real databases:

   ```bash
   pnpm --filter @app/web db:migrate:local
   ```

2. **Run.** Either React Router's dev server, which runs the Worker in
   workerd through the Cloudflare Vite plugin (the `HYPERDRIVE` binding
   points at `localhost:54322` through `wrangler.jsonc`'s
   `localConnectionString`):

   ```bash
   pnpm --filter @app/web dev          # http://localhost:5173
   ```

   or the built Worker under `wrangler dev`, as it deploys:

   ```bash
   pnpm build
   pnpm --filter @app/web preview      # http://localhost:8787
   ```

   For a database elsewhere, `CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_HYPERDRIVE=<url>`
   overrides the local connection string. With no database at all the pages
   render the template's demo data; `/api/health` says whether the database
   is reachable and migrated.

## How it deploys

Merges to `main` converge through [Orun](https://github.com/sourceplane/orun):
`.github/workflows/ci.yml` plans the changed components and runs each lane
against the workspace in `intent.yaml`. Per environment the order is
enforced — **the Supabase project, then the Hyperdrive config over its
database, then the migrations, then the Worker** — because each reads what
the one before it published: the project's ref and password, the Hyperdrive
id the Worker binds, the table the pages query. `stage` deploys first and
`prod` once stage has converged on the same commit; `dev` only verifies.
Every deploy is smoke-tested over HTTP: the library renders, and
`/api/health` answers only when the Worker reaches a migrated database —
through its `BOOKS_SERVICE` binding to itself, as the pages do.

The pipeline holds one credential, GitHub's own `GITHUB_TOKEN`. The
Cloudflare tokens and account id and the Supabase access token and org id
are brokered per run from the workspace's connections; the Supabase
project's credentials and the Hyperdrive id are published by the Terraform
applies as orun secrets. Nothing provider-shaped is stored in the repository
or in GitHub, and the app needs no secret of its own.

Every table in `public` has row-level security and no policy, so Supabase's
Data API (which serves `public` to the project's anon key) returns none of
it; the app connects as the table's owner and is not affected.

**Deploy by hand.** **Run workflow** on the CI workflow in GitHub's Actions tab (on `main`), runs
`ci.yml` for the environment and components you pick, and each one deploys
exactly as a merge would deploy it. Leave the component blank to redeploy
every component in that environment, with nothing changed: after rotating a
secret, say. A component with nothing to run in that environment (a test
suite in `prod`) is left out with a notice.

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

## CI

`.github/workflows/ci.yml` is the Orun pipeline: `orun plan --changed`, then
one job per lane. A pull request runs the verify lanes (the app built and
dry-deployed per environment, both Terraform roots checked and planned, the
migrations planned); a merge applies, migrates and deploys stage → prod. It
plans nothing while `intent.yaml` names the placeholder workspace
`ws_CHANGE_ME`, as this repository does until it is linked. The baseline's
own test tiers arrive with RR4.

## Credit

The app is Cloudflare's [`react-router-postgres-ssr-template`](https://github.com/cloudflare/templates/tree/main/react-router-postgres-ssr-template),
MIT-licensed; `apps/web/LICENSE` carries the licence.
