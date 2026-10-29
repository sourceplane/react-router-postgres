import { describe, expect, it } from "vitest";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import * as path from "node:path";

// apps/web carries TWO wrangler configs, both rendered by tooling/wire and
// both COMMITTED as their fixture render:
//   wrangler.jsonc         what the Cloudflare Vite plugin builds from
//                          (`react-router dev` too): main is the source entry;
//   wrangler.deploy.jsonc  what the lanes dry-run and deploy: main is the
//                          built entry, no re-bundling — the composition checks
//                          it exists BEFORE the build, so it cannot be the
//                          build/server/wrangler.json the plugin writes.
// These hold each render to its template, the two to each other, and a lane's
// live render to the document it is given — the self-binding included: the
// BOOKS_SERVICE service is the Worker's own name in that environment.
const app = path.resolve(__dirname, "../../../apps/web");
const wire = path.resolve(__dirname, "../../../tooling/wire");
const PAIRS = [
  ["wrangler.template.jsonc", "wrangler.jsonc"],
  ["wrangler.deploy.template.jsonc", "wrangler.deploy.jsonc"],
] as const;

function jsonc(text: string): Record<string, any> {
  return JSON.parse(text.replace(/^\s*\/\/.*$/gm, ""));
}

function render(script: "render.mjs" | "live.mjs", template: string, env: string, extra: string[] = [], wiring?: Record<string, string>) {
  const dir = mkdtempSync(path.join(tmpdir(), "wire-"));
  try {
    const out = path.join(dir, "out.jsonc");
    const args =
      script === "render.mjs"
        ? ["--map", path.join(app, "wiring.fixture.json"), "--env", env]
        : ["--components", "cloudflare-hyperdrive", "--env", env, ...extra];
    execFileSync(process.execPath, [path.join(wire, script), "--template", path.join(app, template), "--out", out, ...args], {
      env: { ...process.env, ...wiring },
      stdio: "pipe",
    });
    return readFileSync(out, "utf8");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

describe("apps/web wrangler configs", () => {
  it.each(PAIRS)("%s is committed as its fixture render (pnpm run wire:fixture)", (template, out) => {
    expect(readFileSync(path.join(app, out), "utf8")).toBe(render("render.mjs", template, "stage"));
  });

  it.each(PAIRS)("%s keeps the Hyperdrive id a wiring token and the service the Worker's own", (template) => {
    const text = readFileSync(path.join(app, template), "utf8");
    expect(text).not.toMatch(/"id":\s*"[0-9a-f]{32}"/);
    expect(text).toContain('"id": "@@wiring(cloudflare-hyperdrive/__ENV__:hyperdrive_id)@@"');
    const config = jsonc(text);
    expect(config.services).toEqual([
      { binding: "BOOKS_SERVICE", service: `${config.name}-__ENV__`, entrypoint: "BooksService" },
    ]);
  });

  it("names the Worker the composition deploys, so the self-binding resolves (workerName-<env>)", () => {
    // The lanes run `wrangler deploy --name <workerName>-<env>`, and a service
    // binding names a Worker by its deployed name: BOOKS_SERVICE reaches this
    // Worker only while the three names agree.
    const manifest = readFileSync(path.join(app, "component.yaml"), "utf8");
    const workerName = manifest.match(/^\s*workerName:\s*(\S+)\s*$/m)?.[1];
    const deploy = jsonc(readFileSync(path.join(app, "wrangler.deploy.template.jsonc"), "utf8"));
    expect(workerName).toBe(deploy.name);
    expect(manifest).toMatch(/^\s*wranglerConfig:\s*wrangler\.deploy\.jsonc\s*$/m);
  });

  it("builds and deploys the same Worker: name, compatibility, bindings and settings agree", () => {
    const build = jsonc(readFileSync(path.join(app, "wrangler.template.jsonc"), "utf8"));
    const deploy = jsonc(readFileSync(path.join(app, "wrangler.deploy.template.jsonc"), "utf8"));
    for (const key of ["name", "compatibility_date", "compatibility_flags", "hyperdrive", "services", "placement", "observability", "upload_source_maps"]) {
      expect(deploy[key], key).toEqual(build[key]);
    }
    expect(build.main).toBe("./api/index.js");
    expect(deploy.main).toBe("./build/server/index.js");
    expect(deploy.no_bundle).toBe(true);
    expect(deploy.assets).toEqual({ directory: "./build/client", binding: build.assets.binding });
  });

  it.each(PAIRS)("%s renders a deploy lane its own environment from the live wiring document", (template) => {
    const rendered = jsonc(
      render("live.mjs", template, "prod", [], {
        WIRING_CLOUDFLARE_HYPERDRIVE_PROD: JSON.stringify({ hyperdrive_id: "f".repeat(32), hyperdrive_name: "prod-x-prod" }),
      }),
    );
    expect(rendered.hyperdrive[0].id).toBe("f".repeat(32));
    expect(rendered.services[0].service).toBe(`${rendered.name}-prod`);
  });

  it("renders dev, which nothing applies to, from the fixture — its own name on the self-binding", () => {
    const rendered = jsonc(
      render("live.mjs", "wrangler.deploy.template.jsonc", "dev", ["--fixture", path.join(app, "wiring.fixture.json"), "--fixture-envs", "dev"]),
    );
    expect(rendered.hyperdrive[0].id).toBe("00000000000000000000000000000002");
    expect(rendered.services[0].service).toBe(`${rendered.name}-dev`);
  });

  it("refuses a deploy render with no wiring document", () => {
    expect(() => render("live.mjs", "wrangler.deploy.template.jsonc", "stage", [], { WIRING_CLOUDFLARE_HYPERDRIVE_STAGE: "" })).toThrow();
  });
});
