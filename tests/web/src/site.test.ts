import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import * as path from "node:path";

// The product's name is ONE literal line (app/lib/site.ts) that the rename at
// instantiation rewrites; the library's heading and the page's <title> read it.
const app = path.resolve(__dirname, "../../../apps/web/app");

describe("the product-name seam", () => {
  it("is a single literal SITE_NAME line", () => {
    const site = readFileSync(path.join(app, "lib/site.ts"), "utf8");
    expect(site.match(/^export const SITE_NAME = "[^"\n]+"$/m)).not.toBeNull();
  });

  it("is what the heading and the <title> render", () => {
    expect(readFileSync(path.join(app, "routes/books.jsx"), "utf8")).toContain("<h1>{SITE_NAME}</h1>");
    expect(readFileSync(path.join(app, "root.jsx"), "utf8")).toContain("[{ title: SITE_NAME }]");
  });
});
