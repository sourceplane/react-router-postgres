// React Router's server build exists only in the Vite plugin's build. The
// Hono app imports it lazily, for the page routes these tests never call.
export default {};
