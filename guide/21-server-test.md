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

