*Copied from `options/openhands-test.md` in the ai-server repo; import it as a document named "Option: Testing OpenHands".*

Part of Step 16: OpenHands (agent) (document "Self-Hosted AI Server Setup Guide"). What each failure in the three checks of its Test part means, and how to fix it. Most come from one fact: OpenHands runs every conversation in a separate sandbox container (`oh-agent-server-…`) that it starts on the host Docker, on Docker's default network and on a random host port.

## Check 1: key, network, model

| Result | Cause | Fix |
|---|---|---|
| `OK: …` | Works | — |
| `401` | The key in `LLM_API_KEY` is not valid in LiteLLM (deleted, mistyped, from another LiteLLM) | Create a new key (Install, step 1), put it in `.env` or `prod:/openhands`, recreate OpenHands |
| `401` naming "not allowed to access model" | The key may not use `local-model` | LiteLLM Admin UI → Virtual Keys → `openhands` → Edit → Models |
| `KeyError: 'LLM_API_KEY'` | The container has no such variable | Check `compose.yaml` (`LLM_API_KEY: ${LLM_API_KEY}`) and `.env`, then `docker compose up -d --force-recreate` |
| `Name or service not known` | OpenHands is not on `edge` | `networks: [edge]` in `compose.yaml` |
| `500` or a timeout | The key works; the model behind LiteLLM does not answer | `/opt/stacks/llm-runtime/switch-llm.sh status` |

Check the key's length and prefix without showing it (25 characters, `sk-`):
```bash
docker exec openhands sh -c 'echo ${#LLM_API_KEY} characters, starts with ${LLM_API_KEY%"${LLM_API_KEY#???}"}'
```
`403` from LiteLLM's `/key/info` with this key is normal: an LLM-only key may call models but not the key endpoints.

## Check 2: chat answer

| Symptom | Cause | Fix |
|---|---|---|
| `ERR_SSL_PROTOCOL_ERROR` opening the page | Opened by name: HSTS from `https://<SERVER_HOST>` forces HTTPS on every port | Open `http://<SERVER_IP>:3000` |
| "Settings not found" | Nothing saved yet (first start) | Fill in the Advanced settings and Save |
| Settings gone after a reload | OpenHands cannot write `/.openhands` | `docker inspect openhands --format '{{range .Mounts}}{{.Destination}} <- {{.Name}}{{println}}{{end}}'` must list `/.openhands <- openhands_state` |
| `401` in the chat | The API Key in OpenHands' settings differs from the working one | Paste the `openhands` key into Settings → LLM |

## Check 3: task in a sandbox

| Symptom | Cause | Fix |
|---|---|---|
| `500: Sandbox entered error state: oh-agent-server-…` | OpenHands cannot reach the sandbox through `host.docker.internal` | `extra_hosts: ["host.docker.internal:host-gateway"]` in `compose.yaml`, recreate, start a new conversation |
| "Network Error"; F12 → Network shows `wss://<SERVER_HOST>:<port>/sockets/events/…` failing | The browser cannot open the sandbox port: HTTPS page, or the name instead of the IP | Open OpenHands by `http://<SERVER_IP>:3000`; `OH_SANDBOX_CONTAINER_URL_PATTERN: http://${SERVER_IP}:{port}` |
| Fails on `ws://<SERVER_IP>:<port>/…` | A firewall blocks the random sandbox ports | From the PC: `Test-NetConnection <SERVER_IP> -Port <port>`; allow the ports on the server firewall |
| Hangs at "Starting runtime" for minutes | The sandbox image is still downloading (first task), or OpenHands cannot use the Docker socket | `docker logs openhands 2>&1 \| tail -40` |
| "MCP Connection Failure" | An MCP server the sandbox cannot reach (see Connecting tools (MCP) in the step), or OpenHands' own built-in MCP (a known OpenHands issue) | Tasks still run; remove or change the MCP server |

After a fix that changes `compose.yaml`, remove the old sandboxes and start a **new** conversation; an old one stays bound to its failed sandbox:
```bash
confirm "Remove OpenHands sandbox containers?" && docker ps -aq --filter name=oh-agent-server | xargs -r docker rm -f
```

Logs to look at:
```bash
docker logs openhands 2>&1 | grep -i -E "sandbox|agent-server|error|refused|timeout" | tail -30
docker ps -aq --filter name=oh-agent-server | head -1 | xargs -r -I{} sh -c "docker logs {} 2>&1 | tail -30"
```

---

**Related:**
- Step 16: OpenHands (agent) (document "Self-Hosted AI Server Setup Guide") → Test
