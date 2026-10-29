# react-router-postgres — decisions

The choices that shape this repository, one line each, with where the full
reasoning lives. Superseded decisions stay listed, marked, so the history
reads in order.

| # | Decision | Why | Source |
|---|---|---|---|
| 1 | The template's JavaScript stays JavaScript, as written; tsc checks only what the port adds (`checkJs` off) | Upstream does not pass its own strict `checkJs` (242 errors: no React types, untyped props); rewriting its components to satisfy it is not porting them | `apps/web/tsconfig.json`, design.md §2 |
| 2 | Keep the `BOOKS_SERVICE` self-binding, rendered per environment as `<repo>-web-<env>` | It is the template's design (loaders call a `WorkerEntrypoint` over RPC); `wrangler deploy --dry-run` and `wrangler dev` accept a binding to the Worker's own name, and the wire render already knows the environment | risk RR-A, design.md §3 |
| 3 | Two committed wrangler configs: `wrangler.jsonc` (what the Vite plugin builds from) and `wrangler.deploy.jsonc` (the built entry, `no_bundle`, what the lanes deploy) | The composition checks the deploy config exists BEFORE the build; the plugin's own `build/server/wrangler.json` exists only after it (astro-boilerplate's shape) | design.md §3, tests/web `wrangler-config.test.ts` |
| 4 | Neon → a Supabase project per environment, Hyperdrive in front (postgres-drizzle-starter's roots) | One Postgres provider for every Orun baseline, provisioned by Terraform and wired through orun secrets | design.md §4 |
| 5 | Upstream's `init.sql` becomes three migrations: the table, its nine books (`ON CONFLICT (id) DO NOTHING`, the id sequence moved past them), row-level security | A fresh environment must hold the library before the Worker serves; upstream loaded the script by hand | risk RR-C, IMPLEMENTATION-STATUS |
| 6 | Row-level security on every table in `public`, with no policy | Supabase's Data API serves `public` to the public anon key; the app connects as the table's owner | risk RR-D |
| 7 | `/api/health` through the self-binding (`BooksService.getHealth()`), and the deploy smoke reads it | One check proves the self-binding, Hyperdrive, the database and the migrations; the page's heading is the owner's to change | `apps/web/component.yaml` |
| 8 | The product's name in one seam, `app/lib/site.ts`, read by the library's heading and a `meta()` `<title>` (upstream had none) | The rename engine rewrites one literal line | `tooling/rebrand/rebrand.mjs` |
| 9 | The upstream template's name (`react-router-postgres-ssr-template`) is protected from the rename | It starts with this baseline's slug; renaming its head would point a product at a template that does not exist | `tooling/rebrand/rebrand.mjs` `UPSTREAM`, testing/rebrand.test.sh |
| 10 | The migrations package is named `@saas/db` | stack-tectonic's db-migrate composition builds `--filter=@saas/db` | risk RR-F |
| 11 | `ci.yml` plans nothing while `intent.yaml` names `ws_CHANGE_ME` (the `linked` step) | A bootstrap cannot set a repository variable | `.github/workflows/ci.yml` |
| 12 | stack-tectonic 0.19.0, as the other baselines pin it | 0.20.0's lane-scoped install links each job's node_modules out of its tree | `intent.yaml` |
| 13 | The console card reads `subdomain` from the Cloudflare connection; the console asks for no domain | Both belong to the account or the owner, not to the form | `blueprint.yaml`, `repo-blueprint.yaml` |
| 14 | The turso-starter v8 shape on orun v2.88.0: no `checks.yml`; the brokered keys in one `secrets` reconcile per provider; every component's generated pages in `spec.docs`, the app's domain `app`; the task set-up in the background, each landing checked in the box (`checks: local`), the watch at 5 s | The current standard every Orunbase starter builds to | `repo-blueprint.yaml`, `testing/phases.test.sh`, `testing/coverage.test.sh` |
