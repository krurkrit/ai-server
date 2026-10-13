#!/usr/bin/env bash
# NAME
#     server-test.sh - run the server-side tests of every service in the setup guide
#
# SYNOPSIS
#     server-test.sh [--no-model] [SERVICE ...]
#
# DESCRIPTION
#     Runs the part of each service Test in the guide that works from the server: health
#     endpoints through Caddy, sign-in discovery and the sign-in gate, one model call through
#     LiteLLM and its trace in Langfuse, embeddings, the GPU, the graph databases, and the apps
#     that call LiteLLM from inside their containers. server-status.sh shows whether containers
#     run; this script shows whether they work. Services that are not installed show as --.
#
#     It changes nothing on the server. The model call loads the model if it is not loaded yet
#     (the first call can take a minute) and leaves one trace named server-test in Langfuse.
#
#     Each line starts with a status, like server-status.sh:
#       [  OK  ] green   works as the guide expects
#       [ WARN ] yellow  works, but needs a look
#       [FAILED] red     broken
#       [  --  ] plain   not installed, or skipped
#
#     At the end it lists what only a browser or GitHub can show; those are in each service
#     Test in the guide.
#
# OPTIONS
#     --no-model
#         Skip every call that goes to a model (LiteLLM, Langfuse trace, GPU, embeddings,
#         OpenHands, Open WebUI); quick, and leaves the GPU alone.
#     SERVICE
#         Test only these, in any order: caddy infisical dex outline portainer monitoring
#         sourcebot langfuse litellm qdrant graphdb openhands open-webui runner
#         (litellm includes the LLM runtime). Default: all.
#     -h, --help
#         Show this manual.
#
# EXAMPLES
#     ~/ai-server/server-test.sh
#     ~/ai-server/server-test.sh --no-model
#     ~/ai-server/server-test.sh litellm open-webui
#
# FILES
#     /opt/stacks/shared/.env              SERVER_HOST and SERVER_IP
#     /opt/stacks/caddy/caddy-root-ca.crt  the internal CA, to check the certificate
#     /opt/stacks/graphdb/.env             NEO4J_PASSWORD, for the Neo4j query
#
# ENVIRONMENT
#     STACKS_DIR   where the stacks are (default /opt/stacks)
#     NO_COLOR     set to any value to turn colors off (they are used only on a terminal)
#
# SEE ALSO
#     server-status.sh; the Test part of each service in the setup guide

# -h / --help: show the manual above (the comment block at the top of this file)
if [[ " $* " == *" -h "* || " $* " == *" --help "* ]]; then
  awk 'NR > 1 && /^$/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0" |
    if [[ -t 1 ]] && command -v less >/dev/null 2>&1; then less -FRX; else cat; fi
  exit 0
fi

set -uo pipefail

ALL=(caddy infisical dex outline portainer monitoring sourcebot langfuse litellm qdrant graphdb openhands open-webui runner)
MODEL=1; ONLY=()
for arg in "$@"; do
  case "$arg" in
    --no-model) MODEL=0 ;;
    *)
      if [[ " ${ALL[*]} " == *" $arg "* ]]; then ONLY+=("$arg")
      else echo "Usage: $0 [--no-model] [SERVICE ...] (manual: $0 -h)" >&2; exit 1
      fi ;;
  esac
done

STACKS_DIR=${STACKS_DIR:-/opt/stacks}
SHARED="$STACKS_DIR/shared/.env"
if [[ ! -f "$SHARED" ]]; then echo "$SHARED not found: set up the shared settings first." >&2; exit 1; fi
HOST=$(grep -E '^SERVER_HOST=' "$SHARED" | cut -d= -f2- | tr -d '\042\047')
IP=$(grep -E '^SERVER_IP=' "$SHARED" | cut -d= -f2- | tr -d '\042\047')
HOST=${HOST:-$IP}

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RED=$'\e[31m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
else
  GREEN=""; YELLOW=""; RED=""; BOLD=""; RESET=""
fi
FAILS=0; WARNS=0; OKS=0
ok()   { printf '%s[  OK  ]%s %-15s %s\n' "$GREEN" "$RESET" "$1" "${2:-}"; OKS=$((OKS + 1)); }
warn() { printf '%s[ WARN ]%s %-15s %s\n' "$YELLOW" "$RESET" "$1" "${2:-}"; WARNS=$((WARNS + 1)); }
fail() { printf '%s[FAILED]%s %-15s %s\n' "$RED" "$RESET" "$1" "${2:-}"; FAILS=$((FAILS + 1)); }
none() { printf '[  --  ] %-15s %s\n' "$1" "${2:-}"; }
FIRST=1
section() { if [[ $FIRST -eq 1 ]]; then FIRST=0; else printf '\n'; fi; printf '%s%s%s\n' "$BOLD" "$1" "$RESET"; }

want()    { [[ ${#ONLY[@]} -eq 0 || " ${ONLY[*]} " == *" $1 "* ]]; }
running() { [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == true ]]; }
# HTTP status of a URL through Caddy (000 when nothing answers)
code()    { curl -sk -o /dev/null -w '%{http_code}' --max-time 15 "$1"; }
# Check that a URL answers with one of the expected codes
http() {  # name url expected-codes-regex what
  local c; c=$(code "$2")
  if [[ "$c" =~ ^($3)$ ]]; then ok "$1" "${4:-$2} answers $c"; else fail "$1" "${4:-$2} answers $c, expected $3"; fi
}
# A secret from a running container, never printed
secret()  { docker exec "$1" printenv "$2" 2>/dev/null; }

# One chat call through LiteLLM; prints "<http code> <answer or error>"
llm_call() {  # model [trace-id]
  local key body out
  key=$(secret litellm LITELLM_MASTER_KEY)
  body='{"model":"'"$1"'","max_tokens":20,"messages":[{"role":"user","content":"Say OK"}]'
  [[ -n "${2:-}" ]] && body+=',"metadata":{"trace_id":"'"$2"'","trace_name":"server-test"}'
  body+='}'
  # The key goes in on stdin, so it never shows in the process list
  out=$(printf 'Authorization: Bearer %s\n' "$key" | curl -sk --max-time 300 -H @- \
        -H 'Content-Type: application/json' -d "$body" -w '\n%{http_code}' "https://$HOST:4000/v1/chat/completions")
  printf '%s %s\n' "${out##*$'\n'}" "$(sed -n '1p' <<<"$out" | grep -oE '"content": ?"[^"]*"' | head -1 | cut -d'"' -f4)"
}

# The same check the guide runs inside OpenHands and Open WebUI: their key reaches LiteLLM
app_call() {  # container env-var-with-key
  docker exec "$1" python3 -c "
import os,urllib.request,urllib.error,json
r=urllib.request.Request('http://litellm:4000/v1/chat/completions', data=json.dumps({'model':'local-model','max_tokens':20,'messages':[{'role':'user','content':'Say OK'}]}).encode(), headers={'Authorization':'Bearer '+os.environ['$2'],'Content-Type':'application/json'})
try: print('OK:', json.load(urllib.request.urlopen(r, timeout=300))['choices'][0]['message']['content'].strip()[:40])
except urllib.error.HTTPError as e: print(e.code, e.read().decode()[:200])
except Exception as e: print('error:', str(e)[:200])
" 2>&1 | tail -1
}

printf 'server-test.sh: testing %s (%s)\n\n' "$HOST" "${IP:-no IP}"

if want caddy; then
  section "Caddy"
  if running caddy; then
    for a in "$HOST" "$IP"; do
      [[ -z "$a" ]] && continue
      body=$(curl -sk --max-time 10 "https://$a:9500")
      if [[ "$body" == *"Caddy OK"* ]]; then ok "Health $a" "port 9500 says Caddy OK"; else fail "Health $a" "port 9500 does not answer Caddy OK"; fi
    done
    ca="$STACKS_DIR/caddy/caddy-root-ca.crt"
    if [[ -f "$ca" ]]; then
      if curl -s --cacert "$ca" --max-time 10 -o /dev/null "https://$HOST:9500"; then ok "Certificate" "signed by the internal CA, valid for $HOST"
      else fail "Certificate" "not trusted with $ca, or not valid for $HOST"
      fi
    else
      none "Certificate" "CA not exported to $ca"
    fi
    if out=$(docker exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile 2>&1); then ok "Config" "Caddyfile and conf.d files are valid"
    else fail "Config" "$(grep -m1 -iE 'error' <<<"$out" | cut -c1-120)"
    fi
  else
    none "Caddy" "not running"
  fi
fi

if want infisical; then
  section "Infisical"
  if running infisical; then
    http "Web" "https://$HOST:8080/api/status" "200"
    ps="$STACKS_DIR/infisical/pull-secrets.sh"
    if [[ -x "$ps" && -f "$STACKS_DIR/infisical/pull.env" ]]; then
      out=$("$ps" --dry-run 2>&1 | tail -n 3)
      if grep -qE "already matches|Files to write|Nothing to do" <<<"$out"; then ok "Machine login" "pull-secrets.sh reads Infisical"
      else fail "Machine login" "$(tail -n 1 <<<"$out" | cut -c1-120)"
      fi
    else
      fail "Machine login" "pull-secrets.sh or pull.env missing in $STACKS_DIR/infisical/"
    fi
  else
    none "Infisical" "not running"
  fi
fi

if want dex; then
  section "Dex"
  if running dex; then
    iss=$(curl -sk --max-time 10 "https://$HOST:5556/dex/.well-known/openid-configuration" | grep -oE '"issuer": ?"[^"]*"' | cut -d'"' -f4)
    if [[ "$iss" == "https://$HOST:5556/dex" ]]; then ok "Discovery" "issuer $iss"
    elif [[ -n "$iss" ]]; then fail "Discovery" "issuer $iss, expected https://$HOST:5556/dex"
    else fail "Discovery" "no answer from https://$HOST:5556/dex"
    fi
    if running oauth2-proxy && running prometheus; then
      loc=$(curl -skI --max-time 10 "https://$HOST:9090" | tr -d '\r' | awk 'tolower($1) == "location:" { print $2 }')
      if [[ "$loc" == *oauth2* ]]; then ok "Sign-in gate" "Prometheus sends you to the Dex sign-in"
      else fail "Sign-in gate" "Prometheus opens without the Dex sign-in"
      fi
    else
      none "Sign-in gate" "oauth2-proxy or Prometheus not running"
    fi
  else
    none "Dex" "not running"
  fi
fi

if want outline; then
  section "Outline"
  if running outline; then http "Web" "https://$HOST/_health" "200"; else none "Outline" "not running"; fi
fi

if want portainer; then
  section "Portainer"
  if running portainer; then http "Web" "https://$HOST:9443/api/system/status" "200"; else none "Portainer" "not running"; fi
fi

if want monitoring; then
  section "Monitoring"
  if running prometheus; then
    t=$(docker exec prometheus wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null)
    up=$(grep -o '"health":"up"' <<<"$t" | wc -l); down=$(grep -o '"health":"down"' <<<"$t" | wc -l)
    if [[ -z "$t" ]]; then fail "Targets" "Prometheus API does not answer"
    elif [[ $down -eq 0 ]]; then ok "Targets" "$up up"
    else fail "Targets" "$down down, $up up (see /targets in Prometheus)"
    fi
  else
    none "Prometheus" "not running"
  fi
  if running grafana; then
    h=$(curl -sk --max-time 10 "https://$HOST:9450/api/health")
    if grep -qE '"database": ?"ok"' <<<"$h"; then ok "Grafana" "api/health: database ok"; else fail "Grafana" "api/health does not report database ok"; fi
  else
    none "Grafana" "not running"
  fi
fi

if want sourcebot; then
  section "Sourcebot"
  if running sourcebot; then
    http "Web" "https://$HOST:9460" "200|30[0-9]"
    c=$(code "https://$HOST:9460/api/mcp")
    if [[ "$c" != 000 ]]; then ok "MCP" "api/mcp answers $c"; else fail "MCP" "api/mcp does not answer"; fi
    n=$(docker logs --since 24h sourcebot 2>&1 | grep -ciE '\b(401|404)\b')
    if [[ $n -eq 0 ]]; then ok "Indexing" "no 401 or 404 in the last day"
    else warn "Indexing" "$n lines with 401 or 404 in the last day; the GitHub token cannot see a repository"
    fi
  else
    none "Sourcebot" "not running"
  fi
fi

if want langfuse; then
  section "Langfuse"
  if running langfuse-web; then
    h=$(curl -sk --max-time 10 "https://$HOST:9470/api/public/health")
    if grep -q '"OK"' <<<"$h"; then ok "Web" "api/public/health OK"; else fail "Web" "api/public/health does not answer OK"; fi
  else
    none "Langfuse" "not running"
  fi
fi

if want litellm; then
  section "LiteLLM and the LLM runtime"
  if running litellm; then
    http "Gateway" "https://$HOST:4000/health/liveliness" "200"
    if running ollama; then rt=ollama; elif running vllm; then rt=vllm; else rt=""; fi
    if [[ -z "$rt" ]]; then
      fail "Runtime" "neither Ollama nor vLLM runs (switch-llm.sh ollama)"
    elif [[ $MODEL -eq 0 ]]; then
      none "Model call" "skipped (--no-model)"
    else
      ok "Runtime" "$rt active"
      tid="server-test-$(date +%Y%m%d-%H%M%S)-$RANDOM"
      lf_pk=$(secret litellm LANGFUSE_PUBLIC_KEY)
      read -r c answer < <(llm_call local-model "$([[ -n "$lf_pk" ]] && echo "$tid")")
      if [[ "$c" == 200 ]]; then ok "Model call" "local-model answers: ${answer:0:40}"
      else fail "Model call" "local-model: HTTP $c ${answer:0:80}"
      fi
      if [[ "$c" == 200 && "$rt" == ollama ]]; then
        g=$(docker exec ollama ollama ps 2>/dev/null | sed -n '2p')
        if [[ "$g" == *"100% GPU"* ]]; then ok "GPU" "model runs 100% on the GPU"
        elif [[ -n "$g" ]]; then warn "GPU" "model split between CPU and GPU: it does not fit (see Models in the guide)"
        fi
        key=$(secret litellm LITELLM_MASTER_KEY)
        e=$(printf 'Authorization: Bearer %s\n' "$key" | curl -sk --max-time 120 -H @- -H 'Content-Type: application/json' \
            -d '{"model":"local-embed","input":"test"}' "https://$HOST:4000/v1/embeddings")
        if grep -q '"embedding"' <<<"$e"; then ok "Embeddings" "local-embed answers"; else fail "Embeddings" "local-embed gives no embedding"; fi
      fi
      # The trace of that call in Langfuse
      if [[ -z "$lf_pk" ]]; then
        none "Tracing" "LiteLLM has no Langfuse keys"
      elif [[ "$c" == 200 ]] && running langfuse-web; then
        lf_sk=$(secret litellm LANGFUSE_SECRET_KEY); found=""
        for _ in $(seq 1 12); do
          tc=$(printf 'user = "%s:%s"\n' "$lf_pk" "$lf_sk" | curl -sk -K - -o /dev/null -w '%{http_code}' --max-time 10 "https://$HOST:9470/api/public/traces/$tid")
          [[ "$tc" == 200 ]] && { found=1; break; }
          sleep 5
        done
        if [[ -n "$found" ]]; then ok "Tracing" "the call shows in Langfuse"
        else fail "Tracing" "no trace in Langfuse after 60 s (LiteLLM Langfuse keys or callback)"
        fi
      fi
    fi
  else
    none "LiteLLM" "not running"
  fi
fi

if want qdrant; then
  section "Qdrant"
  if running qdrant; then
    h=$(docker run --rm --network edge curlimages/curl -s --max-time 10 http://qdrant:6333/healthz 2>/dev/null)
    if [[ "$h" == *"passed"* ]]; then ok "API" "healthz check passed (from the edge network)"; else fail "API" "no answer from qdrant:6333 on the edge network"; fi
    http "Dashboard" "https://$HOST:6333/dashboard" "200|302" "dashboard"
  else
    none "Qdrant" "not running"
  fi
fi

if want graphdb; then
  section "Neo4j and Memgraph"
  if running neo4j; then
    pw=$(grep -E '^NEO4J_PASSWORD=' "$STACKS_DIR/graphdb/.env" 2>/dev/null | cut -d= -f2- | tr -d '\042\047')
    # The password goes in through the environment, so it never shows in the process list
    r=$(NEO4J_PASSWORD="$pw" docker exec -e NEO4J_PASSWORD neo4j cypher-shell -u neo4j "RETURN 1 AS ok" 2>&1 | tail -1)
    if [[ "$r" == 1 ]]; then ok "Neo4j" "RETURN 1 gives 1"; else fail "Neo4j" "query failed: ${r:0:100}"; fi
    http "Neo4j Browser" "https://$HOST:7474" "200|302" "Neo4j Browser"
  else
    none "Neo4j" "not running"
  fi
  if running memgraph; then
    if timeout 5 bash -c "exec 3<>/dev/tcp/${IP:-$HOST}/7688" 2>/dev/null; then ok "Memgraph" "bolt port 7688 open"; else fail "Memgraph" "bolt port 7688 closed"; fi
    http "Memgraph Lab" "https://$HOST:9490" "200|302" "Memgraph Lab"
  else
    none "Memgraph" "not running"
  fi
fi

if want openhands; then
  section "OpenHands"
  if ! running openhands; then none "OpenHands" "not running"
  else
    http "Web" "http://${IP:-$HOST}:3000" "200" "http://${IP:-$HOST}:3000"
    if [[ $MODEL -eq 0 ]]; then none "Model call" "skipped (--no-model)"
    else
      r=$(app_call openhands LLM_API_KEY)
      if [[ "$r" == OK:* ]]; then ok "Model call" "its key reaches local-model"; else fail "Model call" "${r:0:120}"; fi
    fi
  fi
fi

if want open-webui; then
  section "Open WebUI"
  if ! running open-webui; then none "Open WebUI" "not running"
  else
    http "Web" "https://$HOST:9485/health" "200"
    if [[ $MODEL -eq 0 ]]; then none "Model call" "skipped (--no-model)"
    else
      r=$(app_call open-webui OPENAI_API_KEY)
      if [[ "$r" == OK:* ]]; then ok "Model call" "its key reaches local-model"; else fail "Model call" "${r:0:120}"; fi
    fi
  fi
fi

if want runner; then
  section "CI runner"
  if running github-runner; then
    last=$(docker logs --tail 200 github-runner 2>&1 | grep -E 'Listening for Jobs|Running job|completed with result|Could not|401|error' | tail -1)
    if [[ "$last" == *"Listening for Jobs"* || "$last" == *"Running job"* || "$last" == *"completed with result"* ]]; then ok "GitHub" "connected, waiting for jobs"
    else fail "GitHub" "not connected: ${last:0:100}"
    fi
  else
    none "CI runner" "not running"
  fi
fi

printf '\n'
if [[ $((OKS + FAILS + WARNS)) -eq 0 ]]; then printf 'Nothing tested: none of these services runs.\n'
elif [[ $FAILS -eq 0 && $WARNS -eq 0 ]]; then printf '%sAll %d tests passed.%s\n' "$GREEN" "$OKS" "$RESET"
else printf '%s%d failed%s, %s%d warning(s)%s.\n' "$RED" "$FAILS" "$RESET" "$YELLOW" "$WARNS" "$RESET"
fi
echo "Not testable from here (see the Test of each service in the guide): the padlock on client PCs, signing in"
echo "through Dex in each app, a document upload in Open WebUI, an OpenHands sandbox task, and a CI job on a pull request."
