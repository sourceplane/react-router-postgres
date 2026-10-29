# @app/web — the books library on Cloudflare Workers

Cloudflare's `react-router-postgres-ssr-template`
([source](https://github.com/cloudflare/templates/tree/main/react-router-postgres-ssr-template),
[Deploy to Cloudflare](https://deploy.workers.cloudflare.com/?url=https://github.com/cloudflare/templates/tree/main/react-router-postgres-ssr-template)):
a library of books, server-rendered by React Router v7 — every book, a genre
sorted by title or author, a book with its related books and the genre
counts — in one Worker with Static Assets, built by the Cloudflare Vite
plugin. Its page loaders call the `BooksService` entrypoint through the
`BOOKS_SERVICE` service binding, which binds this same Worker; the service
queries Postgres through the `HYPERDRIVE` binding.

| File | What it does |
|---|---|
| `app/lib/site.ts` | The product's name: the library's heading and the page's `<title>` |
| `app/routes`, `app/layouts`, `app/components` | The template's pages and components, as upstream wrote them |
| `api/index.js` | The Worker's entry: Hono, React Router's request handler, `/api/health` |
| `api/books-service.js` | `BooksService` (a `WorkerEntrypoint`): `getBooks`, `getBook`, `getRelatedBooks` over a `postgres` client per call on `env.HYPERDRIVE`, the template's mock data when no database is bound, and `getHealth` for `/api/health` |
| `public/images/books` | The covers |
| `wrangler.template.jsonc` → `wrangler.jsonc` | What the Vite plugin builds from (and `react-router dev` runs): `main` is `api/index.js`. The render is committed (`pnpm run wire:fixture`) |
| `wrangler.deploy.template.jsonc` → `wrangler.deploy.jsonc` | What deploys: the built `build/server/index.js`, no re-bundling, `build/client` as assets. The render is committed |
| `wiring.fixture.json` | The placeholder Hyperdrive ids the committed renders carry |

```bash
pnpm db:migrate:local         # packages/db's migrations into LOCAL_DATABASE_URL (default: the Supabase CLI's localhost:54322)
pnpm dev                      # react-router dev — the Worker in workerd through the Vite plugin
pnpm build && pnpm preview    # the built Worker under wrangler dev
```

MIT-licensed by Cloudflare (`LICENSE`).
