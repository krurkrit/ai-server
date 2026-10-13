*Copied from `options/upgrade-older-install.md` in the ai-server repo; import it as a document named "Option: Upgrading an older install".*

For servers set up with an earlier version of the setup guide (document "Self-Hosted AI Server Setup Guide"). A fresh install doesn't need any of this. Do the parts in this order; each one only touches the files of its own step.

## edge network

Part of Step 2 (Shared network, settings). **`edge` without a bridge name** (`ip -br link` shows `br-<random id>` and no `br-edge`): nothing is broken; recreate it only for the readable name. All services are down for a few minutes, so do it outside office hours. Data is untouched: it lives in the volumes.

1. Stop every stack, so nothing is attached to `edge` (`--profile "*"` includes Ollama, vLLM, Neo4j, and Memgraph). Note which of those four were running first: `docker ps --format '{{.Names}}'`.
   ```bash
   confirm "Stop every stack under /opt/stacks?" && for d in /opt/stacks/*/; do [ -f "$d/compose.yaml" ] && (cd "$d" && docker compose --profile "*" stop); done
   ```
2. Recreate the network with the bridge name:
   ```bash
   confirm "Remove and recreate the edge network?" && docker network rm edge && docker network create -o com.docker.network.bridge.name=br-edge edge
   ```
3. Recreate every stack on the new network. `--force-recreate` is required: the stopped containers still point at the removed network, and a plain `up -d` fails with "network … not found".
   ```bash
   for s in caddy infisical dex outline portainer grafana prometheus node-exporter dcgm-exporter sourcebot langfuse litellm qdrant openhands; do [ -f /opt/stacks/$s/compose.yaml ] && (cd /opt/stacks/$s && docker compose up -d --force-recreate); done
   ```
4. Start again only the profile services that were running, also with `--force-recreate` (`switch-llm.sh` and `graphdb.sh` use a plain `up -d`, so not those):
   ```bash
   cd /opt/stacks/llm-runtime && docker compose --profile ollama up -d --force-recreate ollama
   cd /opt/stacks/graphdb && docker compose --profile neo4j --profile memgraph up -d --force-recreate neo4j memgraph
   ```
   With vLLM instead of Ollama: `--profile vllm up -d --force-recreate vllm`.
5. Check: `docker ps -a --filter status=exited --filter status=created --format '{{.Names}}'` prints nothing, and `ip -br link | grep br-edge` shows the bridge. People may need to sign in again.

**A stack network without a bridge name** (Infisical, Outline, Sourcebot, Langfuse, LiteLLM: their databases sit on the stack's own network, shown as another `br-<random id>`): add the `driver_opts` lines under `networks:` → `default:` in its `compose.yaml` as shown in its step. Docker Compose cannot change an existing network, so take the stack down and up again; `down` removes its containers and network, not its volumes. For example Outline:
```bash
confirm "Take the outline stack down and up again (data in volumes is kept)?" && cd /opt/stacks/outline && docker compose down && docker compose up -d
```
Then `ip -br link | grep br-outline` shows the bridge. Only that stack is down meanwhile; `edge` and the other stacks are not touched.

## Caddy: SERVER_HOST

Part of Step 3 (Caddy). For a Caddy with no `SERVER_HOST` in `/opt/stacks/caddy/.env` (it used only `SERVER_IP`): back up Caddy's three files, add the `SERVER_HOST=` line to `.env`, write `compose.yaml` and `Caddyfile` again as shown in Step 3, and recreate Caddy with `docker compose up -d` — a reload is not enough, because the container environment changes. Existing `conf.d` files keep working on the IP.
```bash
cd /opt/stacks/caddy && grep -q "^SERVER_HOST=" .env && echo "already upgraded" || for f in .env compose.yaml Caddyfile; do cp "$f" "$f.bak"; done
```

## Caddy ports for later services

Step 3 publishes every port the guide uses, but a Caddy set up before a service was added to the guide lacks that service's port. Check each one, and add any that is missing as a line under `# Default port of the service` in `/opt/stacks/caddy/compose.yaml`, in this order:

| Service | Check | Line to add |
|---|---|---|
| Infisical (Step 5) | `grep -q '"8080:8080"' /opt/stacks/caddy/compose.yaml && echo ok` | `- "8080:8080"           # Infisical` |
| Dex (Step 6) | `grep -q '"5556:5556"' /opt/stacks/caddy/compose.yaml && echo ok` | `- "5556:5556"           # Dex` |

Then recreate Caddy (its published ports change, so a reload isn't enough):
```bash
cd /opt/stacks/caddy && docker compose up -d
```

## Outline

Part of Step 7 (Outline).

**Outline on `SERVER_IP`** (`/opt/stacks/outline/.env` has `SERVER_IP=`; do the Caddy part above first): back up the three files, change the `SERVER_IP=` line in `.env` to `SERVER_HOST=` (keep every other line — they hold your secrets), write `compose.yaml` and `conf.d/outline.caddy` again as shown in Step 7, then run its `docker compose up -d` and Caddy reload. Data is untouched. Afterwards:
- Everyone is signed out once and signs in again at `https://<SERVER_HOST>`.
- `https://<SERVER_IP>` no longer serves Outline; Outline answers on one address only.
- If you use Azure AD sign-in, add the new redirect URI (shown in Outline's `.env` in Step 7) to the app registration.
```bash
grep -q "^SERVER_IP=" /opt/stacks/outline/.env && cp /opt/stacks/outline/.env /opt/stacks/outline/.env.bak && cp /opt/stacks/outline/compose.yaml /opt/stacks/outline/compose.yaml.bak && cp /opt/stacks/caddy/conf.d/outline.caddy /opt/stacks/caddy/conf.d/outline.caddy.bak
```

**Outline running without Dex:** add the Dex lines to `.env` and the three `OIDC_*_URI` lines to `compose.yaml` as shown in Step 7, then run `docker compose up -d` in `/opt/stacks/outline`. Data is untouched.

## Grafana

Part of Step 9 (Monitoring stack). **Grafana without `grafana.ini`** (`compose.yaml` has `volumes: [grafana_data:/var/lib/grafana]` only): nothing is broken; add the file only to change Grafana's own settings. Write `/opt/stacks/grafana/grafana.ini` as shown in Step 9 first, then change the `volumes:` line in `compose.yaml` to the two lines shown there, and run `cd /opt/stacks/grafana && docker compose up -d --force-recreate grafana`. Data is untouched. Writing `compose.yaml` before the file makes Docker create an empty folder named `grafana.ini`; then remove that folder (`rmdir /opt/stacks/grafana/grafana.ini`), write the file, and recreate.

## Langfuse

Part of Step 11 (Langfuse). **Langfuse on `SERVER_IP`** (`/opt/stacks/langfuse/.env` has `SERVER_IP=`; do the Caddy part above first): back up the files, add a `SERVER_HOST=` line above the `SERVER_IP=` line in `.env` (keep every other line), write `compose.yaml` and `conf.d/langfuse.caddy` again as shown in Step 11, then run its `docker compose up -d` and Caddy reload. Data is untouched; everyone signs in again at `https://<SERVER_HOST>:9470`, and the IP address no longer serves Langfuse.
```bash
grep -q "^SERVER_IP=" /opt/stacks/langfuse/.env && cp /opt/stacks/langfuse/.env /opt/stacks/langfuse/.env.bak && cp /opt/stacks/langfuse/compose.yaml /opt/stacks/langfuse/compose.yaml.bak && cp /opt/stacks/caddy/conf.d/langfuse.caddy /opt/stacks/caddy/conf.d/langfuse.caddy.bak
```

**Langfuse API keys under the old names** (`/opt/stacks/langfuse/.env` has `LANGFUSE_INIT_PROJECT_PUBLIC_KEY=`): rename the two lines to `LANGFUSE_PUBLIC_KEY=` and `LANGFUSE_SECRET_KEY=`, keeping their values, and change the two lines in `compose.yaml` to `LANGFUSE_INIT_PROJECT_PUBLIC_KEY: ${LANGFUSE_PUBLIC_KEY}` and `LANGFUSE_INIT_PROJECT_SECRET_KEY: ${LANGFUSE_SECRET_KEY}`. Keep the values unchanged: Langfuse creates the project keys only on its first start, and LiteLLM must keep sending the same pair. With Infisical, move both keys into `prod:/shared` (and delete them from `prod:/langfuse` and `prod:/litellm`); both `.env` files already have the lines, so `pull-secrets.sh` fills them in. Then `cd /opt/stacks/langfuse && docker compose up -d`.

## Sourcebot

Part of Step 10 (Sourcebot). A Sourcebot without `config.json` or the `sourcebot_data` volume indexes nothing and loses its index on every recreate. Write all four files of Step 10 as shown there, create the new volume, and run its commands; the index rebuilds from the repos.

---

**Related:**
- Before you start (document "Self-Hosted AI Server Setup Guide")
- Access map (document "Self-Hosted AI Server Setup Guide")
- Step 2: Shared network, settings (document "Self-Hosted AI Server Setup Guide")
- Step 3: Caddy (reverse proxy) (document "Self-Hosted AI Server Setup Guide") → Install
- Step 5: Infisical (secrets) (document "Self-Hosted AI Server Setup Guide") → Install
- Step 6: Dex (sign-in) (document "Self-Hosted AI Server Setup Guide") → Install
- Step 7: Outline (wiki) (document "Self-Hosted AI Server Setup Guide") → Install
- Step 9: Monitoring stack (document "Self-Hosted AI Server Setup Guide") → Install
- Step 10: Sourcebot (code search) (document "Self-Hosted AI Server Setup Guide") → Install
- Step 11: Langfuse (LLM tracing) (document "Self-Hosted AI Server Setup Guide") → Install
