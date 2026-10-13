#!/usr/bin/env bash
# NAME
#     server-status.sh - check the server against the setup guide
#
# SYNOPSIS
#     server-status.sh [-h]
#
# DESCRIPTION
#     Read-only: makes no changes. Checks the prerequisites, Docker daemon settings, shared settings,
#     secrets and sign-in, every service, and older installs. Run it before acting on any step of
#     the guide, since the server can drift between sessions. It prints its SCRIPT_VERSION first,
#     so an outdated copy is easy to spot.
#
#     Each line starts with a status, like Ubuntu boot messages:
#       [  OK  ] green   works as the guide expects
#       [ WARN ] yellow  works, but needs a look
#       [FAILED] red     broken or missing where it should exist
#       [  --  ] plain   not installed yet (the guide step has not been done)
#
# OPTIONS
#     -h, --help
#         Show this manual.
#
# ENVIRONMENT
#     NO_COLOR   set to any value to turn colors off (they are used only on a terminal)
#
# SEE ALSO
#     the service status check section of the setup guide

# -h / --help: show the manual above (the comment block at the top of this file)
if [[ " $* " == *" -h "* || " $* " == *" --help "* ]]; then
  awk 'NR > 1 && /^$/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0" |
    if [[ -t 1 ]] && command -v less >/dev/null 2>&1; then less -FRX; else cat; fi
  exit 0
fi

# Date of this version; compare with the copy in the repo or the Outline export to spot an outdated copy
SCRIPT_VERSION="2026-10-13"

set -uo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RED=$'\e[31m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
else
  GREEN=""; YELLOW=""; RED=""; BOLD=""; RESET=""
fi
FAILS=0; WARNS=0

ok()   { printf '%s[  OK  ]%s %-15s %s\n' "$GREEN" "$RESET" "$1" "${2:-}"; }
warn() { printf '%s[ WARN ]%s %-15s %s\n' "$YELLOW" "$RESET" "$1" "${2:-}"; WARNS=$((WARNS + 1)); }
fail() { printf '%s[FAILED]%s %-15s %s\n' "$RED" "$RESET" "$1" "${2:-}"; FAILS=$((FAILS + 1)); }
none() { printf '[  --  ] %-15s %s\n' "$1" "${2:-}"; }
# Section title: bold on a terminal, plain otherwise; a blank line before every section except the first
FIRST=1
section() { if [[ $FIRST -eq 1 ]]; then FIRST=0; else printf '\n'; fi; printf '%s%s%s\n' "$BOLD" "$1" "$RESET"; }

# Run a check command: OK with its output, or FAILED with the given text (default "not found")
chk() {
  local out
  if out=$(eval "$2" 2>/dev/null) && [[ -n "$out" ]]; then ok "$1" "$out"; else fail "$1" "${3:-not found}"; fi
}

printf 'server-status.sh version %s

' "$SCRIPT_VERSION"
section "Prerequisite: Docker / NVIDIA"
chk "OS"            'lsb_release -ds'
chk "Docker"        'docker --version'
chk "Compose"       'docker compose version --short'
chk "Kernel module" 'grep -m1 NVRM /proc/driver/nvidia/version | grep -oE "(Open )?Kernel Module|[0-9]+\.[0-9]+\.[0-9]+" | paste -sd" "'
chk "Driver pkgs"   'dpkg -l | grep -E "^ii +(nvidia-(driver|headless|utils)|linux-modules-nvidia)-" | tr -s " " | cut -d" " -f2 | paste -sd" "'
chk "nvidia-smi"    'nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader'
chk "Toolkit"       'nvidia-ctk --version | head -1'
chk "CDI spec"      'date -r /etc/cdi/nvidia.yaml "+generated %F %R"'
chk "GPU in Docker" 'docker run --rm --device nvidia.com/gpu=all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi --query-gpu=name --format=csv,noheader' "container cannot see the GPU"

section "Docker daemon settings"
if grep -qE '"userland-proxy": *false' /etc/docker/daemon.json 2>/dev/null; then ok "userland-proxy" "off (the kernel forwards ports)"
else warn "userland-proxy" "on: $(pgrep -c docker-proxy 2>/dev/null || echo 0) docker-proxy processes; see Docker daemon settings in the guide"
fi
if grep -q '"max-size"' /etc/docker/daemon.json 2>/dev/null; then ok "Log rotation" "$(grep -oE '"max-size": *"[^"]+"' /etc/docker/daemon.json)"
else warn "Log rotation" "container logs grow without limit; see Docker daemon settings in the guide"
fi

section "User permissions, network, shared settings"
if id -nG "$USER" | grep -qw docker; then ok "docker group" "$USER is a member"; else fail "docker group" "$USER is not a member"; fi
for d in /opt/stacks /opt/backups; do
  if [[ ! -d "$d" ]]; then fail "$d" "does not exist"
  elif [[ "$(stat -c %U "$d")" == "$USER" ]]; then ok "$d" "owned by $USER"
  else fail "$d" "owned by $(stat -c %U "$d"), not $USER"
  fi
done
if docker network inspect edge >/dev/null 2>&1; then ok "edge network" "exists"; else fail "edge network" "not found"; fi
if [[ -f /opt/stacks/shared/.env ]]; then
  ok "shared .env" "$(grep -E "^SERVER_(HOST|IP)=" /opt/stacks/shared/.env | paste -sd" ")"
  if [[ -x /opt/stacks/shared/sync-shared-env.sh ]]; then
    if /opt/stacks/shared/sync-shared-env.sh --dry-run 2>/dev/null | grep -q "already matches"; then ok "shared sync" "every stack matches"
    else warn "shared sync" "stacks differ; run: /opt/stacks/shared/sync-shared-env.sh --dry-run"
    fi
  else
    fail "shared sync" "sync-shared-env.sh not found in /opt/stacks/shared/"
  fi
else
  fail "shared .env" "/opt/stacks/shared/.env not found"
fi

section "Secrets, sign-in, certificates"
# Infisical: the machine login for pull-secrets.sh, and whether every .env matches Infisical
if docker inspect infisical >/dev/null 2>&1; then
  if [[ -f /opt/stacks/infisical/pull.env ]]; then
    mode=$(stat -c %a /opt/stacks/infisical/pull.env)
    if [[ "$mode" == "600" ]]; then ok "pull.env" "present, mode 600"; else warn "pull.env" "mode $mode; run: chmod 600 /opt/stacks/infisical/pull.env"; fi
  else
    fail "pull.env" "/opt/stacks/infisical/pull.env not found (pull-secrets.sh cannot log in)"
  fi
  if [[ -x /opt/stacks/infisical/pull-secrets.sh && -f /opt/stacks/infisical/pull.env ]]; then
    out=$(/opt/stacks/infisical/pull-secrets.sh --dry-run 2>&1 | tail -n 3)
    if grep -q "already matches" <<<"$out"; then ok "Infisical sync" "every .env matches Infisical"
    elif grep -q "Files to write" <<<"$out"; then warn "Infisical sync" "some .env files differ; run: /opt/stacks/infisical/pull-secrets.sh --dry-run"
    else fail "Infisical sync" "$(tail -n 1 <<<"$out")"
    fi
  else
    warn "pull-secrets.sh" "not found in /opt/stacks/infisical/"
  fi
else
  none "Infisical" "not installed"
fi
# Dex sign-in gate: oauth2-proxy accepts only a 16-, 24-, or 32-character cookie secret
if [[ -f /opt/stacks/dex/.env ]]; then
  # tr drops the newline and any surrounding quotes (octal 042 and 047), so only the value is counted
  len=$(grep -E "^GATE_COOKIE_SECRET=" /opt/stacks/dex/.env | cut -d= -f2- | tr -d '\n\042\047' | wc -c)
  case "$len" in
    16|24|32) ok "Gate cookie" "GATE_COOKIE_SECRET is $len characters" ;;
    0) none "Gate cookie" "no GATE_COOKIE_SECRET in /opt/stacks/dex/.env" ;;
    *) fail "Gate cookie" "GATE_COOKIE_SECRET is $len characters; must be 16, 24, or 32 (openssl rand -hex 16)" ;;
  esac
fi
# Caddy CA certificate file: Langfuse mounts it; if it is missing, Docker creates a folder in its place
ca=/opt/stacks/caddy/caddy-root-ca.crt
if [[ -d "$ca" ]]; then fail "CA certificate" "$ca is a folder, not the certificate; remove it and export the certificate again"
elif [[ -f "$ca" ]]; then ok "CA certificate" "$ca"
elif docker inspect caddy >/dev/null 2>&1; then warn "CA certificate" "$ca not exported yet (trusting the internal CA)"
fi

section "Services"
# Status of one container: running (healthy), stopped, broken, or missing
state() {
  docker inspect -f '{{.State.Status}}{{if .State.Health}}/{{.State.Health.Status}}{{end}}' "$1" 2>/dev/null || echo missing
}

# name|space-separated container names, in the deployment order of the guide
SERVICES=(
  "Caddy|caddy"
  "Infisical|infisical infisical-postgres infisical-redis"
  "Dex|dex oauth2-proxy"
  "Outline|outline outline-postgres outline-redis"
  "Portainer|portainer"
  "Grafana|grafana"
  "Prometheus|prometheus"
  "Node Exporter|node-exporter"
  "dcgm-exporter|dcgm-exporter"
  "Sourcebot|sourcebot sourcebot-postgres sourcebot-redis"
  "Langfuse|langfuse-web langfuse-worker langfuse-postgres langfuse-redis langfuse-clickhouse langfuse-minio"
  "LiteLLM|litellm litellm-postgres"
  "Qdrant|qdrant"
  "Neo4j|neo4j"
  "Memgraph|memgraph"
  "OpenHands|openhands"
  "Open WebUI|open-webui"
  "CI runner|github-runner"
)

for entry in "${SERVICES[@]}"; do
  name=${entry%%|*}
  total=0; up=0; missing=0; problems=()
  for c in ${entry#*|}; do
    total=$((total + 1))
    s=$(state "$c")
    case "$s" in
      missing)              missing=$((missing + 1)) ;;
      running|running/healthy) up=$((up + 1)) ;;
      running/starting)     up=$((up + 1)); problems+=("$c starting") ;;
      running/unhealthy)    up=$((up + 1)); problems+=("$c unhealthy") ;;
      *)                    problems+=("$c $s") ;;
    esac
  done
  if [[ $missing -eq $total ]]; then none "$name" "not installed"
  elif [[ $up -eq $total && ${#problems[@]} -eq 0 ]]; then ok "$name" "$up/$total running"
  elif [[ $up -eq $total ]]; then warn "$name" "$(IFS=,; echo "${problems[*]}" | sed 's/,/, /g')"
  else
    [[ $missing -gt 0 ]] && problems+=("$missing missing")
    fail "$name" "$up/$total running; $(IFS=,; echo "${problems[*]}" | sed 's/,/, /g')"
  fi
done

# Ollama and vLLM share the GPU: exactly one should run
o=$(state ollama); v=$(state vllm)
if [[ "$o" == missing && "$v" == missing ]]; then none "Ollama / vLLM" "not installed"
elif [[ "$o" == running* && "$v" == running* ]]; then warn "Ollama / vLLM" "both running; they compete for the GPU (switch-llm.sh ollama|vllm)"
elif [[ "$o" == running* ]]; then ok "Ollama / vLLM" "Ollama active"
elif [[ "$v" == running* ]]; then ok "Ollama / vLLM" "vLLM active"
else warn "Ollama / vLLM" "installed, neither running (switch-llm.sh ollama|vllm)"
fi

section "Older installs"
# An ad hoc combined monitoring stack from before this guide
dir=$(docker inspect prometheus --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' 2>/dev/null || true)
if [[ "$dir" == "/opt/stacks/monitoring" ]]; then warn "Monitoring" "still the old combined /opt/stacks/monitoring stack; see the Monitoring step"
elif [[ -n "$dir" ]]; then ok "Monitoring" "split stacks ($dir)"
else none "Monitoring" "Prometheus not installed"
fi
# Host ports on containers that should only be reached through Caddy or the edge network
for c in grafana prometheus node-exporter dcgm-exporter; do
  p=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Ports}}{{if $v}}{{$k}} {{end}}{{end}}' "$c" 2>/dev/null || true)
  [[ -n "$p" ]] && warn "$c" "publishes host ports (${p% }); the guide reaches it through Caddy or edge only"
done
[[ -f /opt/stacks/caddy/.env ]] && ! grep -q "^SERVER_HOST=" /opt/stacks/caddy/.env && warn "Caddy" "IP-only install; see Upgrading from an IP-only install"

printf '\n'
if [[ $FAILS -eq 0 && $WARNS -eq 0 ]]; then printf '%sAll checks passed.%s\n' "$GREEN" "$RESET"
else printf '%s%d failed%s, %s%d warning(s)%s.\n' "$RED" "$FAILS" "$RESET" "$YELLOW" "$WARNS" "$RESET"
fi
echo "Skip any guide step whose service shows OK; start at the first one marked -- or FAILED."
