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

