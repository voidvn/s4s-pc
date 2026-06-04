#!/bin/sh
set -eu
# OpenSnitch has no built-in retention — prune connection events older than
# ~26 weeks (182 days) from the file-backed SQLite DB.
DB=/var/lib/opensnitchd/opensnitch.db
[ -f "$DB" ] || exit 0
# Table is 'connections' on current schemas; ignore errors if it differs.
sqlite3 "$DB" "DELETE FROM connections WHERE time < datetime('now','-182 days');" 2>/dev/null || true
sqlite3 "$DB" "VACUUM;" 2>/dev/null || true
exit 0
