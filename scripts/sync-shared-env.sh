#!/usr/bin/env bash
# NAME
#     sync-shared-env.sh - copy SERVER_HOST and SERVER_IP into every stack .env
#
# SYNOPSIS
#     sync-shared-env.sh [-h] [--dry-run] [--debug]
#
# DESCRIPTION
#     Reads SERVER_HOST and SERVER_IP from /opt/stacks/shared/.env and updates them in every
#     /opt/stacks/*/.env that already has them. No line is ever added, and an inline comment after
#     a value stays. Shows each change (old -> new), asks once ([y/N]), saves each old file as
#     .env.bak-<timestamp>, and recreates only the stacks that changed (in llm-runtime and graphdb,
#     only the services that were running). When Caddy is recreated, it checks Caddy health.
#
#     With Infisical, pull-secrets.sh runs this script at the end, for stacks without a folder in
#     Infisical.
#
# OPTIONS
#     -h, --help
#         Show this manual.
#     --dry-run
#         Show what would change, change nothing.
#     --debug
#         Also explain each step on stderr: the shared values, every stack and key, and why a stack
#         is skipped. SERVER_HOST and SERVER_IP are not secret, so they are shown.
#
# EXAMPLES
#     sync-shared-env.sh --dry-run
#     sync-shared-env.sh
#
# FILES
#     /opt/stacks/shared/.env   the shared values (the only place to edit them without Infisical)
#
# ENVIRONMENT
#     STACKS_DIR         stacks folder (default /opt/stacks)
#     SHARED_ENV         file to read the shared values from (set by pull-secrets.sh)
#     SYNC_SKIP_STACKS   stacks to leave alone (set by pull-secrets.sh: the ones it writes)
#
# SEE ALSO
#     pull-secrets.sh -h, the shared settings step of the setup guide

# -h / --help: show the manual above (the comment block at the top of this file)
if [[ " $* " == *" -h "* || " $* " == *" --help "* ]]; then
  awk 'NR > 1 && /^$/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0" |
    if [[ -t 1 ]] && command -v less >/dev/null 2>&1; then less -FRX; else cat; fi
  exit 0
fi

set -euo pipefail

STACKS_DIR="${STACKS_DIR:-/opt/stacks}"
SHARED="${SHARED_ENV:-$STACKS_DIR/shared/.env}"
KEYS=(SERVER_HOST SERVER_IP)
# Deployment order of the guide; stacks found on disk but not listed here are handled last
ORDER=(caddy infisical dex outline portainer grafana prometheus node-exporter dcgm-exporter sourcebot langfuse litellm llm-runtime qdrant graphdb openhands open-webui github-runner)
read -r -a SKIP_STACKS <<< "${SYNC_SKIP_STACKS:-}"

DRY=0; DEBUG=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --debug) DEBUG=1 ;;
    *) echo "Unknown option: $a"; exit 1 ;;
  esac
done

# Debug lines go to stderr, prefixed
dbg() { if [[ $DEBUG -eq 1 ]]; then echo "[debug] $*" >&2; fi; }

[[ -f "$SHARED" ]] || { echo "Not found: $SHARED"; exit 1; }

# Value of KEY in a .env file: last assignment wins; an inline " # comment" and outer quotes are dropped
env_value() {
  local v
  v=$(grep -E "^$1=" "$2" | tail -n 1 | cut -d= -f2-) || true
  v="${v%% #*}"
  v="${v%"${v##*[![:space:]]}"}"
  v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"
  printf '%s' "$v"
}

dbg "script: $(readlink -f "$0")"
dbg "stacks directory: $STACKS_DIR"
dbg "shared settings read from: $SHARED"
VALUES=()
for k in "${KEYS[@]}"; do
  v=$(env_value "$k" "$SHARED")
  [[ -n "$v" ]] || { echo "$k is missing or empty in $SHARED"; exit 1; }
  VALUES+=("$k=$v")
done
echo "Shared settings:"; printf '  %s\n' "${VALUES[@]}"

# Stacks in guide order, then any others that have a .env
STACKS=()
for s in "${ORDER[@]}"; do [[ -f "$STACKS_DIR/$s/.env" ]] && STACKS+=("$s"); done
for f in "$STACKS_DIR"/*/.env; do
  [[ -f "$f" ]] || continue
  s=$(basename "$(dirname "$f")")
  [[ "$s" == "shared" ]] && continue
  [[ " ${STACKS[*]} " == *" $s "* ]] || STACKS+=("$s")
done
dbg "stacks with a .env: ${STACKS[*]:-none}"
[[ ${#SKIP_STACKS[@]} -gt 0 ]] && dbg "left alone (written by pull-secrets.sh): ${SKIP_STACKS[*]}"

# Build the new version of each .env in a temp file and collect the ones that differ
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CHANGED=()
for s in "${STACKS[@]}"; do
  if [[ " ${SKIP_STACKS[*]} " == *" $s "* ]]; then
    dbg "$s: skipped, pull-secrets.sh writes this .env"
    continue
  fi
  f="$STACKS_DIR/$s/.env"
  cp "$f" "$TMP/$s.env"
  lines=()
  for kv in "${VALUES[@]}"; do
    k="${kv%%=*}"; v="${kv#*=}"
    if ! grep -qE "^$k=" "$f"; then
      dbg "  $s: $k not in this .env (nothing added)"
      continue
    fi
    cur=$(env_value "$k" "$f")
    if [[ "$cur" == "$v" ]]; then
      dbg "  $s: $k same"
      continue
    fi
    dbg "  $s: $k changed"
    lines+=("  changed: $k ($cur -> $v)")
    # Replace the value, keep any inline comment and the spacing before it
    awk -v k="$k" -v v="$v" '
      index($0, k "=") == 1 {
        rest = substr($0, length(k) + 2)
        suffix = match(rest, /[ \t]+#/) ? substr(rest, RSTART) : ""
        print k "=" v suffix
        next
      }
      { print }
    ' "$TMP/$s.env" > "$TMP/$s.new" && mv "$TMP/$s.new" "$TMP/$s.env"
  done
  if [[ ${#lines[@]} -gt 0 ]]; then
    CHANGED+=("$s")
    echo ""
    echo "$s:"
    printf '%s\n' "${lines[@]}"
    dbg "$s: WILL UPDATE .env"
  else
    dbg "$s: no update, .env already matches"
  fi
done

echo ""
if [[ ${#CHANGED[@]} -eq 0 ]]; then
  echo "Every .env already matches the shared settings. Nothing to do."
  exit 0
fi

echo "To update: ${CHANGED[*]}"
if [[ $DRY -eq 1 ]]; then
  echo "(--dry-run: nothing changed)"
  exit 0
fi
read -rp "Write these .env files and recreate the changed stacks? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]([Ee][Ss])?$ ]] || { echo "Aborted, nothing changed."; exit 0; }

TS=$(date +%Y%m%d-%H%M%S)
RECREATED=()
for s in "${CHANGED[@]}"; do
  cp -p "$STACKS_DIR/$s/.env" "$STACKS_DIR/$s/.env.bak-$TS"
  cat "$TMP/$s.env" > "$STACKS_DIR/$s/.env"   # cat keeps the original file permissions
  echo ""
  echo "Recreating $s:"
  RUNNING=$(cd "$STACKS_DIR/$s" && docker compose --profile "*" ps --services --status running 2>/dev/null || true)
  if [[ -z "$RUNNING" ]]; then
    echo "  nothing running; the new values apply at its next start"
    continue
  fi
  # shellcheck disable=SC2086
  (cd "$STACKS_DIR/$s" && docker compose --profile "*" up -d $RUNNING)
  RECREATED+=("$s")
done

if [[ " ${RECREATED[*]} " == *" caddy "* ]]; then
  IP=$(env_value SERVER_IP "$SHARED")
  echo ""
  echo "Caddy health check:"
  sleep 3
  echo "  $(curl -ks "https://$IP:9500" || echo "failed; see docker logs caddy")"
fi

echo ""
echo "Done. Old files are saved as .env.bak-$TS; delete them once everything works."
