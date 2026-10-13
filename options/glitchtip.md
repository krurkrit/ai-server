# Option: App error tracking (GlitchTip)

Part of [Step 18: CI runner (GitHub)](../ai-server-setup-guide.md#step-18-ci-runner-github) and [AI setup for software development](../ai-setup-for-software-development.md). Collects the errors of the applications you build (exceptions with stack traces, from browser and server code) in one place, with email alerts. GlitchTip uses the Sentry SDKs, so apps report with the usual Sentry library and a GlitchTip address; it is a light, free alternative to self-hosted Sentry (which needs about 16 GB of RAM). About 0.5–1 GB of RAM in all, near-zero CPU at rest. Port 9475 (Caddy's shared block), sign-in through Dex.

**When to set it up.** Apps that already report to Sentry (cloud) or another error tracker keep it; nothing here replaces it. Use this page for new apps, or when you want errors on the server instead: because the SDK is the same, moving an app is a change of DSN only, and an app can report to both during a trial.

## Set it up

1. **Dex client.** In `/opt/stacks/dex/.env` add `GLITCHTIP_OIDC_SECRET=<openssl rand -hex 32>`; in `/opt/stacks/dex/config.yaml` under `staticClients:`:
   ```yaml
     - id: glitchtip
       name: GlitchTip
       secretEnv: GLITCHTIP_OIDC_SECRET
       redirectURIs:
         - https://{{ getenv "SERVER_HOST" }}:9475/accounts/dex/login/callback/
   ```
   and `GLITCHTIP_OIDC_SECRET: ${GLITCHTIP_OIDC_SECRET}` under `environment:` in its `compose.yaml`; then `cd /opt/stacks/dex && docker compose up -d --force-recreate dex`.
2. **Folder, volume, files:**
   ```bash
   mkdir -p /opt/stacks/glitchtip
   docker volume create glitchtip_pg_data
   docker volume create glitchtip_uploads
   cat /etc/ssl/certs/ca-certificates.crt /opt/stacks/caddy/caddy-root-ca.crt > /opt/stacks/glitchtip/ca-bundle.crt
   ```
   `/opt/stacks/glitchtip/.env` (with Infisical, `prod:/glitchtip`; the `SMTP_*` lines come from `prod:/shared`):
   ```env
   SERVER_HOST=<from /opt/stacks/shared/.env>
   SERVER_IP=<from /opt/stacks/shared/.env>
   GLITCHTIP_DB_PASSWORD=CHANGE_ME
   GLITCHTIP_SECRET_KEY=<openssl rand -hex 32>
   SMTP_HOST=smtp.gmail.com
   SMTP_PORT=587
   SMTP_USERNAME=<the dedicated gmail address>
   SMTP_PASSWORD=<16-character app password>
   ```
   `/opt/stacks/glitchtip/compose.yaml` (compare with GlitchTip's current `compose.sample.yml`; its worker command has changed between versions):
   ```yaml
   x-glitchtip: &glitchtip
     image: glitchtip/glitchtip:6
     restart: unless-stopped
     environment:
       GLITCHTIP_DOMAIN: https://${SERVER_HOST}:9475
       SECRET_KEY: ${GLITCHTIP_SECRET_KEY}
       DATABASE_URL: postgres://postgres:${GLITCHTIP_DB_PASSWORD}@glitchtip-postgres:5432/postgres
       VALKEY_URL: redis://glitchtip-redis:6379
       REDIS_URL: redis://glitchtip-redis:6379
       EMAIL_URL: smtp://${SMTP_USERNAME}:${SMTP_PASSWORD}@${SMTP_HOST}:${SMTP_PORT}/?tls=True
       DEFAULT_FROM_EMAIL: ${SMTP_USERNAME}
       ENABLE_USER_REGISTRATION: "false"           # the first account still gets made; the rest sign in through Dex
       ENABLE_SOCIAL_APPS_USER_REGISTRATION: "true"
       # Sign-in through Dex: the server name inside the container, and trust in the internal CA
       SSL_CERT_FILE: /certs/ca-bundle.crt
       REQUESTS_CA_BUNDLE: /certs/ca-bundle.crt
     extra_hosts:
       - "${SERVER_HOST}:${SERVER_IP}"
     volumes:
       - glitchtip_uploads:/code/uploads
       - ./ca-bundle.crt:/certs/ca-bundle.crt:ro
     depends_on:
       glitchtip-postgres: { condition: service_healthy }
       glitchtip-redis: { condition: service_healthy }

   services:
     glitchtip-postgres:
       image: postgres:17
       container_name: glitchtip-postgres
       restart: unless-stopped
       environment:
         POSTGRES_PASSWORD: ${GLITCHTIP_DB_PASSWORD}
       healthcheck:
         test: ["CMD-SHELL", "pg_isready -U postgres"]
         interval: 30s
         start_period: 60s
         start_interval: 3s
         timeout: 5s
         retries: 10
       volumes: [glitchtip_pg_data:/var/lib/postgresql/data]
       networks: [default]

     glitchtip-redis:
       image: redis:7
       container_name: glitchtip-redis
       restart: unless-stopped
       healthcheck:
         test: ["CMD", "redis-cli", "ping"]
         interval: 30s
         start_period: 60s
         start_interval: 3s
         timeout: 10s
         retries: 10
       networks: [default]

     glitchtip:
       <<: *glitchtip
       container_name: glitchtip
       networks: [default, edge]

     glitchtip-worker:
       <<: *glitchtip
       container_name: glitchtip-worker
       command: ./bin/run-worker.sh
       networks: [default]

   networks:
     default:
       driver_opts:
         com.docker.network.bridge.name: br-glitchtip
     edge:
       external: true

   volumes:
     glitchtip_pg_data:
       external: true
     glitchtip_uploads:
       external: true
   ```
3. **Start and route it:**
   ```bash
   cd /opt/stacks/glitchtip && docker compose up -d
   cat > /opt/stacks/caddy/conf.d/glitchtip.caddy <<'EOF'
   https://{$SERVER_HOST}:9475 {
   	tls internal
   	reverse_proxy glitchtip:8000
   }
   EOF
   docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
   ```
4. **First account and Dex.** Make the admin account, then add Dex as a sign-in:
   ```bash
   docker exec -it glitchtip ./manage.py createsuperuser
   ```
   Sign in at `https://<SERVER_HOST>:9475/admin/` → **Social applications** → **Add**: Provider **OpenID Connect**, Provider ID `dex`, Name `Dex`, Client ID `glitchtip`, Secret key = `GLITCHTIP_OIDC_SECRET`, Settings `{"server_url": "https://<SERVER_HOST>:5556/dex"}`, add the site, **Save**. The sign-in page now shows **Dex**.

## Use it in an app

In GlitchTip: create an organization and a project; its settings show a **DSN**. In the app, install the Sentry SDK for its language and set that DSN, e.g. .NET `SentrySdk.Init(o => o.Dsn = "<DSN>")`, JavaScript `Sentry.init({ dsn: "<DSN>" })`. The app must trust the internal CA (browsers with the Step 4 import do; a server app in a container needs the CA file, as GlitchTip itself above). Errors appear within seconds; set alerts per project (email through the SMTP lines).

## Check

```bash
docker ps --filter name=glitchtip --format '{{.Names}}  {{.Status}}'
curl -s -o /dev/null -w "%{http_code}\n" https://${SERVER_HOST}:9475/_health/
docker exec glitchtip python3 -c "import urllib.request; print('Dex:', urllib.request.urlopen('https://${SERVER_HOST}:5556/dex/.well-known/openid-configuration').status)"
```
All four containers `Up` (`glitchtip`, `glitchtip-worker`, `glitchtip-postgres`, `glitchtip-redis`); `200` twice. Then send a test event: in a project, **Settings → Install** shows a one-line test; or from a Python shell with `sentry-sdk` installed, `sentry_sdk.init("<DSN>"); 1/0` — the error shows in the project.

## Remove

```bash
confirm "Stop and remove GlitchTip?" && cd /opt/stacks/glitchtip && docker compose down; cd ~
confirm "Delete all GlitchTip data (volumes glitchtip_pg_data, glitchtip_uploads)?" && docker volume rm glitchtip_pg_data glitchtip_uploads
confirm "Delete the folder and its Caddy file?" && rm -rf /opt/stacks/glitchtip /opt/stacks/caddy/conf.d/glitchtip.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
Then remove the `glitchtip` client from Dex.

---

**Related:**
- [Step 18: CI runner (GitHub)](../ai-server-setup-guide.md#step-18-ci-runner-github) → Usage
