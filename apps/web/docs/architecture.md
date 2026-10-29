# web — architecture

Built by the turbo pipeline from `apps/web` and deployed with wrangler.

|                     |                                    |
| ------------------- | ---------------------------------- |
| Worker config       | `apps/web/wrangler.template.jsonc` |
| Entry               | `./api/index.js`                   |
| Compatibility date  | `2025-10-08`                       |
| Compatibility flags | `nodejs_compat`                    |

## Bindings

| Binding         | Kind                         | Source                                       |
| --------------- | ---------------------------- | -------------------------------------------- |
| `HYPERDRIVE`    | Hyperdrive (pooled Postgres) | `hyperdrive_id` from `cloudflare-hyperdrive` |
| `BOOKS_SERVICE` | Service binding              | Worker `react-router-postgres-web-__ENV__`   |
| `ASSETS`        | Static assets                | `None`                                       |

Identifiers marked _from_ a component are filled in at deploy time from
that component's published outputs for the environment being deployed.

## Wiring

Resolved at deploy time from secrets the infrastructure lanes publish (names only):

- `WIRING_CLOUDFLARE_HYPERDRIVE_PROD`
- `WIRING_CLOUDFLARE_HYPERDRIVE_STAGE`
