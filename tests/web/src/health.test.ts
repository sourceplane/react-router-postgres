import { describe, expect, it } from "vitest";
import worker from "@web/api/index.js";

// /api/health — what the deploy's smoke and the bootstrap's probes read — goes
// through the BOOKS_SERVICE self-binding, as the pages do.
async function health(BOOKS_SERVICE: unknown) {
  const res = await worker.fetch(new Request("https://books.example/api/health"), { BOOKS_SERVICE }, {
    waitUntil() {},
    passThroughOnException() {},
  });
  return { status: res.status, cache: res.headers.get("cache-control"), body: await res.json() };
}

describe("GET /api/health", () => {
  it("answers 200 with the service's verdict when it is healthy", async () => {
    const verdict = { ok: true, source: "database", database: "reachable", schema: "migrated", books: 9 };
    expect(await health({ getHealth: async () => verdict })).toEqual({ status: 200, cache: "no-store", body: verdict });
  });

  it("answers 503 when the service says it is not", async () => {
    const verdict = { ok: false, source: "database", database: "reachable", schema: "missing" };
    const res = await health({ getHealth: async () => verdict });
    expect(res.status).toBe(503);
    expect(res.body).toEqual(verdict);
  });

  it("answers 503 unreachable when the service throws", async () => {
    const res = await health({
      getHealth: async () => {
        throw new Error("connection refused");
      },
    });
    expect(res).toEqual({ status: 503, cache: "no-store", body: { ok: false, database: "unreachable" } });
  });
});
