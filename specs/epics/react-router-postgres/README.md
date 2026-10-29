# Epic: react-router-postgres (RR)

**Cloudflare's React Router + Postgres SSR template is a books library rendered on the server: React Router v7 in SSR mode and a Hono API share one Worker, and every loader reads the books through `BOOKS_SERVICE` — a service binding from the Worker to its own `BooksService` entrypoint — which opens a `postgres` client per call over the `HYPERDRIVE` binding, or serves built-in mock data when there is none. Here the database is a Supabase Postgres project behind Hyperdrive, both from Terraform; upstream's hand-applied `init.sql` becomes three migrations that `db-migrate` applies, with row-level security, before the app serves; and the two wrangler configs the build and the deploy read are rendered per environment, the self-binding naming the environment's own Worker.**

The port keeps the routes, the components, the Hono API, the `BooksService` and its mock fallback, the schema and the nine books. It adds the monorepo wrapper, `/api/health` (the smoke's and the probes' database check), a test package for the service and the configs, the Supabase and Hyperdrive Terraform roots, the migrations package and `db-migrate`, the deploy contract — and makes the repository an Orun baseline.

## Status

| Field | Value |
|-------|-------|
| Status | In progress — RR0–RR3 shipped ([#1](https://github.com/sourceplane/react-router-postgres/pull/1)–[#4](https://github.com/sourceplane/react-router-postgres/pull/4)); RR4 — a baseline — next |
| Cluster | **RR** (RR0–RR4) |
| Owner(s) | `apps/web` (the routes, `api/index.js`, `api/books-service.js`, the two wrangler templates) · `packages/db` (the migrations and their runner) · `tests/web`, `tests/db` · `infra/terraform/{supabase,cloudflare-hyperdrive}`, `infra/db-migrate` |
| Builds on | `postgres-drizzle-starter` (the Lumen data plane: the `supabase` and `cloudflare-hyperdrive` roots, `packages/db` and `db-migrate`, row-level security); `astro-boilerplate` (a Vite build deployed from a committed deploy config) |
| Upstream | [cloudflare/templates `react-router-postgres-ssr-template`](https://github.com/cloudflare/templates/tree/main/react-router-postgres-ssr-template) (MIT, © 2018 Cloudflare, Inc.) |
| Changes | `init.sql` → migrations with row-level security; the wrangler config rendered per environment (two: the build's and the deploy's); `/api/health`; the product name in one file; tests, two Terraform roots, the deploy contract |
| Decisions locked | (1) The app's JavaScript stays as written — not type-checked (design §2). (2) The self-binding is kept: `BOOKS_SERVICE` names `<reponame>-web-<env>`, which is the name the deploy uses (design §3). (3) Two configs: the Vite plugin builds from `wrangler.jsonc`, the deploy reads the committed `wrangler.deploy.jsonc` that points at the build's output (design §3). (4) Neon → Supabase (design §4). (5) Infra before app on main: supabase → cloudflare-hyperdrive → db-migrate → web, enforced; advisory on pull requests. |
| Gate | RR2 applies only with a linked workspace (Supabase + Cloudflare connections); verified by `terraform validate` and, from RR4, the offline end-to-end tier. |

## Read order

1. `design.md` — what maps to what, the bindings, what is out of scope
2. `implementation-plan.md` — the milestones and what "done" means for each
3. `risks-and-open-questions.md` — what could go wrong and what was decided
4. `IMPLEMENTATION-STATUS.md` — what actually shipped (kept distinct from intent)

## Milestones at a glance

| Milestone | What it lands | Done when |
|---|---|---|
| RR0 — the spec | this doc set, the task contracts, the repository's intent, CI and tooling | merged on `main` |
| RR1 — the app on Workers | `apps/web`, the two rendered wrangler configs, `tests/web` | typecheck, lint, test and build green; the Worker serves the library over the binding |
| RR2 — Supabase, Hyperdrive and the schema | the two roots, `packages/db` (`010_books`, `020_books_seed`, `030_row_level_security`), `infra/db-migrate`, `tests/db` | the roots validate; the wiring key matches the templates; the migrations apply and re-apply nothing |
| RR3 — ready to instantiate | README, as-built status | a reader can run, test, preview and deploy it |
| RR4 — a baseline | card, build document, rename engine, bootstrap tooling, the product's README and context pack, component docs, tests, `baseline.yml` / `tag.yml` | a new product goes from nothing to live on stage and prod in one landing; Baseline CI green; tagged `baseline-v1` |
