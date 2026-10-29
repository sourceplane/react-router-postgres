import { afterEach, describe, expect, it, vi } from "vitest";

// The template's BooksService — the RPC entrypoint the page loaders reach
// through the Worker's BOOKS_SERVICE self-binding. With no HYPERDRIVE binding
// it serves the template's mock data (upstream's demo mode); with one it
// queries Postgres. The database path's SQL runs for real when the built
// Worker is served over a migrated Postgres (`db:migrate:local`, then
// `preview`); here `postgres` is a stub that answers what getHealth asks, so
// its verdicts are checked one by one.
const answers: { rows: unknown[] }[] = [];
const ended = vi.fn();
vi.mock("postgres", () => ({
  default: vi.fn(() => {
    const sql = (strings: TemplateStringsArray) => {
      const next = answers.shift();
      if (!next) throw new Error(`unexpected query: ${strings.join("?")}`);
      return Promise.resolve(next.rows);
    };
    sql.end = ended;
    return sql;
  }),
}));

const { BooksService } = await import("@web/api/books-service.js");

function service(env: Record<string, unknown> = {}) {
  const waits: Promise<unknown>[] = [];
  const ctx = { waitUntil: (p: Promise<unknown>) => waits.push(p) };
  return { svc: new BooksService(ctx, env), waits };
}

afterEach(() => {
  answers.length = 0;
  ended.mockReset();
});

describe("BooksService without a database (the template's demo mode)", () => {
  it("lists every mock book, filtered by genre and sorted as asked", async () => {
    const { svc } = service();
    const all = await svc.getBooks({});
    expect(all.source).toBe("mock");
    expect(all.books).toHaveLength(9);
    const sf = await svc.getBooks({ genre: "Science Fiction & Fantasy", sort: "title_asc" });
    expect(sf.books.map((b: { title: string }) => b.title)).toEqual(["The Fifth Season", "The Left Hand of Darkness"]);
    const desc = await svc.getBooks({ sort: "author_desc" });
    expect(desc.books[0].author).toBe("Ursula K. Le Guin");
  });

  it("finds one book, and says 404 for one it does not have", async () => {
    const { svc } = service();
    expect((await svc.getBook("4")).book.title).toBe("Jane Eyre");
    expect(await svc.getBook("99")).toEqual({ error: "Book not found", status: 404 });
  });

  it("finds related books in the same genre, never the book itself", async () => {
    const { svc } = service();
    const related = await svc.getRelatedBooks("3");
    expect(related.bookGenre).toBe("Science Fiction & Fantasy");
    expect(related.relatedBooks.map((b: { id: number }) => b.id)).toEqual([9]);
    expect(related.genreStats[0]).toEqual({ genre: "Literary Fiction", count: 5 });
  });

  it("is not a healthy deploy", async () => {
    const { svc } = service();
    expect(await svc.getHealth()).toEqual({ ok: false, source: "mock", database: "not bound" });
  });
});

describe("BooksService.getHealth with a database", () => {
  const env = { HYPERDRIVE: { connectionString: "postgres://stub" } };

  it("is healthy when the books table exists with row-level security, and counts it", async () => {
    answers.push({ rows: [{ books: "books", rls: true }] }, { rows: [{ n: 9 }] });
    const { svc, waits } = service(env);
    expect(await svc.getHealth()).toEqual({
      ok: true,
      source: "database",
      database: "reachable",
      schema: "migrated",
      books: 9,
    });
    expect(waits).toHaveLength(1);
    expect(ended).toHaveBeenCalledTimes(1);
  });

  it("is not healthy before the migrations ran", async () => {
    answers.push({ rows: [{ books: null, rls: false }] });
    const { svc } = service(env);
    expect(await svc.getHealth()).toEqual({ ok: false, source: "database", database: "reachable", schema: "missing" });
    expect(ended).toHaveBeenCalledTimes(1);
  });

  it("is not healthy when the table is open to Supabase's Data API", async () => {
    answers.push({ rows: [{ books: "books", rls: false }] }, { rows: [{ n: 9 }] });
    const { svc } = service(env);
    const health = await svc.getHealth();
    expect(health.ok).toBe(false);
    expect(health.schema).toBe("no row-level security");
  });
});
