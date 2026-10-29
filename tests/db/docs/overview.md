# db-tests

The migrations' tests (the manifest and its checksums, the template's table and its nine books seeded once, and row-level security on every table in public after every migration, its guard included), run in PGlite on every pull request

The test suite for **db**. It deploys nothing: its lane installs, builds and runs the tests.

|              |                      |
| ------------ | -------------------- |
| Type         | `turbo-package`      |
| Source       | `tests/db`           |
| Package      | `@app/db-tests`      |
| Environments | `dev`: `quick-check` |

## Depends on

- (none)

## Depended on by

- (none)
