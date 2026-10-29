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

This repository is being built in five steps, one pull request each: the
spec (RR0), the app on Workers (RR1), Supabase, Hyperdrive and the schema
from Terraform and migrations (RR2), ready to instantiate (RR3), and the
baseline (RR4). The design, the milestones and the as-built status are in
[`specs/epics/react-router-postgres`](specs/epics/react-router-postgres/README.md).

## Credit

The app is Cloudflare's [`react-router-postgres-ssr-template`](https://github.com/cloudflare/templates/tree/main/react-router-postgres-ssr-template),
MIT-licensed (© 2018 Cloudflare, Inc.); the licence arrives with it, in
`apps/web/LICENSE`, at RR1.
