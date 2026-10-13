#!/usr/bin/env bash
# NAME
#     reset-stack.sh - start a stack again with empty data, keeping its configuration
#
# SYNOPSIS
#     reset-stack.sh [-h] [--dry-run] STACK
#
# DESCRIPTION
#     Gives one stack a fresh start, as on its first install: stops it, deletes every named
#     volume its compose.yaml declares (all of its data), creates them again empty, and starts
#     the stack. compose.yaml, .env, and config files in /opt/stacks/<stack> stay, so the stack
#     comes back with the same settings and secrets.
#
#     Meant for stacks whose data you can lose, e.g. Langfuse (all traces gone; its first start
#     creates the admin user, project, and API keys again from .env, so LiteLLM keeps working).
#     Asks you to type the stack name before deleting anything. Without a terminal it stops.
#
#     Only the services that were running are started again (in llm-runtime and graphdb, only
#     the active profile); a stack that was stopped is started with its default services.
#
# OPTIONS
#     -h, --help
#         Show this manual.
#     --dry-run
#         Show the volumes that would be emptied; change nothing.
#     STACK
#         Stack name: the folder under /opt/stacks.
#
# EXAMPLES
#     reset-stack.sh --dry-run langfuse
#     reset-stack.sh langfuse
#
# FILES
#     /opt/stacks/<stack>/compose.yaml
#
# ENVIRONMENT
#     STACKS_DIR    stacks folder (default /opt/stacks)
#
# SEE ALSO
#     update-stack.sh -h, backup-config.sh -h

# -h / --help: show the manual above (the comment block at the top of this file)
if [[ " $* " == *" -h "* || " $* " == *" --help "* ]]; then
  awk 'NR > 1 && /^$/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0" |
    if [[ -t 1 ]] && command -v less >/dev/null 2>&1; then less -FRX; else cat; fi
  exit 0
fi

set -euo pipefail

DRY=0; STACK=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -*) echo "Usage: $0 [--dry-run] STACK   (manual: $0 -h)"; exit 1 ;;
    *) [[ -z "$STACK" ]] || { echo "Usage: $0 [--dry-run] STACK   (manual: $0 -h)"; exit 1; }; STACK="$a" ;;
  esac
done
[[ -n "$STACK" ]] || { echo "Usage: $0 [--dry-run] STACK   (manual: $0 -h)"; exit 1; }

STACKS_DIR="${STACKS_DIR:-/opt/stacks}"
DIR="$STACKS_DIR/$STACK"
[[ -f "$DIR/compose.yaml" ]] || { echo "No compose.yaml in $DIR"; exit 1; }
cd "$DIR"

RUNNING=$(docker compose --profile "*" ps --services --status running 2>/dev/null || true)
VOLUMES=()
for v in $(docker compose --profile "*" config --volumes 2>/dev/null); do
  if docker volume inspect "$v" >/dev/null 2>&1; then VOLUMES+=("$v")
  elif docker volume inspect "${STACK}_${v}" >/dev/null 2>&1; then VOLUMES+=("${STACK}_${v}")
  else VOLUMES+=("$v"); fi
done

echo ""
echo "$STACK:"
if [[ ${#VOLUMES[@]} -eq 0 ]]; then echo "  no named volumes: nothing to empty"; exit 0; fi
for v in "${VOLUMES[@]}"; do
  size=$(docker system df -v --format '{{range .Volumes}}{{.Name}} {{.Size}}{{"\n"}}{{end}}' 2>/dev/null | awk -v n="$v" '$1 == n {print $2}')
  echo "  empty volume: $v${size:+  ($size)}"
done
echo "  keep: compose.yaml, .env, and the other files in $DIR"
echo "  start again: ${RUNNING:-default services}" | tr '\n' ' '; echo ""

if [[ $DRY -eq 1 ]]; then echo ""; echo "(--dry-run: nothing changed)"; exit 0; fi
if [[ ! -t 0 ]]; then echo "NOTICE: no terminal to confirm on; nothing changed"; exit 1; fi

echo ""
read -rp "All data of $STACK is deleted for good. Type the stack name to go on: " answer || answer=""
[[ "$answer" == "$STACK" ]] || { echo "Aborted; nothing changed."; exit 1; }

echo ""
echo "Stopping $STACK:"
docker compose --profile "*" down
echo "Emptying volumes:"
for v in "${VOLUMES[@]}"; do
  docker volume rm "$v" >/dev/null 2>&1 || true
  docker volume create "$v" >/dev/null
  echo "  $v"
done
echo "Starting $STACK:"
if [[ -n "$RUNNING" ]]; then
  # shellcheck disable=SC2086
  docker compose --profile "*" up -d $RUNNING
else
  docker compose up -d
fi
echo ""
echo "Done. $STACK starts as on its first install; first starts can take a few minutes."
