#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  plexdb_migrate.sh \
    --plex-sqlite "/path/to/Plex SQLite" \
    --plex-lib "/path/to/plexmediaserver/lib" \
    --source-db "/path/to/com.plexapp.plugins.library.db" \
    --target-db "/path/to/new/com.plexapp.plugins.library.db" \
    [--workdir "/path/to/workdir"]

Notes:
  - Target DB must already exist with Plex schema.
  - Added dates are matched by GUID + metadata_type.
  - Accounts are synced by id+name into the target DB before watch history import.
  - Watch history is inserted with account name mapping; if an account name
    is missing, it falls back to the first non-empty account in the target DB.
EOF
}

plex_sqlite="/home/gabriel/PlexDB/plexmediaserver/Plex SQLite"
plex_lib="/home/gabriel/PlexDB/plexmediaserver/lib"
source_db="/home/gabriel/PlexDB/Databases/OLD/com.plexapp.plugins.library.db"
target_db="/home/gabriel/PlexDB/Databases/NEW/com.plexapp.plugins.library.db"
workdir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plex-sqlite)
      plex_sqlite="$2"
      shift 2
      ;;
    --plex-lib)
      plex_lib="$2"
      shift 2
      ;;
    --source-db)
      source_db="$2"
      shift 2
      ;;
    --target-db)
      target_db="$2"
      shift 2
      ;;
    --workdir)
      workdir="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$plex_sqlite" || -z "$plex_lib" || -z "$source_db" || -z "$target_db" ]]; then
  usage
  exit 1
fi

if [[ ! -x "$plex_sqlite" ]]; then
  echo "Plex SQLite not executable: $plex_sqlite" >&2
  exit 1
fi

if [[ ! -d "$plex_lib" ]]; then
  echo "Plex lib folder not found: $plex_lib" >&2
  exit 1
fi

if [[ ! -f "$source_db" ]]; then
  echo "Source DB not found: $source_db" >&2
  exit 1
fi

if [[ ! -f "$target_db" ]]; then
  echo "Target DB not found: $target_db" >&2
  exit 1
fi

if [[ -z "$workdir" ]]; then
  workdir="$(pwd)/plexdb_migrate_work"
fi

mkdir -p "$workdir"

export LD_LIBRARY_PATH="$plex_lib"

watch_csv="$workdir/watched_all_items.csv"
added_csv="$workdir/added_dates.csv"
accounts_csv="$workdir/accounts.csv"

echo "Exporting watch history from source DB..."
"$plex_sqlite" "$source_db" <<SQL
.headers on
.mode csv
.output $watch_csv
SELECT
  COALESCE(a.name, 'Unknown') AS account_name,
  m.account_id,
  m.guid,
  m.metadata_type,
  m.library_section_id,
  m.grandparent_title,
  m.parent_title,
  m.parent_index,
  m."index" AS item_index,
  m.title,
  m.viewed_at,
  m.device_id,
  m.view_type
FROM metadata_item_views m
LEFT JOIN accounts a ON a.id = m.account_id
WHERE m.viewed_at IS NOT NULL;
.output stdout
SQL

echo "Exporting added dates from source DB..."
"$plex_sqlite" "$source_db" <<SQL
.headers on
.mode csv
.output $added_csv
SELECT guid, metadata_type, added_at
FROM metadata_items
WHERE added_at IS NOT NULL AND guid IS NOT NULL;
.output stdout
SQL

echo "Exporting accounts from source DB..."
"$plex_sqlite" "$source_db" <<SQL
.headers off
.mode csv
.output $accounts_csv
SELECT id, name
FROM accounts
WHERE name IS NOT NULL AND TRIM(name) != '';
.output stdout
SQL

echo "Syncing accounts into target DB..."
"$plex_sqlite" "$target_db" <<SQL
BEGIN;
DROP TABLE IF EXISTS temp_accounts;
CREATE TEMP TABLE temp_accounts (id INTEGER, name TEXT);
.mode csv
.import $accounts_csv temp_accounts

INSERT OR REPLACE INTO accounts (id, name)
SELECT DISTINCT t.id, t.name
FROM temp_accounts t
WHERE t.id IS NOT NULL
  AND t.name IS NOT NULL
  AND TRIM(t.name) != '';

DELETE FROM accounts WHERE name = 'name';

DROP TABLE temp_accounts;
COMMIT;
SQL

echo "Importing added dates into target DB..."
"$plex_sqlite" "$target_db" <<SQL
BEGIN;
UPDATE metadata_items SET added_at = NULL;
DROP TABLE IF EXISTS temp_added_dates;
CREATE TEMP TABLE temp_added_dates (
  guid TEXT,
  metadata_type INTEGER,
  added_at INTEGER
);
.mode csv
.import $added_csv temp_added_dates

UPDATE metadata_items
SET added_at = (
  SELECT t.added_at
  FROM temp_added_dates t
  WHERE t.guid = metadata_items.guid
    AND t.metadata_type = metadata_items.metadata_type
)
WHERE guid IN (SELECT guid FROM temp_added_dates);

DROP TABLE temp_added_dates;
COMMIT;
SQL

echo "Importing watch history into target DB..."
"$plex_sqlite" "$target_db" <<SQL
BEGIN;
DELETE FROM metadata_item_views;
DROP TABLE IF EXISTS temp_watch_history;
CREATE TEMP TABLE temp_watch_history (
  account_name TEXT,
  account_id INTEGER,
  guid TEXT,
  metadata_type INTEGER,
  library_section_id INTEGER,
  grandparent_title TEXT,
  parent_title TEXT,
  parent_index INTEGER,
  item_index INTEGER,
  title TEXT,
  viewed_at INTEGER,
  device_id INTEGER,
  view_type INTEGER
);
.mode csv
.import $watch_csv temp_watch_history

DROP TABLE IF EXISTS temp_watch_mapped;
CREATE TEMP TABLE temp_watch_mapped AS
SELECT
  COALESCE(
    (SELECT id FROM accounts WHERE id = w.account_id),
    tgt.id,
    (SELECT id FROM accounts WHERE name IS NOT NULL AND TRIM(name) != '' ORDER BY id LIMIT 1)
  ) AS account_id,
  w.account_name,
  w.metadata_type,
  w.grandparent_title,
  w.parent_title,
  w.parent_index,
  w.item_index,
  w.title,
  w.viewed_at,
  w.device_id,
  w.view_type,
  CASE
    WHEN w.metadata_type = 4 THEN (
      SELECT e.guid
      FROM metadata_items e
      JOIN metadata_items s ON s.id = e.parent_id
      JOIN metadata_items sh ON sh.id = s.parent_id
      WHERE e.metadata_type = 4
        AND sh.title = w.grandparent_title
        AND s."index" = w.parent_index
        AND e."index" = w.item_index
      LIMIT 1
    )
    WHEN w.metadata_type = 2 THEN (
      SELECT guid FROM metadata_items
      WHERE metadata_type = 2 AND title = w.title
      LIMIT 1
    )
    WHEN w.metadata_type = 1 THEN (
      SELECT guid FROM metadata_items
      WHERE metadata_type = 1 AND title = w.title
      LIMIT 1
    )
    WHEN w.metadata_type = 10 THEN (
      SELECT t.guid
      FROM metadata_items t
      JOIN metadata_items alb ON alb.id = t.parent_id
      JOIN metadata_items art ON art.id = alb.parent_id
      WHERE t.metadata_type = 10
        AND alb.metadata_type = 9
        AND art.metadata_type = 8
        AND art.title = w.grandparent_title
        AND alb.title = w.parent_title
        AND t."index" = w.item_index
      LIMIT 1
    )
    ELSE NULL
  END AS mapped_guid
FROM temp_watch_history w
LEFT JOIN accounts tgt ON tgt.name = w.account_name;

INSERT INTO metadata_item_views (
  account_id,
  guid,
  metadata_type,
  library_section_id,
  grandparent_title,
  parent_title,
  parent_index,
  "index",
  title,
  viewed_at,
  device_id,
  view_type
)
SELECT
  w.account_id,
  w.mapped_guid,
  w.metadata_type,
  mi.library_section_id,
  w.grandparent_title,
  w.parent_title,
  w.parent_index,
  w.item_index,
  w.title,
  w.viewed_at,
  w.device_id,
  w.view_type
FROM temp_watch_mapped w
JOIN metadata_items mi ON mi.guid = w.mapped_guid
WHERE w.mapped_guid IS NOT NULL;

DROP TABLE IF EXISTS temp_watch_settings;
CREATE TEMP TABLE temp_watch_settings AS
SELECT
  account_id,
  mapped_guid AS guid,
  MAX(viewed_at) AS last_viewed_at,
  COUNT(*) AS view_count
FROM temp_watch_mapped
WHERE mapped_guid IS NOT NULL
GROUP BY account_id, mapped_guid;

DELETE FROM metadata_item_settings
WHERE (account_id, guid) IN (SELECT account_id, guid FROM temp_watch_settings);

INSERT INTO metadata_item_settings (
  account_id,
  guid,
  view_offset,
  view_count,
  last_viewed_at,
  created_at,
  updated_at
)
SELECT
  account_id,
  guid,
  0,
  view_count,
  last_viewed_at,
  last_viewed_at,
  last_viewed_at
FROM temp_watch_settings;

DROP TABLE temp_watch_history;
DROP TABLE temp_watch_mapped;
DROP TABLE temp_watch_settings;
COMMIT;
SQL

echo "Done. Files saved in: $workdir"