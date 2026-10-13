#!/usr/bin/env bash
# NAME
#     docker-cleanup.sh - remove Docker leftovers safely, asking per kind
#
# SYNOPSIS
#     docker-cleanup.sh [-h] [--dry-run | --yes] [--images] [--email]
#
# DESCRIPTION
#     Lists what Docker keeps that nothing uses, one kind at a time, and asks before removing each
#     kind ([y/N]). Never touches running containers, named volumes, or the edge network, so the
#     data of every stack stays, also of stacks that are stopped right now.
#
#     The kinds, in order:
#       1. OpenHands sandboxes that have stopped (oh-agent-server-...).
#       2. Other stopped containers that belong to no Compose stack (one-off docker run leftovers).
#          Stopped stack containers (for example vLLM while Ollama runs) are kept.
#       3. Networks no container uses, except edge and the built-in ones. Compose creates a stack
#          network again on its next up -d.
#       4. Anonymous volumes (a 64-character hash as the name) that no container uses. Named
#          volumes are only listed, never removed: they are stack data (external: true).
#       5. Dangling images (old layers left by updates).
#       6. With --images: also images no container uses, including stopped ones. They download
#          again when needed, which can be large (vLLM, OpenHands sandboxes).
#       7. The build cache.
#     It shows docker system df before and after.
#
#     For cron: --yes removes without asking, and --email sends the whole report by email, through
#     the SMTP_* settings in /opt/stacks/shared/.env (or /opt/stacks/grafana/.env). With --dry-run,
#     --email is a weekly reminder of what could be removed.
#
# OPTIONS
#     -h, --help
#         Show this manual.
#     --dry-run
#         Only list what would be removed; ask nothing, change nothing.
#     --yes
#         Remove every kind found without asking (for cron). Named volumes and edge stay untouched.
#     --images
#         Also offer to remove images that no container uses (kind 6).
#     --email
#         Send the report by email when done, to CLEANUP_EMAIL_TO (default: the SMTP_USERNAME address).
#
# EXAMPLES
#     docker-cleanup.sh --dry-run
#     docker-cleanup.sh
#     docker-cleanup.sh --images
#     docker-cleanup.sh --dry-run --images --email     # weekly report, from cron
#     docker-cleanup.sh --yes --images --email         # monthly clean-up, from cron
#
# ENVIRONMENT
#     CLEANUP_EMAIL_TO   who gets the report (default: SMTP_USERNAME)
#     SMTP_ENV           file with SMTP_HOST, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD
#                        (default /opt/stacks/shared/.env, then /opt/stacks/grafana/.env)
#
# SEE ALSO
#     The Docker housekeeping step of the setup guide; update-stack.sh -h

# -h / --help: show the manual above (the comment block at the top of this file)
if [[ " $* " == *" -h "* || " $* " == *" --help "* ]]; then
  awk 'NR > 1 && /^$/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0" |
    if [[ -t 1 ]] && command -v less >/dev/null 2>&1; then less -FRX; else cat; fi
  exit 0
fi

set -euo pipefail

DRY=0; YES=0; IMAGES=0; EMAIL=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --yes) YES=1 ;;
    --images) IMAGES=1 ;;
    --email) EMAIL=1 ;;
    *) echo "Usage: $0 [--dry-run | --yes] [--images] [--email]   (manual: $0 -h)"; exit 1 ;;
  esac
done
if [[ $DRY -eq 1 && $YES -eq 1 ]]; then echo "Use --dry-run or --yes, not both"; exit 1; fi
KEEP_NETWORKS=" edge bridge host none "

# Ask once per kind; --yes answers yes, --dry-run or no terminal answers no
ask() {
  local answer=n
  if [[ $DRY -eq 1 ]]; then echo "  (--dry-run: nothing removed)"; return 1; fi
  if [[ $YES -eq 1 ]]; then echo "  (--yes: removing)"; return 0; fi
  if [[ ! -t 0 ]]; then echo "  NOTICE: no terminal to ask on; kept"; return 1; fi
  read -rp "  $1 [y/N] " answer || answer=n
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# Print the list under a heading; returns 1 when there is nothing
show() {
  local title="$1" list="$2"
  echo ""
  echo "$title:"
  if [[ -z "$list" ]]; then echo "  nothing"; return 1; fi
  printf '%s\n' "$list" | sed 's/^/  /'
}

# Value of KEY in a .env file; quotes and an inline comment dropped
env_value() {
  local v
  v=$(grep -E "^$1=" "$2" 2>/dev/null | tail -n 1 | cut -d= -f2-) || true
  v="${v%% #*}"; v="${v%"${v##*[![:space:]]}"}"
  v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"
  printf '%s' "$v"
}

# Mail the report through the SMTP settings the stacks already use
send_report() {
  local report="$1" f host port user pass to scheme=smtp
  for f in "${SMTP_ENV:-}" /opt/stacks/shared/.env /opt/stacks/grafana/.env; do
    [[ -n "$f" && -n "$(env_value SMTP_PASSWORD "$f")" ]] && break
  done
  host=$(env_value SMTP_HOST "$f"); port=$(env_value SMTP_PORT "$f")
  user=$(env_value SMTP_USERNAME "$f"); pass=$(env_value SMTP_PASSWORD "$f")
  to="${CLEANUP_EMAIL_TO:-$user}"
  if [[ -z "$host" || -z "$user" || -z "$pass" ]]; then
    echo "NOTICE: no SMTP_HOST, SMTP_USERNAME, SMTP_PASSWORD found; report not sent"; return 1
  fi
  [[ "$port" == 465 ]] && scheme=smtps
  {
    echo "From: $user"; echo "To: $to"
    echo "Subject: [$(hostname)] docker-cleanup: $([[ $DRY -eq 1 ]] && echo "could be removed" || echo "removed")"
    echo "Content-Type: text/plain; charset=utf-8"; echo ""
    cat "$report"
  } | curl -sS --ssl-reqd --url "$scheme://$host:${port:-587}" --user "$user:$pass"       --mail-from "$user" --mail-rcpt "$to" --upload-file - && echo "Report sent to $to"
}

main() {
echo "Disk use before:"
docker system df

# 1. Stopped OpenHands sandboxes
SANDBOXES=$(docker ps -a --filter name=oh-agent-server --filter status=exited --filter status=created --filter status=dead \
  --format '{{.ID}}  {{.Names}}  {{.Status}}')
if show "Stopped OpenHands sandboxes" "$SANDBOXES" && ask "Remove these sandboxes?"; then
  docker rm $(printf '%s\n' "$SANDBOXES" | awk '{print $1}') >/dev/null
  echo "  removed"
fi

# 2. Stopped containers outside every Compose stack (not sandboxes)
STRAYS=$(docker ps -a --filter status=exited --filter status=created --filter status=dead \
  --format '{{.ID}}  {{.Names}}  {{.Image}}  {{.Status}}  project={{.Label "com.docker.compose.project"}}' |
  awk '$NF == "project=" && $2 !~ /^oh-agent-server/' | sed 's/  project=$//' || true)
if show "Stopped containers outside any stack" "$STRAYS" && ask "Remove these containers (their anonymous volumes are listed next)?"; then
  docker rm $(printf '%s\n' "$STRAYS" | awk '{print $1}') >/dev/null
  echo "  removed"
fi

# 3. Networks no container uses, running or stopped
NETS=""
for n in $(docker network ls --format '{{.Name}}'); do
  [[ "$KEEP_NETWORKS" == *" $n "* ]] && continue
  [[ -n "$(docker ps -aq --filter network="$n")" ]] && continue
  NETS+="$n  ($(docker network inspect -f '{{index .Options "com.docker.network.bridge.name"}}' "$n" 2>/dev/null))"$'\n'
done
NETS=$(printf '%s' "$NETS" | sed 's/  ()$//')
if show "Networks no container uses (edge is always kept)" "$NETS" && ask "Remove these networks?"; then
  docker network rm $(printf '%s\n' "$NETS" | awk '{print $1}') >/dev/null
  echo "  removed"
fi

# 4. Volumes no container uses: anonymous ones can go, named ones are only listed
UNUSED=$(docker volume ls -q --filter dangling=true)
ANON=$(printf '%s\n' "$UNUSED" | grep -E '^[0-9a-f]{64}$' || true)
NAMED=$(printf '%s\n' "$UNUSED" | grep -vE '^[0-9a-f]{64}$' | grep -v '^$' || true)
if show "Anonymous volumes no container uses" "$ANON" && ask "Delete these volumes? Their content is gone for good."; then
  docker volume rm $ANON >/dev/null
  echo "  removed"
fi
if [[ -n "$NAMED" ]]; then
  echo ""
  echo "NOTICE: named volumes no container uses right now (kept; stack data, also of stopped or removed stacks):"
  printf '%s\n' "$NAMED" | sed 's/^/  /'
  echo "  Delete one only when its stack is gone for good: confirm \"Delete volume <name>?\" && docker volume rm <name>"
fi

# 5. Dangling images
DANGLING=$(docker image ls --filter dangling=true --format '{{.ID}}  {{.Repository}}  {{.Size}}')
if show "Dangling images (old layers)" "$DANGLING" && ask "Remove these images?"; then
  docker image prune -f >/dev/null
  echo "  removed"
fi

# 6. With --images: images no container uses, including stopped ones
if [[ $IMAGES -eq 1 ]]; then
  USED=" $(docker ps -aq | xargs -r docker inspect --format '{{.Image}}' | sort -u | tr '\n' ' ') "
  IDLE=$(docker image ls --no-trunc --format '{{.ID}}  {{.Repository}}:{{.Tag}}  {{.Size}}' |
    while read -r id rest; do [[ "$USED" == *" $id "* ]] || echo "$id  $rest"; done | grep -v '<none>' || true)
  if show "Images no container uses (they download again when needed)" "$(printf '%s\n' "$IDLE" | sed -E 's/^sha256:([0-9a-f]{12})[0-9a-f]*/\1/')" &&
     ask "Remove these images?"; then
    docker image rm $(printf '%s\n' "$IDLE" | awk '{print $1}') >/dev/null
    echo "  removed"
  fi
fi

# 7. Build cache
CACHE=$(docker system df --format '{{.Type}}  {{.Size}}  reclaimable {{.Reclaimable}}' | grep -i '^build cache' || true)
if [[ "$CACHE" == *"0B  reclaimable 0B"* ]]; then CACHE=""; fi
if show "Build cache" "$CACHE" && ask "Clear the build cache?"; then
  docker builder prune -f >/dev/null
  echo "  removed"
fi

echo ""
echo "Disk use after:"
docker system df
}

if [[ $EMAIL -eq 1 ]]; then
  REPORT=$(mktemp)
  trap 'rm -f "$REPORT"' EXIT
  main 2>&1 | tee "$REPORT"
  send_report "$REPORT"
else
  main
fi
