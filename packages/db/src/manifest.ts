import type { MigrationManifest } from "./types.js";

// Every migration the runner applies, in order, with the sha256 of its file.
// `pnpm --filter @saas/db run manifest:check` verifies the checksums;
// `manifest:fix` rewrites them after a migration file changes (only ever
// before that migration has been applied anywhere — an applied migration's
// checksum is immutable).
export const manifest: MigrationManifest = {
  version: 1,
  migrations: [
    {
      id: "000_control_baseline",
      context: "control",
      path: "000_control/up.sql",
      checksum:
        "2a5d7f30684c99e3ff441ca8a2c38038dedd1bab4db4a40e92cd36bb22be297f",
      description:
        "Baseline control migration — creates the migration tracking schema",
    },
    {
      id: "010_books",
      context: "app",
      path: "010_books/up.sql",
      checksum:
        "2567cced22856c08aba5d45a5340599f2112428762e47eb2e186eac73ff4b673",
      description:
        "The template's books table, as its init.sql creates it — applied before the Worker serves instead of loaded by hand",
    },
    {
      id: "020_books_seed",
      context: "app",
      path: "020_books_seed/up.sql",
      checksum:
        "243307960a57de4044fa5db84a52297356c0e658aae467cecfb6692780c61eaf",
      description:
        "The template's nine books, as its init.sql inserts them (ON CONFLICT (id) DO NOTHING), and the id sequence moved past them",
    },
    {
      id: "030_row_level_security",
      context: "app",
      path: "030_row_level_security/up.sql",
      checksum:
        "0e54b575bf03a2a2f4949a0bb9097def87f65429fcd37eebe667acc99c8071f0",
      description:
        "Row-level security, with no policies, on every table in public — closed to Supabase's Data API (anon, authenticated), open to the app, which owns them; refuses to run if the app's role would be locked out",
    },
  ],
};
