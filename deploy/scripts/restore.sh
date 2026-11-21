#!/bin/sh
# Restauration : ./deploy/scripts/restore.sh backups/studytimer-AAAAMMJJ-HHMMSS.dump
set -e
[ -f "$1" ] || { echo "Usage: $0 <fichier.dump>"; exit 1; }
docker compose exec -T db pg_restore -U studyuser -d studytimer --clean --if-exists < "$1"
echo "Restauration terminee."
