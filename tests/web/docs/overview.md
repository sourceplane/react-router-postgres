# web-tests

The app's tests (the BooksService entrypoint in demo and database modes, the /api/health check through the self-binding, the product-name seam, and both committed wrangler configs held to their templates and each other)

The test suite for **web**. It deploys nothing: its lane installs, builds and runs the tests.

|              |                      |
| ------------ | -------------------- |
| Type         | `turbo-package`      |
| Source       | `tests/web`          |
| Package      | `@app/web-tests`     |
| Environments | `dev`: `quick-check` |

## Depends on

- (none)

## Depended on by

- (none)
