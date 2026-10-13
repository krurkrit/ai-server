#!/usr/bin/env bash
# NAME
#     backup-config.sh - back up what it takes to reinstall the server, not its data volumes
#
# SYNOPSIS
#     backup-config.sh [-h] [--dry-run] [--keep N]
#
# DESCRIPTION
#     For a development server whose volumes are not backed up: saves everything needed to set
#     the services up again, plus the two databases that are hard to recreate. Into
#     /opt/backups/config/<timestamp>/:
#       stacks.tar.gz      every file in /opt/stacks: compose.yaml, .env, configs, Caddy files,
#                          the internal CA certificate, pull.env (no volumes)
#       scripts.tar.gz     the helper scripts in ~/ai-server
#       system.tar.gz      /etc/docker/daemon.json, and the ufw rules if present
#       crontab.txt        your crontab (the cleanup and backup jobs)
#       infisical.sql.gz   Infisical database (all secrets; encrypted with its encryption key,
#                          which is in stacks.tar.gz, infisical/.env)
#       outline.sql.gz     Outline database (documents and users; uploaded files stay in the
#                          outline_data volume and are not included)
#     A database whose container is not running is skipped with a NOTICE.
#
#     The backup holds every secret of the server: the folder is readable by you only. Copy it
#     off the server (a NAS, another PC); a backup on the same disk does not survive the disk.
#     Old backups beyond --keep are deleted.
#
# OPTIONS
#     -h, --help
#         Show this manual.
#     --dry-run
#         Show what would be saved and deleted; change nothing.
#     --keep N
#         Keep the newest N backups (default 14).
#
# EXAMPLES
#     backup-config.sh --dry-run
#     backup-config.sh
#     backup-config.sh --keep 30
#
# FILES
#     /opt/backups/config/<timestamp>/
#
# ENVIRONMENT
#     STACKS_DIR    stacks folder (default /opt/stacks)
#     BACKUP_ROOT   where backups go (default /opt/backups/config)
#
# SEE ALSO
#     update-stack.sh -h, reset-stack.sh -h, the Update workflow step of the setup guide

# -h / --help: show the manual above (the comment block at the top of this file)
if [[ " $* " == *" -h "* || " $* " == *" --help "* ]]; then
  awk 'NR > 1 && /^$/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0" |
    if [[ -t 1 ]] && command -v less >/dev/null 2>&1; then less -FRX; else cat; fi
  exit 0
fi

set -euo pipefail

DRY=0; KEEP=14
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --keep) [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || { echo "Usage: $0 [--dry-run] [--keep N]   (manual: $0 -h)"; exit 1; }; KEEP="$2"; shift ;;
    *) echo "Usage: $0 [--dry-run] [--keep N]   (manual: $0 -h)"; exit 1 ;;
  esac
  shift
done

STACKS_DIR="${STACKS_DIR:-/opt/stacks}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/backups/config}"
DEST="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
# Databases worth keeping on a development server: container name and output file
DBS=("infisical-postgres|infisical" "outline-postgres|outline")

echo "Backup to $DEST:"
if [[ $DRY -eq 1 ]]; then
  echo "  stacks.tar.gz    $STACKS_DIR ($(du -sh "$STACKS_DIR" 2>/dev/null | cut -f1))"
  echo "  scripts.tar.gz   $HOME/ai-server"
  echo "  system.tar.gz    /etc/docker/daemon.json, /etc/ufw (if present)"
  echo "  crontab.txt"
  for d in "${DBS[@]}"; do
    c=${d%%|*}
    if [[ -n "$(docker ps -q --filter name="^${c}$")" ]]; then echo "  ${d#*|}.sql.gz"; else echo "  NOTICE: $c is not running; would be skipped"; fi
  done
else
  mkdir -p "$DEST"
  chmod 700 "$BACKUP_ROOT" "$DEST"
  # Some files under /opt/stacks belong to containers (root); sudo reads them when needed
  if tar czf "$DEST/stacks.tar.gz" -C "$(dirname "$STACKS_DIR")" "$(basename "$STACKS_DIR")" 2>/dev/null; then
    echo "  stacks.tar.gz"
  else
    sudo tar czf "$DEST/stacks.tar.gz" -C "$(dirname "$STACKS_DIR")" "$(basename "$STACKS_DIR")" && sudo chown "$(id -u):$(id -g)" "$DEST/stacks.tar.gz"
    echo "  stacks.tar.gz (read with sudo)"
  fi
  if [[ -d "$HOME/ai-server" ]]; then tar czf "$DEST/scripts.tar.gz" -C "$HOME" ai-server && echo "  scripts.tar.gz"; fi
  SYSTEM=()
  for f in /etc/docker/daemon.json /etc/ufw; do [[ -e "$f" ]] && SYSTEM+=("${f#/}"); done
  if [[ ${#SYSTEM[@]} -gt 0 ]]; then
    sudo tar czf "$DEST/system.tar.gz" -C / "${SYSTEM[@]}" && sudo chown "$(id -u):$(id -g)" "$DEST/system.tar.gz" && echo "  system.tar.gz"
  fi
  crontab -l > "$DEST/crontab.txt" 2>/dev/null && echo "  crontab.txt" || echo "  (no crontab)"
  for d in "${DBS[@]}"; do
    c=${d%%|*}; out="$DEST/${d#*|}.sql.gz"
    if [[ -z "$(docker ps -q --filter name="^${c}$")" ]]; then
      echo "  NOTICE: $c is not running; its database was not saved"
      continue
    fi
    if docker exec "$c" pg_dumpall -U postgres | gzip > "$out"; then
      echo "  ${d#*|}.sql.gz"
    else
      rm -f "$out"; echo "  NOTICE: pg_dumpall failed for $c"
    fi
  done
  chmod -R go-rwx "$DEST"
  echo "  size: $(du -sh "$DEST" | cut -f1)"
fi

# Keep the newest KEEP backups
OLD=$(ls -1d "$BACKUP_ROOT"/[0-9]*-[0-9]* 2>/dev/null | sort | head -n -"$KEEP" || true)
if [[ -n "$OLD" ]]; then
  echo ""
  if [[ $DRY -eq 1 ]]; then echo "Would delete (older than the newest $KEEP):"; else echo "Deleted (older than the newest $KEEP):"; fi
  printf '%s\n' "$OLD" | sed 's/^/  /'
  if [[ $DRY -eq 0 ]]; then printf '%s\n' "$OLD" | xargs -r rm -rf; fi
fi
if [[ $DRY -eq 1 ]]; then echo ""; echo "(--dry-run: nothing changed)"; fi
