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

