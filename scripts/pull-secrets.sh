#!/usr/bin/env bash
# NAME
#     pull-secrets.sh - write each stack .env from Infisical, then recreate the stacks that changed
#
# SYNOPSIS
#     pull-secrets.sh [-h] [--dry-run] [--debug] [--env ENV] [--ask-remove | --force-remove]
#                     [--stack NAME[,NAME...]] [STACK ...]
#
# DESCRIPTION
#     Matches every stack .env to Infisical: folder ENV:/shared plus folder ENV:/<stack>. When a key is in
#     both, the stack folder wins (a NOTICE says so when the values differ). Only stacks that have
#     a folder in Infisical are touched; the others keep their hand-written .env.
#     Keys from ENV:/shared only update a .env that already has them; they are never added (a new
#     .env gets them all).
#
#     Folders in Infisical are written ENV:/PATH: folder PATH in Infisical environment ENV, e.g.
#     prod:/outline is folder /outline in environment prod. ENV is --env, else INFISICAL_ENV in
#     pull.env, else prod. Folders on the server always start with /opt/.
#
#     An existing .env is edited in place: line order, comments, and blank lines stay. A changed
#     value is replaced on its own line (an inline comment after it stays), a removed key loses
#     only its line, and new keys are added at the end under "# Added by pull-secrets.sh".
#     Values with only plain characters are written unquoted; others as KEY='value'.
#
#     /opt/stacks/shared/.env is matched to ENV:/shared. At the end, sync-shared-env.sh runs (with the
#     same --dry-run and --debug) for stacks without a folder, so they follow ENV:/shared too.
#
#     Infisical fills in secret references in values, e.g. ${prod.shared.SMTP_USERNAME}. It also
#     treats a $ elsewhere in a value as a variable, so keep $ out of secret values.
#
#     SMTP_CONNECTION_URL (Langfuse email) is built, not copied: when a stack .env has that line
#     and ENV:/<stack> does not set it, it becomes smtp://USER:PASSWORD@HOST:PORT from SMTP_USERNAME,
#     SMTP_PASSWORD, SMTP_HOST, and SMTP_PORT (ENV:/<stack> first, then ENV:/shared), with the @ of
#     the address written as %40 (smtps:// for port 465). A URL set in ENV:/<stack>, also one made
#     of references like smtp://${prod.shared.SMTP_USERNAME}:..., is kept with the @ of its address
#     written as %40. A new password in ENV:/shared then updates it too.
#
#     The infisical stack works like the others, except its start keys INFISICAL_DB_PASSWORD,
#     INFISICAL_ENCRYPTION_KEY, and INFISICAL_AUTH_SECRET: they are always kept from the current
#     file and never taken from, changed by, or removed because of Infisical.
#
#     Before writing it asks once for everything ([y/N]), saves each old file as
#     .env.bak-<timestamp>, and recreates only the stacks that changed (in llm-runtime and graphdb,
#     only the services that were running). Output never shows secret values.
#
# OPTIONS
#     -h, --help
#         Show this manual.
#     --dry-run
#         Show which keys would change, by name only, and change nothing.
#     --debug
#         Also explain each step on stderr: settings, login, folders, why a stack is skipped, and
#         per key where it comes from and whether the .env will be updated. Safe to share.
#     --env ENV
#         Read Infisical environment ENV (its slug, e.g. staging) for this run, instead of
#         INFISICAL_ENV in pull.env (default prod). It writes the same .env files, so try it with
#         --dry-run first.
#     --stack NAME[,NAME...]
#         Only these stacks; repeat it or use commas. Plain names after the options do the same.
#         A stack without a directory in /opt/stacks is skipped. sync-shared-env.sh is not run.
#     --ask-remove
#         Ask about each key that is no longer in Infisical ([y/N]); only y removes its line.
#         Without a terminal to ask on, the keys are kept.
#     --force-remove
#         Remove keys that are no longer in Infisical without asking.
#     Default for keys no longer in Infisical: kept, and listed in a NOTICE.
#
# EXAMPLES
#     pull-secrets.sh --dry-run
#     pull-secrets.sh --dry-run --debug 2>&1 | tee /tmp/pull-debug.txt
#     pull-secrets.sh --stack outline,grafana
#     pull-secrets.sh --env staging --dry-run
#     pull-secrets.sh --ask-remove
#
# FILES
#     /opt/stacks/infisical/pull.env    machine login: INFISICAL_CLIENT_ID, INFISICAL_CLIENT_SECRET,
#                                       INFISICAL_PROJECT_ID, INFISICAL_ENV (default prod)
#     /opt/stacks/<stack>/.env          the files it edits
#     /opt/stacks/shared/sync-shared-env.sh
#
# ENVIRONMENT
#     STACKS_DIR         stacks folder (default /opt/stacks)
#     INFISICAL_DOMAIN   Infisical address for the CLI (default http://infisical:8080)
#
# SEE ALSO
#     sync-shared-env.sh -h, the Infisical step of the setup guide

# -h / --help: show the manual above (the comment block at the top of this file)
if [[ " $* " == *" -h "* || " $* " == *" --help "* ]]; then
  awk 'NR > 1 && /^$/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0" |
    if [[ -t 1 ]] && command -v less >/dev/null 2>&1; then less -FRX; else cat; fi
  exit 0
fi

set -euo pipefail

STACKS_DIR="${STACKS_DIR:-/opt/stacks}"
CONF="$STACKS_DIR/infisical/pull.env"
DOMAIN="${INFISICAL_DOMAIN:-http://infisical:8080}"
CLI_IMAGE="infisical/cli:latest"
# Deployment order of the guide; stacks found on disk but not listed here are handled last
ORDER=(caddy infisical dex outline portainer grafana prometheus node-exporter dcgm-exporter sourcebot langfuse litellm llm-runtime qdrant graphdb openhands open-webui github-runner)
SKIP=(shared)

DRY=0; DEBUG=0; REMOVE_MODE=ignore; ASKED=(); ENV_OPT=""
add_stacks() { local IFS=,; for x in $1; do [[ -n "$x" ]] && ASKED+=("$x"); done; return 0; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --debug) DEBUG=1 ;;
    --ask-remove) [[ $REMOVE_MODE == force ]] && { echo "Use --ask-remove or --force-remove, not both"; exit 1; }; REMOVE_MODE=ask ;;
    --force-remove) [[ $REMOVE_MODE == ask ]] && { echo "Use --ask-remove or --force-remove, not both"; exit 1; }; REMOVE_MODE=force ;;
    --env) [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { echo "--env needs an environment slug, e.g. --env staging"; exit 1; }; ENV_OPT="$2"; shift ;;
    --env=*) ENV_OPT="${1#--env=}"; [[ -n "$ENV_OPT" ]] || { echo "--env needs an environment slug, e.g. --env staging"; exit 1; } ;;
    --stack) [[ $# -ge 2 ]] || { echo "--stack needs a stack name"; exit 1; }; add_stacks "$2"; shift ;;
    --stack=*) add_stacks "${1#--stack=}" ;;
    -*) echo "Unknown option: $1"; exit 1 ;;
    *) add_stacks "$1" ;;
  esac
  shift
done

# Debug lines go to stderr, prefixed, and never contain secret values
dbg() { if [[ $DEBUG -eq 1 ]]; then echo "[debug] $*" >&2; fi; }
# Key names of a .env file on one line (values are never shown)
names_of() { grep -oE "^[A-Za-z_][A-Za-z0-9_]*=" "$1" 2>/dev/null | tr -d = | paste -sd' ' || true; }

dbg "script: $(readlink -f "$0")"
dbg "stacks directory: $STACKS_DIR"
dbg "Infisical address: $DOMAIN"
dbg "CLI image: $CLI_IMAGE"
[[ -f "$CONF" ]] || { echo "Not found: $CONF (create it in the Infisical step)"; exit 1; }
dbg "pull.env: $CONF (mode $(stat -c '%a, owner %U' "$CONF"); keys: $(names_of "$CONF"))"

# Value of KEY in a .env file: last assignment wins; an inline " # comment" and outer quotes are dropped
env_value() {
  local v
  v=$(grep -E "^$1=" "$2" | tail -n 1 | cut -d= -f2-) || true
  v="${v%% #*}"
  v="${v%"${v##*[![:space:]]}"}"
  v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"
  printf '%s' "$v"
}

# pull.env uses short names; the Infisical CLI reads its login only from the
# INFISICAL_UNIVERSAL_AUTH_* names, so the values are passed on under those.
for k in INFISICAL_CLIENT_ID INFISICAL_CLIENT_SECRET INFISICAL_PROJECT_ID; do
  [[ -n "$(env_value "$k" "$CONF")" ]] || { echo "$k is missing or empty in $CONF"; exit 1; }
done
INFISICAL_UNIVERSAL_AUTH_CLIENT_ID=$(env_value INFISICAL_CLIENT_ID "$CONF")
INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET=$(env_value INFISICAL_CLIENT_SECRET "$CONF")
PROJECT_ID=$(env_value INFISICAL_PROJECT_ID "$CONF")
# Environment: --env, else INFISICAL_ENV in pull.env, else prod
if [[ -n "$ENV_OPT" ]]; then ENV_SLUG="$ENV_OPT"; ENV_FROM="--env"
else ENV_SLUG=$(env_value INFISICAL_ENV "$CONF"); ENV_FROM="INFISICAL_ENV in pull.env"; fi
if [[ -z "$ENV_SLUG" ]]; then ENV_SLUG=prod; ENV_FROM="default"; fi
export INFISICAL_UNIVERSAL_AUTH_CLIENT_ID INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET
dbg "client ID: ${INFISICAL_UNIVERSAL_AUTH_CLIENT_ID:0:4}... (${#INFISICAL_UNIVERSAL_AUTH_CLIENT_ID} characters)"
dbg "client secret: ${#INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET} characters (value hidden)"
dbg "project ID: $PROJECT_ID"
dbg "environment slug: $ENV_SLUG (from $ENV_FROM)"
if [[ $DEBUG -eq 1 ]]; then
  if docker network inspect edge >/dev/null 2>&1; then dbg "network edge: exists"; else dbg "network edge: MISSING (the CLI container cannot reach Infisical)"; fi
  dbg "infisical container: $(docker inspect -f '{{.State.Status}}' infisical 2>/dev/null || echo 'not found')"
fi

# Run the Infisical CLI in a throwaway container on the edge network (plain HTTP to the infisical
# container, so the internal CA is not needed). Credentials pass as environment, never as arguments.
cli() {
  docker run --rm --network edge -e INFISICAL_DOMAIN="$DOMAIN" \
    -e INFISICAL_UNIVERSAL_AUTH_CLIENT_ID -e INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET -e INFISICAL_TOKEN \
    "$CLI_IMAGE" "$@" --silent --telemetry=false
}

if [[ $DEBUG -eq 1 ]]; then
  dbg "CLI version: $(docker run --rm "$CLI_IMAGE" --version 2>&1 | head -n 1)"
fi
INFISICAL_TOKEN=$(cli login --method=universal-auth --plain) || { echo "Infisical login failed; check $CONF and that the infisical container runs"; exit 1; }
export INFISICAL_TOKEN
dbg "login: OK, access token received (${#INFISICAL_TOKEN} characters, value hidden)"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Export one Infisical folder as dotenv (KEY='value' lines). The CLI fills in secret references
# such as ${prod.shared.KEY} (its default, --expand=true).
pull_folder() {
  local rc=0 env="$ENV_SLUG"
  cli export --projectId="$PROJECT_ID" --env="$env" --path="$1" --format=dotenv --expand=true > "$2" 2> "$2.err" || rc=$?
  if [[ $rc -eq 0 ]]; then
    # The CLI quotes every value (KEY='value'). Drop the quotes when the value has only characters
    # Compose leaves alone; keep them when it has $, #, spaces, quotes, or anything else special.
    sed -E -i "s/^([A-Za-z_][A-Za-z0-9_]*)='([A-Za-z0-9_.\/:@%+,=-]*)'\$/\1=\2/" "$2"
    dbg "folder $env:$1: $(grep -cE '^[A-Za-z_]' "$2" || true) keys: $(names_of "$2")"
  else
    dbg "folder $env:$1: cannot read (exit $rc): $(head -n 3 "$2.err" | paste -sd' ')"
  fi
  return $rc
}

# Key names in a .env file
keys_of() { grep -oE "^[A-Za-z_][A-Za-z0-9_]*=" "$1" 2>/dev/null | tr -d = | sort -u || true; }

pull_folder /shared "$TMP/shared.env" || { echo "Cannot read folder $ENV_SLUG:/shared in Infisical:"; cat "$TMP/shared.env.err"; exit 1; }

# Key names whose value differs between two .env files (quotes ignored)
changed_keys() {
  local k
  for k in $(comm -12 <(keys_of "$1") <(keys_of "$2")); do
    [[ "$(env_value "$k" "$1")" == "$(env_value "$k" "$2")" ]] || echo "$k"
  done
}

# Key names in the first file but not in the second
removed_keys() { comm -23 <(keys_of "$1") <(keys_of "$2"); }

# By default: list the keys that stay although they are not in Infisical
note_ignored() {
  local gone
  [[ $REMOVE_MODE == ignore && -f "$2" ]] || return 0
  gone=$(removed_keys "$2" "$3" | paste -sd' ')
  [[ -z "$gone" ]] || echo "NOTICE: $1: $gone not in Infisical; kept (--ask-remove or --force-remove removes them)"
}

# Show what would change in a file, by key name only; returns 1 when nothing changes
report() {
  local old="$1" new="$2" added removed changed
  [[ -f "$old" ]] || { echo "  new file, keys: $(keys_of "$new" | paste -sd' ')"; return 0; }
  added=$(comm -13 <(keys_of "$old") <(keys_of "$new") | paste -sd' ')
  removed=$(comm -23 <(keys_of "$old") <(keys_of "$new") | paste -sd' ')
  changed=$(changed_keys "$old" "$new" | paste -sd' ')
  [[ $REMOVE_MODE == ignore ]] && removed=""
  [[ -z "$added$removed$changed" ]] && return 1
  [[ -n "$changed" ]] && echo "  changed: $changed"
  [[ -n "$added" ]]   && echo "  added:   $added"
  if [[ -n "$removed" ]]; then
    if [[ $REMOVE_MODE == force ]]; then echo "  REMOVED: $removed   (not in Infisical; --force-remove drops them)"
    else echo "  REMOVED: $removed   (not in Infisical; you are asked about each one before writing)"; fi
  fi
  return 0
}

# Debug: one line per key with where it comes from and what happens to it, then the verdict
explain() {
  [[ $DEBUG -eq 1 ]] || return 0
  local label="$1" old="$2" new="$3" own="$4" k src state n=0
  for k in $( { keys_of "$old"; keys_of "$new"; } | sort -u); do
    if [[ "$label" == "infisical" && " ${PROTECTED[*]} " == *" $k "* ]]; then src="start key"
    elif [[ -n "$own" ]] && keys_of "$own" | grep -qx "$k"; then src="$ENV_SLUG:/$label"
    elif keys_of "$TMP/shared.env" | grep -qx "$k"; then src="$ENV_SLUG:/shared"
    elif [[ "$k" == SMTP_CONNECTION_URL ]] && keys_of "$new" | grep -qx "$k"; then src="built from SMTP_*"
    elif keys_of "$new" | grep -qx "$k"; then src="kept"
    else src="-"; fi
    if [[ ! -f "$old" ]] || ! keys_of "$old" | grep -qx "$k"; then state="added"; n=$((n + 1))
    elif ! keys_of "$new" | grep -qx "$k"; then
      if [[ $REMOVE_MODE == ignore ]]; then state="kept (not in Infisical)"; else state="REMOVED (not in Infisical)"; n=$((n + 1)); fi
    elif [[ "$(env_value "$k" "$old")" != "$(env_value "$k" "$new")" ]]; then state="changed"; n=$((n + 1))
    else state="same"; fi
    printf '[debug]   %-36s %-20s %s\n' "$k" "$src" "$state" >&2
  done
  if [[ $n -gt 0 ]]; then dbg "$label: WILL UPDATE .env ($n keys differ)"; else dbg "$label: no update, .env already matches"; fi
}

# Which stacks: the ones asked for, or every stack directory (guide order first)
STACKS=()
if [[ ${#ASKED[@]} -gt 0 ]]; then
  STACKS=("${ASKED[@]}")
else
  for s in "${ORDER[@]}"; do [[ -d "$STACKS_DIR/$s" ]] && STACKS+=("$s"); done
  for d in "$STACKS_DIR"/*/; do
    s=$(basename "$d")
    [[ " ${SKIP[*]} ${STACKS[*]} " == *" $s "* ]] || STACKS+=("$s")
  done
fi

dbg "stacks to check: ${STACKS[*]:-none}${ASKED[*]:+ (asked on the command line)}"
dbg "handled separately: shared (written from $ENV_SLUG:/shared); infisical keeps its start keys from its own file"

# Keys Infisical needs to start: always carried over from /opt/stacks/infisical/.env
PROTECTED=(INFISICAL_DB_PASSWORD INFISICAL_ENCRYPTION_KEY INFISICAL_AUTH_SECRET)
PROTECTED_RE=$(IFS='|'; echo "${PROTECTED[*]}")

# Notices about the infisical .env; returns 1 when the file is missing (then it is not written)
check_start_keys() {
  local f="$STACKS_DIR/infisical/.env" k
  if [[ ! -f "$f" ]]; then
    echo "NOTICE: $f is missing. Infisical keeps running, but cannot be recreated without it."
    echo "        Write it again by hand (the Infisical step of the guide shows how to read the values back)."
    return 1
  fi
  for k in "${PROTECTED[@]}"; do
    [[ -n "$(env_value "$k" "$f")" ]] || echo "NOTICE: $k is missing or empty in $f"
  done
  return 0
}

CHANGED=()
# Langfuse reads its email settings as one URL, SMTP_CONNECTION_URL, in which the @ of the address
# must be written as %40. When the stack .env has an SMTP_CONNECTION_URL line and the stack folder
# does not set it, build it from SMTP_USERNAME, SMTP_PASSWORD, SMTP_HOST, and SMTP_PORT (stack folder
# first, then ENV:/shared). When the stack folder sets it, write the @ of its address as %40.
url_part() {
  local v="$1"
  v=${v//%/%25}; v=${v//@/%40}; v=${v//:/%3A}; v=${v//\//%2F}; v=${v//\?/%3F}
  v=${v//#/%23}; v=${v// /%20}; v=${v//\'/%27}
  printf '%s' "$v"
}
smtp_value() {
  if keys_of "$TMP/$1.env" | grep -qx "$2"; then env_value "$2" "$TMP/$1.env"; else env_value "$2" "$TMP/shared.env"; fi
}
smtp_url() {
  local s="$1" want="$TMP/$1.want" url rest userinfo user pass u p h port scheme=smtp
  if keys_of "$TMP/$s.env" | grep -qx SMTP_CONNECTION_URL; then
    url=$(env_value SMTP_CONNECTION_URL "$want")
    [[ "$url" == *://*@* ]] || return 0
    rest=${url#*://}; userinfo=${rest%@*}; user=${userinfo%%:*}
    [[ "$user" == *@* ]] || return 0
    pass=""; [[ "$userinfo" == *:* ]] && pass=":${userinfo#*:}"
    url="${url%%://*}://${user//@/%40}${pass}@${rest##*@}"
    dbg "$s: SMTP_CONNECTION_URL from $ENV_SLUG:/$s, @ of the address written as %40"
  elif [[ -f "$STACKS_DIR/$s/.env" ]] && keys_of "$STACKS_DIR/$s/.env" | grep -qx SMTP_CONNECTION_URL; then
    u=$(smtp_value "$s" SMTP_USERNAME); p=$(smtp_value "$s" SMTP_PASSWORD)
    h=$(smtp_value "$s" SMTP_HOST); port=$(smtp_value "$s" SMTP_PORT)
    if [[ -z "$u" || -z "$p" || -z "$h" || -z "$port" ]]; then
      echo "NOTICE: $s: SMTP_CONNECTION_URL not built; SMTP_USERNAME, SMTP_PASSWORD, SMTP_HOST, and SMTP_PORT must all be in $ENV_SLUG:/shared or $ENV_SLUG:/$s"
      return 0
    fi
    [[ "$port" == 465 ]] && scheme=smtps
    url="$scheme://$(url_part "$u"):$(url_part "$p")@$h:$port"
    dbg "$s: SMTP_CONNECTION_URL built from SMTP_USERNAME, SMTP_PASSWORD, SMTP_HOST, SMTP_PORT"
  else
    return 0
  fi
  grep -v '^SMTP_CONNECTION_URL=' "$want" > "$want.tmp" || true
  if [[ "$url" =~ ^[A-Za-z0-9_./:@%+,=-]*$ ]]; then echo "SMTP_CONNECTION_URL=$url"; else echo "SMTP_CONNECTION_URL='$url'"; fi >> "$want.tmp"
  mv "$want.tmp" "$want"
}

MANAGED=()   # stacks this script writes; sync-shared-env.sh leaves them alone
# /opt/stacks/shared/.env mirrors ENV:/shared, so sync-shared-env.sh and server-status.sh agree with Infisical
{ echo "# Written by pull-secrets.sh from Infisical folder $ENV_SLUG:/shared. Edit there, not here."; cat "$TMP/shared.env"; } > "$TMP/shared.want"
dbg "shared: keys from $ENV_SLUG:/shared, compared with $STACKS_DIR/shared/.env"
explain shared "$STACKS_DIR/shared/.env" "$TMP/shared.want" ""
if report "$STACKS_DIR/shared/.env" "$TMP/shared.want" > "$TMP/shared.report"; then
  echo ""; echo "shared:"; cat "$TMP/shared.report"; CHANGED+=("shared")
fi
note_ignored shared "$STACKS_DIR/shared/.env" "$TMP/shared.want"

for s in "${STACKS[@]}"; do
  if [[ " ${SKIP[*]} " == *" $s "* ]]; then
    continue   # shared and infisical are handled above
  fi
  if [[ ! -d "$STACKS_DIR/$s" ]]; then
    dbg "$s: skipped, no directory $STACKS_DIR/$s (stack not deployed here)"
    continue
  fi
  if [[ "$s" == "infisical" ]] && ! check_start_keys; then
    continue
  fi
  if ! pull_folder "/$s" "$TMP/$s.env"; then
    if [[ ${#ASKED[@]} -gt 0 ]]; then echo "Cannot read folder $ENV_SLUG:/$s in Infisical:"; cat "$TMP/$s.env.err"; exit 1; fi
    dbg "$s: skipped, no readable folder $ENV_SLUG:/$s in Infisical; its .env stays hand-written"
    continue   # no folder for this stack: its .env stays hand-written
  fi
  MANAGED+=("$s")
  # A key in both ENV:/shared and the stack folder: the stack folder wins. Say so when the values
  # differ, since a later change in ENV:/shared would then not reach this stack.
  for k in $(comm -12 <(keys_of "$TMP/shared.env") <(keys_of "$TMP/$s.env")); do
    if [[ "$(env_value "$k" "$TMP/shared.env")" != "$(env_value "$k" "$TMP/$s.env")" ]]; then
      echo "NOTICE: $k is in $ENV_SLUG:/shared and $ENV_SLUG:/$s with different values; $ENV_SLUG:/$s wins for this stack. Delete it from $ENV_SLUG:/$s to follow $ENV_SLUG:/shared."
    else
      dbg "$s: $k is in both $ENV_SLUG:/shared and $ENV_SLUG:/$s (same value); delete it from $ENV_SLUG:/$s"
    fi
  done
  drop="$(keys_of "$TMP/$s.env" | paste -sd'|')"
  if [[ "$s" == "infisical" ]]; then
    # Start keys: never from Infisical. Say so when Infisical holds one with another value.
    for k in "${PROTECTED[@]}"; do
      for src in "$TMP/$s.env" "$TMP/shared.env"; do
        if keys_of "$src" | grep -qx "$k" && [[ "$(env_value "$k" "$src")" != "$(env_value "$k" "$STACKS_DIR/$s/.env")" ]]; then
          echo "NOTICE: $k in Infisical differs from $STACKS_DIR/$s/.env; NOT applied (changing it would break Infisical). Delete it from Infisical."
        fi
      done
    done
    drop="$drop|$PROTECTED_RE"
  fi
  # Keys from ENV:/shared go only into a .env that already has them (a new .env gets them all)
  if [[ -f "$STACKS_DIR/$s/.env" ]]; then
    for k in $(comm -23 <(keys_of "$TMP/shared.env") <(keys_of "$STACKS_DIR/$s/.env")); do
      dbg "$s: $k from $ENV_SLUG:/shared not added (this .env does not have it)"
      drop="$drop|$k"
    done
  fi
  # Wanted keys: ENV:/shared first, then the stack folder (a key in both keeps the stack folder value).
  # Existing files are edited in place later; the header is used only when the file is new.
  {
    echo "# Written by pull-secrets.sh from Infisical folders $ENV_SLUG:/shared and $ENV_SLUG:/$s. Edit there, not here."
    grep -vE "^($drop)=" "$TMP/shared.env" || true
    if [[ "$s" == "infisical" ]]; then
      grep -vE "^($PROTECTED_RE)=" "$TMP/$s.env" || true
      for k in "${PROTECTED[@]}"; do grep -E "^$k=" "$STACKS_DIR/$s/.env" | tail -n 1 || true; done
    else
      cat "$TMP/$s.env"
    fi
  } > "$TMP/$s.want"
  smtp_url "$s"
  if [[ -f "$STACKS_DIR/$s/.env" ]]; then dbg "$s: keys from $ENV_SLUG:/shared and $ENV_SLUG:/$s, compared with $STACKS_DIR/$s/.env"; else dbg "$s: keys from $ENV_SLUG:/shared and $ENV_SLUG:/$s; no .env yet, so it will be created"; fi
  explain "$s" "$STACKS_DIR/$s/.env" "$TMP/$s.want" "$TMP/$s.env"
  if report "$STACKS_DIR/$s/.env" "$TMP/$s.want" > "$TMP/$s.report"; then
    echo ""; echo "$s:"; cat "$TMP/$s.report"; CHANGED+=("$s")
  fi
  note_ignored "$s" "$STACKS_DIR/$s/.env" "$TMP/$s.want"
done

# Stacks without a folder in Infisical keep a hand-written .env: sync-shared-env.sh copies
# SERVER_HOST / SERVER_IP from ENV:/shared into them. It gets the same --dry-run / --debug, the ENV:/shared
# values from this run, and the list of stacks this script writes, so it leaves those alone.
SYNC="$STACKS_DIR/shared/sync-shared-env.sh"
run_sync() {
  local args=()
  if [[ ${#ASKED[@]} -gt 0 ]]; then
    dbg "sync-shared-env.sh not run: only the named stacks were checked"
    return 0
  fi
  [[ $DRY -eq 1 ]] && args+=(--dry-run)
  [[ $DEBUG -eq 1 ]] && args+=(--debug)
  echo ""
  if [[ ! -x "$SYNC" ]]; then
    echo "NOTICE: $SYNC is missing or not executable."
    echo "        Stacks without a folder in Infisical keep their SERVER_HOST / SERVER_IP until you run it."
    return 0
  fi
  echo "Stacks without a folder in Infisical (sync-shared-env.sh):"
  SHARED_ENV="$TMP/shared.want" SYNC_SKIP_STACKS="${MANAGED[*]}" "$SYNC" "${args[@]}" || echo "NOTICE: sync-shared-env.sh failed; run it on its own to see why."
}

echo ""
if [[ ${#CHANGED[@]} -eq 0 ]]; then
  echo "Every .env already matches Infisical. Nothing to do."
  run_sync
  exit 0
fi

echo "To update: ${CHANGED[*]}"
if [[ $DRY -eq 1 ]]; then
  echo "(--dry-run: nothing changed)"
  run_sync
  exit 0
fi
# Edit an existing .env in place: same line order, comments and blank lines kept. A changed value
# is replaced on its own line (an inline comment after it stays), keys in $3 (space-separated)
# are deleted, and new keys are added at the end. Prints the result.
edit_in_place() {
  REMOVE=" $3 " awk '
    function keyof(l) { return match(l, /^[A-Za-z_][A-Za-z0-9_]*=/) ? substr(l, 1, RLENGTH - 1) : "" }
    function norm(v) {
      if (match(v, /[ \t]+#/)) v = substr(v, 1, RSTART - 1)
      sub(/[ \t]+$/, "", v)
      if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
      return v
    }
    NR == FNR { k = keyof($0); if (k != "") { if (!(k in want)) order[++n] = k; want[k] = $0 }; next }
    $0 == "# Added by pull-secrets.sh from Infisical" { marked = 1 }
    {
      k = keyof($0)
      if (k == "") { print; next }
      if (!(k in want)) { if (index(ENVIRON["REMOVE"], " " k " ")) next; print; next }
      seen[k] = 1
      cur = substr($0, length(k) + 2); val = substr(want[k], length(k) + 2)
      if (norm(cur) == norm(val)) { print; next }
      print want[k] (match(cur, /[ \t]+#/) ? substr(cur, RSTART) : "")
    }
    END {
      for (i = 1; i <= n; i++) {
        if (order[i] in seen) continue
        if (!marked) { print ""; print "# Added by pull-secrets.sh from Infisical"; marked = 1 }
        print want[order[i]]
      }
    }
  ' "$2" "$1"
}

# Keys no longer in Infisical: keep them all (default), ask for each one (--ask-remove; kept
# unless the answer is y), or remove them all (--force-remove). Then build the file to write: edited in
# place, or the wanted keys if the file is new.
NO_CHANGE=()
for s in "${CHANGED[@]}"; do
  f="$STACKS_DIR/$s/.env"
  if [[ ! -f "$f" ]]; then
    cp "$TMP/$s.want" "$TMP/$s.out"
    continue
  fi
  remove=()
  for k in $(removed_keys "$f" "$TMP/$s.want"); do
    [[ $REMOVE_MODE == ignore ]] && continue
    if [[ $REMOVE_MODE == force ]]; then
      remove+=("$k"); dbg "$s: $k removed without asking (--force-remove)"
      continue
    fi
    answer=n
    if [[ -t 0 ]]; then
      read -rp "Remove $k from $s/.env? It is not in Infisical. [y/N] " answer || answer=n
    else
      echo "NOTICE: no terminal to ask on; keeping $k in $s/.env (--force-remove removes it without asking)."
    fi
    if [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then remove+=("$k"); else echo "  $s: keeping $k"; fi
  done
  edit_in_place "$f" "$TMP/$s.want" "${remove[*]}" > "$TMP/$s.out"
  # Only removals were planned for this stack and every one was kept: nothing left to write
  report "$f" "$TMP/$s.out" > /dev/null || NO_CHANGE+=("$s")
done
if [[ ${#NO_CHANGE[@]} -gt 0 ]]; then
  NEXT=()
  for s in "${CHANGED[@]}"; do [[ " ${NO_CHANGE[*]} " == *" $s "* ]] || NEXT+=("$s"); done
  CHANGED=("${NEXT[@]}")
  echo "No change left for: ${NO_CHANGE[*]}"
  if [[ ${#CHANGED[@]} -eq 0 ]]; then
    echo "Nothing to write."
    run_sync
    exit 0
  fi
  echo "To update: ${CHANGED[*]}"
fi

read -rp "Write these .env files and recreate the changed stacks? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]([Ee][Ss])?$ ]] || { echo "Aborted, nothing changed."; exit 0; }

TS=$(date +%Y%m%d-%H%M%S)
for s in "${CHANGED[@]}"; do
  f="$STACKS_DIR/$s/.env"
  mkdir -p "$STACKS_DIR/$s"
  [[ -f "$f" ]] && cp -p "$f" "$f.bak-$TS"
  cat "$TMP/$s.out" > "$f"   # cat keeps the permissions of an existing file
  chmod 600 "$f"
  [[ "$s" == "shared" ]] && continue
  echo ""
  echo "Recreating $s:"
  RUNNING=$(cd "$STACKS_DIR/$s" && docker compose --profile "*" ps --services --status running 2>/dev/null || true)
  if [[ -z "$RUNNING" ]]; then
    echo "  nothing running; the new values apply at its next start"
    continue
  fi
  # shellcheck disable=SC2086
  (cd "$STACKS_DIR/$s" && docker compose --profile "*" up -d $RUNNING)
done

run_sync

echo ""
echo "Done. Old files are saved as .env.bak-$TS; delete them once everything works."
