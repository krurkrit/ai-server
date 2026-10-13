#!/usr/bin/env bash
# NAME
#     restore-stack.sh - restore one stack from a backup made by update-stack.sh
#
# SYNOPSIS
#     restore-stack.sh [-h] STACK TIMESTAMP [--sql]
#
# DESCRIPTION
#     Asks first ([y/N]), stops the stack, overwrites its volumes with the backup, and starts again
#     only the services that were running before.
#
# OPTIONS
#     -h, --help
#         Show this manual.
#     STACK
#         Stack name: the folder under /opt/stacks.
#     TIMESTAMP
#         A backup folder under /opt/backups/<stack>/, e.g. 20260926-041200.
#         List them with: ls /opt/backups/<stack>/
#     --sql
#         Also replay the pg_dumpall .sql files after restoring the volumes. Off by default: the
#         volume tarballs already hold the Postgres data, and replaying a full dump on top of them
#         only gives "already exists" errors. Use it when a volume tarball is missing or unusable.
#
# EXAMPLES
#     ls /opt/backups/outline/
#     restore-stack.sh outline 20260926-041200
#
# FILES
#     /opt/backups/<stack>/<timestamp>/
#
# SEE ALSO
#     update-stack.sh -h

# -h / --help: show the manual above (the comment block at the top of this file)
if [[ " $* " == *" -h "* || " $* " == *" --help "* ]]; then
  awk 'NR > 1 && /^$/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0" |
    if [[ -t 1 ]] && command -v less >/dev/null 2>&1; then less -FRX; else cat; fi
  exit 0
fi

set -euo pipefail

STACK="${1:-}"
TS="${2:-}"
FLAG="${3:-}"

if [[ -z "$STACK" || -z "$TS" ]]; then
  echo "Usage: $0 STACK TIMESTAMP [--sql]   (manual: $0 -h)"
  echo "Available backups for a stack: ls /opt/backups/<stack-name>/"
  exit 1
fi

STACK_DIR="/opt/stacks/$STACK"
BACKUP_DIR="/opt/backups/$STACK/$TS"

[[ -d "$STACK_DIR" ]]  || { echo "Stack directory not found: $STACK_DIR"; exit 1; }
[[ -d "$BACKUP_DIR" ]] || { echo "Backup not found: $BACKUP_DIR"; exit 1; }

cd "$STACK_DIR"

echo "This will STOP '$STACK', overwrite its volumes with the backup from $TS, then restart it."
read -rp "Continue? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]([Ee][Ss])?$ ]] || { echo "Aborted — nothing changed."; exit 0; }

# Services running right now, across every profile — only these get started again
RUNNING=$(docker compose --profile "*" ps --services --status running 2>/dev/null || true)

echo "Stopping '$STACK':"
docker compose --profile "*" down

# 1. Restore volumes from tarballs
for tarball in "$BACKUP_DIR"/*.tar.gz; do
  [[ -e "$tarball" ]] || continue
  vol=$(basename "$tarball" .tar.gz)
  if docker volume inspect "$vol" >/dev/null 2>&1; then
    FULL_VOL="$vol"
  elif docker volume inspect "${STACK}_${vol}" >/dev/null 2>&1; then
    FULL_VOL="${STACK}_${vol}"
  else
    # Guide stacks declare every volume external:true under its exact name, so create it under that name
    echo "  - volume $vol does not exist yet, creating it"
    docker volume create "$vol" >/dev/null
    FULL_VOL="$vol"
  fi
  echo "  - restoring volume: $FULL_VOL"
  docker run --rm \
    -v "${FULL_VOL}:/data" \
    -v "${BACKUP_DIR}:/backup" \
    alpine sh -c "rm -rf /data/* /data/..?* /data/.[!.]* 2>/dev/null; tar xzf /backup/$(basename "$tarball") -C /data"
done

# 2. Bring the stack back up
echo "Starting '$STACK':"
if [[ -n "$RUNNING" ]]; then
  # shellcheck disable=SC2086
  docker compose --profile "*" up -d $RUNNING
else
  docker compose up -d
fi

# 3. Optionally replay SQL dumps
if [[ "$FLAG" == "--sql" ]]; then
  echo "Replaying SQL dumps (--sql):"
  sleep 5   # give Postgres a moment to accept connections
  for sql in "$BACKUP_DIR"/*.sql; do
    [[ -e "$sql" ]] || continue
    svc=$(basename "$sql" .sql)
    echo "  - restoring database into: $svc"
    docker compose exec -T "$svc" psql -U postgres < "$sql" || \
      echo "    WARNING: restore into $svc reported errors — check output above"
  done
else
  echo "(SQL dumps not replayed — volumes already hold the data. Pass --sql to replay them.)"
fi

echo ""
echo "Restore complete. Current status:"
docker compose --profile "*" ps
echo "Verify the service before trusting this restore."
