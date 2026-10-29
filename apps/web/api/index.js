import { Hono } from "hono";
import { createRequestHandler } from "react-router";
import { BooksService } from "./books-service";

const app = new Hono();

// React Router request handler
const requestHandler = createRequestHandler(
	() => import("virtual:react-router/server-build"),
	import.meta.env.MODE,
);

// Not upstream's: the deploy's smoke check and the bootstrap's probes read
// this. The page proves the Worker serves; this proves what a page cannot say
// on its own — the BOOKS_SERVICE self-binding answers, its HYPERDRIVE binding
// names a real config, Hyperdrive reaches the Supabase database, and db-migrate
// applied the schema: the `books` table exists, with row-level security on.
// Read-only: it never writes.
app.get("/api/health", async (c) => {
	const headers = { "cache-control": "no-store" };
	try {
		const health = await c.env.BOOKS_SERVICE.getHealth();
		return c.json(health, health.ok ? 200 : 503, headers);
	} catch (error) {
		console.error("[Health] check failed:", error);
		return c.json({ ok: false, database: "unreachable" }, 503, headers);
	}
});

// Handle React Router requests
app.get("*", async (c) => {
	return requestHandler(c.req.raw, {
		cloudflare: { env: c.env, ctx: c.executionCtx },
	});
});

// Catch-all route for static assets
app.all("*", async (c) => {
	return c.env.ASSETS.fetch(c.req.raw);
});

export default {
	fetch: app.fetch,
};

export { BooksService };
