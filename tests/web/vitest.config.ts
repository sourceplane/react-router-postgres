import { defineConfig } from "vitest/config";
import * as path from "node:path";

// apps/web's Worker code runs here under Node: `cloudflare:workers` (the
// WorkerEntrypoint base class) and React Router's virtual server build exist
// only inside workerd and the Vite plugin, so each resolves to a stub.
export default defineConfig({
  resolve: {
    alias: {
      "cloudflare:workers": path.resolve(__dirname, "stubs/cloudflare-workers.ts"),
      "virtual:react-router/server-build": path.resolve(__dirname, "stubs/server-build.ts"),
      "@web": path.resolve(__dirname, "../../apps/web"),
    },
  },
  test: {
    include: ["src/**/*.test.ts"],
    environment: "node",
  },
});
