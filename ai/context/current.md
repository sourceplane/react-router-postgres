# react-router-postgres — where this repository stands

The entry page for anyone (or any agent) picking this repository up. It is
this repository's own state and does not ship to a product built from it;
the two pages that do are [operations.md](operations.md) and
[deployment.md](deployment.md).

## What it is

Cloudflare's React Router + Postgres SSR template — a books library
server-rendered by React Router v7, its page loaders calling the Worker's own
`BooksService` entrypoint over a service binding to itself — on Cloudflare
Workers + Static Assets, with the database a Supabase Postgres project
reached through Hyperdrive, packaged as an Orun baseline: `orun new
--blueprint repo-blueprint.yaml` builds a new product in its own repository
and takes it to live on stage and prod in one landing (`01-product`:
supabase → cloudflare-hyperdrive → db-migrate → web per environment), then
records what went live (`02-docs`).

## Release

| | |
|---|---|
| Latest tag | `baseline-v1` (RR4 — the first release, on the turso-starter v8 shape and orun v2.88.0) |
| Proven live | No. Everything short of the platform is proven offline in Baseline CI — a migrated local Postgres served through the built Worker, its self-binding resolving to itself, included; a live bootstrap from a tag is still to come (risk RR-H) |

## Where to read

| Question | Page |
|---|---|
| What shipped, and every departure from upstream | `specs/epics/react-router-postgres/IMPLEMENTATION-STATUS.md` |
| Why it is built this way | [decisions.md](decisions.md), then `specs/epics/react-router-postgres/design.md` |
| What could still go wrong | [open-risks.md](open-risks.md), then `specs/epics/react-router-postgres/risks-and-open-questions.md` |
| How to instantiate it | `BOOTSTRAP.md`, `docs/phases/` |
| What each component is | `<component>/docs/` beside each `component.yaml` — `apps/web`, `packages/db`, `infra/db-migrate`, `infra/terraform/{supabase,cloudflare-hyperdrive}`, `tests/{web,db}` (generated; `python3 tooling/catalog/gen-component-docs.py`) |

## Next

1. Bootstrap one product from `baseline-v1` against a workspace with
   Cloudflare and Supabase connections and room for two Supabase projects
   (RR-E): a real deploy of the self-binding (RR-A) and its timings (closes
   RR-H).
