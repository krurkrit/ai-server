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

