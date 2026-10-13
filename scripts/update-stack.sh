#!/usr/bin/env bash
# NAME
#     update-stack.sh - back up, then update one Docker Compose stack
#
# SYNOPSIS
#     update-stack.sh [-h] STACK [--skip-backup]
#
# DESCRIPTION
#     Backs up the stack, pulls newer images, and recreates it. The backup holds a pg_dumpall .sql
#     file for each running Postgres service and a .tar.gz of each named volume.
#     Only the services that were running before are started again, so in llm-runtime and graphdb
#     Ollama and vLLM stay mutually exclusive.
#
# OPTIONS
#     -h, --help
#         Show this manual.
#     STACK
#         Stack name: the folder under /opt/stacks.
#     --skip-backup
#         Update without making a backup first.
#
# EXAMPLES
#     update-stack.sh outline
#     update-stack.sh llm-runtime --skip-backup
#
# FILES
#     /opt/stacks/<stack>/compose.yaml
#     /opt/backups/<stack>/<timestamp>/   the backup
#
# SEE ALSO
#     restore-stack.sh -h, the update workflow step of the setup guide

# -h / --help: show the manual above (the comment block at the top of this file)
if [[ " $* " == *" -h "* || " $* " == *" --help "* ]]; then
  awk 'NR > 1 && /^$/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0" |
    if [[ -t 1 ]] && command -v less >/dev/null 2>&1; then less -FRX; else cat; fi
  exit 0
fi

set -euo pipefail

STACK="${1:-}"
FLAG="${2:-}"

if [[ -z "$STACK" ]]; then
  echo "Usage: $0 STACK [--skip-backup]   (manual: $0 -h)"
  exit 1
fi

STACK_DIR="/opt/stacks/$STACK"
BACKUP_DIR="/opt/backups/$STACK/$(date +%Y%m%d-%H%M%S)"

if [[ ! -d "$STACK_DIR" ]]; then
  echo "Stack directory not found: $STACK_DIR"
  exit 1
fi

cd "$STACK_DIR"

# Services running right now, across every profile — only these get restarted after the pull
RUNNING=$(docker compose --profile "*" ps --services --status running 2>/dev/null || true)

if [[ "$FLAG" != "--skip-backup" ]]; then
  mkdir -p "$BACKUP_DIR"
  echo "Backing up '$STACK' to $BACKUP_DIR:"

  # 1. Dump any Postgres databases running in this stack
  for svc in $RUNNING; do
    IMAGE=$(docker compose --profile "*" config 2>/dev/null | awk -v s="$svc" '
      $0 ~ "^  "s":" {found=1}
      found && /image:/ {print $2; exit}
    ')
    if [[ "$IMAGE" == postgres:* ]]; then
      echo "  - pg_dumpall: $svc"
      if ! docker compose exec -T "$svc" pg_dumpall -U postgres > "$BACKUP_DIR/${svc}.sql" 2>/dev/null; then
        echo "    WARNING: pg_dumpall failed for $svc — check POSTGRES_USER matches (default assumed: postgres)"
        rm -f "$BACKUP_DIR/${svc}.sql"
      fi
    fi
  done

  # 2. Tar every named volume declared in this stack
  for vol in $(docker compose --profile "*" config --volumes 2>/dev/null); do
    if docker volume inspect "$vol" >/dev/null 2>&1; then
      FULL_VOL="$vol"                     # external:true volumes keep their exact name
    elif docker volume inspect "${STACK}_${vol}" >/dev/null 2>&1; then
      FULL_VOL="${STACK}_${vol}"          # default compose naming: <project>_<volume>
    else
      echo "  - (volume for '$vol' not found, skipping)"
      continue
    fi
    echo "  - tar volume: $FULL_VOL"
    docker run --rm \
      -v "${FULL_VOL}:/data:ro" \
      -v "${BACKUP_DIR}:/backup" \
      alpine tar czf "/backup/${vol}.tar.gz" -C /data .
  done

  echo "Backup complete: $BACKUP_DIR"
else
  echo "Skipping backup (--skip-backup passed)"
fi

echo ""
echo "Pulling latest images for '$STACK' (all profiles):"
docker compose --profile "*" pull

echo "Recreating containers:"
if [[ -n "$RUNNING" ]]; then
  # shellcheck disable=SC2086
  docker compose --profile "*" up -d $RUNNING
else
  docker compose up -d
fi

echo ""
echo "Current status:"
docker compose --profile "*" ps

echo ""
echo "Done. Verify the service works correctly before deleting the backup."
if [[ "$FLAG" != "--skip-backup" ]]; then
  echo "Backup location: $BACKUP_DIR"
fi
