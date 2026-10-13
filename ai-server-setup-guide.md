# Self-Hosted AI Server Setup Guide

Sets up an internal-only AI server (VPN access, no public domain). Caddy fronts every web service with HTTPS from one internal CA, and Outline is the entry point.

How the software team uses the finished server day to day: [AI setup for software development](ai-setup-for-software-development.md). Works on a fresh box or one that already runs some of these services. Each step starts with a check: install, rebuild, or skip. Run `~/ai-server/server-status.sh` any time for a snapshot of what's installed, and `~/ai-server/server-test.sh` to test that it works (see Helper scripts under Before you start).

Steps are ordered by dependency, and no step edits a file created by an earlier step.

## Steps at a glance

| # | Step | What it does |
|---|---|---|
| Preq | [Prerequisite](#prerequisite-docker-and-nvidia) | Docker Engine, Compose, NVIDIA driver + Container Toolkit, GPU passthrough |
| 1 | [User permissions](#step-1-user-permissions) | Run `docker` without `sudo`; own `/opt/stacks` and `/opt/backups` |
| 2 | [Shared network and settings](#step-2-shared-network-settings) | `edge` network, plus `SERVER_HOST` / `SERVER_IP` kept in one file |
| 3 | [Caddy](#step-3-caddy-reverse-proxy) | Reverse proxy + internal CA; its own files are written once |
| 4 | [Trust the internal CA](#step-4-trust-the-internal-ca) | One-time cert import per client machine |
| 5 | [Infisical](#step-5-infisical-secrets) | Secrets in one place; `pull-secrets.sh` writes each stack's `.env` |
| 6 | [Dex](#step-6-dex-sign-in) | Single sign-on for every app, plus a sign-in gate for apps without their own login |
| 7 | [Outline](#step-7-outline-wiki) | Knowledge base, HTTPS entry point |
| 8 | [Portainer](#step-8-portainer-docker-ui) | Docker management UI |
| 9 | [Monitoring](#step-9-monitoring-stack) | Grafana, Prometheus, Node Exporter, dcgm-exporter |
| 10 | [Sourcebot](#step-10-sourcebot-code-search) | Lexical/regex code search |
| 11 | [Langfuse](#step-11-langfuse-llm-tracing) | LLM tracing |
| 12 | [LiteLLM](#step-12-litellm-gateway) | Model routing gateway, traces to Langfuse |
| 13 | [Ollama / vLLM](#step-13-ollama--vllm-runtime) | Local model runtime (one at a time — they share the GPU) |
| 14 | [Qdrant](#step-14-qdrant-vector-db) | Vector database for semantic search |
| 15 | [Graph DB](#step-15-neo4j--memgraph) | Neo4j + Memgraph, both running |
| 16 | [OpenHands](#step-16-openhands-agent) | Autonomous coding agent, plus MCP setup for GitHub, Codex CLI, Claude Code |
| 17 | [Open WebUI](#step-17-open-webui-chat) | Chat in the browser for everyone, with documents; sign-in through Dex |
| 18 | [CI runner](#step-18-ci-runner-github) | Tests, security checks, and AI review of pull requests, run on the server |
| 19 | [Maintain the Outline entry-point page](#step-19-outline-services-page) | Add a link each time you add a service |
| 20 | [Update workflow](#step-20-update-workflow) | Backup-then-update script, per stack |
| 21 | [Server test](#step-21-server-test) | Test every service with one script |
| 22 | [Housekeeping](#step-22-docker-housekeeping) | Review (not delete) unused Docker resources |

## Architecture overview

![Access and entry points: browser and developer machines connect through Caddy, which fronts Outline, Portainer, Grafana, Prometheus, Sourcebot, LiteLLM, Qdrant, Langfuse, Memgraph Lab, Neo4j Browser, Infisical (secrets), Dex (sign-in), and Open WebUI (chat). OpenHands (plain HTTP) and the Neo4j and Memgraph bolt ports are reached directly. Apps that sign in through Dex are marked SSO: Outline, Portainer, Grafana, Langfuse, and Open WebUI with a Dex button, Prometheus, Qdrant, Memgraph Lab, and Neo4j Browser behind the sign-in gate (Dex login first).](diagrams/architecture-access-map.svg)

![AI pipeline: LiteLLM routes to Ollama/vLLM and traces to Langfuse; Ollama produces embeddings for Qdrant; Prometheus scrapes Node Exporter, dcgm-exporter, and LiteLLM, and Grafana reads Prometheus. OpenHands calls LiteLLM, and can query Qdrant and Neo4j/Memgraph directly. Open WebUI calls LiteLLM for chats and embeddings, and keeps documents in Qdrant. The CI runner calls LiteLLM for AI review of pull requests (optional).](diagrams/architecture-ai-pipeline.svg)

## Before you start

**Server name and IP.** Two values every stack uses. Step 2 stores them in `/opt/stacks/shared/.env`, the only place you edit them; `sync-shared-env.sh` copies them into each stack's `.env`.
- `SERVER_HOST` is the address people and tools use: every URL in this guide, and the address that apps with their own sign-in (Infisical, Dex, Outline, Sourcebot, Langfuse) treat as their own.
- `SERVER_IP` is only needed by Caddy, so that APIs also answer on the plain IP (e.g. `https://<SERVER_IP>:4000`) for machines that can't resolve the name. Infisical, Dex, Outline, Sourcebot, Langfuse, and the apps behind the sign-in gate answer on `SERVER_HOST` only, because their sign-in needs one fixed address.
- The guide writes them as `${SERVER_HOST}` / `${SERVER_IP}` in shell commands (shell variables, so commands copy and run as they are), `${SERVER_HOST}` in compose files (filled from each stack's `.env`), `{$SERVER_HOST}` / `{$SERVER_IP}` in Caddy files (read from Caddy's environment), and `<SERVER_HOST>` / `<SERVER_IP>` in addresses to open and in files that cannot read variables (type your values there).

**Load the two variables in your shell** before running the guide's commands. Before Step 2 (no shared file yet), set them by hand; afterwards, read them from the shared file, which also picks up a later change:
```bash
export SERVER_HOST=<your server name> SERVER_IP=<your server IP>    # before the shared file exists
set -a; . /opt/stacks/shared/.env; set +a                         # once /opt/stacks/shared/.env exists
echo "$SERVER_HOST $SERVER_IP"
```
To have them in every new SSH session, add the `set -a; . /opt/stacks/shared/.env; set +a` line to `~/.bashrc`. On your PC (for `scp` and the like), use the `export` line.

**Name or IP?** Use a name only if your internal DNS can have a record for it. With hosts files, every user has to edit one (and edit it again if the IP changes), which costs more than a readable URL is worth. Without DNS, set `SERVER_HOST` to the IP: everything then works on the IP alone, and you can switch to a name later.

**Google sign-in needs a real domain.** Google accepts a sign-in address only if it ends in a public domain ending such as `.com`, and rejects IPs and made-up names like `ai.internal`. It checks only the text and never connects, so a name that exists only in hosts files is enough. If you may want Google sign-in (in Dex or Infisical), pick a name under a domain your company owns, e.g. `ai.domain.com`; see [Google sign-in](options/google-sign-in.md).

**Make the name resolve.** If `SERVER_HOST` is a name, every machine that uses it needs to resolve it to `SERVER_IP` — client PCs, and the server itself (the verify commands run there). Either add a DNS record on your internal DNS (one change, covers everyone), or add a hosts-file line on each machine:
```
<SERVER_IP>    <SERVER_HOST>
```
Hosts file: `/etc/hosts` on Linux/macOS, `C:\Windows\System32\drivers\etc\hosts` on Windows (edit as administrator). Avoid names ending in `.local` (reserved for mDNS). Containers don't need it: they reach each other by container name over `edge`.

**Changing the name or IP later** (new IP, or a DNS name added): edit `/opt/stacks/shared/.env` and run `sync-shared-env.sh` (Step 2) — or, with Infisical (Step 5), edit `prod:/shared` there and run `pull-secrets.sh`. Installs from older versions of this guide, which used only `SERVER_IP`, first need [Upgrading an older install](options/upgrade-older-install.md).

**`confirm` helper.** Every destructive command is written as `confirm "<what it does>" && <command>`. Paste this once per terminal session:
```bash
confirm() {
  read -r -p "$1 [y/N] " reply
  case "$reply" in
    [Yy][Ee][Ss]|[Yy]) return 0 ;;
    *) echo "Aborted — nothing changed."; return 1 ;;
  esac
}
```

**Helper scripts.** All helper scripts (`*.sh`) live in one folder in your home directory on the server, `~/ai-server`. The steps that need a script inside a stack folder link it there (`ln -s`), so updating a script means replacing it in `~/ai-server` only. Which script goes where, updating, and checking the links: [Helper scripts](options/helper-scripts.md).
1. On the server, create the folder:
   ```bash
   mkdir -p ~/ai-server
   ```
2. On your PC, in this repo's folder, copy all scripts from this repo (its `scripts` folder) to it:
   ```bash
   scp scripts/*.sh <user>@${SERVER_HOST}:ai-server/
   ```
3. On the server, make them executable:
   ```bash
   chmod +x ~/ai-server/*.sh
   ```

Every script shows its manual with `-h` (or `--help`): what it does, its options, examples, and the files it uses, e.g. `~/ai-server/pull-secrets.sh -h`.

**Firewall.** The server is meant to be reachable from the office network only. Ports that Docker publishes bypass `ufw`, so `ufw` alone does not limit them; [Firewall](options/firewall.md) sets both up (office network only, through Docker's `DOCKER-USER` chain).

**Volumes are `external: true`.** Create each one with `docker volume create <name>` before a stack's first `up -d`. Compose never deletes external volumes, so `docker compose down -v` and removing containers never lose data. Backups work the same either way.

**Check-first.** Each step starts with a **Check** line listing its containers. Look them up with:
```bash
docker ps -a --filter name=<container-name> --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
```

| Result | Do |
|---|---|
| No output | Not installed — do the step |
| `Up …` and matches this guide | Skip the step |
| Exists but differs from this guide | Run the step's **Check the result** to see what differs. Fix that file and recreate; or start over with the step's **Clean reinstall** (keep the volumes to keep the data), then its Install |

To compare an existing container with the guide: `docker inspect <container-name> --format '{{json .Config.Env}}'`.

## Service status check

| Step | Service | Container | Needs |
|---|---|---|---|
| Preq | Docker, Compose, NVIDIA driver, Toolkit | — (use the pre-flight check) | — |
| 3 | Caddy | `caddy` | `edge` |
| 5 | Infisical | `infisical` | Caddy |
|  | Infisical database | `infisical-postgres` | — |
|  | Infisical cache | `infisical-redis` | — |
| 6 | Dex | `dex` | Caddy |
|  | Sign-in gate | `oauth2-proxy` | Dex |
| 7 | Outline | `outline` | Caddy; Dex for sign-in |
|  | Outline database | `outline-postgres` | — |
|  | Outline cache | `outline-redis` | — |
| 8 | Portainer | `portainer` | Caddy |
| 9 | Grafana | `grafana` | Caddy; Prometheus as data source (added in Grafana's UI) |
|  | Prometheus | `prometheus` | Caddy; scrapes Node Exporter, dcgm-exporter, LiteLLM |
|  | Node Exporter | `node-exporter` | `edge` |
|  | dcgm-exporter | `dcgm-exporter` | `edge`, GPU |
| 10 | Sourcebot | `sourcebot` | Caddy |
|  | Sourcebot database | `sourcebot-postgres` | — |
|  | Sourcebot cache | `sourcebot-redis` | — |
| 11 | Langfuse web | `langfuse-web` | Caddy |
|  | Langfuse worker | `langfuse-worker` | — |
|  | Langfuse database | `langfuse-postgres` | — |
|  | Langfuse cache | `langfuse-redis` | — |
|  | Langfuse traces store | `langfuse-clickhouse` | — |
|  | Langfuse file store | `langfuse-minio` | — |
| 12 | LiteLLM | `litellm` | Caddy; Langfuse (optional); Ollama/vLLM for local models |
|  | LiteLLM database | `litellm-postgres` | — |
| 13 | Ollama | `ollama` (or `/opt/stacks/llm-runtime/switch-llm.sh status`) | `edge`, GPU |
|  | vLLM (instead of Ollama) | `vllm` | `edge`, GPU |
| 14 | Qdrant | `qdrant` | Caddy |
| 15 | Neo4j | `neo4j` (or `/opt/stacks/graphdb/graphdb.sh status`) | Caddy (web UI only) |
|  | Memgraph | `memgraph` | Caddy (web UI only) |
| 16 | OpenHands | `openhands` | Caddy, LiteLLM, Docker socket |
| 17 | Open WebUI | `open-webui` | Caddy, Dex, LiteLLM, Qdrant |
| 18 | CI runner | `github-runner` | GitHub, Docker socket, LiteLLM |

"Caddy" means the service is reached through Caddy; every service also joins `edge`. Estimated CPU, RAM, and disk per service, with totals, are in [Resource usage](#resource-usage).

## Resource usage

What each container uses, to size the server before installing.

| Step | Service | CPU | RAM | Disk |
|---|---|---|---|---|
| Preq | Docker engine (dockerd, containerd, one shim per container, port proxies) | 1–2% → 5–10% while starting or pulling | 0.3–0.5 GB (up to 1.2 GB without the daemon settings) | ~5 GB (packages, base images) + logs and old images over time |
| 3 | Caddy | <1% → 5–20% under load | 30–60 MB | <0.1 GB |
| 5 | Infisical | 1–2% → 20–50% while serving pulls | 300–500 MB | ~1 GB image |
|  | Infisical database | <1% → 5–10% | 50–100 MB | <1 GB (secrets are small) |
|  | Infisical cache | <1% | 10–30 MB | <0.1 GB |
| 6 | Dex | <1% → 5% at sign-in | 20–50 MB | <0.1 GB |
|  | Sign-in gate | <1% → 5% | 10–30 MB | <0.1 GB |
| 7 | Outline | 1–3% → 20–60% (page loads, imports) | 300–600 MB | ~1 GB image + attachments |
|  | Outline database | <1% → 5–20% | 50–150 MB | <1 GB, grows with documents |
|  | Outline cache | <1% | 10–50 MB | <0.1 GB |
| 8 | Portainer | 1–2% → 10–20% | 50–100 MB | ~0.3 GB |
| 9 | Grafana | 1–2% → 10–40% (dashboards) | 100–250 MB | ~0.5 GB |
|  | Prometheus | 1–5% → 20–50% (queries, compaction) | 200–600 MB | 1–5 GB (15 days of metrics) |
|  | Node Exporter | <1% → 2–5% per scrape | 10–30 MB | <0.1 GB |
|  | dcgm-exporter | 1–3% → 5% | 150–300 MB | ~1 GB image |
| 10 | Sourcebot | 1–5% → 100–200% while indexing | 0.5–2 GB (more while indexing) | 1–3× the size of the indexed repos |
|  | Sourcebot database | <1% → 5% | 50–100 MB | <1 GB |
|  | Sourcebot cache | <1% | 10–50 MB | <0.1 GB |
| 11 | Langfuse web | 1–3% → 20–50% | 300–700 MB | ~1 GB image |
|  | Langfuse worker | 2–5% → 50–100% while ingesting | 300–700 MB | ~1 GB image |
|  | Langfuse database | <1% → 5–10% | 50–150 MB | <1 GB |
|  | Langfuse cache | <1% → 5% | 20–100 MB | <0.1 GB |
|  | Langfuse traces store | 2–5% → 50–150% (queries, merges) | 1–2 GB | Grows with traces; a few GB a year for a small team |
|  | Langfuse file store | <1% → 5% | 100–200 MB | Grows with trace events |
| 12 | LiteLLM | 1–3% → 20–50% per busy stream | 300–700 MB | ~1.5 GB image |
|  | LiteLLM database | <1% → 5–10% | 50–100 MB | <1 GB (request logs) |
| 13 | Ollama | <1% → 50–100% while generating (the GPU does the heavy work) | 1–4 GB (model in VRAM, see [Models](#models)) | ~4 GB image (models: see [Models](#models)) |
|  | vLLM (instead of Ollama) | 3–10% → 100% while generating | 4–16 GB (model in VRAM, see [Models](#models)) | ~10 GB image (models: see [Models](#models)) |
| 14 | Qdrant | <1% → 20–100% (search, indexing) | 100 MB + about the size of the vectors | About the size of the vectors (1M × 768-dim ≈ 3–4 GB) |
| 15 | Neo4j | 1–3% → 20–100% (queries) | 1–2 GB (Java) | ~0.5 GB image + graph |
|  | Memgraph | 1–2% → 20–100% (queries) | 0.3 GB + the whole graph (in memory) | ~1 GB image + snapshots |
| 16 | OpenHands | 1–3% → 50–200% per running task | 300–600 MB + 0.5–2 GB per running task | ~3 GB images (app + sandbox) |
| 17 | Open WebUI | <1% → 10–30% while answering or reading documents | 0.5–1.5 GB | ~4 GB image + chats and uploaded files |
| 18 | CI runner | ~0% idle → up to 400% while a job runs (capped) | 0.1–0.2 GB idle, up to 6 GB per job + job containers | ~2 GB image + job images (Playwright ~2 GB) |
| | **Total without models** | **≈ 20–40% idle** | **≈ 7–33 GB** | **≈ 37–69 GB** |

These are rough figures for a small team at normal use; check the real numbers with `docker stats --no-stream` and `docker system df`.
- **CPU** is shown the way `docker stats` shows it: percent of **one** core, so 100% is one full core and 200% is two. Each cell gives idle → busy. Together, everything idles at about 20–40% of one core; busy moments are short (Sourcebot indexing, Langfuse ingesting, OpenHands tasks, model replies). On an 8-core server, `docker stats` can show up to 800% in total.
- **RAM total:** every container at once, with one LLM runtime (Ollama for the low end, vLLM for the high end). Models load into GPU memory (VRAM), not RAM — as long as they fit (see [Models](#models)). An OpenHands task, a large Qdrant collection, or a large graph push toward the high end.
- **Docker itself:** the `Preq` row. Without the [Docker daemon settings](#docker-daemon-settings), most of it is `docker-proxy` — one process per published port, and Caddy publishes 60+; with them it drops to the lower end. The operating system needs its own ~1–2 GB on top of the total.
- **Disk over time:** container logs are capped by the [Docker daemon settings](#docker-daemon-settings); old images are cleared with Step 22.
- **Disk total:** images plus typical data, with both LLM runtimes installed but no models. Add each model's download size from [Models](#models); Sourcebot, Langfuse, and Prometheus data grow over time.

### Models

Open-weight models that run on a 16 GB GPU, best first, as ranked by the [Artificial Analysis Intelligence Index](https://artificialanalysis.ai/leaderboards/models) (one score across reasoning, knowledge, math, coding, and agent tasks; October 2026).
- **Next-Lower OpenAI:** the closest OpenAI model (at its nearest reasoning setting, non-reasoning included) that scores lower on that index; the local model is at least about that good.
- **Runtime:** `O` = Ollama, `v` = vLLM, `O/v` = both. The Note gives the Ollama tag and/or the vLLM model ID; vLLM uses its own 4-bit build, so its sizes can differ.
- **Disk** is the download; **VRAM Used** includes room for about 8k–16k tokens of context.
- **Context (est.):** the longest context that still fits on the 16 GB GPU (the models themselves allow 128k–256k). Ollama uses only 4k by default on GPUs under 24 GB and silently cuts off anything longer, which breaks agent tools (Claude Code, Codex) whose prompts run to 20k tokens and more; the guide sets `OLLAMA_CONTEXT_LENGTH=32768` in `/opt/stacks/llm-runtime/.env`. It applies to every Ollama model: the models in the first three rows then spill more onto the CPU, so lower it (e.g. `16384`) if you mainly use those. 8k tokens ≈ 800 lines of code.

| Model | Runtime | Next-Lower OpenAI | Disk | VRAM Used | Context (est.) | Note |
|---|---|---|---|---|---|---|
| Qwen3.8 27B | O | GPT-6 Luna (high) | ~18 GB | 18 GB+, doesn't fit | 8k–16k | `qwen3.8:27b`. Best quality, but partly on the CPU: ~3–8 words/s; for one-off hard questions. Needs ~4–6 GB free RAM. |
| Qwen3.6 35B A3B | O | GPT-5 mini (high) | ~23 GB | 23 GB+, doesn't fit | 16k–32k | `qwen3.6:35b-a3b`. Mixture-of-experts, so usable split GPU/CPU: ~10–20 words/s. Needs ~8–10 GB free RAM. |
| Gemma 4 26B A4B | O | GPT-5.6 Luna (non-reasoning) | ~16 GB | ~16–17 GB, just over | ~8k | `gemma4:26b`. Small CPU spill, stays fast. |
| Gemma 4 12B | O/v | GPT-5 nano (high), GPT-4.1 | ~7.7 GB (vLLM: 10.3 GB) | ~9–11 GB (vLLM: 14.4 GB) | 32k–64k (vLLM: ~16k) | `gemma4:12b` / `google/gemma-4-12B-it-qat-w4a16-ct`. **Suggested default, and suggested for vLLM** with `VLLM_MAX_MODEL_LEN=16384`. Reads images. |
| Qwen3.5 9B | O | o1-mini | ~6.6 GB | ~8–10 GB | 64k–128k | `qwen3.5:9b`. Fits with the most room for context. |
| gpt-oss 20B | O/v | GPT-4o | ~13–14 GB | ~15 GB | ~32k (vLLM: 8k) | `gpt-oss:20b` / `openai/gpt-oss-20b`. Fills the GPU; in vLLM set `VLLM_MAX_MODEL_LEN=8192`. |

**None of these reaches a current hosted model** such as GPT-5.6 Luna (score 37, against 9–14 for the models that fit fully and 34 for Qwen3.8 27B). For tasks that need that quality, add a hosted model next to the local ones in LiteLLM ([Hosted models](options/litellm-hosted-models.md)), so clients keep one address and key.

**Embeddings** (for Qdrant; not ranked on the index): `qwen3-embedding:0.6b` on Ollama, ~0.6 GB disk, ~1 GB GPU memory, many languages — **suggested**. It runs next to the chat model; while vLLM runs, Ollama is stopped, so embeddings are unavailable until you switch back.

Ollama keeps one chat model in GPU memory and swaps on demand: calling another model unloads the first (a few seconds' pause). List any of these in LiteLLM's `config.yaml` to make them available to clients.

**Rule of thumb for other models:** a 4-bit model needs about 0.6 GB per billion parameters, plus 2–5 GB for context. On 16 GB, that is up to about 14B for a dense model, or about 20B for a mixture-of-experts model. New releases appear often; check the [Ollama library](https://ollama.com/library) and the [Intelligence Index](https://artificialanalysis.ai/leaderboards/models), and judge sizes by the same rule.

**What happens with a model larger than the GPU** (like the first three rows):
- **Ollama** still runs it: it loads as many layers as fit into VRAM and keeps the rest in system RAM, computed by the CPU. It needs that much free RAM and gets slower.
  - A *mixture-of-experts* model uses only a few billion of its parameters per word, so the CPU part stays manageable — roughly 10–25 words per second, against 40–70 for a model that fits.
  - A *dense* model uses all its weights for every word, so the CPU part dominates — roughly 2–8 words per second.
  - Check with `docker exec ollama ollama ps`: the `PROCESSOR` column shows e.g. `25%/75% CPU/GPU` when a model doesn't fit; `100% GPU` is what you want.
- **vLLM** doesn't run it: it stops at startup with an out-of-memory error. Its `--cpu-offload-gb` option can push part of the model into RAM, but at a large speed cost; for models bigger than the GPU, Ollama is the better runtime.
- **Context shrinks first:** a model that only just fits leaves little room for context. Keep `num_ctx` (Ollama) or `VLLM_MAX_MODEL_LEN` (vLLM, in `/opt/stacks/llm-runtime/.env`) modest, e.g. 8k–16k, on a 16 GB GPU.
- **Slow answers hit timeouts** in LiteLLM, OpenHands, or other clients; raise them if you use a model that spills to the CPU.

Speeds and sizes are rough; they depend on the GPU, CPU, RAM speed, context length, and the exact model build.

## Access map

| Step | Service | Access | Kind | Notes |
|---|---|---|---|---|
| 3 | Caddy health | `https://<SERVER_HOST>:9500` | Health check | Assigned port |
| 5 | Infisical | `https://<SERVER_HOST>:8080` | UI + API | Own default; own login, optional Google sign-in (SAML/OIDC is paid) |
| 6 | Dex | `https://<SERVER_HOST>:5556/dex` | Browser UI | Own default; sign-in pages only |
| 7 | Outline | `https://<SERVER_HOST>` | Browser UI | Assigned 443 (Outline's default is 3000) |
| 8 | Portainer | `https://<SERVER_HOST>:9443` | Browser UI | Own default |
| 9 | Grafana | `https://<SERVER_HOST>:9450` | Browser UI | Shared block — Monitoring (9450–9454) |
|  | Prometheus | `https://<SERVER_HOST>:9090` | Browser UI | Own default; behind the sign-in gate |
|  | Node Exporter / dcgm-exporter | internal, `edge` (9100 / 9400) | API | Scraped by Prometheus only |
| 10 | Sourcebot | `https://<SERVER_HOST>:9460` | UI + API | Shared block — Code Intelligence (9460–9464); MCP at `/api/mcp` |
| 11 | Langfuse | `https://<SERVER_HOST>:9470` | UI + API | Shared block — LLM Observability (9470–9474) |
| 12 | LiteLLM | `https://<SERVER_HOST>:4000` | UI + API | Own default; OpenAI-compatible API |
| 13 | Ollama | internal, `edge` (11434) | API | Used through LiteLLM |
|  | vLLM | internal, `edge` (8000) | API | Used through LiteLLM |
| 14 | Qdrant | `https://<SERVER_HOST>:6333` | UI + API | Own default; behind the sign-in gate; gRPC 6334 internal only |
| 15 | Neo4j Browser | `https://<SERVER_HOST>:7474` | Browser UI | Own default; behind the sign-in gate |
|  | Neo4j bolt | `<SERVER_HOST>:7687` | Driver | Direct, not via Caddy |
|  | Memgraph Lab | `https://<SERVER_HOST>:9490` | Browser UI | Shared block — Graph DB Dashboards (9490–9494); behind the sign-in gate |
|  | Memgraph bolt | `<SERVER_HOST>:7688` | Driver | Direct; remapped off Neo4j's 7687 |
| 16 | OpenHands | `http://<SERVER_IP>:3000` | Browser UI | Own default; plain HTTP by IP, not via Caddy: the browser also connects straight to each sandbox's random port |
| 17 | Open WebUI | `https://<SERVER_HOST>:9485` | Browser UI | Shared block — AI Chat (9485–9489); its default 8080 is Infisical's |
| — | *Free* | `9455–9459`, `9465–9469`, `9475–9479`, `9485–9489`, `9495–9499` | — | Future categories; already published by Caddy |

Every `https://` row also answers on `https://<SERVER_IP>:<port>`, for machines that can't resolve the name, except Infisical, Dex, Outline, Sourcebot, Langfuse, Open WebUI, and the apps behind the sign-in gate (name only). With Dex deployed, every app uses the same account: Outline, Grafana, Portainer, Langfuse, Open WebUI, and the LiteLLM Admin UI (up to 5 users) through their "Dex" button, the gated apps through one shared sign-in. The bolt ports aren't behind Caddy, so they answer on both anyway.

**Port rules:** a service keeps its own default port whenever nothing else uses it — that comes first. Only services that would collide (most default to 3000) get a port from the shared 9450–9499 range, in blocks of 5 per category. Caddy publishes every port in Step 3, so a fresh install never edits its `compose.yaml`; a server whose Caddy predates a newly added service adds that one port line ([Upgrading an older install](options/upgrade-older-install.md#caddy-ports-for-later-services)). Internal service-to-service traffic uses plain `http://<container>:<port>` over `edge`, never Caddy's HTTPS. Bolt and gRPC aren't HTTP, so Caddy doesn't front them.

---

## Prerequisite: Docker and NVIDIA

The same commands install on a fresh box and upgrade an existing one.

### Pre-flight check

One line per item, marked green `[  OK  ]` or red `[FAILED]` like Ubuntu boot messages. `server-status.sh` runs the same checks.
```bash
chk() { local out; if out=$(eval "$2" 2>/dev/null) && [ -n "$out" ]; then printf '\e[32m[  OK  ]\e[0m %-15s %s\n' "$1" "$out"; else printf '\e[31m[FAILED]\e[0m %-15s %s\n' "$1" "${3:-not found}"; fi; }

chk "OS"            'lsb_release -ds'
chk "Docker"        'docker --version'
chk "Compose"       'docker compose version --short'
chk "Kernel module" 'grep -m1 NVRM /proc/driver/nvidia/version | grep -oE "(Open )?Kernel Module|[0-9]+\.[0-9]+\.[0-9]+" | paste -sd" "'
chk "Driver pkgs"   'dpkg -l | grep -E "^ii +(nvidia-(driver|headless|utils)|linux-modules-nvidia)-" | tr -s " " | cut -d" " -f2 | paste -sd" "'
chk "nvidia-smi"    'nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader'
chk "Toolkit"       'nvidia-ctk --version | head -1'
chk "CDI spec"      'date -r /etc/cdi/nvidia.yaml "+generated %F %R"'
chk "GPU in Docker" 'docker run --rm --device nvidia.com/gpu=all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi --query-gpu=name --format=csv,noheader' "container cannot see the GPU"
```

| Output shows | Do |
|---|---|
| Every line `[  OK  ]` | Skip to Step 1 |
| `Docker` or `Compose` not found | Docker section |
| `Kernel module` and `Driver pkgs` not found | Driver section → install |
| `Kernel module` shows a version, `nvidia-smi` not found | Driver section → "If `nvidia-smi` isn't found" |
| `nvidia-smi` version differs from `Kernel module` | Reboot (driver updated but old module still loaded); if it persists, [clean driver reinstall](options/preq-clean-reinstall.md#reinstall-the-nvidia-driver) |
| `Toolkit` or `CDI spec` not found, or CDI spec older than the last driver change | Toolkit section |
| Only `GPU in Docker` is `[FAILED]` | [Clean driver reinstall](options/preq-clean-reinstall.md#reinstall-the-nvidia-driver) |

**Starting completely fresh, or recovering a broken install?** See [Clean reinstall](options/preq-clean-reinstall.md): wipe all Docker data, remove Docker, the NVIDIA driver, or the Container Toolkit completely.

### Docker Engine + Compose plugin

**Check:** `docker --version && docker compose version`. Both print a version → already installed; the install command below also upgrades in place.

Add Docker's apt repository (safe to re-run):
```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
```

Install or upgrade:
```bash
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

**Verify:**
```bash
docker run hello-world
docker --version
docker compose version
```

To pin a specific version:
```bash
apt-cache madison docker-ce | awk '{ print $3 }'   # list available versions
sudo apt-get install -y docker-ce=<version-string> docker-ce-cli=<version-string> containerd.io docker-buildx-plugin docker-compose-plugin
```

### NVIDIA driver

**Check:**
```bash
nvidia-smi --query-gpu=driver_version --format=csv,noheader
dpkg -l | grep -E '^ii\s+(nvidia-driver-|nvidia-headless-|linux-modules-nvidia-|nvidia-utils-)'
```
The `dpkg` list is what's actually installed. A `--gpgpu` install shows `nvidia-headless-*` and no `nvidia-driver-*` line; that's expected. If `dpkg` shows nothing but `nvidia-smi` works, the driver came from NVIDIA's `.run` installer; do a [clean driver reinstall](options/preq-clean-reinstall.md#reinstall-the-nvidia-driver).

**Reading package names** (e.g. `nvidia-headless-no-dkms-595-server-open`):

| Part | Meaning |
|---|---|
| `595` | Driver branch |
| `-server` | Server branch, longer support — use this on a headless box |
| `-open` | Open kernel modules — use for Turing (RTX 20-series/T4) and newer; leave off for older GPUs |

Check your GPU and list the drivers available for it:
```bash
nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader
sudo ubuntu-drivers list --gpgpu
```

**Install** (headless compute driver; use the exact string from `list` above):
```bash
sudo ubuntu-drivers install --gpgpu nvidia:595-server-open
confirm "Reboot the server now?" && sudo reboot
```

**Verify:** both show the version you installed, with no errors.
```bash
nvidia-smi
cat /proc/driver/nvidia/version
```

**If `nvidia-smi` isn't found:** the `nvidia-utils-<version>-server` package is missing. Find the build that matches your driver version (from `/proc/driver/nvidia/version`) and install exactly that. Ignore the shell's "can be installed with…" hint; it's often stale.
```bash
sudo apt update
apt-cache madison nvidia-utils-<version>-server   # e.g. nvidia-utils-595-server
sudo apt install nvidia-utils-<version>-server=<exact-version-string-from-madison>
```
If no matching build exists, do a [clean driver reinstall](options/preq-clean-reinstall.md#reinstall-the-nvidia-driver).

### NVIDIA Container Toolkit

**Check:** `nvidia-ctk --version` prints a version → installed. The command below also upgrades in place. Purging `*nvidia*` for the driver removes the toolkit too, so reinstall it after a driver reinstall. To remove it completely, see [Clean reinstall](options/preq-clean-reinstall.md#remove-the-container-toolkit).

Add NVIDIA's apt repository (safe to re-run):
```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
```

Install, configure Docker, and generate the CDI spec:
```bash
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```
Re-run the `cdi generate` line whenever the driver or toolkit changes.

**Verify:**
```bash
docker run --rm --device nvidia.com/gpu=all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi
```
A GPU table means the whole chain works.

**Always use the CDI form** (`--device nvidia.com/gpu=all`, or `devices: [nvidia.com/gpu=all]` in compose). `--gpus all` and Compose's `deploy.resources.reservations.devices` can fail with `AMD CDI spec not found` on some Docker/toolkit versions.

### Docker daemon settings

Two settings in `/etc/docker/daemon.json` that this server needs:
- **`"userland-proxy": false`** — the kernel forwards published ports instead of one `docker-proxy` process per port. Caddy publishes 60+ ports (most of 9450–9499 are reserved for later services), which would otherwise mean 100+ processes and up to ~1 GB of RAM; with this setting the reserved ports cost nothing.
- **Log rotation** — Docker keeps container logs forever by default; this keeps at most 5 files of 10 MB per container, older ones compressed. For ~5 users, that holds about 1–3 weeks of logs for the busiest containers (LiteLLM, the LLM runtime, Langfuse) and months for the rest; worst case ~1.75 GB of disk for all containers together.

**Check:** `cat /etc/docker/daemon.json` — if it already has `"userland-proxy": false` and the `log-opts` below, skip.

The NVIDIA Container Toolkit (above) wrote its own entry into this file, so merge the settings in rather than overwriting it (a copy of the old file is kept as `daemon.json.bak`):
```bash
sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak 2>/dev/null
confirm "Merge these settings into /etc/docker/daemon.json?" && sudo python3 - <<'EOF'
import json, os
path = "/etc/docker/daemon.json"
cfg = json.load(open(path)) if os.path.exists(path) else {}
cfg["userland-proxy"] = False
cfg["log-driver"] = "json-file"
cfg["log-opts"] = {"max-size": "10m", "max-file": "3", "compress": "true"}
json.dump(cfg, open(path, "w"), indent=2)
print(json.dumps(cfg, indent=2))
EOF
confirm "Restart Docker now? Every running container stops briefly and starts again." && sudo systemctl restart docker
```
The printed file should still contain the `nvidia` runtime entry next to the new settings.

**Verify:**
```bash
pgrep -c docker-proxy                          # 0 (or no output) once containers are running
docker info --format '{{.LoggingDriver}}'      # json-file
```
The log limits apply to containers created from now on. Containers that already exist keep their old (unlimited) logs until they're recreated — at their next `update-stack.sh` or `docker compose up -d --force-recreate`.

**Reading logs:** use `docker logs`, which reads all of a container's files, compressed ones included — e.g. `docker logs --since 2h litellm`, or `docker logs --since 24h langfuse-web 2>&1 | grep -i error`. Portainer shows them too.

**Sizing the limit:** rotation is by size, not time, so a week of logs needs `max-size × max-file ≥ daily volume × 7`. After a day or two, list the largest logs and divide each by the days since that container started:
```bash
sudo sh -c 'for f in /var/lib/docker/containers/*/*-json.log; do printf "%8s  %s\n" "$(du -h "$f" | cut -f1)" "$(docker inspect --format "{{.Name}}" "$(basename "$(dirname "$f")")")"; done | sort -h | tail -8'
```
The guide keeps at most 3 files of 10 MB per container (about 30 MB each, roughly 1 GB for all of them), enough for a development server; for a week of a busy container, raise `max-file` (to 5–10) in `/etc/docker/daemon.json` and restart Docker. For a strict time limit (e.g. audits), use the `journald` log driver with a 7-day retention instead.

## Step 1: User permissions

Run this guide as your normal user, not as root. Commands that need root already start with `sudo`; after this step, `docker` and everything under `/opt/stacks` and `/opt/backups` work without it.

**Check:** `docker ps` works without `sudo`, and `ls -ld /opt/stacks /opt/backups` shows your user as owner — if both, skip.

Let your user run `docker`:
```bash
sudo usermod -aG docker $USER
newgrp docker
docker ps   # works without sudo
```
Membership in the `docker` group is effectively root access on this server (a container can mount any host path); only add users you would give `sudo` to.

Create the stack and backup folders, owned by your user (`/opt` itself belongs to root, so a plain `mkdir` there fails):
```bash
sudo install -d -o "$USER" -g "$USER" /opt/stacks /opt/backups
```
If they already exist and belong to root (from an earlier install done with `sudo`), take them over instead:
```bash
confirm "Make $USER the owner of everything under /opt/stacks and /opt/backups?" && sudo chown -R "$USER":"$USER" /opt/stacks /opt/backups
```
This only changes the stack files (compose, `.env`, config) and backups. Service data lives in Docker volumes under `/var/lib/docker` and is not touched.

Backup files that `update-stack.sh` writes through a container end up owned by root; deleting old backups later needs `sudo rm`.

## Step 2: Shared network, settings

**Check:** `docker network ls --filter name=^edge$` — if `edge` is listed, skip the network. `ls /opt/stacks/shared/.env` — if it exists, skip the settings file.

**Shared network.** Create the `edge` network once; Caddy and every app join it to reach each other:
```bash
docker network create -o com.docker.network.bridge.name=br-edge edge
```
The option names the network's bridge `br-edge` on the server (as in `ip -br link`) instead of a random `br-<id>`.

**Recreating `edge` later** (to rename its bridge, or after it was removed): every container on it must then be recreated with `docker compose up -d --force-recreate`. A plain `up -d` or `start` reuses the old container, which still points at the removed network, and fails with "network … not found". See [Upgrading an older install](options/upgrade-older-install.md#edge-network).

**Readable cable names (optional).** Docker connects each container to a network with a cable named `veth<random>`, so `ip -br link` lists dozens of meaningless names. `docker-veth-name.sh` renames them after their container (`veth-ol` for Outline, `veth-ol-pg` for its database, `veth-sb2` for Sourcebot on its second network, and so on). Run it from `~/ai-server` ([Helper scripts](options/helper-scripts.md)):
```bash
sudo ~/ai-server/docker-veth-name.sh
ip -br link | grep veth-
```
The names do not last: Docker gives a container new cables each time it is created or restarted, so run the script again after an update, a restart, or a reboot. Renaming changes only the name, not how containers reach each other. `~/ai-server/docker-veth-name.sh -h` shows the short name rules.

**Shared settings.** `/opt/stacks/shared/.env` is the one place for values every stack uses (see "Before you start"):
```bash
mkdir -p /opt/stacks/shared
```

`/opt/stacks/shared/.env`:
```env
SERVER_HOST=<server-IP-or-DNS-name>   # the IP, unless the name has an internal DNS record
SERVER_IP=<server-IP>
```
Each later step copies these two lines into its own `.env` where it needs them. Nothing reads this file at runtime; the stacks stay self-contained.

Link `sync-shared-env.sh` from `~/ai-server` into the folder ([Helper scripts](options/helper-scripts.md)); `pull-secrets.sh` runs it from there:
```bash
ln -sf ~/ai-server/sync-shared-env.sh /opt/stacks/shared/sync-shared-env.sh
```

**Changing a value later:** edit `/opt/stacks/shared/.env`, preview, then apply:
```bash
/opt/stacks/shared/sync-shared-env.sh --dry-run
/opt/stacks/shared/sync-shared-env.sh
```
It updates `SERVER_HOST` / `SERVER_IP` in every `/opt/stacks/*/.env` that already has them (it never adds lines), saves each old file as `.env.bak-<timestamp>`, asks before changing anything, and recreates only the stacks that changed (a reload isn't enough: the values are fixed into each container when it's created). In `llm-runtime` and `graphdb` it recreates only what was running. After a change, users open the new address; the CA certificate stays the same. Add `--debug` to see every stack and key it checks, and why a stack is left alone. With Infisical (Step 5), `pull-secrets.sh` runs this script for you.

## Step 3: Caddy (reverse proxy)

**Check:** `caddy`.

### Clean reinstall

Removes Caddy as if it had never been installed. Skip it for a first install. Without Caddy no service is reachable from outside. Each line asks first; read the last two before answering.
```bash
confirm "Stop and remove the Caddy container?" && cd /opt/stacks/caddy && docker compose down; cd ~
confirm "Delete the image (downloaded again on the next install)?" && docker image rm caddy:2
confirm "Delete the CA and certificates of Caddy (volume caddy_data)? Every client must then import the new CA again" && docker volume rm caddy_data
confirm "Delete /opt/stacks/caddy, including every service file in conf.d (each step must write its file again)?" && rm -rf /opt/stacks/caddy
```
To reinstall Caddy only and keep the services' routes and the clients' trust, answer no to the last two.

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -x caddy
docker volume ls -q | grep -x caddy_data
ls -d /opt/stacks/caddy 2>/dev/null
```

### Install

**Older install?** See [Upgrading an older install](options/upgrade-older-install.md) (no `SERVER_HOST` in `/opt/stacks/caddy/.env`, or ports missing for services added later).

How Caddy is set up:
- `Caddyfile` and `compose.yaml` are written once, here, and never edited again. `compose.yaml` already publishes every port the guide uses.
- Each later service adds one file, `conf.d/<service>.caddy`, then reloads Caddy (no restart).

```bash
mkdir -p /opt/stacks/caddy/conf.d
```

`/opt/stacks/caddy/Caddyfile`:
```
{
	default_sni {$SERVER_IP}
}

https://{$SERVER_HOST}:9500, https://{$SERVER_IP}:9500 {
	tls internal
	respond "Caddy OK" 200
}

import conf.d/*.caddy
```
- `default_sni` is required. Clients connecting by IP send no TLS server name, so without it every request by IP fails with `tlsv1 alert internal error`. Clients using the hostname send it, and get the certificate for the name.
- Each site lists both addresses, so it answers on the name and on the IP. With no hostname, both variables hold the IP; Caddy accepts the repeated address.
- The `:9500` block is a health check. It also makes Caddy create its CA right away, which Step 4 needs.
- Keep `import conf.d/*.caddy` as the last line. Without it no service is served.

`/opt/stacks/caddy/.env` (both lines from `/opt/stacks/shared/.env`):
```env
SERVER_HOST=<from /opt/stacks/shared/.env>
SERVER_IP=<from /opt/stacks/shared/.env>
```

`/opt/stacks/caddy/compose.yaml`:
```yaml
services:
  caddy:
    image: caddy:2
    container_name: caddy
    restart: unless-stopped
    environment:
      SERVER_HOST: ${SERVER_HOST}
      SERVER_IP: ${SERVER_IP}
    ports:
      # Default port of the service
      - "8080:8080"           # Infisical
      - "5556:5556"           # Dex
      - "9443:9443"           # Portainer
      - "9090:9090"           # Prometheus
      - "4000:4000"           # LiteLLM
      - "6333:6333"           # Qdrant
      - "7474:7474"           # Neo4j Browser
      # Assigned port (not the service default)
      - "9500:9500"           # Caddy health check
      - "443:443"             # Outline
      - "9450-9499:9450-9499" # Grafana 9450, Sourcebot 9460, Langfuse 9470, Open WebUI 9485, Memgraph Lab 9490
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./conf.d:/etc/caddy/conf.d
      - caddy_data:/data
    networks: [edge]

networks:
  edge:
    external: true

volumes:
  caddy_data:
    external: true
```

```bash
docker volume create caddy_data

cd /opt/stacks/caddy && docker compose up -d
```

**Check the result.** Every line must match the table:
```bash
docker inspect caddy --format 'name={{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}'
docker inspect caddy --format 'networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'
docker inspect caddy --format '{{range .Mounts}}mount {{.Destination}} <- {{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}}{{println}}{{end}}'
docker port caddy 443; docker port caddy 9450
docker volume inspect caddy_data --format 'volume={{.Name}}  driver={{.Driver}}'
docker exec caddy printenv SERVER_HOST SERVER_IP
curl -sv https://${SERVER_HOST}:9500 -o /dev/null 2>&1 | grep -E "issuer:|HTTP/"
```

| Line | Expected |
|---|---|
| `name=` | `/caddy  state=running  restart=unless-stopped`, image `caddy:2` |
| `networks=` | `edge` |
| `mount` | `/etc/caddy/Caddyfile <- /opt/stacks/caddy/Caddyfile`, `/etc/caddy/conf.d <- /opt/stacks/caddy/conf.d`, `/data <- caddy_data` |
| `docker port` | `0.0.0.0:443` and `0.0.0.0:9450` (plus `[::]` lines): the ports are published |
| `volume=` | `caddy_data  driver=local` |
| `printenv` | your `SERVER_HOST` and `SERVER_IP` |
| `curl` | `issuer: CN=Caddy Local Authority …` and `HTTP/2 200` |

**Verify:**
```bash
curl -k https://${SERVER_HOST}:9500
curl -k https://${SERVER_IP}:9500
```
Expect `Caddy OK` from both. If the first fails with "Could not resolve host", the name isn't in this server's hosts file or DNS yet (see "Before you start"). Otherwise check the container got both values (empty means `.env` is missing), that the Caddyfile is valid, and the log:
```bash
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy printenv SERVER_HOST SERVER_IP
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy validate --config /etc/caddy/Caddyfile
docker logs caddy 2>&1 | grep -iE "error|certificate" | tail -20
```

**Adding a service to Caddy** (every later step uses this pattern):
```bash
cat > /opt/stacks/caddy/conf.d/<service>.caddy <<'EOF'
https://{$SERVER_HOST}:<PORT>, https://{$SERVER_IP}:<PORT> {
	tls internal
	reverse_proxy <container-name>:<container-port>
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
A `502` afterwards means Caddy works but the service behind it isn't up; check `docker logs <container-name>`. Exceptions to this pattern list only `https://{$SERVER_HOST}…`, because their sign-in works on one fixed address: Infisical, Dex, Outline, Sourcebot, Langfuse, and the apps behind the sign-in gate.

### Test

1. **Both addresses:** `curl -k https://${SERVER_HOST}:9500` and `curl -k https://${SERVER_IP}:9500` print `Caddy OK`.
2. **A route reloads:** `docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile` prints nothing (no error).
3. **From a PC:** after Step 4 (CA imported), `https://<SERVER_HOST>:9500` opens in a browser with a padlock and shows `Caddy OK`.

## Step 4: Trust the internal CA

Do this once on each client machine.

```bash
cd /opt/stacks/caddy
docker compose exec caddy cat /data/caddy/pki/authorities/local/root.crt > caddy-root-ca.crt
```
Copy `caddy-root-ca.crt` to each client and import it:
- **Windows:** `certmgr.msc` → Trusted Root Certification Authorities → Import
- **macOS:** open the file → Keychain Access → set "Always Trust"
- **Linux:** `sudo cp caddy-root-ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates`
- **Firefox:** Settings → Privacy & Security → Certificates → View Certificates → Import

One import covers every service on this server, including ones not deployed yet.

## Step 5: Infisical (secrets)

Keeps every stack's secrets (passwords, keys, tokens) in one place, with a web UI and version history, instead of spread over `.env` files. The free, self-hosted version is all this needs: storing secrets, folders, versions, and the CLI have no user or identity limit. Paid-only features (SSO, audit logs, custom roles, rotation) aren't used.

How it fits: each later step still shows its `.env` — with Infisical, that block is the list of keys to create in Infisical, and `pull-secrets.sh` writes the file. Compose, `update-stack.sh`, and the stacks themselves don't change and never talk to Infisical; if Infisical is down, everything keeps running on the last `.env` it wrote. Skip this step to write every `.env` by hand.

**Two kinds of folders.** From here on, the guide writes a folder *in Infisical* as `prod:/<name>`: environment Production, folder `<name>`, as Infisical shows it (Production → `outline`). A folder *on the server* is always written in full, starting with `/opt/`. They often share a name, but are different things:

| | Server folder | Infisical folder |
|---|---|---|
| Example | `/opt/stacks/outline/` | `prod:/outline` |
| Holds | `compose.yaml`, `.env`, config files | Secrets: keys and values |
| You edit it with | An editor on the server (`nano`) | Infisical's web UI |
| Link between them | `pull-secrets.sh` copies `prod:/shared` + `prod:/<stack>` into `/opt/stacks/<stack>/.env` | |

So `prod:/infisical` holds optional secrets for Infisical itself (e.g. `SMTP_*`), while `/opt/stacks/infisical/` holds its compose file, `.env`, `pull.env`, and `pull-secrets.sh`.

**Check:** `infisical`, `infisical-postgres`, `infisical-redis`.

### Clean reinstall

Removes Infisical as if it had never been installed. Skip it for a first install. **Every secret stored in Infisical is lost** with its volumes, unless you have a backup (`backup-config.sh` keeps the database and `.env`). The stacks keep running on the `.env` files `pull-secrets.sh` already wrote. Each line asks first.
```bash
confirm "Stop and remove the Infisical containers?" && cd /opt/stacks/infisical && docker compose down; cd ~
confirm "Delete all secrets, users, and settings (volumes infisical_pg_data, infisical_redis_data)?" && docker volume rm infisical_pg_data infisical_redis_data
confirm "Delete /opt/stacks/infisical (.env with the encryption key, pull.env, the pull-secrets.sh link)?" && rm -rf /opt/stacks/infisical
confirm "Delete its Caddy file (infisical.caddy)?" && rm -f /opt/stacks/caddy/conf.d/infisical.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the Infisical image (downloaded again on the next install)?" && docker image rm infisical/infisical:latest
```

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -E '^infisical(-postgres|-redis)?$'
docker volume ls -q | grep -E '^infisical_'
ls -d /opt/stacks/infisical /opt/stacks/caddy/conf.d/infisical.caddy 2>/dev/null
```

### Install

**Caddy set up before Infisical was in this guide?** Add its port first: [Upgrading an older install](options/upgrade-older-install.md#caddy-ports-for-later-services).

```bash
mkdir -p /opt/stacks/infisical
```

`/opt/stacks/infisical/.env` — the one `.env` that stays hand-written, since Infisical needs it to start:
```env
SERVER_HOST=<from /opt/stacks/shared/.env>
# Read before Infisical starts
INFISICAL_DB_PASSWORD=<openssl rand -hex 24>
INFISICAL_ENCRYPTION_KEY=<openssl rand -hex 16>   # -hex 16: exactly 32 characters
INFISICAL_AUTH_SECRET=<openssl rand -base64 32>
# Optional email (see the guide option: email for all services); with Infisical these come from prod:/shared
# SMTP_HOST=smtp.gmail.com
# SMTP_PORT=587
# SMTP_USERNAME=<the dedicated gmail address>
# SMTP_PASSWORD=<16-character app password>
# Optional Google sign-in (see the guide option: Google sign-in); needs SERVER_HOST under a real domain.
# The same Google client and names as Dex; with Infisical these come from prod:/shared
# GOOGLE_CLIENT_ID=<Google client ID>
# GOOGLE_CLIENT_SECRET=<Google client secret>
```
**Back up this file somewhere off the server** (a password manager is fine). `INFISICAL_ENCRYPTION_KEY` encrypts every secret; without it, a restored database is unreadable.

**Why this `.env` is different from every other stack's.** `pull-secrets.sh` treats three kinds of `.env` differently:

| | `shared` | `infisical` | Other stacks (with a folder in Infisical) |
|---|---|---|---|
| File | `/opt/stacks/shared/.env` | `/opt/stacks/infisical/.env` | `/opt/stacks/<stack>/.env` |
| Source of truth | Infisical folder `prod:/shared` | Infisical folders `prod:/shared` + `prod:/infisical`, except the three start keys: this file | Infisical folders `prod:/shared` + `prod:/<stack>` |
| Can every key live in Infisical? | Yes | No: `INFISICAL_DB_PASSWORD`, `INFISICAL_ENCRYPTION_KEY`, and `INFISICAL_AUTH_SECRET` are read before Infisical starts | Yes |
| A key that is not in Infisical | Kept, listed in a NOTICE (`--ask-remove` or `--force-remove` removes it) | The same, except the three start keys: always kept, never shown | Kept, listed in a NOTICE (`--ask-remove` or `--force-remove` removes it) |
| How `pull-secrets.sh` writes it | Matches it to `prod:/shared` | Matches it to `prod:/shared` + `prod:/infisical`; never takes, changes, or removes the three start keys because of Infisical | Matches it to `prod:/shared` + `prod:/<stack>` |
| After a change | Nothing to recreate; the other stacks get the new values | Infisical is recreated | The stack is recreated (only the services that were running) |

A stack with no folder in Infisical, `infisical` included, keeps its hand-written `.env`; `sync-shared-env.sh`, which `pull-secrets.sh` runs at the end, updates only its `SERVER_HOST` / `SERVER_IP`.

Keeping the start keys in Infisical as well would not help: the encryption key would sit inside the vault it unlocks, and a rebuild would need Infisical running to fetch the keys that start it. That is why `pull-secrets.sh` ignores the start keys in Infisical: if Infisical holds one with a different value, it only prints a NOTICE. Edit them only in this file.

**Never delete this file.** If it is lost while Infisical still runs, the values are still in the containers: `docker inspect infisical --format '{{range .Config.Env}}{{println .}}{{end}}'` (`ENCRYPTION_KEY`, `AUTH_SECRET`) and the same for `infisical-postgres` (`POSTGRES_PASSWORD`). Write the file again before any `docker compose up -d` here.

`/opt/stacks/infisical/compose.yaml`:
```yaml
services:
  infisical-postgres:
    image: postgres:17
    container_name: infisical-postgres
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: ${INFISICAL_DB_PASSWORD}
      POSTGRES_DB: infisical
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 30s          # once healthy; fast checks only while starting:
      start_period: 60s
      start_interval: 3s
      timeout: 5s
      retries: 10
    volumes: [infisical_pg_data:/var/lib/postgresql/data]
    networks: [default]

  infisical-redis:
    image: redis:7
    container_name: infisical-redis
    restart: unless-stopped
    volumes: [infisical_redis_data:/data]
    networks: [default]

  infisical:
    image: infisical/infisical:latest
    container_name: infisical
    restart: unless-stopped
    environment:
      NODE_ENV: production
      SITE_URL: https://${SERVER_HOST}:8080
      ENCRYPTION_KEY: ${INFISICAL_ENCRYPTION_KEY}
      AUTH_SECRET: ${INFISICAL_AUTH_SECRET}
      DB_CONNECTION_URI: postgres://postgres:${INFISICAL_DB_PASSWORD}@infisical-postgres:5432/infisical
      REDIS_URL: redis://infisical-redis:6379
      TELEMETRY_ENABLED: "false"
      # Email: off while SMTP_HOST is empty
      SMTP_HOST: ${SMTP_HOST:-}
      SMTP_PORT: ${SMTP_PORT:-587}
      SMTP_USERNAME: ${SMTP_USERNAME:-}
      SMTP_PASSWORD: ${SMTP_PASSWORD:-}
      SMTP_FROM_ADDRESS: ${SMTP_USERNAME:-}
      SMTP_FROM_NAME: AI Server
      # Google sign-in: off while GOOGLE_CLIENT_ID is empty. Infisical reads its own names;
      # .env uses the same names as Dex, so one value serves both.
      CLIENT_ID_GOOGLE_LOGIN: ${GOOGLE_CLIENT_ID:-}
      CLIENT_SECRET_GOOGLE_LOGIN: ${GOOGLE_CLIENT_SECRET:-}
    depends_on:
      infisical-postgres: { condition: service_healthy }
      infisical-redis: { condition: service_started }
    networks: [default, edge]

networks:
  default:
    driver_opts:
      com.docker.network.bridge.name: br-infisical
  edge:
    external: true

volumes:
  infisical_pg_data:
    external: true
  infisical_redis_data:
    external: true
```
```bash
docker volume create infisical_pg_data
docker volume create infisical_redis_data

cd /opt/stacks/infisical && docker compose up -d
```

```bash
cat > /opt/stacks/caddy/conf.d/infisical.caddy <<'EOF'
https://{$SERVER_HOST}:8080 {
	tls internal
	reverse_proxy infisical:8080
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
Like Outline, Infisical answers on `SERVER_HOST` only: its `SITE_URL` is one fixed address. The first start runs database migrations; give it a minute (`docker logs -f infisical`).

**Check the result.** Every line must match the table:
```bash
docker inspect -f '{{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}' infisical infisical-postgres infisical-redis
docker inspect -f '{{.Name}}  networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' infisical infisical-postgres infisical-redis
docker inspect -f '{{.Name}}  health={{.State.Health.Status}}' infisical-postgres infisical-redis
docker inspect -f '{{.Name}}{{range .Mounts}}  {{.Destination}} <- {{.Name}}{{end}}' infisical-postgres infisical-redis
docker exec infisical sh -c 'echo "ENCRYPTION_KEY: ${#ENCRYPTION_KEY} characters, AUTH_SECRET: ${#AUTH_SECRET} characters, SITE_URL: $SITE_URL"'
curl -sv https://${SERVER_HOST}:8080 -o /dev/null 2>&1 | grep -E "issuer:|HTTP/"
```

| Line | Expected |
|---|---|
| state | all three `running`, `restart=unless-stopped`; images `infisical/infisical:latest`, `postgres:17`, `redis:7` |
| networks | `infisical`: `edge infisical_default`; the other two: `infisical_default` only (the databases stay off `edge`) |
| health | `healthy` for both |
| mounts | `/var/lib/postgresql/data <- infisical_pg_data`, `/data <- infisical_redis_data` |
| environment | `ENCRYPTION_KEY: 32 characters`, `AUTH_SECRET: 44 characters`, `SITE_URL: https://<SERVER_HOST>:8080` |
| `curl` | `issuer: CN=Caddy Local Authority …` and `HTTP/2 200` |

**Verify:** `https://<SERVER_HOST>:8080` loads with a trusted padlock.

### Authentication

Infisical keeps its own login: email and password, and the first account is the server admin.

**Google Account** (free): a **Continue with Google** button, turned on with the `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` lines in `.env` (the same names and values as Dex). A Google sign-in with the same email opens the same Infisical account. See [Google sign-in](options/google-sign-in.md). Dex and Azure would need Infisical's SAML/OIDC sign-in, which is 💲 paid, so Infisical takes Google directly.

### Usage

**Set up the project** at `https://<SERVER_HOST>:8080`:
1. Create the first account — it becomes the server admin. No email is sent; Infisical runs without SMTP. Inviting more people without SMTP should give you an invite link to pass on yourself; for invites by email, turn on [Email (SMTP)](options/smtp-email.md).
2. Create a project: **Secrets Management** → **+ Add New Project**, **Project Name** e.g. `ai-server`, then **Create Project**. It comes with three environments, Development, Staging, and Production; this guide uses only **Production** (its slug, `prod`, is what `pull.env` names).
3. Open **Production** in the project. Create a folder named **`shared`**, i.e. `prod:/shared` (the add menu next to **+ Add a New Secret** → **Add Folder**), open it, and add `SERVER_HOST` and `SERVER_IP` with **+ Add a New Secret**, using the same values as `/opt/stacks/shared/.env`.
4. Create one folder per stack, named exactly like its server folder under `/opt/stacks/` (`prod:/dex`, `prod:/outline`, `prod:/grafana`, `prod:/langfuse`, …), each holding the keys that step's `.env` shows — except `SERVER_HOST` / `SERVER_IP`, which come from `prod:/shared`. A key in a stack folder wins over `prod:/shared` for that stack, so a copy there would stop later `prod:/shared` changes from reaching it; `pull-secrets.sh` prints a NOTICE when the two differ. For a stack that already has a `.env`, drag the file onto the folder page (or use **Paste Secrets**), set **Target Environments** to Production, and select **Upload Secrets**; then delete those two keys there. A stack with no folder keeps its hand-written `.env`.
5. Organization → Access Control → **Identities** → create an identity (e.g. `ai-server-pull`, organization role Member), open it, add **Universal Auth**, and create a client secret. Then in the project → Access Control → Identities, add it with the **Viewer** role (read-only).
6. Copy the project ID from the project settings.

`/opt/stacks/infisical/pull.env` — the machine login for `pull-secrets.sh`:
```env
INFISICAL_CLIENT_ID=<Universal Auth client ID>
INFISICAL_CLIENT_SECRET=<Universal Auth client secret>
INFISICAL_PROJECT_ID=<project ID>
INFISICAL_ENV=prod
```
```bash
chmod 600 /opt/stacks/infisical/.env /opt/stacks/infisical/pull.env
```

Link `pull-secrets.sh` from `~/ai-server` into the folder ([Helper scripts](options/helper-scripts.md)), then preview:
```bash
ln -sf ~/ai-server/pull-secrets.sh /opt/stacks/infisical/pull-secrets.sh
/opt/stacks/infisical/pull-secrets.sh --dry-run
```
The dry run lists, per stack, which keys would be added, changed, or removed — names only, never values. The `.env` of a stack with a folder in Infisical is matched to `prod:/shared` and that folder, and `/opt/stacks/shared/.env` to `prod:/shared`. Keys from `prod:/shared` only update a `.env` that already has them and are never added to it (a new `.env` gets them all). Each file is edited in place: line order, comments, and blank lines stay; a changed value is replaced on its own line (an inline comment after it stays); new keys are added at the end under `# Added by pull-secrets.sh from Infisical`. **`REMOVED` means the key is in the current `.env` but not in Infisical.** By default such keys are kept where they are and only listed in a NOTICE, on every run until you add them to Infisical or remove them. To remove them, `--ask-remove` asks about each one (`Remove GRAFANA_SSO from grafana/.env? [y/N]`; `y` deletes only that line, anything else keeps it), and `--force-remove` removes them all without asking. Infisical's own `.env` follows the same rule, except its three start keys: they are always kept from the file and never shown. When the list looks right, run it without `--dry-run`: it asks first (one `[y/N]` for everything, after any `--ask-remove` questions), saves each old file as `.env.bak-<timestamp>`, writes the edited `.env` (mode 600), and recreates only the stacks that changed (in `llm-runtime` and `graphdb`, only what was running). It also writes `/opt/stacks/shared/.env` from `prod:/shared`.

**Unexpected result** (e.g. "Nothing to do" although you changed a secret)? Add `--debug`: it explains each step — the `pull.env` it read, the login, every folder and its key names, and why a stack was skipped — without printing any secret value, so the output is safe to share:
```bash
/opt/stacks/infisical/pull-secrets.sh --dry-run --debug 2>&1 | tee /tmp/pull-debug.txt
```
Add `--stack <name>` (or several, `--stack outline,grafana`) to look at only those stacks. The Infisical environment is `INFISICAL_ENV` in `pull.env` (`prod` when left out); `--env <slug>` reads another one for a single run, e.g. `--env staging --dry-run`. It writes the same `.env` files, so try it with `--dry-run` first.

**From here on, with Infisical:** when a step shows a `.env`, create those keys in Infisical under `prod:/<stack>` instead, run `/opt/stacks/infisical/pull-secrets.sh <stack>`, then continue with the step's `docker compose up -d`. To change a secret later — or `SERVER_HOST` / `SERVER_IP` in `prod:/shared` — edit it in Infisical and run `pull-secrets.sh`. When `prod:/shared` changed, it then runs `/opt/stacks/shared/sync-shared-env.sh` by itself, so stacks without a folder in Infisical get the new `SERVER_HOST` / `SERVER_IP` too (stacks it already wrote match and stay untouched). Every stack whose `.env` changes is recreated (a restart would keep the old values), so a `prod:/shared` change recreates nearly everything, Caddy included: expect a short interruption.

Plain values are written as is (`SMTP_PORT=587`). A value with any other character — `$`, `#`, a space, `?`, and so on — is written in single quotes (`KEY='value'`), which Compose reads literally. A value must not contain a single quote itself. **Infisical references** work in values: `${prod.shared.SMTP_USERNAME}` arrives as that key's value, because `pull-secrets.sh` reads with Infisical's default `--expand=true`. Infisical may treat any other `$` in a value as a variable too, so keep `$` out of passwords stored in Infisical (generated secrets from `openssl rand -hex` never contain it).

**Option:** [Sync to Azure Key Vault](options/infisical-azure-key-vault.md) — Infisical copies a folder's secrets into a key vault and keeps them updated (free in self-hosted Infisical).

**Verify:** `/opt/stacks/infisical/pull-secrets.sh --dry-run` prints either "Nothing to do" or the list above, not a login error.

### Test

1. **Sign-in:** `https://<SERVER_HOST>:8080` opens with a padlock; you sign in as the admin (and with Google, if turned on).
2. **The machine login:** `/opt/stacks/infisical/pull-secrets.sh --dry-run` prints "Nothing to do" or a list of keys, not a login error.
3. **A secret reaches a stack, without changing it:** add a key `PULL_TEST=1` to `prod:/shared` in Infisical, add an empty `PULL_TEST=` line to `/opt/stacks/caddy/.env`, and run `pull-secrets.sh --stack caddy --dry-run`: it lists `changed: PULL_TEST`. Delete the key in Infisical and the line from the file.

## Step 6: Dex (sign-in)

One sign-in for the whole server. Dex is a small sign-in service: you list users and passwords in its config file, and every app that supports it shows a "Sign in with Dex" button — Outline, Grafana, Portainer, Langfuse, Open WebUI, and the LiteLLM Admin UI (free for up to 5 users). Apps without their own sign-in support (Prometheus, the Qdrant dashboard, Neo4j Browser, Memgraph Lab) sit behind a **sign-in gate** (oauth2-proxy) that sends people to the same Dex login first. No SMTP relay or Azure admin rights needed.

What "single sign-on" means here: one account and password for every app. The four gated apps share one sign-in. The four apps with a Dex button each ask for the password once more, because Dex on its own doesn't remember a login between apps. Once a Microsoft (or Google, Auth0) connector is enabled ([Outside sign-in](options/dex-outside-sign-in.md)), that provider remembers the login, and the button signs people in without asking again.

Skip this step to keep every app on its own login; each later step says which lines to leave out.

**Check:** `dex`, `oauth2-proxy`.

### Clean reinstall

Removes Dex and the sign-in gate as if they had never been installed. Skip it for a first install. **Every app that signs in through Dex stops working** until Dex is back; the gated apps (Prometheus, Qdrant, Neo4j Browser, Memgraph Lab) answer with an error. People keep their accounts in each app (matched by email), so they sign in as before once Dex returns. Each line asks first.
```bash
confirm "Stop and remove Dex and the sign-in gate?" && cd /opt/stacks/dex && docker compose down; cd ~
confirm "Delete Dex data (volume dex_data: sessions and signing keys)?" && docker volume rm dex_data
confirm "Delete /opt/stacks/dex (.env with every client secret, config.yaml with the users)?" && rm -rf /opt/stacks/dex
confirm "Delete its Caddy files (dex.caddy, and the gate 00-sso.caddy that the gated apps import)?" && rm -f /opt/stacks/caddy/conf.d/dex.caddy /opt/stacks/caddy/conf.d/00-sso.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the Dex and gate images?" && docker image rm ghcr.io/dexidp/dex:latest quay.io/oauth2-proxy/oauth2-proxy:latest
```
With `00-sso.caddy` gone, Caddy refuses the gated apps' files (`import sso` unknown) until it is written again; reinstall Dex before reloading Caddy, or use [Without the sign-in gate](options/without-sign-in-gate.md). A new `.env` means new client secrets: copy each one into its app again (the `*_OIDC_SECRET` lines of the later steps).

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -E '^(dex|oauth2-proxy)$'
docker volume ls -q | grep -x dex_data
ls -d /opt/stacks/dex /opt/stacks/caddy/conf.d/dex.caddy /opt/stacks/caddy/conf.d/00-sso.caddy 2>/dev/null
```

### Install

**Caddy set up before Dex was in this guide?** Add its port first: [Upgrading an older install](options/upgrade-older-install.md#caddy-ports-for-later-services).

```bash
mkdir -p /opt/stacks/dex
```

`/opt/stacks/dex/.env`:
```env
SERVER_HOST=<from /opt/stacks/shared/.env>
OUTLINE_OIDC_SECRET=<openssl rand -hex 32>     # Outline uses the same value
GRAFANA_OIDC_SECRET=<openssl rand -hex 32>     # Grafana uses the same value
PORTAINER_OIDC_SECRET=<openssl rand -hex 32>   # entered in the Portainer web UI
LANGFUSE_OIDC_SECRET=<openssl rand -hex 32>    # Langfuse uses the same value
LITELLM_OIDC_SECRET=<openssl rand -hex 32>     # LiteLLM Admin UI uses the same value
OPENWEBUI_OIDC_SECRET=<openssl rand -hex 32>   # Open WebUI uses the same value
GATE_OIDC_SECRET=<openssl rand -hex 32>        # the sign-in gate (oauth2-proxy)
GATE_COOKIE_SECRET=<openssl rand -hex 16>      # -hex 16, not 32: must be exactly 32 characters
# Outside sign-in providers (optional, see the guide options: Google sign-in, outside sign-in); fill in only when you enable one
# GOOGLE_CLIENT_ID=<Google client ID>               # the same Google client as Infisical; with Infisical from prod:/shared
# GOOGLE_CLIENT_SECRET=<Google client secret>
# MS_CLIENT_ID=<Application (client) ID>
# MS_CLIENT_SECRET=<Azure client secret value>
# MS_TENANT_ID=<Directory (tenant) ID>
# ENTRA_GUEST_CLIENT_ID=<Application (client) ID in the tenant you administer>
# ENTRA_GUEST_CLIENT_SECRET=<client secret from the tenant you administer>
# ENTRA_GUEST_TENANT_ID=<Directory (tenant) ID of the tenant you administer>
# AUTH0_ISSUER=https://<your-tenant>.auth0.com/     # exactly as Auth0 shows it, with the trailing slash
# AUTH0_CLIENT_ID=<Auth0 client ID>
# AUTH0_CLIENT_SECRET=<Auth0 client secret>
```
`GATE_COOKIE_SECRET` is the odd one out: oauth2-proxy accepts only 16, 24, or 32 characters, so it takes `openssl rand -hex 16`. A 64-character value (from `-hex 32`) makes the `oauth2-proxy` container restart with "cookie_secret must be 16, 24, or 32 bytes". Check it with `grep ^GATE_COOKIE_SECRET= /opt/stacks/dex/.env | cut -d= -f2 | tr -d '\n' | wc -c` (expect `32`).

Make a password hash for each user (Caddy from Step 3 has the tool; it asks for the password twice):
```bash
docker exec -it caddy caddy hash-password
```
Copy the last line, the one starting with `$2a$`. Don't pipe this command into anything (e.g. `| tr`): the pipe hides the password prompts, so it looks stuck.

And a unique ID for each user:
```bash
cat /proc/sys/kernel/random/uuid
```

`/opt/stacks/dex/config.yaml` — Dex fills in `{{ getenv "SERVER_HOST" }}` from its environment each time it starts:
```yaml
issuer: https://{{ getenv "SERVER_HOST" }}:5556/dex

storage:
  type: sqlite3
  config:
    file: /var/dex/dex.db

web:
  http: 0.0.0.0:5556

oauth2:
  skipApprovalScreen: true

# Custom login page: off until you uncomment it (see the guide option: custom login page)
# frontend:
#   dir: /srv/dex/web-custom
#   theme: custom
#   issuer: "AI Server"   # page title, and the heading "Log in to AI Server"
#   extra:                # your own values for custom templates (see the guide option: custom login page)
#     helpText: "Trouble signing in? Contact the server admin."
#     helpURL: "https://{{ getenv "SERVER_HOST" }}"

enablePasswordDB: true

# One client per app. Listing an app that is not deployed yet does no harm.
staticClients:
  - id: outline
    name: Outline
    secretEnv: OUTLINE_OIDC_SECRET
    redirectURIs:
      - https://{{ getenv "SERVER_HOST" }}/auth/oidc.callback
  - id: grafana
    name: Grafana
    secretEnv: GRAFANA_OIDC_SECRET
    redirectURIs:
      - https://{{ getenv "SERVER_HOST" }}:9450/login/generic_oauth
  - id: portainer
    name: Portainer
    secretEnv: PORTAINER_OIDC_SECRET
    redirectURIs:
      - https://{{ getenv "SERVER_HOST" }}:9443
  - id: langfuse
    name: Langfuse
    secretEnv: LANGFUSE_OIDC_SECRET
    redirectURIs:
      - https://{{ getenv "SERVER_HOST" }}:9470/api/auth/callback/custom
  - id: litellm
    name: LiteLLM
    secretEnv: LITELLM_OIDC_SECRET
    redirectURIs:
      - https://{{ getenv "SERVER_HOST" }}:4000/sso/callback
  - id: open-webui
    name: Open WebUI
    secretEnv: OPENWEBUI_OIDC_SECRET
    redirectURIs:
      - https://{{ getenv "SERVER_HOST" }}:9485/oauth/oidc/callback
  - id: sso-gate
    name: Sign-in gate
    secretEnv: GATE_OIDC_SECRET
    redirectURIs:   # one per app behind the gate
      - https://{{ getenv "SERVER_HOST" }}:9090/oauth2/callback
      - https://{{ getenv "SERVER_HOST" }}:6333/oauth2/callback
      - https://{{ getenv "SERVER_HOST" }}:7474/oauth2/callback
      - https://{{ getenv "SERVER_HOST" }}:9490/oauth2/callback

# One entry per user. Email must be unique; Outline uses it to identify the person.
staticPasswords:
  - email: "admin@example.internal"
    username: "admin"
    preferredUsername: "admin"
    hash: "<output of caddy hash-password>"
    userID: "<output of /proc/sys/kernel/random/uuid>"

# Outside sign-in providers: off until you uncomment one (see the guide options: Google sign-in, outside sign-in).
# Each adds a button on the Dex sign-in page, next to the username and password form.
# connectors:
#   - type: google
#     id: google
#     name: Google
#     config:
#       clientID: {{ getenv "GOOGLE_CLIENT_ID" }}
#       clientSecret: $GOOGLE_CLIENT_SECRET
#       redirectURI: https://{{ getenv "SERVER_HOST" }}:5556/dex/callback
#       # hostedDomains: [domain.com]    # allow only accounts of your Google Workspace domain
#   - type: microsoft
#     id: microsoft
#     name: Microsoft
#     config:
#       clientID: {{ getenv "MS_CLIENT_ID" }}
#       clientSecret: $MS_CLIENT_SECRET
#       tenant: {{ getenv "MS_TENANT_ID" }}
#       redirectURI: https://{{ getenv "SERVER_HOST" }}:5556/dex/callback
#   # Microsoft through a tenant you administer, with colleagues invited as guests (see the guide option)
#   - type: oidc
#     id: entra-guests
#     name: Microsoft
#     config:
#       issuer: https://login.microsoftonline.com/{{ getenv "ENTRA_GUEST_TENANT_ID" }}/v2.0
#       clientID: {{ getenv "ENTRA_GUEST_CLIENT_ID" }}
#       clientSecret: $ENTRA_GUEST_CLIENT_SECRET
#       redirectURI: https://{{ getenv "SERVER_HOST" }}:5556/dex/callback
#       scopes: [openid, profile, email]
#       insecureSkipEmailVerified: true   # Entra sends no email_verified claim
#   - type: oidc
#     id: auth0
#     name: Auth0
#     config:
#       issuer: {{ getenv "AUTH0_ISSUER" }}
#       clientID: {{ getenv "AUTH0_CLIENT_ID" }}
#       clientSecret: $AUTH0_CLIENT_SECRET
#       redirectURI: https://{{ getenv "SERVER_HOST" }}:5556/dex/callback
#       scopes: [openid, profile, email]
```

`/opt/stacks/dex/compose.yaml`:
```yaml
services:
  dex:
    image: ghcr.io/dexidp/dex:latest
    container_name: dex
    restart: unless-stopped
    command: ["dex", "serve", "/etc/dex/config.yaml"]
    environment:
      SERVER_HOST: ${SERVER_HOST}
      OUTLINE_OIDC_SECRET: ${OUTLINE_OIDC_SECRET}
      GRAFANA_OIDC_SECRET: ${GRAFANA_OIDC_SECRET}
      PORTAINER_OIDC_SECRET: ${PORTAINER_OIDC_SECRET}
      LANGFUSE_OIDC_SECRET: ${LANGFUSE_OIDC_SECRET}
      LITELLM_OIDC_SECRET: ${LITELLM_OIDC_SECRET}
      OPENWEBUI_OIDC_SECRET: ${OPENWEBUI_OIDC_SECRET}
      GATE_OIDC_SECRET: ${GATE_OIDC_SECRET}
      # Outside sign-in providers; empty until set in .env
      GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID:-}
      GOOGLE_CLIENT_SECRET: ${GOOGLE_CLIENT_SECRET:-}
      MS_CLIENT_ID: ${MS_CLIENT_ID:-}
      MS_CLIENT_SECRET: ${MS_CLIENT_SECRET:-}
      MS_TENANT_ID: ${MS_TENANT_ID:-}
      ENTRA_GUEST_CLIENT_ID: ${ENTRA_GUEST_CLIENT_ID:-}
      ENTRA_GUEST_CLIENT_SECRET: ${ENTRA_GUEST_CLIENT_SECRET:-}
      ENTRA_GUEST_TENANT_ID: ${ENTRA_GUEST_TENANT_ID:-}
      AUTH0_ISSUER: ${AUTH0_ISSUER:-}
      AUTH0_CLIENT_ID: ${AUTH0_CLIENT_ID:-}
      AUTH0_CLIENT_SECRET: ${AUTH0_CLIENT_SECRET:-}
    volumes:
      - ./config.yaml:/etc/dex/config.yaml:ro
      - dex_data:/var/dex
      # - ./web:/srv/dex/web-custom:ro   # custom login page (optional)
    networks: [edge]

  # Sign-in gate for apps without their own sign-in. Caddy asks it before letting a request through.
  oauth2-proxy:
    image: quay.io/oauth2-proxy/oauth2-proxy:latest
    container_name: oauth2-proxy
    restart: unless-stopped
    environment:
      OAUTH2_PROXY_PROVIDER: oidc
      OAUTH2_PROXY_PROVIDER_DISPLAY_NAME: Dex
      OAUTH2_PROXY_CLIENT_ID: sso-gate
      OAUTH2_PROXY_CLIENT_SECRET: ${GATE_OIDC_SECRET}
      OAUTH2_PROXY_COOKIE_SECRET: ${GATE_COOKIE_SECRET}
      OAUTH2_PROXY_COOKIE_SECURE: "true"
      OAUTH2_PROXY_EMAIL_DOMAINS: "*"
      OAUTH2_PROXY_SCOPE: openid email profile
      # The browser reaches Dex through Caddy; the gate calls Dex directly (it does not trust the internal CA)
      OAUTH2_PROXY_OIDC_ISSUER_URL: https://${SERVER_HOST}:5556/dex
      OAUTH2_PROXY_SKIP_OIDC_DISCOVERY: "true"
      OAUTH2_PROXY_LOGIN_URL: https://${SERVER_HOST}:5556/dex/auth
      OAUTH2_PROXY_REDEEM_URL: http://dex:5556/dex/token
      OAUTH2_PROXY_OIDC_JWKS_URL: http://dex:5556/dex/keys
      OAUTH2_PROXY_WHITELIST_DOMAINS: ${SERVER_HOST}:*
      OAUTH2_PROXY_HTTP_ADDRESS: 0.0.0.0:4180
      OAUTH2_PROXY_REVERSE_PROXY: "true"
      OAUTH2_PROXY_SET_XAUTHREQUEST: "true"
      OAUTH2_PROXY_SKIP_PROVIDER_BUTTON: "true"
      OAUTH2_PROXY_UPSTREAMS: static://202
    depends_on: [dex]
    networks: [edge]

networks:
  edge:
    external: true

volumes:
  dex_data:
    external: true
```
```bash
docker volume create dex_data

cd /opt/stacks/dex && docker compose up -d
```

```bash
cat > /opt/stacks/caddy/conf.d/dex.caddy <<'EOF'
https://{$SERVER_HOST}:5556 {
	tls internal
	reverse_proxy dex:5556
}
EOF
cat > /opt/stacks/caddy/conf.d/00-sso.caddy <<'EOF'
# Sign-in gate, used by a site as: import sso <container>:<port>
(sso) {
	handle /oauth2/* {
		reverse_proxy oauth2-proxy:4180
	}
	handle {
		forward_auth oauth2-proxy:4180 {
			uri /oauth2/auth
			copy_headers X-Auth-Request-User X-Auth-Request-Email
			@signin status 401
			handle_response @signin {
				redir * /oauth2/sign_in?rd={scheme}://{hostport}{uri}
			}
		}
		reverse_proxy {args[0]}
	}
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
- Like Outline, Dex answers on `SERVER_HOST` only: its `issuer` is one fixed address.
- `00-sso.caddy` defines the gate once; the `00-` keeps it first when Caddy loads `conf.d/`. Apps behind the gate (Steps 9, 14, 15) use `import sso <container>:<port>` in place of `reverse_proxy`, and answer on `SERVER_HOST` only, because the sign-in cookie belongs to one address.
- The gate lets in anyone who can sign in to Dex. Internal traffic between containers (e.g. Grafana reading `http://prometheus:9090`) never passes Caddy, so it isn't gated.

**Check the result.** Every line must match the table:
```bash
docker inspect -f '{{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}' dex oauth2-proxy
docker inspect -f '{{.Name}}  networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' dex oauth2-proxy
docker inspect dex --format '{{range .Mounts}}mount {{.Destination}} <- {{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}}{{println}}{{end}}'
docker inspect oauth2-proxy --format '{{range .Config.Env}}{{println .}}{{end}}' | grep ^OAUTH2_PROXY_COOKIE_SECRET= | cut -d= -f2 | tr -d '\n' | wc -c
docker exec dex grep -c "^  - id:" /etc/dex/config.yaml
curl -sv https://${SERVER_HOST}:5556/dex/.well-known/openid-configuration -o /dev/null 2>&1 | grep -E "issuer:|HTTP/"
```

| Line | Expected |
|---|---|
| state | both `running`, `restart=unless-stopped`; images `ghcr.io/dexidp/dex:latest`, `quay.io/oauth2-proxy/oauth2-proxy:latest` |
| networks | `edge` for both |
| `mount` | `/etc/dex/config.yaml <- /opt/stacks/dex/config.yaml`, `/var/dex <- dex_data` |
| `wc -c` | `32`: the gate cookie secret's length (the gate refuses any other; the value is not shown) |
| `grep -c` | the number of clients in `config.yaml` (one per app, plus `sso-gate`) |
| `curl` | `issuer: CN=Caddy Local Authority …` and `HTTP/2 200` |

**Verify:**
```bash
curl -k https://${SERVER_HOST}:5556/dex/.well-known/openid-configuration
```
Expect JSON whose `issuer` is `https://<SERVER_HOST>:5556/dex`. If Dex keeps restarting, `docker logs dex` names the config line it rejects. The gate is checked when the first gated app is deployed (Step 9): opening Prometheus should show the Dex login first.

### Authentication

Dex is where people actually sign in; every app behind it trusts Dex. Its sign-in page shows one button per method, listed in this order in `config.yaml`:

**Dex local users** (free, default): usernames and passwords in `staticPasswords`. Works without any outside account or internet access; keep at least your own entry as a fallback when outside providers are on.

**Managing users:** `config.yaml` is the user list, so unlike other config files it's meant to change: add, edit, or remove an entry under `staticPasswords`, then `cd /opt/stacks/dex && docker compose up -d --force-recreate dex`. Recreate, don't just restart: `config.yaml` is mounted as a single file, and editors that save by replacing the file (vim, for one) leave a running container looking at the old copy, so a restart reloads stale settings. Check with `docker exec dex grep email /etc/dex/config.yaml`. A new password is a new `hash`. Removing someone from Dex stops new sign-ins; also suspend them in Outline (Settings → Members), since their current Outline session stays valid until it expires. Users can't reset their own password; you change the hash.

**Google Account** (free): a **Google** button through the `google` connector, so company Google accounts work in every app behind Dex at once. Needs `SERVER_HOST` under a real domain. See [Google sign-in](options/google-sign-in.md).

**Azure** (free): a **Microsoft** button through the `microsoft` connector (people in your tenant) or `entra-guests` (colleagues invited as guests into a tenant you administer). Registering the app may need a tenant admin. See [Outside sign-in](options/dex-outside-sign-in.md), which also covers Auth0.

Apps match people by email, so someone who signs in with Google one day and Microsoft the next stays one user as long as both give the same address.

### Options

- [Custom login page](options/dex-custom-login-page.md) — your own name, logo, the Inter font, and your own HTML for the sign-in page.

### Test

1. **Discovery:** `curl -sk https://${SERVER_HOST}:5556/dex/.well-known/openid-configuration` prints JSON with `"issuer":"https://<SERVER_HOST>:5556/dex"`.
2. **A password sign-in:** after Step 7, Outline's **Continue with Dex** shows Dex's sign-in page; a user from `staticPasswords` signs in and lands in Outline.
3. **The gate:** after Step 9, `curl -skI https://${SERVER_HOST}:9090 | head -3` shows a `302` to `/oauth2/sign_in`; in a browser, Prometheus asks for the Dex sign-in first.
4. **Outside providers** (if turned on): the Dex page shows **Google** or **Microsoft**, and signing in with it reaches the app.

## Step 7: Outline (wiki)

**Check:** `outline`, `outline-postgres`, `outline-redis`.

### Clean reinstall

Removes Outline as if it had never been installed. Skip it for a first install. **All documents, users, and uploaded files are lost** with the volumes; `backup-config.sh` keeps the database (documents and users), not the uploaded files. Each line asks first.
```bash
confirm "Stop and remove the Outline containers?" && cd /opt/stacks/outline && docker compose down; cd ~
confirm "Delete all documents, users, and uploads (volumes outline_pg_data, outline_redis_data, outline_data)?" && docker volume rm outline_pg_data outline_redis_data outline_data
confirm "Delete /opt/stacks/outline (.env with its secrets)?" && rm -rf /opt/stacks/outline
confirm "Delete its Caddy file (outline.caddy)?" && rm -f /opt/stacks/caddy/conf.d/outline.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the Outline image (downloaded again on the next install)?" && docker image rm docker.getoutline.com/outlinewiki/outline:latest
```
Its Dex client (`outline` in Dex `config.yaml`) can stay for a reinstall; remove it if Outline is gone for good.

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -E '^outline(-postgres|-redis)?$'
docker volume ls -q | grep -E '^outline_'
ls -d /opt/stacks/outline /opt/stacks/caddy/conf.d/outline.caddy 2>/dev/null
```

### Install

**Older install?** See [Upgrading an older install](options/upgrade-older-install.md#outline) (Outline on `SERVER_IP`, or Outline running without Dex).

**Sign-in:** Outline has no password login, so it needs at least one sign-in method before it starts. The `.env` below sets up Dex; the others are under Authentication at the end of this step.

```bash
mkdir -p /opt/stacks/outline
```

`/opt/stacks/outline/.env`:
```env
SERVER_HOST=<from /opt/stacks/shared/.env>
OUTLINE_DB_PASSWORD=CHANGE_ME
OUTLINE_SECRET_KEY=<openssl rand -hex 32>
OUTLINE_UTILS_SECRET=<openssl rand -hex 32>
# Dex sign-in; leave these three out if Dex is not deployed
OIDC_CLIENT_ID=outline
OIDC_CLIENT_SECRET=<OUTLINE_OIDC_SECRET from /opt/stacks/dex/.env>
OIDC_DISPLAY_NAME=Dex
# Optional email: notifications and magic-link sign-in (see the guide option: email for all services)
# SMTP_HOST=smtp.gmail.com
# SMTP_PORT=587
# SMTP_SECURE=false            # false for 587 (STARTTLS); true for 465 (implicit TLS)
# SMTP_USERNAME=<the dedicated gmail address>
# SMTP_PASSWORD=<16-character app password>
# SMTP_FROM_EMAIL=<the same gmail address>
# Optional Google sign-in without Dex; redirect URI: https://<SERVER_HOST>/auth/google.callback
# GOOGLE_CLIENT_ID=<Google client ID>
# GOOGLE_CLIENT_SECRET=<Google client secret>
# Optional Azure AD sign-in without Dex; redirect URI: https://<SERVER_HOST>/auth/azure.callback
# AZURE_CLIENT_ID=<app registration client ID>
# AZURE_CLIENT_SECRET=<app registration secret>
# AZURE_RESOURCE_APP_ID=<optional, for Graph API group claims>
```

`/opt/stacks/outline/compose.yaml`:
```yaml
services:
  outline-postgres:
    image: postgres:17
    container_name: outline-postgres
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: ${OUTLINE_DB_PASSWORD}
      POSTGRES_DB: outline
    volumes: [outline_pg_data:/var/lib/postgresql/data]
    networks: [default]

  outline-redis:
    image: redis:7
    container_name: outline-redis
    restart: unless-stopped
    volumes: [outline_redis_data:/data]
    networks: [default]

  outline:
    image: docker.getoutline.com/outlinewiki/outline:latest
    container_name: outline
    restart: unless-stopped
    environment:
      URL: https://${SERVER_HOST}
      FORCE_HTTPS: "false"
      SECRET_KEY: ${OUTLINE_SECRET_KEY}
      UTILS_SECRET: ${OUTLINE_UTILS_SECRET}
      DATABASE_URL: postgres://postgres:${OUTLINE_DB_PASSWORD}@outline-postgres:5432/outline
      PGSSLMODE: disable     # the bundled Postgres has no SSL; Outline requires SSL unless told otherwise
      REDIS_URL: redis://outline-redis:6379
      FILE_STORAGE: local
      FILE_STORAGE_LOCAL_ROOT_DIR: /var/lib/outline/data
      # Dex endpoints: the browser goes through Caddy, Outline itself calls Dex directly
      # (it does not trust the internal CA). Unused unless OIDC_CLIENT_ID is set in .env.
      OIDC_AUTH_URI: https://${SERVER_HOST}:5556/dex/auth
      OIDC_TOKEN_URI: http://dex:5556/dex/token
      OIDC_USERINFO_URI: http://dex:5556/dex/userinfo
    env_file: .env
    volumes: [outline_data:/var/lib/outline/data]
    depends_on: [outline-postgres, outline-redis]
    networks: [default, edge]

networks:
  default:
    driver_opts:
      com.docker.network.bridge.name: br-outline
  edge:
    external: true

volumes:
  outline_pg_data:
    external: true
  outline_redis_data:
    external: true
  outline_data:
    external: true
```
`env_file: .env` passes every line of `.env` into the container, so Outline sees the sign-in settings (`OIDC_*`, `SMTP_*`, `GOOGLE_*`, `AZURE_*`) under the exact names it reads. Without it, `.env` is only used to fill in `${…}` in this file. Values under `environment:` win if both set the same name.

```bash
docker volume create outline_pg_data
docker volume create outline_redis_data
docker volume create outline_data

cd /opt/stacks/outline && docker compose up -d
```

```bash
cat > /opt/stacks/caddy/conf.d/outline.caddy <<'EOF'
https://{$SERVER_HOST} {
	tls internal
	reverse_proxy outline:3000
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```

**Check the result.** Every line must match the table:
```bash
docker inspect -f '{{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}' outline outline-postgres outline-redis
docker inspect -f '{{.Name}}  networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' outline outline-postgres outline-redis
docker inspect -f '{{.Name}}{{range .Mounts}}  {{.Destination}} <- {{.Name}}{{end}}' outline outline-postgres outline-redis
docker exec outline sh -c 'echo "SECRET_KEY: ${#SECRET_KEY} characters, URL: $URL, OIDC client: ${OIDC_CLIENT_ID:-none}"'
docker exec outline getent hosts dex outline-postgres outline-redis
curl -sv https://${SERVER_HOST} -o /dev/null 2>&1 | grep -E "issuer:|HTTP/"
```

| Line | Expected |
|---|---|
| state | all three `running`, `restart=unless-stopped`; images `outlinewiki/outline:latest` (from `docker.getoutline.com`), `postgres:17`, `redis:7` |
| networks | `outline`: `edge outline_default`; the other two: `outline_default` only |
| mounts | `/var/lib/outline/data <- outline_data`, `/var/lib/postgresql/data <- outline_pg_data`, `/data <- outline_redis_data` |
| environment | `SECRET_KEY: 64 characters`, `URL: https://<SERVER_HOST>`, `OIDC client: outline` (with Dex) |
| `getent` | an address for each: `dex` over `edge`, the databases over `outline_default` |
| `curl` | `issuer: CN=Caddy Local Authority …` and `HTTP/2 200` (or `302`) |

**Verify:** `curl -kI https://${SERVER_HOST}` returns `200` or `302`, and `https://<SERVER_HOST>` loads in a browser with no warning, showing a sign-in button for each method you set up (with Dex: "Continue with Dex"). Sign in; the first account becomes the admin.

### Authentication

Outline has no password login of its own; the first person to sign in becomes the admin. Each method below adds its own button.

**Dex** (free): the `OIDC_*` lines in `.env`, set up above; the button reads **Continue with Dex**. If sign-in fails, the log says why:
```bash
docker logs outline --since 10m 2>&1 | grep -iE "oidc|auth|smtp|error" | tail -20
```
- No sign-in button at all: no method is configured. Check `docker exec outline env | grep -E "^(OIDC_CLIENT_ID|SMTP_HOST|GOOGLE_CLIENT_ID|AZURE_CLIENT_ID)="`.
- Dex shows "Invalid redirect URI" or "Unregistered redirect_uri": `SERVER_HOST` differs between `/opt/stacks/dex/.env` and `/opt/stacks/outline/.env`; run `sync-shared-env.sh`.
- Dex shows "Invalid client credentials": `OIDC_CLIENT_SECRET` in Outline differs from `OUTLINE_OIDC_SECRET` in Dex.

**Google Account** (free): through Dex's Google connector, with nothing to change here. Outline's own Google sign-in is also free (the `GOOGLE_*` lines in `.env`), but needs its own redirect address in Google.

**Azure** (free): through Dex's Microsoft connector, with nothing to change here. Outline's own Azure AD sign-in (the `AZURE_*` lines in `.env`) is also free: [Email and Azure AD sign-in](options/outline-email-and-azure.md#azure-ad-sign-in).

**Email magic link** (free, needs SMTP): people get a sign-in link by email. See [Email (SMTP) for all services](options/smtp-email.md).

### Test

1. **Sign-in:** `https://<SERVER_HOST>` shows **Continue with Dex** (and the other methods you set up); signing in lands you in Outline. The first account is the admin.
2. **A document:** create a document with a heading and an image; reload the page: both are still there (database and `outline_data` work).
3. **Search:** search for a word from the document; it is found.
4. **Email** (if set up): Settings → Members → invite yourself at another address; the invitation arrives.

## Step 8: Portainer (Docker UI)

**Check:** `portainer`.

### Clean reinstall

Removes Portainer as if it had never been installed. Skip it for a first install, and for an existing install that you only move into this layout (migrate it instead, under Install). **Its users, environments, and settings are lost** with the volume; the containers it shows are not touched. Each line asks first.
```bash
confirm "Stop and remove the Portainer container?" && cd /opt/stacks/portainer && docker compose down; cd ~
confirm "Delete Portainer users and settings (volume portainer_data)? The next start shows the setup wizard" && docker volume rm portainer_data
confirm "Delete /opt/stacks/portainer and its Caddy file?" && rm -rf /opt/stacks/portainer /opt/stacks/caddy/conf.d/portainer.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the Portainer image (downloaded again on the next install)?" && docker image rm portainer/portainer-ce:lts
```
After a reinstall, open `https://<SERVER_HOST>:9443` within 5 minutes to create the admin (Portainer locks the setup after that; `docker restart portainer` reopens it), and set up Dex sign-in again (Authentication).

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -x portainer
docker volume ls -q | grep portainer
ls -d /opt/stacks/portainer /opt/stacks/caddy/conf.d/portainer.caddy 2>/dev/null
```

### Install

An existing install holds real data (users, environments), so migrate it; don't reinstall. See how it runs now:
```bash
docker inspect portainer --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}'
```
- **"no such object"** → fresh install; follow the step.
- **Empty** (bare `docker run`) → migrate: the compose file below reuses the existing `portainer_data` volume.
- **A path** → already Compose-managed; make sure its `portainer_data` volume is `external: true` and it has no `ports:` of its own.

```bash
mkdir -p /opt/stacks/portainer
```
`/opt/stacks/portainer/compose.yaml`:
```yaml
services:
  portainer:
    image: portainer/portainer-ce:lts
    container_name: portainer
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks: [edge]

networks:
  edge:
    external: true

volumes:
  portainer_data:
    external: true
```
No `ports:`. Caddy serves `:9443` and proxies to Portainer's internal HTTP port `9000`, so the browser sees the trusted CA, not Portainer's self-signed cert.

`docker volume create` is a no-op if `portainer_data` already exists; it never resets it. Skip the `confirm` line on a fresh install.
```bash
docker volume create portainer_data

confirm "Stop and remove the existing Portainer container? (its data volume is untouched)" && docker rm -f portainer
cd /opt/stacks/portainer && docker compose up -d
```
If an earlier deploy without `external: true` created an empty duplicate volume, remove it:
```bash
docker volume ls | grep portainer
confirm "Remove the empty duplicate volume portainer_portainer_data? (real one is portainer_data, untouched)" && docker volume rm portainer_portainer_data
```
```bash
cat > /opt/stacks/caddy/conf.d/portainer.caddy <<'EOF'
https://{$SERVER_HOST}:9443, https://{$SERVER_IP}:9443 {
	tls internal
	reverse_proxy portainer:9000
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
**Check the result.** Every line must match the table:
```bash
docker inspect portainer --format 'name={{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}'
docker inspect portainer --format 'networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}  ports={{range $p, $b := .NetworkSettings.Ports}}{{if $b}}{{$p}} {{end}}{{end}}'
docker inspect portainer --format '{{range .Mounts}}mount {{.Destination}} <- {{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}}{{println}}{{end}}'
docker volume ls -q | grep portainer
curl -sv https://${SERVER_HOST}:9443 -o /dev/null 2>&1 | grep -E "issuer:|HTTP/"
```

| Line | Expected |
|---|---|
| `name=` | `/portainer  state=running  restart=unless-stopped`, image `portainer/portainer-ce:lts` |
| `networks=` | `edge`, and `ports=` empty (nothing published; Caddy fronts it) |
| `mount` | `/data <- portainer_data` and `/var/run/docker.sock <- /var/run/docker.sock` |
| `volume ls` | `portainer_data` only (no `portainer_portainer_data` duplicate) |
| `curl` | `issuer: CN=Caddy Local Authority …` and `HTTP/2 200` |

**Verify:** `https://<SERVER_HOST>:9443` shows your existing login (not the setup wizard) with a trusted padlock.

### Authentication

Portainer keeps its local `admin` login; each method below adds an OAuth button.

**Dex** (free): set in Portainer's web UI, no file change: Settings → Authentication → **OAuth** → provider **Custom**, then:

| Field | Value |
|---|---|
| Client ID | `portainer` |
| Client secret | `PORTAINER_OIDC_SECRET` from `/opt/stacks/dex/.env` |
| Authorization URL | `https://<SERVER_HOST>:5556/dex/auth` |
| Access token URL | `http://dex:5556/dex/token` |
| Resource URL | `http://dex:5556/dex/userinfo` |
| Redirect URL | `https://<SERVER_HOST>:9443` |
| User identifier | `email` |
| Scopes | `openid email profile` |

Turn on **Automatic user provisioning** so a person's first sign-in creates their Portainer user (a standard user; promote admins under Users). Without it, sign-in fails for anyone without a Portainer user yet, even though the Dex log shows `login successful`: Portainer just returns to its login page. Keep the local `admin` login as a fallback.

**Google Account** (free): through Dex's Google connector, with nothing to change here. Portainer's built-in Google preset is 💲 paid (Business Edition), and Community Edition takes only one OAuth provider, so Dex is how several providers share it.

**Azure** (free): through Dex's Microsoft connector, with nothing to change here. Portainer's built-in Microsoft preset is 💲 paid (Business Edition).

### Test

1. **Sign-in:** `https://<SERVER_HOST>:9443` shows your login (not the setup wizard); with Dex, **Login with OAuth** signs you in.
2. **It sees Docker:** Home → the local environment lists the server's containers (`caddy`, `outline`, …) as running.
3. **An action works:** open a container's **Logs** (e.g. `caddy`): recent lines appear.

## Step 9: Monitoring stack

**Check:** `grafana`, `prometheus`, `node-exporter`, `dcgm-exporter`.

### Clean reinstall

Removes the four monitoring stacks as if they had never been installed. Skip it for a first install. **Dashboards, Grafana users and settings, and all collected metrics are lost** with the volumes. The options on top (Alerts, Central logs) have their own Remove parts. Each line asks first.
```bash
confirm "Stop and remove Grafana, Prometheus, Node Exporter, and dcgm-exporter?" && for s in grafana prometheus node-exporter dcgm-exporter; do (cd /opt/stacks/$s && docker compose down); done
confirm "Delete dashboards, Grafana users, and all metrics (volumes grafana_data, prometheus_data)?" && docker volume rm grafana_data prometheus_data
confirm "Delete the four stack folders and the Caddy files grafana.caddy and prometheus.caddy?" && rm -rf /opt/stacks/grafana /opt/stacks/prometheus /opt/stacks/node-exporter /opt/stacks/dcgm-exporter /opt/stacks/caddy/conf.d/grafana.caddy /opt/stacks/caddy/conf.d/prometheus.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the four images (downloaded again on the next install)?" && docker image rm grafana/grafana:latest prom/prometheus:latest prom/node-exporter:latest nvcr.io/nvidia/k8s/dcgm-exporter:latest
```

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -E '^(grafana|prometheus|node-exporter|dcgm-exporter)$'
docker volume ls -q | grep -E '^(grafana|prometheus)_data$'
ls -d /opt/stacks/grafana /opt/stacks/prometheus /opt/stacks/node-exporter /opt/stacks/dcgm-exporter 2>/dev/null
```

### Install

An older combined stack at `/opt/stacks/monitoring` may exist. Check:
```bash
docker inspect prometheus --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' 2>/dev/null
```
If it prints `/opt/stacks/monitoring`, back up anything worth keeping, then take it down:
```bash
confirm "Tear down the old combined /opt/stacks/monitoring stack? (containers only; volumes are kept)" && cd /opt/stacks/monitoring && docker compose down
```

```bash
mkdir -p /opt/stacks/{grafana,prometheus,node-exporter,dcgm-exporter}
```

`/opt/stacks/grafana/.env`:
```env
SERVER_HOST=<from /opt/stacks/shared/.env>
GRAFANA_ADMIN_PASSWORD=CHANGE_ME
# Sign-in through Dex; set GRAFANA_SSO=false and leave the secret out if Dex is not deployed
GRAFANA_SSO=true
GRAFANA_OIDC_SECRET=<GRAFANA_OIDC_SECRET from /opt/stacks/dex/.env>
# Optional email (see the guide option: email for all services); with Infisical these come from prod:/shared
# SMTP_ENABLED=true            # alert emails
# SMTP_HOST=smtp.gmail.com
# SMTP_PORT=587
# SMTP_USERNAME=<the dedicated gmail address>
# SMTP_PASSWORD=<16-character app password>
```

`/opt/stacks/grafana/compose.yaml`:
```yaml
services:
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
      GF_SERVER_ROOT_URL: https://${SERVER_HOST}:9450
      # Look and time zone for everyone who has not picked their own (profile -> Preferences)
      GF_USERS_DEFAULT_THEME: system                 # dark, light, or system (follows the computer)
      GF_DATE_FORMATS_DEFAULT_TIMEZONE: Asia/Bangkok # an IANA time zone, or browser (the time zone of each viewer)
      # Sign-in through Dex: the browser goes through Caddy, Grafana itself calls Dex directly
      GF_AUTH_GENERIC_OAUTH_ENABLED: ${GRAFANA_SSO:-false}
      GF_AUTH_GENERIC_OAUTH_NAME: Dex
      GF_AUTH_GENERIC_OAUTH_CLIENT_ID: grafana
      GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET: ${GRAFANA_OIDC_SECRET:-}
      GF_AUTH_GENERIC_OAUTH_SCOPES: openid email profile
      GF_AUTH_GENERIC_OAUTH_AUTH_URL: https://${SERVER_HOST}:5556/dex/auth
      GF_AUTH_GENERIC_OAUTH_TOKEN_URL: http://dex:5556/dex/token
      GF_AUTH_GENERIC_OAUTH_API_URL: http://dex:5556/dex/userinfo
      GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP: "true"
      # Email for alerts: off unless SMTP_ENABLED=true in .env
      GF_SMTP_ENABLED: ${SMTP_ENABLED:-false}
      GF_SMTP_HOST: ${SMTP_HOST:-smtp.gmail.com}:${SMTP_PORT:-587}
      GF_SMTP_USER: ${SMTP_USERNAME:-}
      GF_SMTP_PASSWORD: ${SMTP_PASSWORD:-}
      GF_SMTP_FROM_ADDRESS: ${SMTP_USERNAME:-}
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana.ini:/etc/grafana/grafana.ini:ro
    networks: [edge]

networks:
  edge:
    external: true

volumes:
  grafana_data:
    external: true
```

`/opt/stacks/grafana/grafana.ini` — Grafana's own settings, all left at their defaults; uncomment a line to change it:
```ini
# Settings set under environment: in compose.yaml win over this file, so they are not repeated here:
# [server], [security], [auth.generic_oauth], [smtp], and the default theme and time zone.
# Keep secrets out of this file.

[users]
# Role for people who sign in through Dex for the first time: Viewer, Editor, or Admin
# auto_assign_org_role = Viewer

[dashboards]
# Fastest refresh a dashboard may use
# min_refresh_interval = 5s
```

**Grafana settings:** each setting can live in `grafana.ini` (`[section]` + `key`) or in an environment variable named `GF_<SECTION>_<KEY>`, with dots written as `_`. For example `[auth.generic_oauth] enabled` is `GF_AUTH_GENERIC_OAUTH_ENABLED`. The variable wins when both are set. Values that come from `.env` (passwords, the server name, sign-in, email) are variables in `compose.yaml`, and the default theme and time zone are written there directly; everything else goes in `grafana.ini`. Create the file before the first `up -d`: if it's missing, Docker creates an empty folder named `grafana.ini` and Grafana won't start. Grafana reads the file only at start, so after an edit run `cd /opt/stacks/grafana && docker compose up -d --force-recreate grafana`. Check with `docker exec grafana cat /etc/grafana/grafana.ini`. The full list of settings is in Grafana's documentation under "Configure Grafana". **Older install?** Grafana set up without `grafana.ini`: see [Upgrading an older install](options/upgrade-older-install.md#grafana).

**Option:** [Email (SMTP) for all services](options/smtp-email.md) — one Gmail account sends mail for every app; the lines are already in this step's files, commented out.

`/opt/stacks/prometheus/prometheus.yml` (`.yml`, not `.yaml`: it's the path the Prometheus image reads by default, `/etc/prometheus/prometheus.yml`, and the name its docs use):
```yaml
global:
  scrape_interval: 30s            # how often each target is read
scrape_configs:
  - job_name: node-exporter
    static_configs: [{ targets: ["node-exporter:9100"] }]
  - job_name: dcgm-exporter
    static_configs: [{ targets: ["dcgm-exporter:9400"] }]
  - job_name: litellm            # shows DOWN unless the LiteLLM Enterprise Prometheus callback is enabled
    static_configs: [{ targets: ["litellm:4000"] }]
```

`/opt/stacks/prometheus/compose.yaml`:
```yaml
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    # The two start options of the image, plus how long to keep data: 30 days, at most 5 GB
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --storage.tsdb.retention.time=30d
      - --storage.tsdb.retention.size=5GB
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    networks: [edge]

networks:
  edge:
    external: true

volumes:
  prometheus_data:
    external: true
```

**How much Prometheus keeps:** it reads each target every 30 seconds (`scrape_interval`), enough to see GPU load from model answers, and keeps 30 days, enough for a development server (`90d` to compare a month with the ones before). Old data is deleted when it is 30 days old or the data passes 5 GB, whichever comes first; with the targets here it stays near 0.5 GB. `command:` replaces the image's start options, which is why it repeats the image's own two (`--config.file`, `--storage.tsdb.path`) before the retention ones. To change a value, edit the file and run `cd /opt/stacks/prometheus && docker compose up -d --force-recreate prometheus`; check under Status → Runtime & Build Information (`https://<SERVER_HOST>:9090/status`). With a 30-second interval, Grafana `rate()` panels need a window of at least 2 minutes (`rate(...[2m])`).

`/opt/stacks/node-exporter/compose.yaml`:
```yaml
services:
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    # Report the host name of the server (Nodename in Grafana), not the container ID
    uts: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro,rslave
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
      # Off by default; adds process, thread, and PID counts (System Processes in Grafana)
      - '--collector.processes'
    networks: [edge]

networks:
  edge:
    external: true
```

`/opt/stacks/dcgm-exporter/compose.yaml`:
```yaml
services:
  dcgm-exporter:
    image: nvcr.io/nvidia/k8s/dcgm-exporter:latest
    container_name: dcgm-exporter
    restart: unless-stopped
    devices:
      - nvidia.com/gpu=all
    networks: [edge]

networks:
  edge:
    external: true
```

```bash
docker volume create grafana_data
docker volume create prometheus_data

cd /opt/stacks/grafana        && docker compose up -d
cd /opt/stacks/prometheus     && docker compose up -d
cd /opt/stacks/node-exporter  && docker compose up -d
cd /opt/stacks/dcgm-exporter  && docker compose up -d
```

Front Grafana and Prometheus through Caddy (the exporters stay internal):
```bash
cat > /opt/stacks/caddy/conf.d/grafana.caddy <<'EOF'
https://{$SERVER_HOST}:9450, https://{$SERVER_IP}:9450 {
	tls internal
	reverse_proxy grafana:3000
}
EOF
cat > /opt/stacks/caddy/conf.d/prometheus.caddy <<'EOF'
https://{$SERVER_HOST}:9090 {
	tls internal
	import sso prometheus:9090
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```

**Check the result.** Every line must match the table:
```bash
docker inspect -f '{{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}' grafana prometheus node-exporter dcgm-exporter
docker inspect -f '{{.Name}}  networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}  uts={{.HostConfig.UTSMode}}' grafana prometheus node-exporter dcgm-exporter
docker inspect -f '{{.Name}}{{range .Mounts}}  {{.Destination}} <- {{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}}{{end}}' grafana prometheus
docker inspect prometheus --format '{{join .Args " "}}'
docker exec grafana sh -c 'echo "root URL: $GF_SERVER_ROOT_URL, Dex: $GF_AUTH_GENERIC_OAUTH_ENABLED, theme: $GF_USERS_DEFAULT_THEME"'
docker exec node-exporter hostname
curl -sk "https://${SERVER_HOST}:9450/api/health"; echo
curl -sv https://${SERVER_HOST}:9450 -o /dev/null 2>&1 | grep -E "issuer:|HTTP/"
```

| Line | Expected |
|---|---|
| state | all four `running`, `restart=unless-stopped` |
| networks | `edge` for all four; `node-exporter` with `uts=host` |
| mounts | Grafana: `/var/lib/grafana <- grafana_data`, `/etc/grafana/grafana.ini <- /opt/stacks/grafana/grafana.ini`; Prometheus: `/etc/prometheus/prometheus.yml <- /opt/stacks/prometheus/prometheus.yml`, `/prometheus <- prometheus_data` |
| Prometheus args | include `--storage.tsdb.retention.time=30d` and `--storage.tsdb.retention.size=5GB` |
| Grafana environment | `root URL: https://<SERVER_HOST>:9450`, `Dex: true` (with Dex), your theme |
| `hostname` | the server host name (not a container ID) |
| `api/health` | JSON with `"database": "ok"` |
| `curl` | `issuer: CN=Caddy Local Authority …` and `HTTP/2 200` (or `302` to the login) |

**Verify:** `https://<SERVER_HOST>:9090/targets` first shows the Dex login (with the gate), then node-exporter and dcgm-exporter UP (litellm stays DOWN, which is expected).

### Authentication

**Grafana** keeps its local `admin` login.

**Dex** (free): the `GF_AUTH_GENERIC_OAUTH_*` lines, switched by `GRAFANA_SSO` in `.env`. With Dex, Grafana's login page gets a "Sign in with Dex" button; people who sign in that way join as Viewers (change it with `auto_assign_org_role` in `grafana.ini`), and the local `admin` can promote them (Administration → Users). The local `admin` login keeps working. Sign-in through Dex works on `https://<SERVER_HOST>:9450` (Grafana's root URL); the IP address still serves the local login.

The `GF_AUTH_GENERIC_OAUTH_*` lines need no editing; they connect Grafana to the `grafana` client already in Dex's `config.yaml`:

| Line | Value | Meaning |
|---|---|---|
| `ENABLED` | `${GRAFANA_SSO:-false}` | On or off, from `GRAFANA_SSO` in `.env` |
| `NAME` | `Dex` | The button text: "Sign in with Dex" |
| `CLIENT_ID` | `grafana` | Matches `- id: grafana` in Dex `config.yaml` |
| `CLIENT_SECRET` | `${GRAFANA_OIDC_SECRET:-}` | Equals `GRAFANA_OIDC_SECRET` in `/opt/stacks/dex/.env` |
| `SCOPES` | `openid email profile` | Asks Dex for the email address and name |
| `AUTH_URL` | `https://${SERVER_HOST}:5556/dex/auth` | Opened by the browser, so through Caddy |
| `TOKEN_URL`, `API_URL` | `http://dex:5556/dex/...` | Called by Grafana itself, straight over `edge` |
| `ALLOW_SIGN_UP` | `"true"` | Creates the Grafana user at the first sign-in |

`GF_SERVER_ROOT_URL` matters too: Grafana sends people back to `<root URL>/login/generic_oauth`, which must match the `grafana` entry under `redirectURIs` in Dex `config.yaml`.

To turn it on:
1. `grep ^GRAFANA_OIDC_SECRET= /opt/stacks/dex/.env` and copy the value.
2. In `/opt/stacks/grafana/.env`, set `GRAFANA_SSO=true` and `GRAFANA_OIDC_SECRET=` that value. With Infisical, give `GRAFANA_OIDC_SECRET` the same value in `prod:/dex` and `prod:/grafana`, then run `pull-secrets.sh`.
3. `cd /opt/stacks/grafana && docker compose up -d`
4. Check: `docker exec grafana printenv GF_AUTH_GENERIC_OAUTH_ENABLED GF_SERVER_ROOT_URL` prints `true` and `https://<SERVER_HOST>:9450`.
5. Open `https://<SERVER_HOST>:9450`, click **Sign in with Dex**, sign in, and you're back in Grafana as a Viewer. Sign in as `admin` to make yourself Admin (Administration → Users).

| Symptom | Cause |
|---|---|
| No "Sign in with Dex" button | `GRAFANA_SSO` isn't `true`, or Grafana wasn't recreated |
| Dex says "Unregistered redirect_uri" | Grafana was opened by IP, or `SERVER_HOST` differs between the Dex and Grafana `.env` (run `sync-shared-env.sh`) |
| Back in Grafana with "Login failed" | `GRAFANA_OIDC_SECRET` differs between the Dex and Grafana `.env` |

The reason behind a failure: `docker logs grafana 2>&1 | grep -i oauth | tail`.

**Google Account** (free): through Dex's Google connector, with nothing to change here. Grafana's own Google login (`GF_AUTH_GOOGLE_*`) is also free.

**Azure** (free): through Dex's Microsoft connector, with nothing to change here. Grafana's own Azure AD login (`GF_AUTH_AZUREAD_*`) is also free.

**Prometheus** has no login of its own:
- **Dex** (free): it sits behind the sign-in gate from Step 6, so people sign in through Dex first. No Dex? See [Without the sign-in gate](options/without-sign-in-gate.md).
- **Google Account** (free) and **Azure** (free): through Dex. The gate offers whatever Dex offers, so turning on Google or Microsoft in Dex covers Prometheus too. oauth2-proxy could also use Google or Azure directly (free), but then every gated app skips Dex.

### Usage

In Grafana (`https://<SERVER_HOST>:9450`, user `admin`), add Prometheus as a data source (Connections → Data sources → Prometheus) with URL `http://prometheus:9090`, and set its **Scrape interval** to `30s` to match `prometheus.yml`. Then import two ready-made dashboards (Dashboards → New → Import, enter the ID, pick the Prometheus data source): `1860` Node Exporter Full (CPU, memory, disks, network) and `12239` NVIDIA DCGM Exporter (GPU). Import by ID needs the server to reach `grafana.com`; otherwise download the JSON from `https://grafana.com/grafana/dashboards/<ID>` on your PC and upload it on the same page.

**Option:** [Alerts](options/alerts.md) — email when a service stops answering, a certificate stops renewing, or the disk, memory, or GPU temperature crosses a limit (blackbox exporter and Grafana alert rules).

**Option:** [Central logs](options/central-logs.md) — every container's logs in Grafana (Loki and Alloy), searchable and kept 30 days.

**Option:** [Node Exporter Full panels](options/node-exporter-full-panels.md) — what each panel shows, which ones stay empty and why, what turning on more costs, and which to keep.

### Test

1. **Targets:** `https://<SERVER_HOST>:9090/targets` (after the Dex sign-in) shows `node-exporter` and `dcgm-exporter` UP.
2. **Data flows:** in Prometheus, the query `up` lists both with value `1`; `DCGM_FI_DEV_GPU_TEMP` returns the GPU temperature.
3. **Grafana:** sign in with Dex; Connections → Data sources → Prometheus → **Save & test** says it works; a dashboard (e.g. Node Exporter Full) shows CPU, memory, and disk with recent values.
4. **Email** (if set up): Alerting → Contact points → the email contact point → **Test** sends a mail.

## Step 10: Sourcebot (code search)

**Check:** `sourcebot`, `sourcebot-postgres`, `sourcebot-redis`.

### Clean reinstall

Removes Sourcebot as if it had never been installed. Skip it for a first install. Its users, settings, and search index are lost with the volumes; the index rebuilds from the repositories on the next install. Each line asks first.
```bash
confirm "Stop and remove the Sourcebot containers?" && cd /opt/stacks/sourcebot && docker compose down; cd ~
confirm "Delete users, settings, and the index (volumes sourcebot_pg_data, sourcebot_redis_data, sourcebot_data)?" && docker volume rm sourcebot_pg_data sourcebot_redis_data sourcebot_data
confirm "Delete /opt/stacks/sourcebot (.env, config.json) and its Caddy file?" && rm -rf /opt/stacks/sourcebot /opt/stacks/caddy/conf.d/sourcebot.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the Sourcebot image (downloaded again on the next install)?" && docker image rm docker.sourcebot.dev/sourcebot-dev/sourcebot:latest
```
Revoke its GitHub token on GitHub if Sourcebot is gone for good.

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -E '^sourcebot(-postgres|-redis)?$'
docker volume ls -q | grep -E '^sourcebot_'
ls -d /opt/stacks/sourcebot /opt/stacks/caddy/conf.d/sourcebot.caddy 2>/dev/null
```

### Install

**Older install?** See [Upgrading an older install](options/upgrade-older-install.md#sourcebot) (no `config.json` or `sourcebot_data` volume).

```bash
mkdir -p /opt/stacks/sourcebot
```

`/opt/stacks/sourcebot/.env`:
```env
SERVER_HOST=<from /opt/stacks/shared/.env>
SOURCEBOT_DB_PASSWORD=<openssl rand -hex 24>
SOURCEBOT_AUTH_SECRET=<openssl rand -base64 33>
SOURCEBOT_ENCRYPTION_KEY=<openssl rand -base64 24>
GITHUB_TOKEN=<read-only token for the repos to index; leave empty for public repos only>
```

`/opt/stacks/sourcebot/config.json` — the repositories to index:
```json
{
  "$schema": "https://raw.githubusercontent.com/sourcebot-dev/sourcebot/main/schemas/v3/index.json",
  "connections": {
    "github": {
      "type": "github",
      "repos": ["<owner>/<repo>"],
      "token": { "env": "GITHUB_TOKEN" }
    }
  }
}
```
List repositories under `repos`, or index whole accounts with `"orgs": ["<org>"]` / `"users": ["<user>"]`. GitLab, Gitea, Bitbucket, and plain Git URLs work the same way with their own `type` (see Sourcebot's docs). Sourcebot re-reads this file on its own, so adding a repo later needs no restart.

`/opt/stacks/sourcebot/compose.yaml` (Sourcebot's official compose, with this guide's conventions):
```yaml
services:
  sourcebot-postgres:
    image: postgres:17
    container_name: sourcebot-postgres
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: ${SOURCEBOT_DB_PASSWORD}
      POSTGRES_DB: sourcebot
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 30s          # once healthy; fast checks only while starting:
      start_period: 60s
      start_interval: 3s
      timeout: 3s
      retries: 10
    volumes: [sourcebot_pg_data:/var/lib/postgresql/data]
    networks: [default]

  sourcebot-redis:
    image: redis:7
    container_name: sourcebot-redis
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 30s          # once healthy; fast checks only while starting:
      start_period: 60s
      start_interval: 3s
      timeout: 10s
      retries: 10
    volumes: [sourcebot_redis_data:/data]
    networks: [default]

  sourcebot:
    image: docker.sourcebot.dev/sourcebot-dev/sourcebot:latest
    container_name: sourcebot
    restart: unless-stopped
    environment:
      CONFIG_PATH: /data/config.json
      AUTH_URL: https://${SERVER_HOST}:9460
      AUTH_SECRET: ${SOURCEBOT_AUTH_SECRET}
      SOURCEBOT_ENCRYPTION_KEY: ${SOURCEBOT_ENCRYPTION_KEY}
      DATABASE_URL: postgresql://postgres:${SOURCEBOT_DB_PASSWORD}@sourcebot-postgres:5432/sourcebot
      REDIS_URL: redis://sourcebot-redis:6379
      GITHUB_TOKEN: ${GITHUB_TOKEN:-}
    volumes:
      - ./config.json:/data/config.json:ro
      - sourcebot_data:/data          # search index and cloned repos
    depends_on:
      sourcebot-postgres: { condition: service_healthy }
      sourcebot-redis: { condition: service_healthy }
    networks: [default, edge]

networks:
  default:
    driver_opts:
      com.docker.network.bridge.name: br-sourcebot
  edge:
    external: true

volumes:
  sourcebot_pg_data:
    external: true
  sourcebot_redis_data:
    external: true
  sourcebot_data:
    external: true
```
```bash
docker volume create sourcebot_pg_data
docker volume create sourcebot_redis_data
docker volume create sourcebot_data

cd /opt/stacks/sourcebot && docker compose up -d
```
```bash
cat > /opt/stacks/caddy/conf.d/sourcebot.caddy <<'EOF'
https://{$SERVER_HOST}:9460 {
	tls internal
	reverse_proxy sourcebot:3000
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
Sourcebot answers on `SERVER_HOST` only: its `AUTH_URL` is one fixed address.

**Check the result.** Every line must match the table:
```bash
docker inspect -f '{{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}' sourcebot sourcebot-postgres sourcebot-redis
docker inspect -f '{{.Name}}  networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' sourcebot sourcebot-postgres sourcebot-redis
docker inspect -f '{{.Name}}  health={{.State.Health.Status}}' sourcebot-postgres sourcebot-redis
docker inspect -f '{{.Name}}{{range .Mounts}}  {{.Destination}} <- {{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}}{{end}}' sourcebot sourcebot-postgres sourcebot-redis
docker exec sourcebot sh -c 'echo "AUTH_SECRET: ${#AUTH_SECRET} characters, encryption key: ${#SOURCEBOT_ENCRYPTION_KEY} characters, GitHub token: ${#GITHUB_TOKEN} characters, AUTH_URL: $AUTH_URL"'
curl -sv https://${SERVER_HOST}:9460 -o /dev/null 2>&1 | grep -E "issuer:|HTTP/"
```

| Line | Expected |
|---|---|
| state | all three `running`, `restart=unless-stopped`; images `sourcebot-dev/sourcebot:latest`, `postgres:17`, `redis:7` |
| networks | `sourcebot`: `edge sourcebot_default`; the other two: `sourcebot_default` only |
| health | `healthy` for both |
| mounts | `sourcebot`: `/data/config.json <- /opt/stacks/sourcebot/config.json` and `/data <- sourcebot_data`; `sourcebot_pg_data`, `sourcebot_redis_data` on the other two |
| environment | `AUTH_SECRET: 44 characters`, `encryption key: 32 characters`, a GitHub token length (0 only for public repositories), `AUTH_URL: https://<SERVER_HOST>:9460` |
| `curl` | `issuer: CN=Caddy Local Authority …` and `HTTP/2 200` (or a `30x` redirect) |

**Verify:** `https://<SERVER_HOST>:9460` loads; create the owner account on first visit.

### Authentication

Sourcebot keeps its own login: email and password, with the owner account created on the first visit.

**Dex**, **Google Account**, and **Azure**: 💲 paid. Single sign-on is a Sourcebot Enterprise feature, so none of them is set up here.

### Usage

Indexing starts on its own (`docker logs -f sourcebot`); a search finds code once the repos are indexed. Its MCP endpoint (`/api/mcp`) is used in Step 16.

### Test

1. **Sign-in:** `https://<SERVER_HOST>:9460` asks for the owner account on the first visit, then signs in. From Sourcebot v6, activate it once (Settings → License; free for up to 5 users).
2. **Indexing:** `docker logs sourcebot 2>&1 | grep -i -E "index|error" | tail` shows each repository from `config.json` indexed, with no `404` or `401` (those mean the GitHub token cannot see the repository).
3. **A search:** search for a function name you know; results come from the right repository and file.
4. **MCP** (for agents): `curl -sk -o /dev/null -w "%{http_code}\n" https://${SERVER_HOST}:9460/api/mcp` answers (not `000`); an agent with it configured finds code by name.

## Step 11: Langfuse (LLM tracing)

Comes before LiteLLM so LiteLLM's config can include Langfuse's keys from the start. Skip this step if you don't want tracing; Step 12 says which lines to leave out.

**Check:** `langfuse-web`, `langfuse-worker`, `langfuse-postgres`, `langfuse-redis`, `langfuse-clickhouse`, `langfuse-minio`. Older installs may use Compose's default names (`langfuse-langfuse-web-1`, …).

### Clean reinstall

Removes Langfuse as if it had never been installed. Skip it for a first install. **All traces, users, and projects are lost** with the volumes. To keep the installation and only empty it (all traces gone, same keys), use `reset-stack.sh langfuse` instead ([Update workflow](#step-20-update-workflow)). Each line asks first.
```bash
confirm "Stop and remove the six Langfuse containers?" && cd /opt/stacks/langfuse && docker compose down; cd ~
confirm "Delete all traces, users, and projects (volumes langfuse_pg_data, langfuse_redis_data, langfuse_ch_data, langfuse_ch_logs, langfuse_minio_data)?" && docker volume rm langfuse_pg_data langfuse_redis_data langfuse_ch_data langfuse_ch_logs langfuse_minio_data
confirm "Delete /opt/stacks/langfuse (.env with its secrets and API keys) and its Caddy file?" && rm -rf /opt/stacks/langfuse /opt/stacks/caddy/conf.d/langfuse.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the Langfuse images (downloaded again on the next install)?" && docker image rm docker.langfuse.com/langfuse/langfuse:4 docker.langfuse.com/langfuse/langfuse-worker:4 clickhouse/clickhouse-server:25.12 cgr.dev/chainguard/minio
```
With new API keys in a new `.env`, give LiteLLM the same `LANGFUSE_PUBLIC_KEY` and `LANGFUSE_SECRET_KEY` (with Infisical, they come from `prod:/shared`), or LiteLLM's traces are rejected.

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -E '^langfuse-'
docker volume ls -q | grep -E '^langfuse_'
ls -d /opt/stacks/langfuse /opt/stacks/caddy/conf.d/langfuse.caddy 2>/dev/null
```

### Install

**Older install?** See [Upgrading an older install](options/upgrade-older-install.md#langfuse) (Langfuse on `SERVER_IP`).

```bash
mkdir -p /opt/stacks/langfuse
```

`/opt/stacks/langfuse/.env` (replace every `CHANGE_ME`):
```env
SERVER_HOST=<from /opt/stacks/shared/.env>
SERVER_IP=<from /opt/stacks/shared/.env>
LANGFUSE_DB_PASSWORD=CHANGE_ME
LANGFUSE_NEXTAUTH_SECRET=CHANGE_ME          # openssl rand -hex 32
LANGFUSE_SALT=CHANGE_ME                     # openssl rand -hex 32
LANGFUSE_ENCRYPTION_KEY=CHANGE_ME           # openssl rand -hex 32 — must be exactly 64 hex chars
LANGFUSE_CLICKHOUSE_PASSWORD=CHANGE_ME
LANGFUSE_REDIS_PASSWORD=CHANGE_ME
LANGFUSE_MINIO_PASSWORD=CHANGE_ME
# First-run bootstrap: creates the org, project, admin user, and the project API key pair on first start,
# so LiteLLM can use the keys straight away without clicking through the UI.
LANGFUSE_INIT_USER_EMAIL=CHANGE_ME
LANGFUSE_INIT_USER_PASSWORD=CHANGE_ME
# The same two names and values as in LiteLLM; with Infisical, keep them once in prod:/shared
LANGFUSE_PUBLIC_KEY=pk-lf-CHANGE_ME     # any unique string with this prefix
LANGFUSE_SECRET_KEY=sk-lf-CHANGE_ME     # any unique string with this prefix
# Sign-in through Dex; leave out, with the AUTH_CUSTOM_* lines in compose.yaml, if Dex is not deployed
LANGFUSE_OIDC_SECRET=<LANGFUSE_OIDC_SECRET from /opt/stacks/dex/.env>
# Optional email (see the guide option: email for all services); Langfuse takes one URL, with the @ in the address written as %40.
# With Infisical, leave SMTP_CONNECTION_URL empty: pull-secrets.sh builds it from the SMTP_* keys in prod:/shared
# SMTP_USERNAME=<the dedicated gmail address>
# SMTP_CONNECTION_URL=smtp://<name>%40gmail.com:<app-password>@smtp.gmail.com:587
```

`/opt/stacks/langfuse/compose.yaml` (Langfuse's official compose, with this guide's conventions):
```yaml
x-langfuse-env: &langfuse-env
  NEXTAUTH_URL: https://${SERVER_HOST}:9470
  DATABASE_URL: postgresql://postgres:${LANGFUSE_DB_PASSWORD}@langfuse-postgres:5432/langfuse
  SALT: ${LANGFUSE_SALT}
  ENCRYPTION_KEY: ${LANGFUSE_ENCRYPTION_KEY}
  TELEMETRY_ENABLED: "false"
  CLICKHOUSE_MIGRATION_URL: clickhouse://langfuse-clickhouse:9000
  CLICKHOUSE_URL: http://langfuse-clickhouse:8123
  CLICKHOUSE_USER: clickhouse
  CLICKHOUSE_PASSWORD: ${LANGFUSE_CLICKHOUSE_PASSWORD}
  CLICKHOUSE_CLUSTER_ENABLED: "false"
  REDIS_HOST: langfuse-redis
  REDIS_PORT: "6379"
  REDIS_AUTH: ${LANGFUSE_REDIS_PASSWORD}
  LANGFUSE_S3_EVENT_UPLOAD_BUCKET: langfuse
  LANGFUSE_S3_EVENT_UPLOAD_REGION: auto
  LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID: minio
  LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY: ${LANGFUSE_MINIO_PASSWORD}
  LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT: http://langfuse-minio:9000
  LANGFUSE_S3_EVENT_UPLOAD_FORCE_PATH_STYLE: "true"
  LANGFUSE_S3_EVENT_UPLOAD_PREFIX: events/
  LANGFUSE_S3_MEDIA_UPLOAD_BUCKET: langfuse
  LANGFUSE_S3_MEDIA_UPLOAD_REGION: auto
  LANGFUSE_S3_MEDIA_UPLOAD_ACCESS_KEY_ID: minio
  LANGFUSE_S3_MEDIA_UPLOAD_SECRET_ACCESS_KEY: ${LANGFUSE_MINIO_PASSWORD}
  LANGFUSE_S3_MEDIA_UPLOAD_ENDPOINT: http://langfuse-minio:9000
  LANGFUSE_S3_MEDIA_UPLOAD_FORCE_PATH_STYLE: "true"
  LANGFUSE_S3_MEDIA_UPLOAD_PREFIX: media/
  # Email (invites, password reset): off while SMTP_CONNECTION_URL is empty
  SMTP_CONNECTION_URL: ${SMTP_CONNECTION_URL:-}
  EMAIL_FROM_ADDRESS: ${SMTP_USERNAME:-}

x-langfuse-depends: &langfuse-depends
  langfuse-postgres:   { condition: service_healthy }
  langfuse-redis:      { condition: service_healthy }
  langfuse-clickhouse: { condition: service_healthy }
  langfuse-minio:      { condition: service_healthy }

services:
  langfuse-postgres:
    image: postgres:17
    container_name: langfuse-postgres
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: ${LANGFUSE_DB_PASSWORD}
      POSTGRES_DB: langfuse
      TZ: UTC
      PGTZ: UTC
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 30s          # once healthy; fast checks only while starting:
      start_period: 60s
      start_interval: 3s
      timeout: 3s
      retries: 10
    volumes: [langfuse_pg_data:/var/lib/postgresql/data]
    networks: [default]

  langfuse-redis:
    image: redis:7
    container_name: langfuse-redis
    restart: unless-stopped
    command: --requirepass ${LANGFUSE_REDIS_PASSWORD} --maxmemory-policy noeviction
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 30s          # once healthy; fast checks only while starting:
      start_period: 60s
      start_interval: 3s
      timeout: 10s
      retries: 10
    volumes: [langfuse_redis_data:/data]
    networks: [default]

  langfuse-clickhouse:
    image: clickhouse/clickhouse-server:25.12
    container_name: langfuse-clickhouse
    restart: unless-stopped
    user: "101:101"
    environment:
      CLICKHOUSE_DB: default
      CLICKHOUSE_USER: clickhouse
      CLICKHOUSE_PASSWORD: ${LANGFUSE_CLICKHOUSE_PASSWORD}
    healthcheck:
      test: wget --no-verbose --tries=1 --spider http://localhost:8123/ping || exit 1
      interval: 30s          # once healthy; fast checks only while starting:
      start_period: 60s
      start_interval: 3s
      timeout: 5s
      retries: 10
    volumes:
      - langfuse_ch_data:/var/lib/clickhouse
      - langfuse_ch_logs:/var/log/clickhouse-server
    networks: [default]

  langfuse-minio:
    image: cgr.dev/chainguard/minio
    container_name: langfuse-minio
    restart: unless-stopped
    entrypoint: sh
    command: -c 'mkdir -p /data/langfuse && minio server --address ":9000" --console-address ":9001" /data'
    environment:
      MINIO_ROOT_USER: minio
      MINIO_ROOT_PASSWORD: ${LANGFUSE_MINIO_PASSWORD}
    healthcheck:
      test: ["CMD", "mc", "ready", "local"]
      interval: 30s          # once healthy; fast checks only while starting:
      start_period: 60s
      start_interval: 3s
      timeout: 5s
      retries: 5
    volumes: [langfuse_minio_data:/data]
    networks: [default]

  langfuse-worker:
    image: docker.langfuse.com/langfuse/langfuse-worker:4
    container_name: langfuse-worker
    restart: unless-stopped
    environment:
      <<: *langfuse-env
    depends_on: *langfuse-depends
    networks: [default]

  langfuse-web:
    image: docker.langfuse.com/langfuse/langfuse:4
    container_name: langfuse-web
    restart: unless-stopped
    environment:
      <<: *langfuse-env
      NEXTAUTH_SECRET: ${LANGFUSE_NEXTAUTH_SECRET}
      LANGFUSE_S3_MEDIA_UPLOAD_INTERNAL_ENDPOINT: http://langfuse-minio:9000
      LANGFUSE_INIT_ORG_ID: default-org
      LANGFUSE_INIT_ORG_NAME: Default
      LANGFUSE_INIT_PROJECT_ID: default-project
      LANGFUSE_INIT_PROJECT_NAME: Default
      # Langfuse reads its own names; .env uses the same names as LiteLLM, so one value serves both
      LANGFUSE_INIT_PROJECT_PUBLIC_KEY: ${LANGFUSE_PUBLIC_KEY}
      LANGFUSE_INIT_PROJECT_SECRET_KEY: ${LANGFUSE_SECRET_KEY}
      LANGFUSE_INIT_USER_EMAIL: ${LANGFUSE_INIT_USER_EMAIL}
      LANGFUSE_INIT_USER_NAME: admin
      LANGFUSE_INIT_USER_PASSWORD: ${LANGFUSE_INIT_USER_PASSWORD}
      # Sign-in through Dex. Langfuse looks Dex up at its HTTPS address, so it needs the
      # server name inside the container (extra_hosts) and must trust the internal CA.
      AUTH_CUSTOM_CLIENT_ID: langfuse
      AUTH_CUSTOM_CLIENT_SECRET: ${LANGFUSE_OIDC_SECRET}
      AUTH_CUSTOM_ISSUER: https://${SERVER_HOST}:5556/dex
      AUTH_CUSTOM_NAME: Dex
      AUTH_CUSTOM_SCOPE: openid email profile
      AUTH_CUSTOM_ALLOW_ACCOUNT_LINKING: "true"
      NODE_EXTRA_CA_CERTS: /certs/caddy-root-ca.crt
    extra_hosts:
      - "${SERVER_HOST}:${SERVER_IP}"
    volumes:
      - /opt/stacks/caddy/caddy-root-ca.crt:/certs/caddy-root-ca.crt:ro   # made when trusting the internal CA
    depends_on: *langfuse-depends
    networks: [default, edge]

networks:
  default:
    driver_opts:
      com.docker.network.bridge.name: br-langfuse
  edge:
    external: true

volumes:
  langfuse_pg_data:
    external: true
  langfuse_redis_data:
    external: true
  langfuse_ch_data:
    external: true
  langfuse_ch_logs:
    external: true
  langfuse_minio_data:
    external: true
```
Check `ls /opt/stacks/caddy/caddy-root-ca.crt` before starting: if the file is missing, Docker creates an empty folder in its place and Langfuse cannot reach Dex.

```bash
docker volume create langfuse_pg_data
docker volume create langfuse_redis_data
docker volume create langfuse_ch_data
docker volume create langfuse_ch_logs
docker volume create langfuse_minio_data

cd /opt/stacks/langfuse && docker compose up -d
```
The first start runs database migrations; give it a minute (`docker logs -f langfuse-web`).
```bash
cat > /opt/stacks/caddy/conf.d/langfuse.caddy <<'EOF'
https://{$SERVER_HOST}:9470 {
	tls internal
	reverse_proxy langfuse-web:3000
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
**Check the result.** Every line must match the table:
```bash
docker inspect -f '{{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}' langfuse-web langfuse-worker langfuse-postgres langfuse-redis langfuse-clickhouse langfuse-minio
docker inspect -f '{{.Name}}  networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' langfuse-web langfuse-worker langfuse-clickhouse
docker inspect -f '{{.Name}}  health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' langfuse-postgres langfuse-redis langfuse-clickhouse langfuse-minio
docker volume ls -q | grep -E '^langfuse_'
docker exec langfuse-web sh -c 'echo "ENCRYPTION_KEY: ${#ENCRYPTION_KEY} characters, NEXTAUTH_URL: $NEXTAUTH_URL, init keys: ${#LANGFUSE_INIT_PROJECT_PUBLIC_KEY}/${#LANGFUSE_INIT_PROJECT_SECRET_KEY} characters"'
docker exec langfuse-web getent hosts ${SERVER_HOST} langfuse-postgres langfuse-clickhouse
curl -sk https://${SERVER_HOST}:9470/api/public/health; echo
curl -sv https://${SERVER_HOST}:9470 -o /dev/null 2>&1 | grep -E "issuer:|HTTP/"
```

| Line | Expected |
|---|---|
| state | all six `running`, `restart=unless-stopped` |
| networks | `langfuse-web`: `edge langfuse_default`; worker and ClickHouse: `langfuse_default` only |
| health | `healthy` for Postgres, Redis, ClickHouse, MinIO |
| volumes | `langfuse_pg_data`, `langfuse_redis_data`, `langfuse_ch_data`, `langfuse_ch_logs`, `langfuse_minio_data`; no hash-named ones |
| environment | `ENCRYPTION_KEY: 64 characters`, `NEXTAUTH_URL: https://<SERVER_HOST>:9470`, both init keys non-zero |
| `getent` | `SERVER_HOST` as your `SERVER_IP` (for Dex), and the two databases |
| `api/public/health` | `{"status":"OK", …}` |
| `curl` | `issuer: CN=Caddy Local Authority …` and `HTTP/2 200` (or a `30x` redirect) |

**Verify:** log in at `https://<SERVER_HOST>:9470` with `LANGFUSE_INIT_USER_EMAIL` / `LANGFUSE_INIT_USER_PASSWORD`. The `LANGFUSE_INIT_*` values only apply on the very first start.

**Option:** [Email (SMTP) for all services](options/smtp-email.md) — one Gmail account sends mail for every app; the lines are already in this step's files, commented out.

### Authentication

Langfuse keeps its own login: email and password, with `LANGFUSE_INIT_USER_EMAIL` as the first admin.

**Dex** (free): the `AUTH_CUSTOM_*` lines in `compose.yaml`. With Dex, the login page gets a "Dex" button next to email and password. `AUTH_CUSTOM_ALLOW_ACCOUNT_LINKING` lets someone whose Langfuse account already exists (e.g. the `LANGFUSE_INIT_USER_EMAIL` admin) sign in through Dex with the same email.

**Google Account** (free): through Dex's Google connector, with nothing to change here. Langfuse's own Google sign-in (`AUTH_GOOGLE_CLIENT_ID`, `AUTH_GOOGLE_CLIENT_SECRET`) is also free.

**Azure** (free): through Dex's Microsoft connector, with nothing to change here. Langfuse's own Azure AD sign-in (`AUTH_AZURE_AD_CLIENT_ID`, `AUTH_AZURE_AD_CLIENT_SECRET`, `AUTH_AZURE_AD_TENANT_ID`) is also free.

### Usage

**What gets traced:**
- Calls **through LiteLLM** are traced automatically once Step 12 is done.
- Calls made **directly to Ollama/vLLM** bypass LiteLLM and aren't traced unless the calling app uses the Langfuse SDK itself (pointed at `http://langfuse-web:3000`). To trace everything, send all model calls through LiteLLM.

**Limitation:** MinIO is internal-only, so media attachments (images/audio on traces) don't upload. Text tracing works fully.

### Test

1. **Sign-in:** `https://<SERVER_HOST>:9470` signs in with **Dex** and with the `LANGFUSE_INIT_USER_EMAIL` account; the project from `.env` is there.
2. **A trace arrives:** after Step 12, call a model through LiteLLM (its Test); within a minute the call shows under Traces, with prompt, answer, tokens, and time.
3. **The keys match:** Settings → API Keys lists the public key `LANGFUSE_PUBLIC_KEY` from `.env` (the same one LiteLLM uses).

## Step 12: LiteLLM (gateway)

**Check:** `litellm`, `litellm-postgres`.

### Clean reinstall

Removes LiteLLM as if it had never been installed. Skip it for a first install. **Every virtual key, team, budget, and usage record is lost** with the volume; every client (OpenHands, Open WebUI, the CI runner, developers) needs a new key afterwards. Each line asks first.
```bash
confirm "Stop and remove LiteLLM and its database?" && cd /opt/stacks/litellm && docker compose down; cd ~
confirm "Delete all virtual keys, budgets, and usage (volume litellm_pg_data)?" && docker volume rm litellm_pg_data
confirm "Delete /opt/stacks/litellm (.env with the master key, config.yaml with the models) and its Caddy file?" && rm -rf /opt/stacks/litellm /opt/stacks/caddy/conf.d/litellm.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the LiteLLM image (downloaded again on the next install)?" && docker image rm docker.litellm.ai/berriai/litellm:main-latest
```
The Presidio containers of [Data protection for hosted models](options/litellm-guardrails.md), if used, go with `docker compose down` too.

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -E '^litellm'
docker volume ls -q | grep -x litellm_pg_data
ls -d /opt/stacks/litellm /opt/stacks/caddy/conf.d/litellm.caddy 2>/dev/null
```

### Install

```bash
mkdir -p /opt/stacks/litellm
```

`/opt/stacks/litellm/.env`:
```env
SERVER_HOST=<from /opt/stacks/shared/.env>
LITELLM_DB_PASSWORD=CHANGE_ME
LITELLM_MASTER_KEY=sk-CHANGE_ME             # must start with "sk-"; this is the admin key and the API key clients use
# Admin UI sign-in through Dex (free for up to 5 users); uncomment with the lines in compose.yaml
# LITELLM_OIDC_SECRET=<LITELLM_OIDC_SECRET from /opt/stacks/dex/.env>
# LITELLM_PROXY_ADMIN_ID=<your LiteLLM user ID, shown after your first Dex sign-in>
# The same two lines as in /opt/stacks/langfuse/.env (with Infisical, from prod:/shared). Leave both out if Langfuse is not deployed.
LANGFUSE_PUBLIC_KEY=<LANGFUSE_PUBLIC_KEY from /opt/stacks/langfuse/.env>
LANGFUSE_SECRET_KEY=<LANGFUSE_SECRET_KEY from /opt/stacks/langfuse/.env>
# Optional hosted models (see the guide option: hosted models); uncomment the keys you use,
# and the matching models in config.yaml
# ANTHROPIC_API_KEY=<Claude API key from console.anthropic.com>
# OPENAI_API_KEY=<OpenAI API key from platform.openai.com>
# AZURE_OPENAI_API_KEY=<key of your Azure OpenAI resource>
# AZURE_OPENAI_API_BASE=https://<resource>.openai.azure.com
```

`/opt/stacks/litellm/config.yaml` lists the models clients can pick, by the name they use (`model_name`), and where each one runs (`model`, exactly as pulled into Ollama or set as `VLLM_MODEL`). The models are five from [Models](#models); pull them in Step 13. Names follow one pattern: family and version, then size, lowercase with dashes (`qwen3.8-27b`), never the runtime, so a name stays right when a model moves to another runtime.
- `local-model` is "whatever runs now": the same model (Gemma 4 12B) listed once per runtime. Only one runtime runs at a time (Step 13); LiteLLM tries the other entry when one cannot be reached, so `local-model` always answers. OpenHands and anything that should not care which model it gets use it.
- A model listed for both runtimes (`gemma4-12b`) works either way. A model listed only for Ollama (the other four) is still in the model list while vLLM runs, but calling it fails ("No deployments available") until you switch back to Ollama. After switching, recreate LiteLLM (`cd /opt/stacks/litellm && docker compose up -d --force-recreate litellm`) to skip its 5-minute wait before it tries the other runtime again.
- Ollama keeps one chat model in GPU memory: calling another unloads the first (a few seconds). Keep everyday use on `local-model`, and call the larger ones on purpose.
```yaml
model_list:
  # Whatever runs now: Gemma 4 12B on Ollama or vLLM
  - model_name: local-model
    litellm_params:
      model: openai/gemma4:12b
      api_base: http://ollama:11434/v1
      api_key: none
  - model_name: local-model
    litellm_params:
      model: openai/google/gemma-4-12B-it-qat-w4a16-ct   # VLLM_MODEL in /opt/stacks/llm-runtime/.env
      api_base: http://vllm:8000/v1
      api_key: none

  # Gemma 4 12B: everyday default, fits the GPU, reads images (Ollama or vLLM)
  - model_name: gemma4-12b
    litellm_params:
      model: openai/gemma4:12b
      api_base: http://ollama:11434/v1
      api_key: none
  - model_name: gemma4-12b
    litellm_params:
      model: openai/google/gemma-4-12B-it-qat-w4a16-ct
      api_base: http://vllm:8000/v1
      api_key: none

  # Qwen3.5 9B: fastest, most room for context (Ollama only)
  - model_name: qwen3.5-9b
    litellm_params:
      model: openai/qwen3.5:9b
      api_base: http://ollama:11434/v1
      api_key: none

  # Gemma 4 26B A4B: smarter than 12B, still fast, about 8k context (Ollama only)
  - model_name: gemma4-26b-a4b
    litellm_params:
      model: openai/gemma4:26b
      api_base: http://ollama:11434/v1
      api_key: none

  # Qwen3.6 35B A3B: harder reasoning and code, partly on the CPU (Ollama only)
  - model_name: qwen3.6-35b-a3b
    litellm_params:
      model: openai/qwen3.6:35b-a3b
      api_base: http://ollama:11434/v1
      api_key: none

  # Qwen3.8 27B: best quality, slow (about 3-8 words/s), for occasional hard questions (Ollama only)
  - model_name: qwen3.8-27b
    litellm_params:
      model: openai/qwen3.8:27b
      api_base: http://ollama:11434/v1
      api_key: none

  # Embeddings for Qdrant (Ollama only)
  - model_name: local-embed
    litellm_params:
      model: openai/qwen3-embedding:0.6b
      api_base: http://ollama:11434/v1
      api_key: none

  # Hosted models (see the guide option: hosted models): uncomment a block, and its key in .env.
  # They cost money per call; give each developer a virtual key with a budget.
  # On the company key (-shared): billed to the company; set budgets on virtual keys
  # Claude
  # - model_name: claude-sonnet-5.5-shared
  #   litellm_params:
  #     model: anthropic/claude-sonnet-5-5
  #     api_key: os.environ/ANTHROPIC_API_KEY
  # - model_name: claude-haiku-4.5-shared
  #   litellm_params:
  #     model: anthropic/claude-haiku-4-5-20251001
  #     api_key: os.environ/ANTHROPIC_API_KEY
  # OpenAI: the model ID as listed at platform.openai.com/docs/models
  # - model_name: <openai-model-name>-shared
  #   litellm_params:
  #     model: openai/<openai-model-id>
  #     api_key: os.environ/OPENAI_API_KEY
  # Azure OpenAI: the deployment name from your Azure OpenAI resource
  # - model_name: azure-gpt-shared
  #   litellm_params:
  #     model: azure/<deployment-name>
  #     api_base: os.environ/AZURE_OPENAI_API_BASE
  #     api_key: os.environ/AZURE_OPENAI_API_KEY
  #     api_version: "2024-06-01"
  # On the caller own key (no suffix): the developer pays with their own Claude or OpenAI key,
  # sent as api_key in each request; the call still goes through LiteLLM and into Langfuse.
  # Only api_key may come from the caller, never api_base (it could redirect the call).
  # - model_name: claude-sonnet-5.5
  #   litellm_params:
  #     model: anthropic/claude-sonnet-5-5
  #     configurable_clientside_auth_params: ["api_key"]
  # - model_name: <openai-model-name>
  #   litellm_params:
  #     model: openai/<openai-model-id>
  #     configurable_clientside_auth_params: ["api_key"]

router_settings:
  num_retries: 1
  allowed_fails: 1
  cooldown_time: 300

# Leave this block out if Langfuse is not deployed.
litellm_settings:
  success_callback: ["langfuse"]
  failure_callback: ["langfuse"]

# Admin UI sign-in with the master key: turn it off once you have your own admin account
# (see Authentication in the LiteLLM part of the guide)
# general_settings:
#   disable_env_credential_login: true
```
**Option:** [Adding or removing a model](options/litellm-models.md) — pull a model, list it under a name in `config.yaml`, remove one, or change the vLLM model.

**Option:** [Developer tools](options/developer-tools.md) — point VS Code, Claude Code, Claude Desktop, Codex, T3 Code, and Orca at LiteLLM (or, for testing, straight at Ollama or vLLM).

**Option:** [Data protection for hosted models](options/litellm-guardrails.md) — mask email addresses, phone numbers, and similar before a prompt goes to a hosted model (Presidio guardrail).

**Option:** [Hosted models](options/litellm-hosted-models.md) — add Azure OpenAI (or another hosted API) next to the local models, behind the same LiteLLM key.

**Paid feature, not used here:** Prometheus metrics (`callbacks: ["prometheus"]`) are an Enterprise feature. Without them Prometheus shows the `litellm` target as DOWN, which is harmless.

`/opt/stacks/litellm/compose.yaml`:
```yaml
services:
  litellm-postgres:
    image: postgres:17
    container_name: litellm-postgres
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: ${LITELLM_DB_PASSWORD}
      POSTGRES_DB: litellm
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 30s          # once healthy; fast checks only while starting:
      start_period: 60s
      start_interval: 3s
      timeout: 3s
      retries: 10
    volumes: [litellm_pg_data:/var/lib/postgresql/data]
    networks: [default]

  litellm:
    image: docker.litellm.ai/berriai/litellm:main-latest
    container_name: litellm
    restart: unless-stopped
    environment:
      DATABASE_URL: postgresql://postgres:${LITELLM_DB_PASSWORD}@litellm-postgres:5432/litellm
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      # Langfuse — plain HTTP over the edge network; Caddy HTTPS is only for browsers.
      # Harmless if Langfuse is not deployed and the callback block is left out of config.yaml.
      LANGFUSE_PUBLIC_KEY: ${LANGFUSE_PUBLIC_KEY:-}
      LANGFUSE_SECRET_KEY: ${LANGFUSE_SECRET_KEY:-}
      LANGFUSE_HOST: http://langfuse-web:3000
      # Admin UI sign-in through Dex (free for up to 5 users): uncomment with the lines in .env.
      # The browser goes through Caddy; LiteLLM calls Dex directly over edge.
      # PROXY_BASE_URL: https://${SERVER_HOST}:4000
      # GENERIC_CLIENT_ID: litellm
      # GENERIC_CLIENT_SECRET: ${LITELLM_OIDC_SECRET}
      # GENERIC_AUTHORIZATION_ENDPOINT: https://${SERVER_HOST}:5556/dex/auth
      # GENERIC_TOKEN_ENDPOINT: http://dex:5556/dex/token
      # GENERIC_USERINFO_ENDPOINT: http://dex:5556/dex/userinfo
      # GENERIC_SCOPE: openid email profile
      # GENERIC_USER_ID_ATTRIBUTE: sub
      # GENERIC_USER_EMAIL_ATTRIBUTE: email
      # PROXY_ADMIN_ID: ${LITELLM_PROXY_ADMIN_ID}   # uncomment after your first Dex sign-in
      # Hosted models: empty unless set in .env
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:-}
      OPENAI_API_KEY: ${OPENAI_API_KEY:-}
      AZURE_OPENAI_API_KEY: ${AZURE_OPENAI_API_KEY:-}
      AZURE_OPENAI_API_BASE: ${AZURE_OPENAI_API_BASE:-}
    volumes:
      - ./config.yaml:/app/config.yaml:ro
    command: ["--config", "/app/config.yaml"]
    depends_on:
      litellm-postgres: { condition: service_healthy }
    networks: [default, edge]

networks:
  default:
    driver_opts:
      com.docker.network.bridge.name: br-litellm
  edge:
    external: true

volumes:
  litellm_pg_data:
    external: true
```
```bash
docker volume create litellm_pg_data

cd /opt/stacks/litellm && docker compose up -d
```
```bash
cat > /opt/stacks/caddy/conf.d/litellm.caddy <<'EOF'
https://{$SERVER_HOST}:4000, https://{$SERVER_IP}:4000 {
	tls internal
	reverse_proxy litellm:4000
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
**Check the result.** Every line must match the table:
```bash
docker inspect -f '{{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}' litellm litellm-postgres
docker inspect -f '{{.Name}}  networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' litellm litellm-postgres
docker inspect -f '{{.Name}}  health={{.State.Health.Status}}' litellm-postgres
docker inspect litellm --format '{{range .Mounts}}mount {{.Destination}} <- {{.Source}}{{println}}{{end}}'
docker exec litellm sh -c 'echo "master key: ${#LITELLM_MASTER_KEY} characters, starts ${LITELLM_MASTER_KEY%"${LITELLM_MASTER_KEY#???}"}, Langfuse key: ${#LANGFUSE_PUBLIC_KEY} characters, Langfuse: $LANGFUSE_HOST"'
docker exec litellm getent hosts ollama langfuse-web
curl -sk https://${SERVER_HOST}:4000/health/liveliness; echo
curl -sv https://${SERVER_HOST}:4000/health/liveliness -o /dev/null 2>&1 | grep -E "issuer:|HTTP/"
```

| Line | Expected |
|---|---|
| state | both `running`, `restart=unless-stopped`; images `berriai/litellm:main-latest`, `postgres:17` |
| networks | `litellm`: `edge litellm_default`; `litellm-postgres`: `litellm_default` only |
| health | `healthy` |
| `mount` | `/app/config.yaml <- /opt/stacks/litellm/config.yaml` |
| environment | a master key starting `sk-`, a Langfuse key length (0 only without Langfuse), `Langfuse: http://langfuse-web:3000` |
| `getent` | an address for `ollama` (once Step 13 runs) and `langfuse-web` |
| `liveliness` | `"I'm alive!"` |
| `curl` | `issuer: CN=Caddy Local Authority …` and `HTTP/2 200` (or a `30x` redirect) |

**Verify:** `https://<SERVER_HOST>:4000/ui` loads the Admin UI. Calls to `local-model` fail until Step 13 is done.

### Authentication

LiteLLM keeps its own login. The first sign-in to the Admin UI uses `LITELLM_MASTER_KEY`; API clients use the master key or virtual keys made in the UI.

**Your own admin account.** After that first sign-in, the Admin UI warns "Environment-credential login is enabled": anyone with the master key can sign in as admin. Give each admin their own account, then turn the master-key sign-in off:
1. In the Admin UI, **Internal Users** → **+ Invite User**: your email, role **Admin** (Proxy Admin). Copy the invitation link it shows, open it (a private window works), and set a password.
2. Sign out and sign in with that email and password. Go on only when this works; otherwise step 3 locks you out of the UI.
3. In `/opt/stacks/litellm/config.yaml`, uncomment the `general_settings:` block at the end (`disable_env_credential_login: true`), then `cd /opt/stacks/litellm && docker compose up -d --force-recreate litellm`.
4. Check: the warning is gone, your own account signs in, and the master key no longer signs in to the UI. The master key still works for API calls (such as creating virtual keys); test one to be sure.

Add other admins the same way, each with their own account. Locked out: comment the block again and recreate LiteLLM; the master-key sign-in works again.

**Dex** (free for up to 5 users, 💲 beyond): the Admin UI can sign in through Dex. LiteLLM single sign-on is free for up to 5 users since v1.76.0; more need a LiteLLM Enterprise license. It covers the Admin UI only (the people who manage keys and models); API clients keep using virtual keys. To turn it on:
1. Dex installed from an older version of this guide: add `LITELLM_OIDC_SECRET` (`openssl rand -hex 32`) to `/opt/stacks/dex/.env`, the `litellm` client to `config.yaml`, and the `LITELLM_OIDC_SECRET` line to its `compose.yaml`, as shown in Step 6; then `cd /opt/stacks/dex && docker compose up -d --force-recreate dex`.
2. In `/opt/stacks/litellm/.env`, uncomment `LITELLM_OIDC_SECRET` and set it to the value from `/opt/stacks/dex/.env` (with Infisical, the same value in `prod:/dex` and `prod:/litellm`); check that `SERVER_HOST` is there.
3. In `/opt/stacks/litellm/compose.yaml`, uncomment the Dex lines except `PROXY_ADMIN_ID`, then `cd /opt/stacks/litellm && docker compose up -d --force-recreate litellm`.
4. Open `https://<SERVER_HOST>:4000/ui`, sign in through Dex, and copy your user ID from the UI (Internal Users). Put it in `LITELLM_PROXY_ADMIN_ID` in `.env`, uncomment `PROXY_ADMIN_ID` in `compose.yaml`, and recreate LiteLLM: you are now admin. Others who sign in through Dex join as internal users; promote them under Internal Users.
5. Then turn off the master-key sign-in as in **Your own admin account** (step 3 there).

**Google Account** and **Azure**: through Dex's Google and Microsoft connectors, with the same 5-user limit. LiteLLM's own Google and Microsoft sign-in counts the same way.

### Test

1. **Admin UI:** `https://<SERVER_HOST>:4000/ui` signs in (your own admin account, or Dex); **Models** lists the names from `config.yaml`.
2. **A model call** (after Step 13): the `curl` under "Verify through LiteLLM" in Step 13 returns an answer from `local-model`.
3. **A virtual key works:** create a test key (Virtual Keys → Create, models `local-model`), call `local-model` with it: an answer; delete the key, call again: `401`.
4. **Tracing:** the call from 2 shows in Langfuse under Traces within a minute.

## Step 13: Ollama / vLLM runtime

Ollama and vLLM share the GPU, so only one runs at a time.

**Check:** `ollama`, `vllm`.

### Clean reinstall

Removes Ollama and vLLM as if they had never been installed. Skip it for a first install. LiteLLM, OpenHands, and Open WebUI get no answers from local models until it is back. The model volumes hold large downloads; keep them for a reinstall unless you want the disk space back. Each line asks first.
```bash
confirm "Stop and remove Ollama and vLLM?" && cd /opt/stacks/llm-runtime && docker compose --profile "*" down; cd ~
confirm "Delete every downloaded model (volumes ollama_data, vllm_hf_cache; tens of GB to download again)?" && docker volume rm ollama_data vllm_hf_cache
confirm "Delete /opt/stacks/llm-runtime (.env, compose.yaml, the switch-llm.sh link)?" && rm -rf /opt/stacks/llm-runtime
confirm "Delete the Ollama and vLLM images (about 14 GB together)?" && docker image rm ollama/ollama:latest vllm/vllm-openai:latest
```
Revoke the Hugging Face token (huggingface.co → Settings → Access Tokens) if vLLM is gone for good.

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -E '^(ollama|vllm)$'
docker volume ls -q | grep -E '^(ollama_data|vllm_hf_cache)$'
ls -d /opt/stacks/llm-runtime 2>/dev/null
```

### Install

```bash
mkdir -p /opt/stacks/llm-runtime
```

`/opt/stacks/llm-runtime/.env`:
```env
VLLM_MODEL=google/gemma-4-12B-it-qat-w4a16-ct   # Hugging Face model ID; must match the vLLM entries in LiteLLM config.yaml and fit the GPU
VLLM_MAX_MODEL_LEN=16384                 # longest context vLLM reserves memory for; see the Models table
HF_TOKEN=                                # Hugging Face read token, for models that need their license accepted (Gemma does)
OLLAMA_CONTEXT_LENGTH=32768              # tokens Ollama gives each model; its default (4k on GPUs under 24 GB) silently cuts off agent tools such as Claude Code and Codex
```

**Sizing a model to your GPU** (`nvidia-smi --query-gpu=name,memory.total --format=csv`):
- Weights: about 2 GB per billion parameters unquantized, about 0.6 GB per billion at 4-bit (AWQ/GPTQ, Ollama's `q4` tags).
- Keep 20–30% of VRAM free for context.
- Rough fits: 16 GB → 14B 4-bit or 7B unquantized; 24 GB → up to ~32B 4-bit; 48 GB+ → 70B 4-bit.
- Suggested Qwen models, their sizes, and what happens with a 30B model on a 16 GB GPU: [Models](#models).
- vLLM takes 90% of VRAM by default, which is why Ollama and vLLM can't run together.

`/opt/stacks/llm-runtime/compose.yaml`:
```yaml
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    profiles: ["ollama"]
    restart: unless-stopped
    devices:
      - nvidia.com/gpu=all
    environment:
      OLLAMA_CONTEXT_LENGTH: ${OLLAMA_CONTEXT_LENGTH:-32768}
    volumes: [ollama_data:/root/.ollama]
    networks: [edge]
    # OPTIONAL — direct host access for testing, bypasses LiteLLM entirely.
    # Uncomment to let anything on the VPN hit Ollama directly (no API key,
    # no budget/rate limiting — LiteLLM controls do not apply here).
    # Comment back out when done testing.
    # ports:
    #   - "11434:11434"

  vllm:
    image: vllm/vllm-openai:latest
    container_name: vllm
    profiles: ["vllm"]
    restart: unless-stopped
    devices:
      - nvidia.com/gpu=all
    ipc: host                               # vLLM needs large shared memory for its worker processes
    environment:
      HF_TOKEN: ${HF_TOKEN:-}
    command: ["--model", "${VLLM_MODEL}", "--max-model-len", "${VLLM_MAX_MODEL_LEN:-16384}"]
    volumes: [vllm_hf_cache:/root/.cache/huggingface]
    networks: [edge]
    # OPTIONAL — same trade-off as Ollama above: direct, unauthenticated
    # access for testing. Comment back out when done.
    # ports:
    #   - "8000:8000"

networks:
  edge:
    external: true

volumes:
  ollama_data:
    external: true
  vllm_hf_cache:
    external: true
```
Neither runtime has a host port or a Caddy route. LiteLLM and other containers reach them over `edge`.

Link `switch-llm.sh` from `~/ai-server` into the stack folder ([Helper scripts](options/helper-scripts.md)), then start Ollama:
```bash
docker volume create ollama_data
docker volume create vllm_hf_cache

ln -sf ~/ai-server/switch-llm.sh /opt/stacks/llm-runtime/switch-llm.sh
cd /opt/stacks/llm-runtime
./switch-llm.sh ollama    # or: vllm / status / stop
```
**The Ollama models:** pull the ones named in LiteLLM's config:
```bash
docker exec ollama ollama pull gemma4:12b
docker exec ollama ollama pull qwen3-embedding:0.6b
# The other models listed in LiteLLM config.yaml (about 64 GB in total; pull only the ones you try)
docker exec ollama ollama pull qwen3.5:9b
docker exec ollama ollama pull gemma4:26b
docker exec ollama ollama pull qwen3.6:35b-a3b
docker exec ollama ollama pull qwen3.8:27b
```
**The vLLM model** has no pull command: vLLM downloads `VLLM_MODEL` from Hugging Face on its first start (about 10 GB for Gemma 4 12B) into the `vllm_hf_cache` volume, and reuses it after that. Gemma needs its license accepted first: sign in at huggingface.co, open `https://huggingface.co/google/gemma-4-12B-it-qat-w4a16-ct`, accept the license, create a read token (Settings → Access Tokens), and put it in `HF_TOKEN=` in `/opt/stacks/llm-runtime/.env`. Then start vLLM once to download and test it, and switch back to Ollama:
```bash
cd /opt/stacks/llm-runtime
./switch-llm.sh vllm
docker logs -f vllm      # wait for "Application startup complete", then Ctrl+C
./switch-llm.sh ollama
```
A `401` or `403` in the log means the license or token is missing; `CUDA out of memory` means the model or `VLLM_MAX_MODEL_LEN` is too large for the GPU. The next `./switch-llm.sh vllm` starts in about a minute, without downloading again.

To add, remove, or change a model later: [Adding or removing a model](options/litellm-models.md).

**Check the result.** Every line must match the table:
```bash
/opt/stacks/llm-runtime/switch-llm.sh status
docker inspect -f '{{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}  networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' ollama
docker inspect ollama --format '{{range .Mounts}}mount {{.Destination}} <- {{.Name}}{{println}}{{end}}  devices={{range .HostConfig.Devices}}{{.PathOnHost}} {{end}}'
docker exec ollama nvidia-smi -L
docker exec ollama sh -c 'echo "context: $OLLAMA_CONTEXT_LENGTH"'
docker exec ollama ollama list
docker exec litellm getent hosts ollama
```

| Line | Expected |
|---|---|
| `status` | `Ollama: Up …`, `vLLM: not running` (only one runs at a time) |
| `ollama` | `state=running  restart=unless-stopped`, image `ollama/ollama:latest`, `networks=edge` |
| `mount` | `/root/.ollama <- ollama_data`, and `devices=nvidia.com/gpu=all` |
| `nvidia-smi -L` | your GPU, e.g. `GPU 0: NVIDIA …`: the container sees it |
| `context` | `32768` (or the value in `.env`) |
| `ollama list` | every model named in LiteLLM's `config.yaml` that you pulled, plus `qwen3-embedding:0.6b` |
| `getent` | an address for `ollama`: LiteLLM can reach it |

With vLLM running instead (`switch-llm.sh vllm`): `vllm` is `running` with `/root/.cache/huggingface <- vllm_hf_cache`, `docker exec vllm nvidia-smi -L` shows the GPU, and `docker logs vllm 2>&1 | grep -m1 "Application startup complete"` prints a line.

**Verify through LiteLLM:**
```bash
curl -k https://${SERVER_HOST}:4000/v1/chat/completions \
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>" -H "Content-Type: application/json" \
  -d '{"model":"local-model","messages":[{"role":"user","content":"Say OK"}]}'
```

**Option:** [Direct test ports](options/llm-direct-test-ports.md) — reach Ollama or vLLM from outside Docker for testing, bypassing LiteLLM.

### Authentication

Ollama and vLLM have no login and no browser UI. They stay internal on `edge`; people and tools reach them through LiteLLM and its keys.

### Test

1. **Through LiteLLM:** the `curl` above returns an answer from `local-model`.
2. **On the GPU:** right after that call, `docker exec ollama ollama ps` lists the model with `100% GPU` (a `CPU/GPU` split means it does not fit; see [Models](#models)).
3. **Embeddings:** `docker exec ollama ollama run qwen3-embedding:0.6b "test" >/dev/null && echo OK` prints `OK`.
4. **The switch:** `./switch-llm.sh vllm`, wait for `Application startup complete` (`docker logs -f vllm`), repeat test 1 (`local-model` now answers from vLLM), then `./switch-llm.sh ollama`.

## Step 14: Qdrant (vector DB)

Adds semantic search next to Sourcebot's keyword search. Ollama creates the embeddings (`qwen3-embedding:0.6b`); Qdrant stores and searches them on CPU.

**Check:** `qdrant`.

### Clean reinstall

Removes Qdrant as if it had never been installed. Skip it for a first install. **Every collection is lost** with the volume, including the documents Open WebUI stored; they have to be uploaded and indexed again. Each line asks first.
```bash
confirm "Stop and remove the Qdrant container?" && cd /opt/stacks/qdrant && docker compose down; cd ~
confirm "Delete every collection (volume qdrant_data)?" && docker volume rm qdrant_data
confirm "Delete /opt/stacks/qdrant and its Caddy file?" && rm -rf /opt/stacks/qdrant /opt/stacks/caddy/conf.d/qdrant.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the Qdrant image (downloaded again on the next install)?" && docker image rm qdrant/qdrant:latest
```

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -x qdrant
docker volume ls -q | grep -x qdrant_data
ls -d /opt/stacks/qdrant /opt/stacks/caddy/conf.d/qdrant.caddy 2>/dev/null
```

### Install

```bash
mkdir -p /opt/stacks/qdrant
```

`/opt/stacks/qdrant/compose.yaml`:
```yaml
services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    volumes: [qdrant_data:/qdrant/storage]
    networks: [edge]
    # gRPC (6334) is a raw binary protocol like the Neo4j bolt port, so Caddy
    # does not front it. Only exposed if something outside Docker needs it
    # directly; uncomment to test:
    # ports:
    #   - "6334:6334"

networks:
  edge:
    external: true

volumes:
  qdrant_data:
    external: true
```
```bash
docker volume create qdrant_data

cd /opt/stacks/qdrant && docker compose up -d
```
```bash
cat > /opt/stacks/caddy/conf.d/qdrant.caddy <<'EOF'
https://{$SERVER_HOST}:6333 {
	tls internal
	import sso qdrant:6333
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
**Check the result.** Every line must match the table:
```bash
docker inspect qdrant --format 'name={{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}'
docker inspect qdrant --format 'networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}  ports={{range $p, $b := .NetworkSettings.Ports}}{{if $b}}{{$p}} {{end}}{{end}}'
docker inspect qdrant --format '{{range .Mounts}}mount {{.Destination}} <- {{.Name}}{{println}}{{end}}'
docker run --rm --network edge curlimages/curl -s http://qdrant:6333/healthz; echo
curl -skI https://${SERVER_HOST}:6333/dashboard | head -1
curl -sv https://${SERVER_HOST}:6333 -o /dev/null 2>&1 | grep -E "issuer:"
```

| Line | Expected |
|---|---|
| `name=` | `/qdrant  state=running  restart=unless-stopped`, image `qdrant/qdrant:latest` |
| `networks=` | `edge`, and `ports=` empty (Caddy fronts it; gRPC 6334 stays internal) |
| `mount` | `/qdrant/storage <- qdrant_data` |
| `healthz` | `healthz check passed` |
| `curl -skI` | `HTTP/2 302`: the sign-in gate sends the browser to Dex first |
| `issuer` | `CN=Caddy Local Authority …` |

**Verify** from inside Docker (the gate only applies to traffic through Caddy):
```bash
docker run --rm --network edge curlimages/curl -s http://qdrant:6333/collections
```
A fresh install returns `{"result":{"collections":[]},...}`. In a browser, `https://<SERVER_HOST>:6333/dashboard` shows the Dex login first, then the dashboard.

### Authentication

Qdrant has no login of its own.

**Dex** (free): the dashboard and API sit behind the sign-in gate from Step 6. The gate is for people with a browser. Scripts and agents on other machines can't pass it; run them in a container on `edge` (they use `http://qdrant:6333` directly), or see [Without the sign-in gate](options/without-sign-in-gate.md#qdrant-with-an-api-key) for Qdrant with an API key instead.

**Google Account** (free) and **Azure** (free): through Dex. The gate offers whatever Dex offers, so turning on Google or Microsoft in Dex covers this app too. oauth2-proxy could also use Google or Azure directly (free), but then every gated app skips Dex.

### Usage

**Not included:** indexing. Filling Qdrant needs your own script that chunks files, gets embeddings from Ollama (`/api/embeddings`, or LiteLLM's `local-embed`), and upserts them (`PUT /collections/<name>/points`).

### Test

1. **The API, from inside Docker:** the `collections` call above returns a list (empty on a fresh install).
2. **Write and read a point** (a throwaway collection):
   ```bash
   docker run --rm --network edge curlimages/curl -s -X PUT http://qdrant:6333/collections/test -H "Content-Type: application/json" -d '{"vectors":{"size":3,"distance":"Cosine"}}'
   docker run --rm --network edge curlimages/curl -s -X PUT http://qdrant:6333/collections/test/points -H "Content-Type: application/json" -d '{"points":[{"id":1,"vector":[0.1,0.2,0.3]}]}'
   docker run --rm --network edge curlimages/curl -s -X POST http://qdrant:6333/collections/test/points/search -H "Content-Type: application/json" -d '{"vector":[0.1,0.2,0.3],"limit":1}'
   confirm "Delete the test collection?" && docker run --rm --network edge curlimages/curl -s -X DELETE http://qdrant:6333/collections/test
   ```
   The search returns point `1` with a score near `1.0`.
3. **The dashboard:** `https://<SERVER_HOST>:6333/dashboard` asks for the Dex sign-in, then shows the collections (after Step 17, Open WebUI's appear once a document is uploaded).

## Step 15: Neo4j + Memgraph

Neither uses the GPU, so both run together.

**Check:** `neo4j`, `memgraph`.

### Clean reinstall

Removes Neo4j and Memgraph as if they had never been installed. Skip it for a first install. **Every graph is lost** with the volumes. Neo4j sets `NEO4J_PASSWORD` only on its first start with an empty volume, so after a reinstall the password in `.env` applies again. Each line asks first.
```bash
confirm "Stop and remove Neo4j and Memgraph?" && cd /opt/stacks/graphdb && docker compose --profile "*" down; cd ~
confirm "Delete every graph (volumes neo4j_data, neo4j_logs, memgraph_data)?" && docker volume rm neo4j_data neo4j_logs memgraph_data
confirm "Delete /opt/stacks/graphdb (.env, compose.yaml, the graphdb.sh link) and the Caddy files neo4j.caddy, memgraph.caddy?" && rm -rf /opt/stacks/graphdb /opt/stacks/caddy/conf.d/neo4j.caddy /opt/stacks/caddy/conf.d/memgraph.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the Neo4j and Memgraph images?" && docker image rm neo4j:5 memgraph/memgraph-platform:latest
```

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -E '^(neo4j|memgraph)$'
docker volume ls -q | grep -E '^(neo4j_data|neo4j_logs|memgraph_data)$'
ls -d /opt/stacks/graphdb 2>/dev/null
```

### Install

```bash
mkdir -p /opt/stacks/graphdb
```

`/opt/stacks/graphdb/.env`:
```env
NEO4J_PASSWORD=CHANGE_ME        # at least 8 characters
```

`/opt/stacks/graphdb/compose.yaml`:
```yaml
services:
  neo4j:
    image: neo4j:5
    container_name: neo4j
    profiles: ["neo4j"]
    restart: unless-stopped
    ports:
      - "7687:7687"   # bolt
    environment:
      NEO4J_AUTH: neo4j/${NEO4J_PASSWORD}
    volumes:
      - neo4j_data:/data
      - neo4j_logs:/logs   # the image declares both; named, so no anonymous volume appears
    networks: [edge]

  memgraph:
    image: memgraph/memgraph-platform:latest
    container_name: memgraph
    profiles: ["memgraph"]
    restart: unless-stopped
    ports:
      - "7688:7687"   # bolt, remapped off the Neo4j port 7687
    volumes: [memgraph_data:/var/lib/memgraph]
    networks: [edge]

networks:
  edge:
    external: true

volumes:
  neo4j_data:
    external: true
  neo4j_logs:
    external: true
  memgraph_data:
    external: true
```
The web UIs (Neo4j Browser, Memgraph Lab) have no host ports; Caddy fronts them. The bolt ports are published directly because bolt isn't HTTP.

Link `graphdb.sh` from `~/ai-server` into the stack folder ([Helper scripts](options/helper-scripts.md)), then start both:
```bash
docker volume create neo4j_data
docker volume create neo4j_logs
docker volume create memgraph_data

ln -sf ~/ai-server/graphdb.sh /opt/stacks/graphdb/graphdb.sh
cd /opt/stacks/graphdb
./graphdb.sh both       # default — starts and keeps both running
./graphdb.sh status     # or: neo4j / memgraph / stop, if you ever want to isolate one
```
```bash
cat > /opt/stacks/caddy/conf.d/neo4j.caddy <<'EOF'
# Neo4j Browser runs in the browser and opens its database connection as a WebSocket to this
# same address (bolt+s://SERVER_HOST:7474); those go to the bolt port, the rest to the web UI.
# Written out instead of import sso, which allows only one target; same sign-in gate.
https://{$SERVER_HOST}:7474 {
	tls internal
	handle /oauth2/* {
		reverse_proxy oauth2-proxy:4180
	}
	handle {
		forward_auth oauth2-proxy:4180 {
			uri /oauth2/auth
			copy_headers X-Auth-Request-User X-Auth-Request-Email
			@signin status 401
			handle_response @signin {
				redir * /oauth2/sign_in?rd={scheme}://{hostport}{uri}
			}
		}
		@bolt {
			header Connection *Upgrade*
			header Upgrade websocket
		}
		reverse_proxy @bolt neo4j:7687
		reverse_proxy neo4j:7474
	}
}
EOF
cat > /opt/stacks/caddy/conf.d/memgraph.caddy <<'EOF'
https://{$SERVER_HOST}:9490 {
	tls internal
	import sso memgraph:3000
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
**Check the result.** Every line must match the table:
```bash
/opt/stacks/graphdb/graphdb.sh status
docker inspect -f '{{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}  networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' neo4j memgraph
docker inspect -f '{{.Name}}{{range .Mounts}}  {{.Destination}} <- {{.Name}}{{end}}' neo4j memgraph
docker port neo4j 7687; docker port memgraph 7687
docker exec neo4j cypher-shell -u neo4j -p "$(grep ^NEO4J_PASSWORD= /opt/stacks/graphdb/.env | cut -d= -f2-)" "RETURN 1 AS ok"
curl -skI https://${SERVER_HOST}:7474 | head -1; curl -skI https://${SERVER_HOST}:9490 | head -1
```

| Line | Expected |
|---|---|
| `status` | both running |
| state | both `running`, `restart=unless-stopped`, images `neo4j:5` and `memgraph/memgraph-platform:latest`, `networks=edge` |
| mounts | `neo4j`: `/data <- neo4j_data`, `/logs <- neo4j_logs`; `memgraph`: `/var/lib/memgraph <- memgraph_data`. A long hash instead of a name is an anonymous volume: give that path a named volume, as for Neo4j's logs |
| `docker port` | `0.0.0.0:7687` (Neo4j) and `0.0.0.0:7688` (Memgraph): the bolt ports for drivers |
| `cypher-shell` | `ok` / `1`: the password in `.env` works |
| `curl -skI` | `HTTP/2 302` twice: the sign-in gate is in front of both web UIs |

**Verify:** `https://<SERVER_HOST>:7474` and `https://<SERVER_HOST>:9490` show the Dex login first (or pass straight through if you already signed in), then Neo4j Browser and Memgraph Lab. In Neo4j Browser's connect form, set **Connect URL** to `bolt+s://<SERVER_HOST>:7474` (not the suggested `neo4j://localhost:7687`), user `neo4j`, password `NEO4J_PASSWORD`. A browser page cannot open the unencrypted bolt port 7687, and `neo4j://` asks the server for addresses that point to `localhost`; the `bolt+s` connection goes through Caddy, encrypted and behind the same sign-in. Drivers connect to `<SERVER_HOST>:7687` (Neo4j) and `<SERVER_HOST>:7688` (Memgraph).

### Authentication

Neo4j keeps its own database login (`neo4j` / `NEO4J_PASSWORD`), asked in Neo4j Browser and by drivers. Memgraph Lab has no login of its own.

**Dex** (free): both web UIs sit behind the sign-in gate from Step 6, in front of the database login. The bolt ports are not gated. No Dex? See [Without the sign-in gate](options/without-sign-in-gate.md).

**Google Account** (free) and **Azure** (free): through Dex. The gate offers whatever Dex offers, so turning on Google or Microsoft in Dex covers both web UIs too. oauth2-proxy could also use Google or Azure directly (free), but then every gated app skips Dex.

### Test

1. **Neo4j Browser:** `https://<SERVER_HOST>:7474`, the Dex sign-in, then connect with `bolt+s://<SERVER_HOST>:7474`, user `neo4j`; run `RETURN 1` and get `1`.
2. **Memgraph Lab:** `https://<SERVER_HOST>:9490`, the Dex sign-in, connect; run `RETURN 1;` and get `1`.
3. **A driver from a PC** (the bolt ports): e.g. Python `neo4j` package, `GraphDatabase.driver("bolt://<SERVER_HOST>:7687", auth=("neo4j", "<password>"))` runs `RETURN 1`; the same with port `7688` for Memgraph.
4. **Data survives a restart:** `CREATE (:Test {name: "x"})` in Neo4j Browser, `./graphdb.sh stop`, `./graphdb.sh both`, `MATCH (n:Test) RETURN n` still finds it; delete it with `MATCH (n:Test) DELETE n`.

## Step 16: OpenHands (agent)

An AI coding agent: it plans a task, writes and runs code in a sandbox, and uses models through LiteLLM. It mounts the host's Docker socket to start a sandbox container per conversation, so it can control every container on this host; keep it internal-only.

**Check:** `openhands` (and, while a conversation runs, an `oh-agent-server-…` sandbox).

### Clean reinstall

Removes OpenHands as if it had never been installed. Skip it for a first install. Each line asks first; the volume line deletes all OpenHands settings and conversations.
```bash
confirm "Stop and remove the OpenHands container?" && cd /opt/stacks/openhands && docker compose down; cd ~
confirm "Remove all OpenHands sandbox containers?" && docker ps -aq --filter name=oh-agent-server | xargs -r docker rm -f
confirm "Delete OpenHands settings and conversations (volume openhands_state)?" && docker volume rm openhands_state
confirm "Delete the stack folder /opt/stacks/openhands?" && rm -rf /opt/stacks/openhands
confirm "Delete the Caddy file of an older install (openhands.caddy)?" && rm -f /opt/stacks/caddy/conf.d/openhands.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
Optional, to download everything again on the next install (the OpenHands and sandbox images, several GB):
```bash
docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -i openhands
confirm "Delete the OpenHands and sandbox images?" && docker image ls -q --filter reference='*/openhands/*' | xargs -r docker image rm
```
Outside the server, if you are not reinstalling: revoke its LiteLLM key (Admin UI → Virtual Keys → `openhands` → Delete) and delete the Infisical folder `prod:/openhands`.

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -E '^openhands$|^oh-agent-server'
docker volume ls -q | grep -i openhands
ls -d /opt/stacks/openhands 2>/dev/null
```

### Install

1. **A LiteLLM key for OpenHands.** OpenHands gets its own LiteLLM virtual key, not the master key, so it can be limited to some models and revoked on its own. Create it with the master key, or in the LiteLLM Admin UI (Virtual Keys → Create New Key, alias `openhands`):
   ```bash
   curl -k https://${SERVER_HOST}:4000/key/generate \
     -H "Authorization: Bearer <LITELLM_MASTER_KEY>" -H "Content-Type: application/json" \
     -d '{"key_alias":"openhands","models":["local-model"]}'
   ```
   Copy the `"key"` value from the answer (it starts with `sk-` and is shown only once). Add more model names to `models` to let OpenHands use them, or leave `models` out for all.

2. **The stack folder and its files:**
   ```bash
   mkdir -p /opt/stacks/openhands
   ```
   `/opt/stacks/openhands/.env` (with Infisical, the folder `prod:/openhands`):
   ```env
   SERVER_IP=<from /opt/stacks/shared/.env>
   LLM_API_KEY=<the openhands virtual key from LiteLLM>
   ```
   `/opt/stacks/openhands/compose.yaml`:
   ```yaml
   services:
     openhands:
       image: docker.openhands.dev/openhands/openhands:latest
       container_name: openhands
       restart: unless-stopped
       environment:
         LLM_BASE_URL: http://litellm:4000
         LLM_API_KEY: ${LLM_API_KEY}
         LLM_MODEL: litellm_proxy/local-model   # litellm_proxy/ + a model_name from /opt/stacks/litellm/config.yaml
         OH_PERSISTENCE_DIR: /.openhands
         RUNTIME: docker
         # The browser connects straight to each sandbox, on a random host port: tell it the server IP
         OH_SANDBOX_CONTAINER_URL_PATTERN: http://${SERVER_IP}:{port}
         OH_WEB_URL: http://${SERVER_IP}:3000
       # Plain HTTP on its own port, not through Caddy (see the guide: OpenHands)
       ports:
         - "3000:3000"
       volumes:
         - /var/run/docker.sock:/var/run/docker.sock
         - openhands_state:/.openhands
       # OpenHands runs each task in a sandbox container it starts on the host Docker
       # (oh-agent-server-...), and reaches it through the host: needs this name
       extra_hosts:
         - "host.docker.internal:host-gateway"
       networks: [edge]

   networks:
     edge:
       external: true

   volumes:
     openhands_state:
       external: true
   ```

3. **Start it:**
   ```bash
   docker volume create openhands_state
   cd /opt/stacks/openhands && docker compose up -d
   ```

4. **Check the result.** Every line must match the table; a difference points at the file to fix (then `docker compose up -d --force-recreate` and check again):
   ```bash
   docker inspect openhands --format 'name={{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}'
   docker inspect openhands --format 'networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'
   docker inspect openhands --format '{{range .Mounts}}mount {{.Destination}} <- {{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}}{{println}}{{end}}'
   docker inspect openhands --format 'ports={{range $p, $b := .NetworkSettings.Ports}}{{$p}}->{{range $b}}{{.HostPort}}{{end}} {{end}} extra_hosts={{.HostConfig.ExtraHosts}}'
   docker volume inspect openhands_state --format 'volume={{.Name}}  driver={{.Driver}}'
   docker exec openhands sh -c 'echo "LLM_API_KEY: ${#LLM_API_KEY} characters"; echo "sandbox URL: $OH_SANDBOX_CONTAINER_URL_PATTERN"; echo "web URL: $OH_WEB_URL"'
   docker exec openhands getent hosts litellm host.docker.internal
   curl -s -o /dev/null -w "from the server: %{http_code}\n" http://localhost:3000
   curl -s -o /dev/null -w "by IP: %{http_code}\n" http://${SERVER_IP}:3000
   ```

   | Line | Expected |
   |---|---|
   | `name=` | `/openhands  state=running  restart=unless-stopped`, image `docker.openhands.dev/openhands/openhands:latest` |
   | `networks=` | `edge` (only) |
   | `mount` | `/.openhands <- openhands_state` and `/var/run/docker.sock <- /var/run/docker.sock`; no long hash-named volume |
   | `ports=` | `3000/tcp->3000`, `extra_hosts=[host.docker.internal:host-gateway]` |
   | `volume=` | `openhands_state  driver=local` |
   | `LLM_API_KEY`, URLs | `25 characters` (a LiteLLM key; only its length is shown), sandbox URL `http://<SERVER_IP>:{port}`, web URL `http://<SERVER_IP>:3000` with your server IP filled in |
   | `getent` | an address for `litellm` (on `edge`) and one for `host.docker.internal` (the host) |
   | `from the server`, `by IP` | `200` both; also open `http://<SERVER_IP>:3000` from your PC |

   OpenHands has no certificate to check: it is plain HTTP by design (see below).

5. **Point OpenHands at LiteLLM.** Open `http://<SERVER_IP>:3000` (`http`, by IP; see below). A dialog "AI Provider Configuration" opens; a "Settings not found" message at first is normal (nothing is saved yet). Turn on **Advanced**, fill in, and **Save**:

   | Field | Value |
   |---|---|
   | Custom Model | `litellm_proxy/local-model` |
   | Base URL | `http://litellm:4000` |
   | API Key | the `openhands` virtual key |

   These settings are stored by OpenHands and take precedence over the `LLM_*` lines in `compose.yaml`; after a key change, update them here too. Reload the page: the values must still be there.

**Why plain HTTP by IP, without Caddy:** OpenHands runs each task in a sandbox container (`oh-agent-server-…`) that Docker publishes on a random host port, and the browser connects to that port directly (`/sockets/events/…`). Caddy cannot front ports it does not know in advance, and an HTTPS page may not open an unencrypted connection, so OpenHands answers on its own port 3000 over plain HTTP, like its sandboxes; it is the one browser app outside Caddy. Open it by **IP address**, not by `SERVER_HOST`: apps on `https://<SERVER_HOST>` (Outline) tell browsers to use only HTTPS for that name (HSTS), on every port, so `http://<SERVER_HOST>:3000` is turned into `https://` and fails with `ERR_SSL_PROTOCOL_ERROR`. HSTS never applies to an IP address. Sandbox ports are open on the network while a task runs, each protected by its own session key.

**Verify:** `http://<SERVER_IP>:3000` loads with the settings saved; the full check is under [Test](#test).

### Authentication

OpenHands has no login in its self-hosted version: anyone who can reach port 3000 can use it, and through it the Docker socket. Keep the port reachable only from your own network.

**Dex**, **Google Account**, and **Azure**: not set up here. They would need the sign-in gate, which works only through Caddy, and OpenHands runs outside Caddy.

### Connecting tools (MCP)

These are settings in the clients, not new containers. OpenHands' MCP settings live in its Settings UI (Settings → MCP) and change between versions; check its docs for the exact fields.

**In OpenHands, MCP servers run from the sandbox**, which sits on Docker's default network: it cannot reach names on `edge` (such as `sourcebot`), has no Docker inside it, and does not know `SERVER_HOST`. So:
- **GitHub:** use GitHub's hosted MCP server: URL `https://api.githubcopilot.com/mcp/`, header `Authorization: Bearer <token>` with a fine-grained, repo-scoped token.
- **Sourcebot:** not reachable from OpenHands in this setup; use it from developer machines (below).
- An "MCP Connection Failure" message with no MCP server configured comes from OpenHands' own built-in MCP and is a known OpenHands issue; tasks still run.

**On developer machines** (Claude Code, Codex): Sourcebot at `https://<SERVER_HOST>:9460/api/mcp`. GitHub's MCP server runs locally per client, each with its own token:

Codex CLI; point its models at LiteLLM as in [Developer tools](options/developer-tools.md):
```bash
export GITHUB_PERSONAL_ACCESS_TOKEN=<token>
codex mcp add github -- docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN ghcr.io/github/github-mcp-server
```

Claude Code, in `.mcp.json` or via `claude mcp add`:
```json
{
  "mcpServers": {
    "github": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "-e", "GITHUB_PERSONAL_ACCESS_TOKEN", "ghcr.io/github/github-mcp-server"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "<token>" }
    }
  }
}
```

**Qdrant and Neo4j/Memgraph (not wired by this guide):** agents have no built-in integration for these.
- **Qdrant search** takes two calls: embed the query with Ollama (`POST http://ollama:11434/api/embeddings`, same model used for indexing), then search Qdrant (`POST http://qdrant:6333/collections/<name>/points/search`).
- **Graph queries** need Cypher over bolt. Community Neo4j MCP servers exist, and Memgraph speaks the same protocol.

Expose either to the agent as an MCP server or an HTTP tool.

**Other developer tools** (OpenCode, etc.) aren't hosted here; point them at LiteLLM: `https://<SERVER_HOST>:4000`.

### Test

Three checks, each one layer further. If one fails, [Testing OpenHands](options/openhands-test.md) has the error table.

1. **Key, network, and model**, from inside the OpenHands container (prints `OK: …`):
   ```bash
   docker exec openhands python3 -c "
   import os,urllib.request,urllib.error,json
   r=urllib.request.Request('http://litellm:4000/v1/chat/completions', data=json.dumps({'model':'local-model','messages':[{'role':'user','content':'Say OK'}]}).encode(), headers={'Authorization':'Bearer '+os.environ['LLM_API_KEY'],'Content-Type':'application/json'})
   try: print('OK:', json.load(urllib.request.urlopen(r, timeout=120))['choices'][0]['message']['content'])
   except urllib.error.HTTPError as e: print(e.code, e.read().decode()[:400])
   "
   ```
2. **A chat answer:** in a new conversation, ask `What is 2+2? Answer in one word.` The call appears under the key `openhands` in LiteLLM (**Usage**) and in Langfuse.
3. **A task in a sandbox:** in a new conversation, ask `Create a file hello.py that prints "Hello from OpenHands", run it, and show me the output.` The first task takes a few minutes (the sandbox image downloads). It must show `Hello from OpenHands`; meanwhile `docker ps --filter name=oh-agent-server` lists the sandbox.

## Step 17: Open WebUI (chat)

A chat app in the browser for everyone, like ChatGPT: people sign in through Dex, pick any model LiteLLM offers, and chat with their own documents and shared knowledge bases. It uses the server's other parts: models and tracing through LiteLLM (so every chat shows in Langfuse), documents stored in Qdrant, and embeddings from `local-embed`.

**Check:** `open-webui`.

### Clean reinstall

Removes Open WebUI as if it had never been installed. Skip it for a first install. Each line asks first; the volume line deletes all chats, users, settings, and uploaded documents. Their vectors in Qdrant are left behind; delete them in the Qdrant dashboard (collections starting with `open-webui`) if you want Qdrant clean too.
```bash
confirm "Stop and remove the Open WebUI container?" && cd /opt/stacks/open-webui && docker compose down; cd ~
confirm "Delete Open WebUI chats, users, settings, and files (volume openwebui_data)?" && docker volume rm openwebui_data
confirm "Delete the stack folder /opt/stacks/open-webui?" && rm -rf /opt/stacks/open-webui
confirm "Delete its Caddy file (open-webui.caddy)?" && rm -f /opt/stacks/caddy/conf.d/open-webui.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the Open WebUI image (downloaded again on the next install)?" && docker image rm ghcr.io/open-webui/open-webui:main
```
Outside the server, if you are not reinstalling: revoke its LiteLLM key (Admin UI → Virtual Keys → `open-webui` → Delete), delete the Infisical folder `prod:/open-webui`, and remove the `open-webui` client from Dex `config.yaml` (Step 6).

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -x open-webui
docker volume ls -q | grep -i openwebui
ls -d /opt/stacks/open-webui /opt/stacks/caddy/conf.d/open-webui.caddy 2>/dev/null
```

### Install

1. **Its Dex client** is already in Step 6 (`open-webui`, secret `OPENWEBUI_OIDC_SECRET` in `/opt/stacks/dex/.env`). Dex installed from an older version of this guide: add `OPENWEBUI_OIDC_SECRET=<openssl rand -hex 32>` to Dex's `.env`, the `open-webui` client to its `config.yaml`, and the `OPENWEBUI_OIDC_SECRET` line to its `compose.yaml` as shown in Step 6, then `cd /opt/stacks/dex && docker compose up -d --force-recreate dex`.

2. **A LiteLLM key for Open WebUI**, for chats and for document embeddings. Leave `models` out so users can pick every model; LiteLLM keys per person are not needed, as Open WebUI keeps its own users:
   ```bash
   curl -k https://${SERVER_HOST}:4000/key/generate \
     -H "Authorization: Bearer <LITELLM_MASTER_KEY>" -H "Content-Type: application/json" \
     -d '{"key_alias":"open-webui"}'
   ```
   Copy the `"key"` value (shown only once).

3. **The stack folder and its files:**
   ```bash
   mkdir -p /opt/stacks/open-webui
   ```
   `/opt/stacks/open-webui/.env` (with Infisical, the folder `prod:/open-webui`):
   ```env
   SERVER_HOST=<from /opt/stacks/shared/.env>
   SERVER_IP=<from /opt/stacks/shared/.env>
   OPENWEBUI_SECRET_KEY=<openssl rand -hex 32>             # signs sign-in sessions; keep it, or everyone is signed out
   OPENWEBUI_OIDC_SECRET=<OPENWEBUI_OIDC_SECRET from /opt/stacks/dex/.env>
   OPENWEBUI_LITELLM_KEY=<the open-webui virtual key from LiteLLM>
   # QDRANT_API_KEY=<QDRANT_API_KEY from /opt/stacks/qdrant/.env>   # only when Qdrant has an API key
   ```
   Open WebUI reads Dex at its HTTPS address, so it needs the server name inside the container and must trust Caddy's internal CA next to the public ones. Make that certificate bundle (again after the CA changes):
   ```bash
   cat /etc/ssl/certs/ca-certificates.crt /opt/stacks/caddy/caddy-root-ca.crt > /opt/stacks/open-webui/ca-bundle.crt
   ```
   `/opt/stacks/open-webui/compose.yaml`:
   ```yaml
   services:
     open-webui:
       image: ghcr.io/open-webui/open-webui:main
       container_name: open-webui
       restart: unless-stopped
       environment:
         WEBUI_URL: https://${SERVER_HOST}:9485
         WEBUI_SECRET_KEY: ${OPENWEBUI_SECRET_KEY}
         # Models: everything LiteLLM offers, traced in Langfuse; no direct Ollama
         ENABLE_OLLAMA_API: "false"
         OPENAI_API_BASE_URL: http://litellm:4000/v1
         OPENAI_API_KEY: ${OPENWEBUI_LITELLM_KEY}
         # Sign-in through Dex; people who sign in for the first time get an account
         ENABLE_OAUTH_SIGNUP: "true"
         OAUTH_MERGE_ACCOUNTS_BY_EMAIL: "true"
         OAUTH_PROVIDER_NAME: Dex
         OPENID_PROVIDER_URL: https://${SERVER_HOST}:5556/dex/.well-known/openid-configuration
         OPENID_REDIRECT_URI: https://${SERVER_HOST}:9485/oauth/oidc/callback
         OAUTH_CLIENT_ID: open-webui
         OAUTH_CLIENT_SECRET: ${OPENWEBUI_OIDC_SECRET}
         OAUTH_SCOPES: openid email profile
         DEFAULT_USER_ROLE: user                 # Dex decides who may sign in; no approval step
         SSL_CERT_FILE: /certs/ca-bundle.crt
         REQUESTS_CA_BUNDLE: /certs/ca-bundle.crt
         # Documents: vectors in the shared Qdrant, embeddings from LiteLLM (local-embed on Ollama)
         VECTOR_DB: qdrant
         QDRANT_URI: http://qdrant:6333
         QDRANT_API_KEY: ${QDRANT_API_KEY:-}     # only when Qdrant has an API key (guide option)
         RAG_EMBEDDING_ENGINE: openai
         RAG_OPENAI_API_BASE_URL: http://litellm:4000/v1
         RAG_OPENAI_API_KEY: ${OPENWEBUI_LITELLM_KEY}
         RAG_EMBEDDING_MODEL: local-embed
       extra_hosts:
         - "${SERVER_HOST}:${SERVER_IP}"
       volumes:
         - openwebui_data:/app/backend/data
         - ./ca-bundle.crt:/certs/ca-bundle.crt:ro
       networks: [edge]

   networks:
     edge:
       external: true

   volumes:
     openwebui_data:
       external: true
   ```

4. **Start it and route it through Caddy:**
   ```bash
   docker volume create openwebui_data
   cd /opt/stacks/open-webui && docker compose up -d
   ```
   ```bash
   cat > /opt/stacks/caddy/conf.d/open-webui.caddy <<'EOF'
   https://{$SERVER_HOST}:9485 {
   	tls internal
   	reverse_proxy open-webui:8080
   }
   EOF
   docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
   ```
   The first start takes a minute or two. Open WebUI answers on `SERVER_HOST` only: its sign-in needs one fixed address.

5. **Check the result.** Every line must match the table:
   ```bash
   docker inspect open-webui --format 'name={{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}'
   docker inspect open-webui --format 'networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'
   docker inspect open-webui --format '{{range .Mounts}}mount {{.Destination}} <- {{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}}{{println}}{{end}}'
   docker inspect open-webui --format 'extra_hosts={{.HostConfig.ExtraHosts}}'
   docker volume inspect openwebui_data --format 'volume={{.Name}}  driver={{.Driver}}'
   docker exec open-webui sh -c 'echo "LiteLLM key: ${#OPENAI_API_KEY} characters"; echo "WEBUI_URL: $WEBUI_URL"; echo "embeddings: $RAG_EMBEDDING_MODEL"'
   docker exec open-webui getent hosts litellm qdrant ${SERVER_HOST}
   docker exec open-webui python3 -c "import urllib.request; print('Dex:', urllib.request.urlopen('https://${SERVER_HOST}:5556/dex/.well-known/openid-configuration').status)"
   curl -sv https://${SERVER_HOST}:9485 -o /dev/null 2>&1 | grep -E "subject:|issuer:|HTTP/"
   ```

   | Line | Expected |
   |---|---|
   | `name=` | `/open-webui  state=running  restart=unless-stopped`, image `ghcr.io/open-webui/open-webui:main` |
   | `networks=` | `edge` (only) |
   | `mount` | `/app/backend/data <- openwebui_data` and `/certs/ca-bundle.crt <- /opt/stacks/open-webui/ca-bundle.crt`; no hash-named volume |
   | `extra_hosts=` | `[<SERVER_HOST>:<SERVER_IP>]` with your values |
   | `volume=` | `openwebui_data  driver=local` |
   | Environment | `LiteLLM key: 25 characters`, `WEBUI_URL: https://<SERVER_HOST>:9485`, `embeddings: local-embed` |
   | `getent` | an address for `litellm`, `qdrant` (on `edge`), and `SERVER_HOST` (your `SERVER_IP`) |
   | `Dex:` | `200`: the container reaches Dex and trusts its certificate |
   | `curl` | `issuer: CN=Caddy Local Authority …` and `HTTP/2 200` |

6. **Sign in.** Open `https://<SERVER_HOST>:9485` and click **Continue with Dex**. The **first** account that signs in becomes the Open WebUI admin, so sign in yourself first. In the admin panel (your name → Admin Panel → Settings), check that **Connections** lists `http://litellm:4000/v1` and that the model picker shows LiteLLM's names (`local-model`, `gemma4-12b`, …).

**Settings live in Open WebUI's database after the first start.** Most of the values above (models, documents, sign-in names) are read from `compose.yaml` only on the very first start; later changes go in the Admin Panel, or set `ENABLE_PERSISTENT_CONFIG: "false"` to make `compose.yaml` win. The sign-in (OAuth) lines are an exception: they are always read from `compose.yaml`.

**Verify:** `https://<SERVER_HOST>:9485` shows **Continue with Dex**, you are admin after signing in, and the model list shows LiteLLM's models.

### Authentication

Open WebUI keeps its own accounts; this guide signs them in through Dex. Its own email-and-password form stays on the sign-in page as a fallback for the admin.

**Dex** (free): the `OAUTH_*` and `OPENID_*` lines. New people get an account at their first sign-in (`ENABLE_OAUTH_SIGNUP`) as a normal user; the admin can make others admin (Admin Panel → Users). Someone who first had a password account keeps it when signing in through Dex with the same email (`OAUTH_MERGE_ACCOUNTS_BY_EMAIL`).

**Google Account** and **Azure** (free): through Dex's Google and Microsoft connectors, with nothing to change here. Open WebUI's own Google and Microsoft sign-in (`GOOGLE_CLIENT_ID`, `MICROSOFT_CLIENT_ID`) also works, but then it skips Dex.

### Usage

- **Models:** every model in LiteLLM's `config.yaml` appears by its name. Hide some or rename them for users under Admin Panel → Settings → Models; the Services page in Outline explains which name is for what.
- **Documents in a chat:** drop a file into the chat; Open WebUI stores it in Qdrant and answers with citations.
- **Shared knowledge:** Workspace → Knowledge → create a collection (e.g. HR policies), upload files, and share it with a group. In a chat, type `#` and pick the collection.
- **Custom assistants:** Workspace → Models → create one with its own instructions, a base model, and knowledge, e.g. "Policy helper" on `qwen3.5-9b` with the HR collection.
- **Usage per person** shows in Langfuse (each chat is a trace, with the user); LiteLLM counts it all under the key `open-webui`.

### Test

1. **Models through LiteLLM**, from inside the container (prints `OK: …`):
   ```bash
   docker exec open-webui python3 -c "
   import os,urllib.request,urllib.error,json
   r=urllib.request.Request('http://litellm:4000/v1/chat/completions', data=json.dumps({'model':'local-model','messages':[{'role':'user','content':'Say OK'}]}).encode(), headers={'Authorization':'Bearer '+os.environ['OPENAI_API_KEY'],'Content-Type':'application/json'})
   try: print('OK:', json.load(urllib.request.urlopen(r, timeout=120))['choices'][0]['message']['content'])
   except urllib.error.HTTPError as e: print(e.code, e.read().decode()[:400])
   "
   ```
2. **Sign-in:** in a private browser window, open `https://<SERVER_HOST>:9485`, **Continue with Dex**, sign in with Google; you land in Open WebUI as a user.
3. **Chat:** pick `local-model` and ask `What is 2+2? Answer in one word.` The call shows in Langfuse within a minute.
4. **Documents:** upload a small text file with a made-up fact ("The office plant is called Herbert.") and ask "What is the office plant called?". The answer names Herbert and cites the file; the Qdrant dashboard (`https://<SERVER_HOST>:6333/dashboard`) now lists an `open-webui` collection.

| Symptom | Cause |
|---|---|
| Dex button missing, or "Continue with Dex" ends in an error page | `OPENID_PROVIDER_URL` not reachable: check the `Dex:` line of step 5 (name in `extra_hosts`, `ca-bundle.crt`) |
| Dex says "Unregistered redirect_uri" | The Dex client lacks `https://<SERVER_HOST>:9485/oauth/oidc/callback`, or `SERVER_HOST` differs between the Dex and Open WebUI `.env` |
| No models in the picker | Wrong `OPENWEBUI_LITELLM_KEY` (test 1), or Admin Panel → Settings → Connections changed after the first start |
| Upload fails or answers ignore the file | Embeddings: `local-embed` needs Ollama running (`switch-llm.sh status`); or Qdrant not reachable (`getent hosts qdrant`) |
| New users wait for approval | `DEFAULT_USER_ROLE` was not `user` on the first start; change it in Admin Panel → Settings → General |

## Step 18: CI runner (GitHub)

Runs your GitHub repositories' workflow jobs on this server: tests, security checks, and AI review on every pull request. Jobs on the server reach LiteLLM, so reviews can use the local models and code stays in-house, and they use no GitHub minutes. The runner starts job containers through the host's Docker socket, so a workflow can control every container on this host: **connect it to private repositories only**; on a public repository, anyone's pull request could run code here. How the team uses it: [AI setup for software development](ai-setup-for-software-development.md).

**Check:** `github-runner`.

### Clean reinstall

Removes the runner as if it had never been installed. Skip it for a first install. Each line asks first.
```bash
confirm "Stop and remove the runner container?" && cd /opt/stacks/github-runner && docker compose down; cd ~
confirm "Delete the stack folder /opt/stacks/github-runner (settings and job work folders)?" && sudo rm -rf /opt/stacks/github-runner
confirm "Delete the runner image (downloaded again on the next install)?" && docker image rm myoung34/github-runner:latest
```
On GitHub: remove the runner from the list (organization or repository → Settings → Actions → Runners → `ai-server` → Remove) if it still shows, and delete its access token (your profile → Settings → Developer settings → Fine-grained tokens). Delete the Infisical folder `prod:/github-runner` if you used one.

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -x github-runner
ls -d /opt/stacks/github-runner 2>/dev/null
```

### Install

1. **A GitHub token for the runner**, so it can register itself (again after every job, see `EPHEMERAL`). Your profile → Settings → Developer settings → **Fine-grained tokens** → Generate:
   - **For a whole organization** (every repository in it): Resource owner = the organization; Organization permissions → **Self-hosted runners: Read and write**.
   - **For one repository:** Resource owner = its owner; Only select repositories → the repository; Repository permissions → **Administration: Read and write**.
   Copy the token (shown once). An organization may need to approve it (Settings → Personal access tokens → Pending requests).

2. **The stack folder and its files:**
   ```bash
   mkdir -p /opt/stacks/github-runner/work
   ```
   `/opt/stacks/github-runner/.env` (with Infisical, the folder `prod:/github-runner`):
   ```env
   RUNNER_SCOPE=org                     # org: every repository of ORG_NAME; repo: only REPO_URL
   ORG_NAME=<GitHub organization>       # with RUNNER_SCOPE=org
   # REPO_URL=https://github.com/<owner>/<repository>   # with RUNNER_SCOPE=repo
   GITHUB_RUNNER_TOKEN=<the fine-grained token>
   ```
   `/opt/stacks/github-runner/compose.yaml`:
   ```yaml
   services:
     github-runner:
       image: myoung34/github-runner:latest
       container_name: github-runner
       restart: unless-stopped
       environment:
         RUNNER_SCOPE: ${RUNNER_SCOPE}
         ORG_NAME: ${ORG_NAME:-}
         REPO_URL: ${REPO_URL:-}
         ACCESS_TOKEN: ${GITHUB_RUNNER_TOKEN}
         RUNNER_NAME: ai-server
         LABELS: ai-server                  # workflows pick it with runs-on: [self-hosted, ai-server]
         EPHEMERAL: "true"                  # a fresh runner for every job: nothing left from the last one
         DISABLE_AUTO_UPDATE: "true"        # updates come with update-stack.sh
         # Job folders at the same path inside and outside the container, so containers a job
         # starts through the host Docker see the same files
         RUNNER_WORKDIR: /opt/stacks/github-runner/work
       volumes:
         - /var/run/docker.sock:/var/run/docker.sock
         - /opt/stacks/github-runner/work:/opt/stacks/github-runner/work
       # One job at a time (one runner), and a cap so a test run cannot starve the models
       mem_limit: 6g
       cpus: 4
       networks: [edge]                     # jobs reach LiteLLM as http://litellm:4000

   networks:
     edge:
       external: true
   ```
   The cap covers jobs that run inside the runner; containers a job starts itself (scanners, Playwright) take their own `--memory` flag, as in the example workflow.

3. **Start it:**
   ```bash
   cd /opt/stacks/github-runner && docker compose up -d
   ```

4. **Check the result.** Every line must match the table:
   ```bash
   docker inspect github-runner --format 'name={{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}'
   docker inspect github-runner --format 'networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'
   docker inspect github-runner --format '{{range .Mounts}}mount {{.Destination}} <- {{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}}{{println}}{{end}}'
   docker inspect github-runner --format 'memory={{.HostConfig.Memory}}  cpus={{.HostConfig.NanoCpus}}'
   docker exec github-runner sh -c 'echo "token: ${#ACCESS_TOKEN} characters, scope: $RUNNER_SCOPE, labels: $LABELS"'
   docker exec github-runner getent hosts litellm
   docker logs github-runner 2>&1 | grep -E "Listening for Jobs|Runner successfully added|error" | tail -5
   ```

   | Line | Expected |
   |---|---|
   | `name=` | `/github-runner  state=running  restart=unless-stopped`, image `myoung34/github-runner:latest` |
   | `networks=` | `edge` |
   | `mount` | `/var/run/docker.sock <- /var/run/docker.sock` and `/opt/stacks/github-runner/work <- /opt/stacks/github-runner/work` (same path both sides) |
   | `memory=` | `6442450944  cpus=4000000000` (6 GB, 4 cores) |
   | Environment | `token: 93 characters` (fine-grained tokens are about that long), your scope, `labels: ai-server` |
   | `getent` | an address for `litellm` |
   | Log | `Runner successfully added` and `Listening for Jobs`, no `error` |

   On GitHub: the organization or repository → Settings → Actions → **Runners** lists `ai-server` as **Idle**.

**Verify:** the runner shows as Idle on GitHub, and a workflow with `runs-on: [self-hosted, ai-server]` runs on it (see Test below).

### Authentication

The runner has no web page or login. It signs in to GitHub with its token, and only repositories in its scope can send it jobs. Workflows reach LiteLLM with a virtual key stored as a GitHub secret (see the AI review option), never the master key.

### Usage

**A workflow per repository.** Add `.github/workflows/ci.yml` to each repository; it runs on every pull request and on pushes to `main`. Keep the jobs the repository needs, delete the rest:
```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]

jobs:
  # Security checks: secrets, insecure code, vulnerable dependencies. Each tool runs as its own
  # container with a memory cap; the job folder has the same path on the host (see compose.yaml).
  checks:
    runs-on: [self-hosted, ai-server]
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0                    # full history, so Gitleaks also checks earlier commits
      - name: Secrets (Gitleaks)
        run: docker run --rm --memory 1g -v "$PWD:/repo" ghcr.io/gitleaks/gitleaks:latest detect --source /repo --redact --no-banner
      - name: Code patterns (Semgrep)
        run: docker run --rm --memory 2g -v "$PWD:/src" -w /src semgrep/semgrep semgrep scan --config p/default --metrics=off --error
      - name: Dependencies and Dockerfiles (Trivy)
        run: docker run --rm --memory 2g -v "$PWD:/src" -v trivy_cache:/root/.cache aquasec/trivy:latest fs --scanners vuln,misconfig --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 /src

  # Unit tests: .NET
  test-dotnet:
    runs-on: [self-hosted, ai-server]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: "9.0.x"
      - run: dotnet test --logger "console;verbosity=normal"

  # Unit tests: JavaScript / TypeScript (Vitest)
  test-js:
    runs-on: [self-hosted, ai-server]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "22"
      - run: npm ci
      - run: npx vitest run

  # End-to-end in real browsers (Playwright), in its own container with the browsers inside
  e2e:
    runs-on: [self-hosted, ai-server]
    needs: [test-js]
    container:
      image: mcr.microsoft.com/playwright:v1.56.0-noble   # match the Playwright version in package.json
      options: --memory 4g --ipc=host
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npx playwright test
```

**Make the checks required.** Repository → Settings → Branches → add a rule for `main`: **Require a pull request before merging**, and **Require status checks to pass** with the jobs above (`checks`, `test-dotnet`, `test-js`, `e2e`). Then nothing reaches `main` without passing tests and checks.

- **One job at a time:** jobs queue on GitHub and run one after another; a pull request's checks take a few minutes each. Long queues mean adding a second runner (a copy of the stack with another `RUNNER_NAME`), at the cost of more CPU and RAM next to the models.
- **Images used by jobs** (Playwright, scanners) stay on the server between runs; `docker-cleanup.sh` (Step 22) removes them when unused.
- **AI review on pull requests:** [AI code review (PR-Agent)](options/pr-agent.md) adds a review job that uses LiteLLM.

**Option:** [AI code review (PR-Agent)](options/pr-agent.md) — AI review comments on every pull request, from a local or hosted model through LiteLLM.

**Option:** [App error tracking (GlitchTip)](options/glitchtip.md) — errors of the apps you build, with the Sentry SDKs (about 1 GB of RAM); for later, apps already on Sentry keep it.

### Test

1. **A job runs here.** In a test repository, push a branch with this `.github/workflows/runner-test.yml` and open a pull request:
   ```yaml
   name: Runner test
   on: [pull_request]
   jobs:
     hello:
       runs-on: [self-hosted, ai-server]
       steps:
         - run: echo "Hello from $(hostname)"; docker version --format '{{.Server.Version}}'
   ```
   The job turns green within a minute; its log shows the Docker version (the job can use Docker). Meanwhile `docker logs github-runner 2>&1 | tail` shows the job running.
2. **The checks work.** In the same pull request, add a file `leak.txt` with a fake GitHub token (`token = "ghp_1a2B3c4D5e6F7g8H9i0J1k2L3m4N5o6P7q8R"`) and the `checks` job: it fails on Gitleaks. Remove the file: it passes.

| Symptom | Cause |
|---|---|
| Job stays "Waiting for a runner" | Labels differ (`runs-on` must include `ai-server`), the repository is outside the runner's scope, or the runner is offline (`docker logs github-runner`) |
| Log: `Could not get a registration token` / `401` | Token expired, wrong permission, or awaiting the organization's approval |
| Scanner step: `no such file or directory` for `/repo` | The work folder is not mounted at the same path inside and outside the container |
| A job is killed (`exit code 137`) | It hit a memory cap; raise `mem_limit` or the step's `--memory` |

## Step 19: Outline services page

The one step you come back to: it's content inside Outline, not config. Create a "Services" document in Outline and add a line each time you deploy a service:
```
- Outline:      https://<SERVER_HOST>
- Infisical:    https://<SERVER_HOST>:8080
- Portainer:    https://<SERVER_HOST>:9443
- Grafana:      https://<SERVER_HOST>:9450
- Prometheus:   https://<SERVER_HOST>:9090
- Sourcebot:    https://<SERVER_HOST>:9460
- Langfuse:     https://<SERVER_HOST>:9470
- LiteLLM:      https://<SERVER_HOST>:4000
- Qdrant:       https://<SERVER_HOST>:6333
- Neo4j:        https://<SERVER_HOST>:7474
- Memgraph Lab: https://<SERVER_HOST>:9490
- OpenHands:    http://<SERVER_IP>:3000
- Open WebUI:   https://<SERVER_HOST>:9485
```

**Say how to sign in to each service** next to its link: "Google (through Dex)" for the apps behind Dex, and **Own login** for the others, with the reason, so users know why they need a separate account: Infisical (Dex sign-in needs an Infisical Enterprise license; Google sign-in is free), Sourcebot (SSO requires a Sourcebot Enterprise license), LiteLLM (an API key from the admin; Admin UI through Dex is free for up to 5 users since v1.76.0, more need a LiteLLM Enterprise license).

**AI models on the same page,** so users know which name to pick and what works while vLLM runs. Copy the table, and update it when you change `/opt/stacks/litellm/config.yaml`:

| Model name | What it is | Use for | Speed | Works on |
|---|---|---|---|---|
| `local-model` | Whatever runs now (Gemma 4 12B) | Default; tools that should not care | Fast | Always |
| `gemma4-12b` | Gemma 4 12B | Everyday chat and code; reads images | Fast | Ollama and vLLM |
| `qwen3.5-9b` | Qwen3.5 9B | Long documents and large files (most context) | Fastest | Ollama only |
| `gemma4-26b-a4b` | Gemma 4 26B A4B | Better answers, short context (~8k tokens) | Fast | Ollama only |
| `qwen3.6-35b-a3b` | Qwen3.6 35B A3B | Harder reasoning and code | Medium | Ollama only |
| `qwen3.8-27b` | Qwen3.8 27B | Best answers for occasional hard questions | Slow | Ollama only |

Add for users: the API address `https://<SERVER_HOST>:4000` (OpenAI-compatible) and how to get an API key; that "Ollama only" models fail while the server runs vLLM (`./switch-llm.sh status` shows which); and that switching between models takes a few seconds the first time, because only one is kept in GPU memory.

**Share the CA certificate on the same page** so new users can trust every service:
1. Copy `caddy-root-ca.crt` (made in Step 4) to your PC, and get its fingerprint:
   ```bash
   openssl x509 -in /opt/stacks/caddy/caddy-root-ca.crt -noout -fingerprint -sha256
   ```
2. Drag the `.crt` file into the "Services" document; Outline stores it as a downloadable attachment. Paste the fingerprint next to it, so users can check they got the right file (Windows shows it under the certificate's Details → Thumbprint, as SHA-1; compare with `-sha1` instead of `-sha256` there).
3. Add the import steps from Step 4 below it.

A new user sees one certificate warning the first time they open Outline, before they've imported the certificate. That's expected; they continue once, download, import, and restart the browser.

Only share `root.crt`. **Never** share `root.key` from the same Caddy folder — anyone with it can issue certificates your clients will trust. The root certificate is valid for 10 years; it only changes if Caddy's `caddy_data` volume is lost, and then you re-share the new one.

## Step 20: Update workflow

`update-stack.sh` and `restore-stack.sh` run from `~/ai-server` ([Helper scripts](options/helper-scripts.md)). Use `update-stack.sh` instead of a bare `docker compose pull && up -d`. It backs up the stack's Postgres databases and volumes to `/opt/backups/<stack>/<timestamp>/`, then pulls and recreates. In `llm-runtime` and `graphdb` it restarts only what was running.

```bash
~/ai-server/update-stack.sh outline
~/ai-server/update-stack.sh outline --skip-backup   # skip backup if no schema/data change expected
```
**A development server without volume backups:** always add `--skip-backup`; old backups from earlier updates can be deleted: `confirm "Delete all stack backups in /opt/backups?" && sudo rm -rf /opt/backups/*`. Instead, `backup-config.sh` keeps what it takes to install everything again: every file in `/opt/stacks` (compose files, `.env`, configs, Caddy files, the CA), the helper scripts, the Docker daemon and firewall settings, your crontab, and the Infisical and Outline databases (secrets, documents). No volumes. It keeps the newest 14 in `/opt/backups/config/`, readable by you only, since they hold every secret:
```bash
~/ai-server/backup-config.sh --dry-run
~/ai-server/backup-config.sh
```
Daily, in your crontab (`crontab -e`):
```
0 2 * * *   $HOME/ai-server/backup-config.sh >/dev/null 2>&1
```
Copy `/opt/backups/config` off the server now and then (a NAS, another PC); a backup on the same disk does not survive the disk. To reinstall from it: unpack `stacks.tar.gz` and `scripts.tar.gz`, create the volumes, start the stacks in step order, and replay a database into its fresh container, e.g. `gunzip -c outline.sql.gz | docker exec -i outline-postgres psql -U postgres`.

**Start a stack fresh** (all its data gone, its settings kept), e.g. Langfuse when its traces should go: `reset-stack.sh` empties every volume of the stack and starts it again; it asks you to type the stack name first.
```bash
~/ai-server/reset-stack.sh --dry-run langfuse
~/ai-server/reset-stack.sh langfuse
```
Langfuse then creates its admin user, project, and API keys again from its `.env`, so LiteLLM keeps sending traces with the same keys.
Stacks: `caddy`, `infisical`, `dex`, `outline`, `portainer`, `grafana`, `prometheus`, `node-exporter`, `dcgm-exporter`, `sourcebot`, `langfuse`, `litellm`, `llm-runtime`, `qdrant`, `graphdb`, `openhands`, `open-webui`, `github-runner`.

**Restore:** `~/ai-server/restore-stack.sh <stack-name> <timestamp>`. It asks first, stops the stack, restores the volumes, and restarts what was running. Add `--sql` to also replay the `.sql` dumps; only needed if a volume tarball is missing or damaged. List backups with `ls /opt/backups/<stack-name>/`.

## Step 21: Server test

Every service step ends with a **Test**. `server-test.sh` runs the part of those tests that works from the server, for every installed service at once; `server-status.sh` shows whether the containers run and the base settings are right. Run both after an install, after an update ([Step 20](#step-20-update-workflow)), or whenever something seems off:

```bash
~/ai-server/server-status.sh
~/ai-server/server-test.sh
```

Services that are not installed show `--`. For a `[FAILED]` line, open that service's Test in its step; the symptom tables there name the usual causes. `server-test.sh --no-model` skips the model calls (quick, leaves the GPU alone); `server-test.sh litellm open-webui` tests only those services (`-h` lists the names).

| Service | `server-test.sh` tests | Still by hand (browser or GitHub) |
|---|---|---|
| [Caddy](#step-3-caddy-reverse-proxy) | Health on the name and the IP, certificate from the internal CA, config valid | The padlock on client PCs ([Step 4](#step-4-trust-the-internal-ca)) |
| [Infisical](#step-5-infisical-secrets) | Web answers, `pull-secrets.sh` signs in | Sign-in |
| [Dex](#step-6-dex-sign-in) | Discovery with the right issuer, sign-in gate in front of Prometheus | Signing in to each app with the same account |
| [Outline](#step-7-outline-wiki) | Health | A document, search, email |
| [Portainer](#step-8-portainer-docker-ui) | API answers | Sign-in, container logs |
| [Monitoring](#step-9-monitoring-stack) | Every Prometheus target up, Grafana database ok | A dashboard with recent values |
| [Sourcebot](#step-10-sourcebot-code-search) | Web and MCP answer, no `401`/`404` from GitHub in the last day | A search |
| [Langfuse](#step-11-langfuse-llm-tracing) | Health | Sign-in |
| [LiteLLM](#step-12-litellm-gateway) and [the runtime](#step-13-ollama--vllm-runtime) | Gateway health, a `local-model` call, its trace in Langfuse, the model fully on the GPU, embeddings | Admin UI, virtual keys, `switch-llm.sh vllm` |
| [Qdrant](#step-14-qdrant-vector-db) | API on the `edge` network, dashboard answers | Writing and searching a point |
| [Neo4j + Memgraph](#step-15-neo4j--memgraph) | A Neo4j query, the Memgraph bolt port, both web apps answer | A driver from a PC, data after a restart |
| [OpenHands](#step-16-openhands-agent) | Web answers, its key reaches `local-model` | A sandbox task |
| [Open WebUI](#step-17-open-webui-chat) | Health, its key reaches `local-model` | Sign-in, a chat, a document upload |
| [CI runner](#step-18-ci-runner-github) | Connected to GitHub | A job on a pull request |

## Step 22: Docker housekeeping

`docker-cleanup.sh` (in `~/ai-server`, [Helper scripts](options/helper-scripts.md)) lists what Docker keeps that nothing uses and asks per kind before removing it: stopped OpenHands sandboxes, stopped containers outside any stack, networks no container uses, anonymous (hash-named) volumes no container uses, dangling images, and the build cache; with `--images` also images no container uses. It never touches running containers, named volumes, or `edge`, so the data of every stack stays, also of stacks that are stopped. Preview first:
```bash
~/ai-server/docker-cleanup.sh --dry-run
~/ai-server/docker-cleanup.sh
```
It shows `docker system df` before and after. Named volumes no container uses are only listed: a volume counts as unused whenever its container is stopped, so check each one first. Never remove `portainer_data` or the data volume of a stack you still use.

**Automatic, by email.** A weekly report of what could be removed, and a monthly clean-up (stopped sandboxes, stray containers, unused networks and anonymous volumes, old and unused images, build cache; never named volumes or `edge`). It mails through the `SMTP_*` settings already in `/opt/stacks/shared/.env` (from `prod:/shared`) or `/opt/stacks/grafana/.env` ([Email (SMTP) for all services](options/smtp-email.md)); `CLEANUP_EMAIL_TO` sends it elsewhere. Add to your crontab (`crontab -e`):
```
# Docker clean-up: report every Monday 08:00, remove on the 1st of each month 08:30
0 8 * * 1   $HOME/ai-server/docker-cleanup.sh --dry-run --images --email >/dev/null 2>&1
30 8 1 * *  $HOME/ai-server/docker-cleanup.sh --yes --images --email >/dev/null 2>&1
```
Test the mail once by hand: `~/ai-server/docker-cleanup.sh --dry-run --email`. Removed images download again when a stack needs them (`update-stack.sh`, `switch-llm.sh vllm`), which can take a while for vLLM.

Remove a confirmed leftover by name:
```bash
confirm "Delete volume <name>? This is permanent." && docker volume rm <name>
confirm "Delete image <name>?" && docker image rm <name>
```
**Don't run `docker system prune -a --volumes` or `docker volume prune`.** Pruning ignores `external: true` and deletes any volume whose container happens to be stopped.

## Design decisions

1. **Sign-in through Dex** — one account for every app, managed on this server, so no SMTP relay or Azure admin rights are needed. Email and Microsoft/Google/Auth0 sign-in are options on top.
2. **Caddy is append-only** — its two files are written once in Step 3; each service adds one `conf.d` file. That's why Caddy comes before every service it fronts.
3. **Langfuse before LiteLLM** — so LiteLLM's config is written once with tracing already wired.
4. **Portainer and Neo4j Browser go through Caddy** on their own default ports, so they get the trusted CA instead of a self-signed cert or plain HTTP.
5. **Neo4j + Memgraph both run** — they don't share the GPU; Ollama and vLLM do, so only one of those runs at a time.
6. **GitHub MCP runs per client**, not as a hosted service; developer tools reach the server through LiteLLM and Sourcebot's MCP endpoint.
