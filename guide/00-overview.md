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

