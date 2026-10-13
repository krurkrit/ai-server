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

