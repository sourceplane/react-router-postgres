# react-router-postgres — open risks

What is not yet proven or not yet decided. The full write-up of every risk,
including the accepted and resolved ones, is
`specs/epics/react-router-postgres/risks-and-open-questions.md`; this page
lists only what is still live, so it should be short.

| ID | Risk | State | What closes it |
|---|---|---|---|
| RR-A | The self-binding on a REAL first deploy: a dry run and `wrangler dev` accept a service binding to the Worker's own name, but neither creates a Worker that does not exist yet | OPEN | One bootstrap's web lane deploying `<repo>-web-stage` for the first time |
| RR-H | No live bootstrap yet: the repository created and linked, the five keys minted, real Terraform applies of the Supabase projects and Hyperdrive configs, a `db-migrate` apply against a real Supabase project, a real `wrangler deploy`, Hyperdrive's read cache and the probes are all unproven | OPEN | One bootstrap from a tag against a workspace with Cloudflare and Supabase connections |

Accepted, and worth knowing before you change them: RR-B (the template's
JavaScript is not type-checked), RR-E (two Supabase projects per product —
an owner prerequisite on the free plan), RR-F (the migrations package is
named `@saas/db`).
