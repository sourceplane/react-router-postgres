# react-router-postgres — design

## 1. What the template is

One Worker. `api/index.js` is a Hono app: every GET goes to React Router's
request handler (`virtual:react-router/server-build`, SSR), anything else to
the static assets. The routes (`app/routes.js`) are a layout and three pages
— the library (`/`), a book (`/book/:bookId`) and a genre
(`/genre/:genreId`) — and their loaders read the books through
`context.cloudflare.env.BOOKS_SERVICE`, a **service binding from the Worker
to itself**: `api/books-service.js` exports `BooksService`, a
`WorkerEntrypoint` whose RPC methods (`getBooks`, `getBook`,
`getRelatedBooks`) open a `postgres` client over `env.HYPERDRIVE` per call
and close it with `ctx.waitUntil(sql.end())`. With no `HYPERDRIVE` binding
the service answers from `api/lib/mockData.js` and the page shows a banner
saying so. The schema and nine sample books are `init.sql`, applied by hand
(or by the template's docker compose); the database upstream suggests is
Neon. The Cloudflare Vite plugin builds it (`vite.config.js`).

## 2. The mapping (upstream → here)

| Upstream | Here |
|---|---|
| One package at the repository root | `apps/web` (`@app/web`) inside the Lumen monorepo (pnpm, turbo), the template's files as written |
| `wrangler.jsonc` with the Hyperdrive block commented out and `service` = the template's own name | `wrangler.template.jsonc` with the binding's id a wiring token, `@@wiring(cloudflare-hyperdrive/__ENV__:hyperdrive_id)@@`, and `service` = `<reponame>-web-__ENV__`; rendered per environment (§3) |
| Neon, created in its dashboard | `infra/terraform/supabase` (one project per environment; ref, password and DB URL as secrets — Lumen's three) + `infra/terraform/cloudflare-hyperdrive` (the config fronting it; wiring `{hyperdrive_id, hyperdrive_name}`) — §4 |
| `init.sql`, applied by hand | `packages/db/src/migrations`: `010_books` (the table as written), `020_books_seed` (the nine books, `ON CONFLICT (id) DO NOTHING`, then the id sequence moved past them), `030_row_level_security` — applied by `infra/db-migrate` per environment, after the project and the Hyperdrive config exist and before the Worker deploys |
| No health check | `GET /api/health` → `BooksService.getHealth()`: 200 `{"ok":true,"source":"database",…}` only when the database behind the binding is reachable, the `books` table exists and has row-level security on; 503 otherwise, and `"source":"mock"` when there is no binding. The deploy's smoke and the docs phase's probes read it |
| The library's heading and `<title>` | `SITE_NAME` in `app/lib/site.ts`, one literal line the rename engine rewrites to the product's name |
| `npm run deploy` | Orun: `apps/web/component.yaml` renders both configs for `$ORUN_ENVIRONMENT`, builds, and deploys `<reponame>-web-{stage,prod}` on merge to `main` once the product is linked, after `cloudflare-hyperdrive` and `db-migrate` (enforced on main) |
| `tsconfig.cloudflare.json`, `tsconfig.node.json`, `worker-configuration.d.ts` | one `tsconfig.json` on the monorepo's base with `allowJs` and `checkJs: false` (the JavaScript is not type-checked; risk RR-B), `env.d.ts` for the bindings |

**The JavaScript stays JavaScript.** Upstream is `.js` and `.jsx` with JSDoc
hints it does not hold itself to: under `checkJs` it reports 242 errors.
Converting it to TypeScript, or annotating it until it passes, would rewrite
every file a reader compares with upstream. `pnpm typecheck` runs React
Router's typegen and `tsc` over the TypeScript this repository adds; the
JavaScript is linted (`eslint` with React's `jsx-uses-vars`), and its
behaviour is held by `tests/web` and the end-to-end tier.

## 3. The bindings and the two configs

```
request ──► Worker (<reponame>-web-<env>) ──► Hono ──► React Router loader
                                                         │ context.cloudflare.env.BOOKS_SERVICE
                                                         ▼
                      service binding to ITSELF ──► BooksService (WorkerEntrypoint, RPC)
                                                         │ postgres(env.HYPERDRIVE.connectionString) per call
                                                         ▼
                                       Hyperdrive (pooled) ──► Supabase Postgres
                                       no HYPERDRIVE ──► mock data + banner
before the first deploy: db-migrate → books, the nine books, row-level security
```

**The self-binding is kept.** A service binding names a Worker by its
deployed name, and the composition deploys `wrangler deploy --name
<workerName>-<env>`, so `BOOKS_SERVICE` must name `<reponame>-web-<env>`:
the template writes `<reponame>-web-__ENV__`, and the renderer replaces
`__ENV__` with the environment. The configs' own `name` is the same
`<reponame>-web-__ENV__`: the deploy passes that name anyway, and `wrangler
dev` and `react-router dev` resolve a service binding only to a Worker of
exactly the binding's name, so locally the Worker is the one it binds — as
upstream's config, whose `name` and `service` are one string, has it. On a Worker's very first deploy the binding
names a Worker that does not exist until that deploy finishes. Upstream's
own Deploy to Cloudflare button makes exactly that first deploy, with the
binding naming the Worker being created; here it is proven by `wrangler
deploy --dry-run`, not yet by a live first deploy (risk RR-A). The
end-to-end tier serves the built Worker under exactly that name and checks
that the loaders read the database through the binding.

**Two configs, both rendered, both committed.** The Cloudflare Vite plugin
builds from `wrangler.jsonc` (`main: ./api/index.js`, the source) and writes
`build/server/index.js` and `build/client`. The composition checks that the
component's `wranglerConfig` exists BEFORE the build, in a fresh checkout,
then deploys it with `wrangler deploy --config`. So the deploy reads a second
config, `wrangler.deploy.jsonc` — the same bindings, `main:
./build/server/index.js`, `no_bundle`, the assets directory `./build/client`
— as astro-boilerplate does. Both come from templates
(`wrangler.template.jsonc`, `wrangler.deploy.template.jsonc`), are committed
as the fixture render (`pnpm run wire:fixture`, from `wiring.fixture.json`),
and are re-rendered by the deploy's build command from this environment's
`WIRING_CLOUDFLARE_HYPERDRIVE_<ENV>` before the build. `tests/web` fails if
the two disagree on a binding, or if a committed render is not the fixture's.

On a push to main the four data-plane and app components converge in one
run, per environment, in the order `supabase → cloudflare-hyperdrive →
db-migrate → web`, because each component that reads another's output
declares `dependsOn` on it with `mode: enforced` (advisory on a pull
request).

## 4. Neon → Supabase

The template needs a Postgres Hyperdrive can reach; Neon is upstream's
suggestion, not a dependency. The Lumen data plane this repository builds on
is a Supabase project per environment, provisioned by Terraform with the
connections the console already brokers, so the database is Supabase's. A
Supabase project serves `public` through its Data API to anyone holding the
project's anon key, which is public by design — so `030_row_level_security`
turns row-level security on with no policy (risk RR-D). The app connects as
`postgres`, the table's owner, through Hyperdrive and is not subject to it.

## 5. The repository

```
apps/web                               the template + the monorepo build
  api/index.js                         Hono: /api/health, React Router, assets
  api/books-service.js                 BooksService (upstream's) + getHealth()
  app/                                 the routes, components and layout, as written
  app/lib/site.ts                      the product's name
  wrangler.template.jsonc              the build's config: HYPERDRIVE, BOOKS_SERVICE, ASSETS
  wrangler.deploy.template.jsonc       the deploy's config: the same, over build/
packages/db                            the migrations and Lumen's runner (@saas/db)
infra/terraform/supabase               the Supabase project per environment
infra/terraform/cloudflare-hyperdrive  the Hyperdrive config per environment
infra/db-migrate                       applies packages/db's migrations per environment
tests/web                              vitest: the service's mock mode and health, /api/health, the configs
tests/db                               vitest: the manifest, the seed, row-level security (PGlite)
```

## 6. Out of scope

Writing books (upstream reads only), auth and row-level security *policies*
(the app does not use Supabase's Data API or Auth, so RLS is on with none),
a custom domain.
