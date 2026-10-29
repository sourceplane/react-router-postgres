# react-router-postgres

Cloudflare's [React Router + Postgres SSR template](https://github.com/cloudflare/templates/tree/main/react-router-postgres-ssr-template)
— a books library server-rendered by React Router v7, its page loaders
calling the Worker's own `BooksService` entrypoint over a service binding to
itself — on **Cloudflare Workers + Static Assets** through the Cloudflare
Vite plugin, with its Postgres a **Supabase** project's database reached
through **Cloudflare Hyperdrive**. Terraform provisions both per environment
and Orun's `db-migrate` applies the schema and the library's books, all on
every merge to `main`.

## Live deployment

<!-- 02-docs:begin -->
Not recorded yet. The bootstrap's last phase writes the live URLs, the
workspace, what the database check reports and the secrets the product
uses into
[ai/context/deployment.md](ai/context/deployment.md); how the product deploys
and how to operate it is in
[ai/context/operations.md](ai/context/operations.md).
<!-- 02-docs:end -->

## What is here

| Surface | Where |
|---|---|
| The product's name (the library's heading and the page's `<title>`) | `apps/web/app/lib/site.ts` |
| The routes, layout and components | `apps/web/app` |
| The Worker: the request handler, `/api/health`, the `BooksService` entrypoint and its `postgres` client per call over `env.HYPERDRIVE` | `apps/web/api` |
| The covers | `apps/web/public/images/books` |
| The build, and the two wrangler configs (what the Vite plugin builds from, and what deploys) | `apps/web/vite.config.js`, `wrangler.template.jsonc` → `wrangler.jsonc`, `wrangler.deploy.template.jsonc` → `wrangler.deploy.jsonc`, `component.yaml` |
| The schema, the books and row-level security, as migrations, and their runner | `packages/db` (`@saas/db`) |
| The Supabase project, the Hyperdrive config, the migration step | `infra/terraform/supabase`, `infra/terraform/cloudflare-hyperdrive`, `infra/db-migrate` |
| Tests | `tests/web`, `tests/db` (vitest) |

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # re-render both wrangler configs from their templates (they are committed)
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

**Deploy by hand.** Orunbase's **Deploy** button on a component, or **Run
workflow** on the CI workflow in GitHub's Actions tab (on `main`), runs
`ci.yml` for the environment and components you pick, and each one deploys
exactly as a merge would deploy it. Leave the component blank to redeploy
every component in that environment, with nothing changed: after rotating a
secret, say. A component with nothing to run in that environment (a test
suite in `prod`) is left out with a notice.

## Changing the library

The books are rows in the `books` table. To change the catalogue, write a
migration under `packages/db/src/migrations/` (list it in `src/manifest.ts`;
`pnpm --filter @saas/db run manifest:fix` writes its checksum), or edit the
rows in the Supabase dashboard's SQL editor. The covers are static assets in
`apps/web/public/images/books`; a book's `image_url` names its cover.
Hyperdrive caches plain reads for up to a minute, so a change can take that
long to show.

## Custom domain

The app answers on workers.dev from its first deploy. To serve it on your
own domain, attach the domain to the Worker in Cloudflare (Workers & Pages →
`react-router-postgres-web-prod` → Settings → Domains & Routes) and merge
nothing: the pages render no absolute link to themselves.

The repository names the domain in one place, `BASE_DOMAIN` under each
environment's `env:` in `intent.yaml`, which the product was born with as the
reserved placeholder `react-router-postgres.example.com`. Nothing builds a URL
from it; it records the domain. Replace it with yours when you attach one.

## CI

| Workflow | What it runs |
|---|---|
| `ci.yml` | the Orun pipeline, and the only workflow: `orun plan --changed`, then one job per lane. A pull request runs the verify lanes — the app built and dry-deployed for each environment, both Terraform roots checked and planned, the migrations planned and their checksums verified — with nothing applied or deployed. They do not typecheck, lint or run the tests: run `pnpm typecheck`, `pnpm lint` and `pnpm test` before you push (Getting started, above). A merge applies, migrates and deploys stage → prod |

## Credit

The app is Cloudflare's [`react-router-postgres-ssr-template`](https://github.com/cloudflare/templates/tree/main/react-router-postgres-ssr-template),
MIT-licensed; `apps/web/LICENSE` carries the licence.
