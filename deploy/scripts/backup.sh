#!/bin/sh
# Sauvegarde quotidienne PostgreSQL (dump compresse), rotation KEEP_DAYS jours.
set -e
ts=$(date +%Y%m%d-%H%M%S)
pg_dump --format=custom --file="/backups/studytimer-$ts.dump"
find /backups -name 'studytimer-*.dump' -mtime +"${KEEP_DAYS:-14}" -delete
echo "[backup] studytimer-$ts.dump OK"
