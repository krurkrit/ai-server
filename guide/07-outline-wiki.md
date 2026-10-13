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

