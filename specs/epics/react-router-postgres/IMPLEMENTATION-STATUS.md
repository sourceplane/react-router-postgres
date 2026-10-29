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
| RR4 — a baseline | ✅ Shipped (offline-proven; no live bootstrap yet, risk RR-H) | [#5](https://github.com/sourceplane/react-router-postgres/pull/5) (RR-5), tagged `baseline-v1` |

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

## RR4 — a baseline (RR-5)

The repository is an Orun baseline on the Lumen conventions, held to the
starter standard and built the way turso-starter builds a product: ONE
landing. `blueprint.yaml` is the card (`requires: [github, cloudflare,
supabase]`; the five brokered keys — `CLOUDFLARE_API_TOKEN`,
`CLOUDFLARE_HYPERDRIVE_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`,
`SUPABASE_ACCESS_TOKEN`, `SUPABASE_ORG_ID` — as a preview; the programme
`01-product`, `02-docs`; `expectedMinutes` 18, the two phase cards' 17 + 1).
`repo-blueprint.yaml` places every module in `01-product` and lands it as one
pull request; `02-docs` records the deployment from probed facts and puts
the bootstrap's deferrals back.

- **The rename engine** (`tooling/rebrand/rebrand.mjs`, Cirrus's engine,
  this tree's rules): the repository slug, `SITE_NAME`, the Worker and the
  self-binding's service, the Supabase project and the Hyperdrive config,
  the domain placeholder and the workers.dev subdomain. Upstream's own
  identity — its directory in cloudflare/templates, its name, its Deploy to
  Cloudflare link — is protected: the banner and the app's README say where
  the code came from. The epic slug a bootstrap files its task under is
  `library-baselining`, which does not contain the repository slug, so the
  engine's word-bounded rule never rewrites it.
- **The edges.** `cloudflare-hyperdrive` on `supabase`; `db-migrate` on
  both; `web` on `cloudflare-hyperdrive` and `db-migrate` — `mode: enforced`
  on a push to main, advisory on a pull request.
- **The component docs** are generated (`tooling/catalog/gen-component-docs.py`)
  and checked in Baseline CI.

### Verified (RR4)

- Contract tests: manifest, phases, coverage, rebrand, retouch,
  bootstrap-defer; the component docs match their manifests; `orun catalog
  validate` reports no errors.
- The blueprint read by the bootstrap floor (`orun new --status`); the leak
  gate (137 files derived, nothing local, built or provenance-shaped); the
  offline bootstrap with the blueprint's own hooks, then the product's own
  plan for the 01-product merge — supabase → cloudflare-hyperdrive →
  db-migrate → web on stage and prod, enforced; advisory on a pull request —
  and a `--resume` that changes nothing.
- The end-to-end tier: the product installed, type-checked, linted, tested
  and built; the migrations applied by the product's own runner to a local
  Postgres with Supabase's roles, and a re-apply applying nothing; the stage
  web lane's own steps in the job tree orun stages, its dry deploy binding
  the stage Hyperdrive id and `BOOKS_SERVICE (<repo>-web-stage#BooksService)`;
  the built Worker served by `wrangler dev` under that name over the
  database — eight concurrent first requests each rendering the nine books
  through the self-binding, the component's own smoke, every route, a book
  added behind the app's back taking id 10 — and the Data API's roles
  reading none of it.
- Not verified: everything risk RR-H names.
