// The Worker's bindings (wrangler.template.jsonc). api/ and app/ are
// JavaScript and read them untyped; this is what they are.
interface Env {
  HYPERDRIVE: Hyperdrive;
  BOOKS_SERVICE: Service;
  ASSETS: Fetcher;
}
