# Plex DB Recovery: Watch History + Added Dates

This workspace contains a recovery workflow for migrating watch history and added dates from a corrupted Plex database into a brand new Plex database created by a fresh server install.

## What happened and why this works
- A new Plex server rebuilds libraries from scratch, which can change GUIDs (e.g., old `plex://episode/...` vs new `local://...`).
- Plex does **not** mark items as watched from history alone. It relies on per-user rows in `metadata_item_settings` (`view_count`, `last_viewed_at`, etc.).
- We exported history and added dates from the old DB, then **mapped** history to the new DB using titles/season/episode numbers (and track artist/album/index for music). This avoids GUID mismatches.
- We also synced account names so watch history is assigned to the correct user IDs in the new DB.

## Files
- `plexdb_migrate.sh` — migration script (exports from OLD and imports into NEW).
- `plexdb_migrate_work/` — working folder where CSV exports are stored.

## Requirements
- Plex SQLite binary and libraries from the Plex bundle.
- Old DB: `Databases/OLD/com.plexapp.plugins.library.db`
- New DB: `Databases/NEW/com.plexapp.plugins.library.db`

## Run the migration
1. Ensure the new DB exists and has the Plex schema (created by Plex after initial setup).
2. Make sure Plex is **stopped** while you modify the DB.
3. Run the script:
   - `./plexdb_migrate.sh`
4. Start Plex again.

## If Plex still shows everything unwatched
1. **Refresh metadata** for affected libraries so titles and season/episode indices are populated in the NEW DB.
2. Re-run `./plexdb_migrate.sh`.
3. Restart Plex.

## What the script does
- Exports watch history from `metadata_item_views` in the OLD DB.
- Exports added dates from `metadata_items.added_at` in the OLD DB.
- Syncs account names into the NEW DB.
- Clears NEW DB watch history and existing added dates.
- Maps watch history to NEW DB items by:
  - Show title + season + episode number (TV)
  - Title (movies)
  - Artist + album + track index (music)
- Inserts mapped watch history into:
  - `metadata_item_views`
  - `metadata_item_settings` (per-user watched status)
- Updates `metadata_items.added_at` in the NEW DB.

## Notes
- If libraries were not fully scanned yet, mapping can fail until metadata is refreshed.
- If you use multiple users, verify accounts exist in the NEW DB after migration.

## Troubleshooting
- GUID mismatch is normal after a rebuild. Mapping by title/season/episode is the fix.
- If a specific show is missing, check that NEW DB has titles and indices for that show.
