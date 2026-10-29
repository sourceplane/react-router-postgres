# Epics

Orun-style work programs. Each epic is a folder carrying `epic.yaml` (the
declaration the platform reads: slug, key prefix, milestones with exit
criteria and task keys) beside its doc set. The pull request that adds the
folder is the adoption; the merge creates the epic in the workspace.

| Epic | Cluster | Status | What it is |
|------|---------|--------|------------|
| [`react-router-postgres/`](./react-router-postgres/) | **RR** | In progress (RR3 shipped; RR4 next) | Cloudflare's React Router + Postgres SSR template — a server-rendered books library, React Router v7 and a Hono API in one Worker reading Postgres through Hyperdrive and a service binding to itself — on Cloudflare Workers with Supabase Postgres, and an Orun baseline that instantiates it in one landing (RR4) |

As-built ≠ intent: what shipped lives in each epic's `IMPLEMENTATION-STATUS.md`.
