#!/usr/bin/env bash
# NAME
#     graphdb.sh - start or stop Neo4j and Memgraph
#
# SYNOPSIS
#     graphdb.sh [-h] neo4j|memgraph|both|stop|status
#
# DESCRIPTION
#     Neither uses the GPU, so both can run together (the default). Works from any folder: it
#     changes to the stack folder, /opt/stacks/graphdb, where compose.yaml with both profiles lives.
#
# OPTIONS
#     -h, --help
#         Show this manual.
#     neo4j
#         Start Neo4j.
#     memgraph
#         Start Memgraph.
#     both
#         Start both.
#     stop
#         Stop both.
#     status
#         Show both containers.
#
# EXAMPLES
#     graphdb.sh both
#     graphdb.sh status
#
# FILES
#     /opt/stacks/graphdb/compose.yaml
#
# SEE ALSO
#     the Neo4j + Memgraph step of the setup guide

# -h / --help: show the manual above (the comment block at the top of this file)
if [[ " $* " == *" -h "* || " $* " == *" --help "* ]]; then
  awk 'NR > 1 && /^$/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0" |
    if [[ -t 1 ]] && command -v less >/dev/null 2>&1; then less -FRX; else cat; fi
  exit 0
fi

set -e
cd "${STACKS_DIR:-/opt/stacks}/graphdb"

case "${1:-}" in
  neo4j)
    docker compose --profile neo4j up -d neo4j
    ;;
  memgraph)
    docker compose --profile memgraph up -d memgraph
    ;;
  both)
    docker compose --profile neo4j --profile memgraph up -d neo4j memgraph
    ;;
  stop)
    docker compose --profile neo4j --profile memgraph stop neo4j memgraph 2>/dev/null || true
    echo "Both stopped."
    ;;
  status)
    docker compose --profile "*" ps
    ;;
  *)
    echo "Usage: $0 neo4j|memgraph|both|stop|status   (manual: $0 -h)"
    exit 1
    ;;
esac
