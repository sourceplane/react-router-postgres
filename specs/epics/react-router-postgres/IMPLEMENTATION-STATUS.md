# react-router-postgres (RR) — Implementation status

As-built ≠ intent. This file records what actually shipped, and every place
the code departed from `design.md` or from the upstream template
([cloudflare/templates `react-router-postgres-ssr-template`](https://github.com/cloudflare/templates/tree/main/react-router-postgres-ssr-template),
at `7ae5750`, MIT).

| Milestone | State | PR |
|---|---|---|
| RR0 — the spec | ✅ Shipped | [#1](https://github.com/sourceplane/react-router-postgres/pull/1) (RR-1) |
| RR1 — the app on Workers | ✅ Shipped | [#2](https://github.com/sourceplane/react-router-postgres/pull/2) (RR-2) |
| RR2 — Supabase, Hyperdrive and the schema | ✅ Shipped (validated; apply gated on a linked workspace) | [#3](https://github.com/sourceplane/react-router-postgres/pull/3) (RR-3) |
| RR3 — ready to instantiate | ✅ Shipped | [#4](https://github.com/sourceplane/react-router-postgres/pull/4) (RR-4) |
| RR4 — a baseline | Planned | — |

## Departures from the upstream template

### Where it lives

Upstream's package is `apps/web` (`@app/web`) in the monorepo; its files are
copied as written, with upstream's `LICENSE` beside them
(`apps/web/LICENSE`). Upstream's `package-lock.json`, `docker-compose.yml`,
`tsconfig.cloudflare.json`, `tsconfig.node.json` and
`worker-configuration.d.ts` are not carried: pnpm locks the workspace, the
local database is the Supabase CLI's or any Postgres (`LOCAL_DATABASE_URL`),
one `tsconfig.json` extends the monorepo's, and `env.d.ts` declares the
three bindings.

### The wrangler config — two, rendered per environment

Upstream's `wrangler.jsonc` comments the Hyperdrive block out and names the
Worker, and the service it binds to, `react-router-postgres-ssr-template`.
Here `wrangler.template.jsonc` (the build's) and
`wrangler.deploy.template.jsonc` (the deploy's: `main:
./build/server/index.js`, `no_bundle`, `assets.directory: ./build/client`)
carry the Hyperdrive binding with its id a wiring token and the
`BOOKS_SERVICE` service `<reponame>-web-__ENV__`; both are committed as their
fixture render and re-rendered by the deploy's build command for its
environment (design §3). The Worker's `name` in both is
`<reponame>-web-__ENV__` too, rendered per environment — the name the
composition deploys it under (`<workerName>-<env>`, `workerName`
`<reponame>-web`) — so, as in upstream's config, the Worker and the service
it binds are one name, deployed and under `react-router dev` or `wrangler
dev`. Compatibility date, flags, Smart Placement, observability and source
maps are upstream's.

### `/api/health` and `BooksService.getHealth()`

New: a Hono route before the React Router handler, and an RPC method on
upstream's `BooksService` that reports whether the database behind the
binding is reachable, holds `books` and has row-level security on it — the
deploy's smoke and the docs phase's probes read it. `no-store`, 503 when it
is not `ok`. With no binding it reports `"source":"mock"` and 503: the mock
library is a development mode, not a healthy deploy.

### `SITE_NAME`

The library's heading (`routes/books.jsx`) and the page's `<title>` (new in
`root.jsx`, through React Router's `meta`) read `SITE_NAME` from
`app/lib/site.ts` — "My Library" here, rewritten to a product's name at
instantiation. Upstream's heading was the same text inline; it had no
`<title>`.

### `init.sql` → migrations

`010_books` is upstream's `CREATE TABLE` as written; `020_books_seed` its
nine INSERTs with `ON CONFLICT (id) DO NOTHING`, plus a `setval` that moves
the id sequence past them — upstream's explicit ids left it at 1, so the
first book added without an id would have collided with book 1 (risk RR-C);
`030_row_level_security` enables RLS on every table in `public`, guarded
(risk RR-D).

### Behaviour kept as upstream, recorded

- `/book/99` (no such book) answers 500, not 404: the loader throws a 404
  `Response` inside its own `try` and its `catch` re-throws a 500.
- A `POST /` answers 404: the Hono app routes only GETs to React Router, and
  the assets catch-all has no such file.
- The `postgres` client is opened per RPC call with upstream's options
  (`max: 5`, `fetch_types: false`) and closed with `ctx.waitUntil(sql.end())`.

### Lint

Upstream ships no lint config. `eslint.config.mjs` adds the monorepo's
TypeScript rules plus, for the JavaScript, `js.configs.recommended` and
React's `jsx-uses-vars` (components used only in JSX are not unused);
`no-unused-vars` ignores arguments and caught errors, which upstream's
handlers name and do not use. No upstream line changed for lint.

## Versions

| Package | Version | Why |
|---|---|---|
| react-router / @react-router/dev | 7.9.6 | upstream's pin |
| react / react-dom | 19.2.1 | upstream's pin |
| @cloudflare/vite-plugin | 1.52.1 | upstream's pin |
| hono / postgres | 4.11.1 / 3.4.7 | upstream's pins |
| tailwindcss / @tailwindcss/postcss | 4.1.17 | upstream's pin |
| wrangler | 4.136.1 | the deploy CLI the lanes run; compatibility_date 2025-10-08 as upstream |

## Verified (RR1–RR3)

- `pnpm install`, `pnpm run wire:fixture`, `pnpm typecheck`, `pnpm lint`,
  `pnpm test` (`tests/web` 22, `tests/db` 11) and `pnpm build` green.
- `wrangler deploy --dry-run --config wrangler.deploy.jsonc --name
  x-web-stage`: `env.HYPERDRIVE` and `env.BOOKS_SERVICE
  (x-web-stage#BooksService)`, 187 KiB gzipped.
- The README's local run from a fresh tree: `pnpm --filter @app/web
  db:migrate:local` into a local Postgres (twice: the second applies
  nothing), then `pnpm --filter @app/web preview` — the built Worker under
  `wrangler dev`, named by its config: the loaders read the nine books
  through the self-binding; `/api/health` 200.
- Fixed in RR3: RR1's configs named the Worker `<reponame>-web` while its
  binding named `<reponame>-web-stage`. Deployed that was harmless (the
  lanes pass `--name <reponame>-web-<env>`), but locally `wrangler dev`
  could not resolve the binding (`Worker "react-router-postgres-web-stage"
  not found`) and every loader failed; the configs now name the Worker per
  environment, as the deploy does.
- `terraform validate` green on `infra/terraform/supabase` and
  `infra/terraform/cloudflare-hyperdrive`.
- Not verified: a Terraform apply, a `db-migrate` apply against a real
  Supabase project and a live deploy — all need the product linked to an
  Orun workspace with Supabase and Cloudflare connections (risk RR-H).

