#!/usr/bin/env bash
# NAME
#     switch-llm.sh - switch the GPU between Ollama and vLLM
#
# SYNOPSIS
#     switch-llm.sh [-h] ollama|vllm|status|stop
#
# DESCRIPTION
#     Ollama and vLLM share the GPU, so only one runs at a time. Starting one stops the other first,
#     then shows the running container and GPU memory use. Works from any folder: it changes to its
#     stack folder, /opt/stacks/llm-runtime, where compose.yaml with both profiles lives.
#
# OPTIONS
#     -h, --help
#         Show this manual.
#     ollama
#         Stop vLLM if it runs, start Ollama.
#     vllm
#         Stop Ollama if it runs, start vLLM.
#     status
#         Show which one is running.
#     stop
#         Stop both, freeing the GPU.
#
# EXAMPLES
#     switch-llm.sh status
#     switch-llm.sh vllm
#
# FILES
#     /opt/stacks/llm-runtime/compose.yaml
#
# SEE ALSO
#     the Ollama / vLLM step of the setup guide

# -h / --help: show the manual above (the comment block at the top of this file)
if [[ " $* " == *" -h "* || " $* " == *" --help "* ]]; then
  awk 'NR > 1 && /^$/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0" |
    if [[ -t 1 ]] && command -v less >/dev/null 2>&1; then less -FRX; else cat; fi
  exit 0
fi

set -e
cd "${STACKS_DIR:-/opt/stacks}/llm-runtime"

TARGET="$1"
VALID="ollama vllm status stop"

usage() {
  echo "Usage: $0 ollama|vllm|status|stop   (manual: $0 -h)"
  exit 1
}

if [[ -z "$TARGET" ]] || ! grep -qw "$TARGET" <<< "$VALID"; then
  usage
fi

case "$TARGET" in
  status)
    O=$(docker ps --filter 'name=^ollama$' --format '{{.Status}}')
    V=$(docker ps --filter 'name=^vllm$'   --format '{{.Status}}')
    echo "Ollama: ${O:-not running}"
    echo "vLLM:   ${V:-not running}"
    exit 0
    ;;
  stop)
    docker compose --profile ollama stop ollama 2>/dev/null || true
    docker compose --profile vllm stop vllm 2>/dev/null || true
    echo "Both stopped. GPU freed."
    exit 0
    ;;
esac

OTHER=$([[ "$TARGET" == "ollama" ]] && echo "vllm" || echo "ollama")

echo "Stopping $OTHER (if running)..."
docker compose --profile "$OTHER" stop "$OTHER" 2>/dev/null || true

echo "Starting $TARGET..."
docker compose --profile "$TARGET" up -d "$TARGET"

echo ""
echo "Now running: $TARGET"
docker ps --filter "name=$TARGET" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# Quick VRAM sanity check
if command -v nvidia-smi >/dev/null 2>&1; then
  echo ""
  echo "GPU memory usage:"
  nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader
fi
