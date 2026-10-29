# react-router-postgres — risks and open questions

## RR-A — The self-binding on a Worker's first deploy (OPEN)

`BOOKS_SERVICE` names `<reponame>-web-<env>`, the Worker being deployed. On
an environment's first deploy that Worker does not exist yet. Upstream's
Deploy to Cloudflare button makes the same first deploy (its `service` is
the Worker's own name), and `wrangler deploy --dry-run` accepts the binding;
neither is a live first deploy from this repository. If Cloudflare refuses
it, the fallback is the upstream-sanctioned one: the loaders call
`BooksService` in-process when the binding is absent — a code change kept
out of the port until a live bootstrap shows it is needed. The names must
stay equal: `component.yaml`'s `workerName` is `<reponame>-web`, the
composition deploys `<workerName>-<env>`, and the template's `service` is
`<reponame>-web-__ENV__`; `tests/web` fails if they drift.

## RR-B — The JavaScript is not type-checked (ACCEPTED)

Upstream's `.js`/`.jsx` reports 242 errors under `checkJs`. It is kept as
written (design §2): `checkJs` is off, `eslint` lints it with React's
`jsx-uses-vars`, and `tests/web` and the e2e tier hold its behaviour.

## RR-C — `init.sql` as migrations (RESOLVED)

Upstream applies `init.sql` by hand; an unattended first deploy needs the
schema before the app. It is three migrations. Upstream inserts the nine
books with explicit ids and leaves the `SERIAL` sequence at 1, so the first
book a product adds without an id would collide with book 1;
`020_books_seed` moves the sequence past the seed (`setval`), and the e2e
inserts a tenth book to prove it. `ON CONFLICT (id) DO NOTHING` makes the
seed safe to re-run; the ledger means it never is.

## RR-D — Supabase's Data API and a table with no RLS (RESOLVED)

Upstream assumed a private Postgres. A Supabase project serves `public`
through PostgREST to anyone with the project's anon key, which is public by
design, so `books` would have been readable and writable from the internet.
`030_row_level_security` enables RLS with no policy: `anon` and
`authenticated` get nothing, and the app — which connects as `postgres`, the
table's owner — is not subject to it. Its guard refuses to run if `postgres`
would be locked out. `tests/db` fails on any table in `public` without RLS,
and `/api/health` answers 503 for a `books` table without it.

## RR-E — Two Supabase projects per product (OWNER PREREQUISITE)

Stage and prod are separate projects, and Supabase's free plan allows two
active projects per organization. The card's description and BOOTSTRAP.md
say so; an org without room fails the supabase apply ("project limit"),
nothing downstream runs, and a re-run after freeing room adopts what exists.

## RR-F — The migrations package is named `@saas/db` (ACCEPTED)

stack-tectonic's `db-migrate` composition (0.19.0) builds
`--filter=@saas/db` and runs `dist/runner/cli.js` two levels above the
component's `path`. Lumen's package carries that name, so this one does too;
it is a build-system name, not this product's.

## RR-G — Hyperdrive's read cache (ACCEPTED)

The Hyperdrive config caches read queries (60 s `max_age`, 15 s
stale-while-revalidate) and does not invalidate them on a write. The app
only reads and the books change only through migrations, so a page can be
up to a minute stale after one — as any Hyperdrive read is. `/api/health`'s
query calls `to_regclass` (STABLE) and is never cached. Not observable
offline: `wrangler dev`'s local binding has no cache.

## RR-H — No live bootstrap yet (OPEN)

Everything short of the platform is proven on every pull request: the card
against the build, the blueprint read by the pinned orun, the leak gate, the
offline bootstrap with the blueprint's own hooks, the product's own plan
(supabase → cloudflare-hyperdrive → db-migrate → web per environment,
enforced on main, advisory on a pull request), and the produced product
migrated by its own runner into a local Postgres with Supabase's roles,
built in the job tree, dry-deployed with both bindings, served under its
own deployed name over that database with eight concurrent first requests,
smoke-tested, and read by the Data API's roles, which see nothing. NOT
proven: the repository created and linked, the five keys minted by
`integrations/reconcile`, a real `terraform apply` of the Supabase projects
and the Hyperdrive configs (both roots are held to `terraform validate`), a
`db-migrate` apply against a real Supabase project, a real `wrangler
deploy` — the self-binding's first deploy among it (RR-A) — Hyperdrive's
read cache (RR-G), and the probes of `/` and `/api/health`. Closes with one
bootstrap from a tag against a workspace with Cloudflare and Supabase
connections and room for two Supabase projects (RR-E).
