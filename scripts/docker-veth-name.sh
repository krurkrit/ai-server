#!/usr/bin/env bash
# NAME
#     docker-veth-name.sh - give the veth cables of running containers readable names
#
# SYNOPSIS
#     sudo docker-veth-name.sh [-h]
#
# DESCRIPTION
#     Docker connects each container to its networks with veth cables named vethXXXXXXX, which
#     show up in ip -br link. This script renames the host end of
#     each cable after its container: veth-<short> for the first network (eth0 inside the
#     container), veth-<short>2, veth-<short>3, ... for the next ones (eth1, eth2, ...).
#
#     The short names are listed in the script (e.g. outline -> ol, outline-postgres -> ol-pg).
#     Other containers get their name without dashes, cut to 8 characters. Linux allows at most
#     15 characters in an interface name, so keep short names to 9 characters or fewer.
#
#     It prints each rename, then a count. A cable that already has its name is left alone;
#     when the name is taken by another interface, a NOTICE says so and the cable keeps its name.
#
#     The names do not last: Docker creates new cables with random names each time a container is
#     created or restarted. Run the script again after an update, a restart, or a reboot.
#     Renaming does not change how containers talk to each other; only the name changes.
#
# OPTIONS
#     -h, --help
#         Show this manual.
#
# EXAMPLES
#     sudo ./docker-veth-name.sh
#     ip -br link | grep veth-
#
# SEE ALSO
#     ip-link(8)

# -h / --help: show the manual above (the comment block at the top of this file)
if [[ " $* " == *" -h "* || " $* " == *" --help "* ]]; then
  awk 'NR > 1 && /^$/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0" |
    if [[ -t 1 ]] && command -v less >/dev/null 2>&1; then less -FRX; else cat; fi
  exit 0
fi

set -uo pipefail

if [[ $# -gt 0 ]]; then
  echo "Usage: sudo $0   (manual: $0 -h)" >&2
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo $0" >&2
  exit 1
fi

# Short name per container, in the guide deployment order. At most 9 characters, so that
# veth-<short> plus a network number fits the 15-character limit of interface names.
NAMES=(caddy
       infisical infisical-postgres infisical-redis
       dex oauth2-proxy
       outline outline-postgres outline-redis
       portainer
       grafana prometheus node-exporter dcgm-exporter
       sourcebot sourcebot-postgres sourcebot-redis
       langfuse-web langfuse-worker langfuse-postgres langfuse-redis langfuse-clickhouse langfuse-minio
       litellm litellm-postgres
       ollama vllm
       qdrant
       neo4j memgraph
       openhands)
SHORTS=(caddy
        ifs ifs-pg ifs-rd
        dex oauth
        ol ol-pg ol-rd
        portainer
        grafana prom nodeexp dcgm
        sb sb-pg sb-rd
        lf lf-wk lf-pg lf-rd lf-ch lf-minio
        llm llm-pg
        ollama vllm
        qdrant
        neo4j memgraph
        openhands)

short_name() {
  local i
  for i in "${!NAMES[@]}"; do
    [[ "${NAMES[$i]}" == "$1" ]] && { echo "${SHORTS[$i]}"; return; }
  done
  # Not in the list: the container name without dashes or dots, cut to 8 characters
  printf '%s' "$1" | tr -cd 'a-zA-Z0-9_' | cut -c1-8
}

renamed=0; same=0
while read -r pid name; do
  name=${name#/}
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || continue
  short=$(short_name "$name")

  # Each network inside the container (eth0, eth1, ...) and the index of its host end (@ifN)
  while IFS= read -r line; do
    inside=$(sed -E 's/^[0-9]+: ([^:@]+).*/\1/' <<< "$line")
    [[ "$inside" == "lo" ]] && continue
    peer=$(sed -nE 's/.*@if([0-9]+):.*/\1/p' <<< "$line")
    [[ -n "$peer" ]] || continue

    host_if=$(ip -o link show | awk -F': ' -v i="$peer" '$1 == i { split($2, a, "@"); print a[1]; exit }')
    [[ -n "$host_if" ]] || continue

    # eth0 gets no number, eth1 gets 2, eth2 gets 3, ...
    suffix=""
    if [[ "$inside" =~ ^eth([1-9][0-9]*)$ ]]; then
      suffix=$((BASH_REMATCH[1] + 1))
    fi
    target="veth-${short}${suffix}"

    if [[ "$host_if" == "$target" ]]; then
      same=$((same + 1))
      continue
    fi
    if ip link show dev "$target" &>/dev/null; then
      echo "NOTICE: $name: $target is already taken; $host_if keeps its name"
      continue
    fi
    if ip link set dev "$host_if" name "$target"; then
      echo "  $name: $host_if -> $target"
      renamed=$((renamed + 1))
    else
      echo "NOTICE: $name: could not rename $host_if to $target"
    fi
  done < <(nsenter -t "$pid" -n ip -o link show)
done < <(docker ps -q | xargs -r docker inspect -f '{{.State.Pid}} {{.Name}}')

echo "Done. Renamed $renamed; $same already had their name. Check with: ip -br link | grep veth-"
