## Step 5: Infisical (secrets)

Keeps every stack's secrets (passwords, keys, tokens) in one place, with a web UI and version history, instead of spread over `.env` files. The free, self-hosted version is all this needs: storing secrets, folders, versions, and the CLI have no user or identity limit. Paid-only features (SSO, audit logs, custom roles, rotation) aren't used.

How it fits: each later step still shows its `.env` — with Infisical, that block is the list of keys to create in Infisical, and `pull-secrets.sh` writes the file. Compose, `update-stack.sh`, and the stacks themselves don't change and never talk to Infisical; if Infisical is down, everything keeps running on the last `.env` it wrote. Skip this step to write every `.env` by hand.

**Two kinds of folders.** From here on, the guide writes a folder *in Infisical* as `prod:/<name>`: environment Production, folder `<name>`, as Infisical shows it (Production → `outline`). A folder *on the server* is always written in full, starting with `/opt/`. They often share a name, but are different things:

| | Server folder | Infisical folder |
|---|---|---|
| Example | `/opt/stacks/outline/` | `prod:/outline` |
| Holds | `compose.yaml`, `.env`, config files | Secrets: keys and values |
| You edit it with | An editor on the server (`nano`) | Infisical's web UI |
| Link between them | `pull-secrets.sh` copies `prod:/shared` + `prod:/<stack>` into `/opt/stacks/<stack>/.env` | |

So `prod:/infisical` holds optional secrets for Infisical itself (e.g. `SMTP_*`), while `/opt/stacks/infisical/` holds its compose file, `.env`, `pull.env`, and `pull-secrets.sh`.

**Check:** `infisical`, `infisical-postgres`, `infisical-redis`.

### Clean reinstall

Removes Infisical as if it had never been installed. Skip it for a first install. **Every secret stored in Infisical is lost** with its volumes, unless you have a backup (`backup-config.sh` keeps the database and `.env`). The stacks keep running on the `.env` files `pull-secrets.sh` already wrote. Each line asks first.
```bash
confirm "Stop and remove the Infisical containers?" && cd /opt/stacks/infisical && docker compose down; cd ~
confirm "Delete all secrets, users, and settings (volumes infisical_pg_data, infisical_redis_data)?" && docker volume rm infisical_pg_data infisical_redis_data
confirm "Delete /opt/stacks/infisical (.env with the encryption key, pull.env, the pull-secrets.sh link)?" && rm -rf /opt/stacks/infisical
confirm "Delete its Caddy file (infisical.caddy)?" && rm -f /opt/stacks/caddy/conf.d/infisical.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the Infisical image (downloaded again on the next install)?" && docker image rm infisical/infisical:latest
```

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -E '^infisical(-postgres|-redis)?$'
docker volume ls -q | grep -E '^infisical_'
ls -d /opt/stacks/infisical /opt/stacks/caddy/conf.d/infisical.caddy 2>/dev/null
```

### Install

**Caddy set up before Infisical was in this guide?** Add its port first: [Upgrading an older install](options/upgrade-older-install.md#caddy-ports-for-later-services).

```bash
mkdir -p /opt/stacks/infisical
```

`/opt/stacks/infisical/.env` — the one `.env` that stays hand-written, since Infisical needs it to start:
```env
SERVER_HOST=<from /opt/stacks/shared/.env>
# Read before Infisical starts
INFISICAL_DB_PASSWORD=<openssl rand -hex 24>
INFISICAL_ENCRYPTION_KEY=<openssl rand -hex 16>   # -hex 16: exactly 32 characters
INFISICAL_AUTH_SECRET=<openssl rand -base64 32>
# Optional email (see the guide option: email for all services); with Infisical these come from prod:/shared
# SMTP_HOST=smtp.gmail.com
# SMTP_PORT=587
# SMTP_USERNAME=<the dedicated gmail address>
# SMTP_PASSWORD=<16-character app password>
# Optional Google sign-in (see the guide option: Google sign-in); needs SERVER_HOST under a real domain.
# The same Google client and names as Dex; with Infisical these come from prod:/shared
# GOOGLE_CLIENT_ID=<Google client ID>
# GOOGLE_CLIENT_SECRET=<Google client secret>
```
**Back up this file somewhere off the server** (a password manager is fine). `INFISICAL_ENCRYPTION_KEY` encrypts every secret; without it, a restored database is unreadable.

**Why this `.env` is different from every other stack's.** `pull-secrets.sh` treats three kinds of `.env` differently:

| | `shared` | `infisical` | Other stacks (with a folder in Infisical) |
|---|---|---|---|
| File | `/opt/stacks/shared/.env` | `/opt/stacks/infisical/.env` | `/opt/stacks/<stack>/.env` |
| Source of truth | Infisical folder `prod:/shared` | Infisical folders `prod:/shared` + `prod:/infisical`, except the three start keys: this file | Infisical folders `prod:/shared` + `prod:/<stack>` |
| Can every key live in Infisical? | Yes | No: `INFISICAL_DB_PASSWORD`, `INFISICAL_ENCRYPTION_KEY`, and `INFISICAL_AUTH_SECRET` are read before Infisical starts | Yes |
| A key that is not in Infisical | Kept, listed in a NOTICE (`--ask-remove` or `--force-remove` removes it) | The same, except the three start keys: always kept, never shown | Kept, listed in a NOTICE (`--ask-remove` or `--force-remove` removes it) |
| How `pull-secrets.sh` writes it | Matches it to `prod:/shared` | Matches it to `prod:/shared` + `prod:/infisical`; never takes, changes, or removes the three start keys because of Infisical | Matches it to `prod:/shared` + `prod:/<stack>` |
| After a change | Nothing to recreate; the other stacks get the new values | Infisical is recreated | The stack is recreated (only the services that were running) |

A stack with no folder in Infisical, `infisical` included, keeps its hand-written `.env`; `sync-shared-env.sh`, which `pull-secrets.sh` runs at the end, updates only its `SERVER_HOST` / `SERVER_IP`.

Keeping the start keys in Infisical as well would not help: the encryption key would sit inside the vault it unlocks, and a rebuild would need Infisical running to fetch the keys that start it. That is why `pull-secrets.sh` ignores the start keys in Infisical: if Infisical holds one with a different value, it only prints a NOTICE. Edit them only in this file.

**Never delete this file.** If it is lost while Infisical still runs, the values are still in the containers: `docker inspect infisical --format '{{range .Config.Env}}{{println .}}{{end}}'` (`ENCRYPTION_KEY`, `AUTH_SECRET`) and the same for `infisical-postgres` (`POSTGRES_PASSWORD`). Write the file again before any `docker compose up -d` here.

`/opt/stacks/infisical/compose.yaml`:
```yaml
services:
  infisical-postgres:
    image: postgres:17
    container_name: infisical-postgres
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: ${INFISICAL_DB_PASSWORD}
      POSTGRES_DB: infisical
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 30s          # once healthy; fast checks only while starting:
      start_period: 60s
      start_interval: 3s
      timeout: 5s
      retries: 10
    volumes: [infisical_pg_data:/var/lib/postgresql/data]
    networks: [default]

  infisical-redis:
    image: redis:7
    container_name: infisical-redis
    restart: unless-stopped
    volumes: [infisical_redis_data:/data]
    networks: [default]

  infisical:
    image: infisical/infisical:latest
    container_name: infisical
    restart: unless-stopped
    environment:
      NODE_ENV: production
      SITE_URL: https://${SERVER_HOST}:8080
      ENCRYPTION_KEY: ${INFISICAL_ENCRYPTION_KEY}
      AUTH_SECRET: ${INFISICAL_AUTH_SECRET}
      DB_CONNECTION_URI: postgres://postgres:${INFISICAL_DB_PASSWORD}@infisical-postgres:5432/infisical
      REDIS_URL: redis://infisical-redis:6379
      TELEMETRY_ENABLED: "false"
      # Email: off while SMTP_HOST is empty
      SMTP_HOST: ${SMTP_HOST:-}
      SMTP_PORT: ${SMTP_PORT:-587}
      SMTP_USERNAME: ${SMTP_USERNAME:-}
      SMTP_PASSWORD: ${SMTP_PASSWORD:-}
      SMTP_FROM_ADDRESS: ${SMTP_USERNAME:-}
      SMTP_FROM_NAME: AI Server
      # Google sign-in: off while GOOGLE_CLIENT_ID is empty. Infisical reads its own names;
      # .env uses the same names as Dex, so one value serves both.
      CLIENT_ID_GOOGLE_LOGIN: ${GOOGLE_CLIENT_ID:-}
      CLIENT_SECRET_GOOGLE_LOGIN: ${GOOGLE_CLIENT_SECRET:-}
    depends_on:
      infisical-postgres: { condition: service_healthy }
      infisical-redis: { condition: service_started }
    networks: [default, edge]

networks:
  default:
    driver_opts:
      com.docker.network.bridge.name: br-infisical
  edge:
    external: true

volumes:
  infisical_pg_data:
    external: true
  infisical_redis_data:
    external: true
```
```bash
docker volume create infisical_pg_data
docker volume create infisical_redis_data

cd /opt/stacks/infisical && docker compose up -d
```

```bash
cat > /opt/stacks/caddy/conf.d/infisical.caddy <<'EOF'
https://{$SERVER_HOST}:8080 {
	tls internal
	reverse_proxy infisical:8080
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
Like Outline, Infisical answers on `SERVER_HOST` only: its `SITE_URL` is one fixed address. The first start runs database migrations; give it a minute (`docker logs -f infisical`).

**Check the result.** Every line must match the table:
```bash
docker inspect -f '{{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}' infisical infisical-postgres infisical-redis
docker inspect -f '{{.Name}}  networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' infisical infisical-postgres infisical-redis
docker inspect -f '{{.Name}}  health={{.State.Health.Status}}' infisical-postgres infisical-redis
docker inspect -f '{{.Name}}{{range .Mounts}}  {{.Destination}} <- {{.Name}}{{end}}' infisical-postgres infisical-redis
docker exec infisical sh -c 'echo "ENCRYPTION_KEY: ${#ENCRYPTION_KEY} characters, AUTH_SECRET: ${#AUTH_SECRET} characters, SITE_URL: $SITE_URL"'
curl -sv https://${SERVER_HOST}:8080 -o /dev/null 2>&1 | grep -E "issuer:|HTTP/"
```

| Line | Expected |
|---|---|
| state | all three `running`, `restart=unless-stopped`; images `infisical/infisical:latest`, `postgres:17`, `redis:7` |
| networks | `infisical`: `edge infisical_default`; the other two: `infisical_default` only (the databases stay off `edge`) |
| health | `healthy` for both |
| mounts | `/var/lib/postgresql/data <- infisical_pg_data`, `/data <- infisical_redis_data` |
| environment | `ENCRYPTION_KEY: 32 characters`, `AUTH_SECRET: 44 characters`, `SITE_URL: https://<SERVER_HOST>:8080` |
| `curl` | `issuer: CN=Caddy Local Authority …` and `HTTP/2 200` |

**Verify:** `https://<SERVER_HOST>:8080` loads with a trusted padlock.

### Authentication

Infisical keeps its own login: email and password, and the first account is the server admin.

**Google Account** (free): a **Continue with Google** button, turned on with the `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` lines in `.env` (the same names and values as Dex). A Google sign-in with the same email opens the same Infisical account. See [Google sign-in](options/google-sign-in.md). Dex and Azure would need Infisical's SAML/OIDC sign-in, which is 💲 paid, so Infisical takes Google directly.

### Usage

**Set up the project** at `https://<SERVER_HOST>:8080`:
1. Create the first account — it becomes the server admin. No email is sent; Infisical runs without SMTP. Inviting more people without SMTP should give you an invite link to pass on yourself; for invites by email, turn on [Email (SMTP)](options/smtp-email.md).
2. Create a project: **Secrets Management** → **+ Add New Project**, **Project Name** e.g. `ai-server`, then **Create Project**. It comes with three environments, Development, Staging, and Production; this guide uses only **Production** (its slug, `prod`, is what `pull.env` names).
3. Open **Production** in the project. Create a folder named **`shared`**, i.e. `prod:/shared` (the add menu next to **+ Add a New Secret** → **Add Folder**), open it, and add `SERVER_HOST` and `SERVER_IP` with **+ Add a New Secret**, using the same values as `/opt/stacks/shared/.env`.
4. Create one folder per stack, named exactly like its server folder under `/opt/stacks/` (`prod:/dex`, `prod:/outline`, `prod:/grafana`, `prod:/langfuse`, …), each holding the keys that step's `.env` shows — except `SERVER_HOST` / `SERVER_IP`, which come from `prod:/shared`. A key in a stack folder wins over `prod:/shared` for that stack, so a copy there would stop later `prod:/shared` changes from reaching it; `pull-secrets.sh` prints a NOTICE when the two differ. For a stack that already has a `.env`, drag the file onto the folder page (or use **Paste Secrets**), set **Target Environments** to Production, and select **Upload Secrets**; then delete those two keys there. A stack with no folder keeps its hand-written `.env`.
5. Organization → Access Control → **Identities** → create an identity (e.g. `ai-server-pull`, organization role Member), open it, add **Universal Auth**, and create a client secret. Then in the project → Access Control → Identities, add it with the **Viewer** role (read-only).
6. Copy the project ID from the project settings.

`/opt/stacks/infisical/pull.env` — the machine login for `pull-secrets.sh`:
```env
INFISICAL_CLIENT_ID=<Universal Auth client ID>
INFISICAL_CLIENT_SECRET=<Universal Auth client secret>
INFISICAL_PROJECT_ID=<project ID>
INFISICAL_ENV=prod
```
```bash
chmod 600 /opt/stacks/infisical/.env /opt/stacks/infisical/pull.env
```

Link `pull-secrets.sh` from `~/ai-server` into the folder ([Helper scripts](options/helper-scripts.md)), then preview:
```bash
ln -sf ~/ai-server/pull-secrets.sh /opt/stacks/infisical/pull-secrets.sh
/opt/stacks/infisical/pull-secrets.sh --dry-run
```
The dry run lists, per stack, which keys would be added, changed, or removed — names only, never values. The `.env` of a stack with a folder in Infisical is matched to `prod:/shared` and that folder, and `/opt/stacks/shared/.env` to `prod:/shared`. Keys from `prod:/shared` only update a `.env` that already has them and are never added to it (a new `.env` gets them all). Each file is edited in place: line order, comments, and blank lines stay; a changed value is replaced on its own line (an inline comment after it stays); new keys are added at the end under `# Added by pull-secrets.sh from Infisical`. **`REMOVED` means the key is in the current `.env` but not in Infisical.** By default such keys are kept where they are and only listed in a NOTICE, on every run until you add them to Infisical or remove them. To remove them, `--ask-remove` asks about each one (`Remove GRAFANA_SSO from grafana/.env? [y/N]`; `y` deletes only that line, anything else keeps it), and `--force-remove` removes them all without asking. Infisical's own `.env` follows the same rule, except its three start keys: they are always kept from the file and never shown. When the list looks right, run it without `--dry-run`: it asks first (one `[y/N]` for everything, after any `--ask-remove` questions), saves each old file as `.env.bak-<timestamp>`, writes the edited `.env` (mode 600), and recreates only the stacks that changed (in `llm-runtime` and `graphdb`, only what was running). It also writes `/opt/stacks/shared/.env` from `prod:/shared`.

**Unexpected result** (e.g. "Nothing to do" although you changed a secret)? Add `--debug`: it explains each step — the `pull.env` it read, the login, every folder and its key names, and why a stack was skipped — without printing any secret value, so the output is safe to share:
```bash
/opt/stacks/infisical/pull-secrets.sh --dry-run --debug 2>&1 | tee /tmp/pull-debug.txt
```
Add `--stack <name>` (or several, `--stack outline,grafana`) to look at only those stacks. The Infisical environment is `INFISICAL_ENV` in `pull.env` (`prod` when left out); `--env <slug>` reads another one for a single run, e.g. `--env staging --dry-run`. It writes the same `.env` files, so try it with `--dry-run` first.

**From here on, with Infisical:** when a step shows a `.env`, create those keys in Infisical under `prod:/<stack>` instead, run `/opt/stacks/infisical/pull-secrets.sh <stack>`, then continue with the step's `docker compose up -d`. To change a secret later — or `SERVER_HOST` / `SERVER_IP` in `prod:/shared` — edit it in Infisical and run `pull-secrets.sh`. When `prod:/shared` changed, it then runs `/opt/stacks/shared/sync-shared-env.sh` by itself, so stacks without a folder in Infisical get the new `SERVER_HOST` / `SERVER_IP` too (stacks it already wrote match and stay untouched). Every stack whose `.env` changes is recreated (a restart would keep the old values), so a `prod:/shared` change recreates nearly everything, Caddy included: expect a short interruption.

Plain values are written as is (`SMTP_PORT=587`). A value with any other character — `$`, `#`, a space, `?`, and so on — is written in single quotes (`KEY='value'`), which Compose reads literally. A value must not contain a single quote itself. **Infisical references** work in values: `${prod.shared.SMTP_USERNAME}` arrives as that key's value, because `pull-secrets.sh` reads with Infisical's default `--expand=true`. Infisical may treat any other `$` in a value as a variable too, so keep `$` out of passwords stored in Infisical (generated secrets from `openssl rand -hex` never contain it).

**Option:** [Sync to Azure Key Vault](options/infisical-azure-key-vault.md) — Infisical copies a folder's secrets into a key vault and keeps them updated (free in self-hosted Infisical).

**Verify:** `/opt/stacks/infisical/pull-secrets.sh --dry-run` prints either "Nothing to do" or the list above, not a login error.

### Test

1. **Sign-in:** `https://<SERVER_HOST>:8080` opens with a padlock; you sign in as the admin (and with Google, if turned on).
2. **The machine login:** `/opt/stacks/infisical/pull-secrets.sh --dry-run` prints "Nothing to do" or a list of keys, not a login error.
3. **A secret reaches a stack, without changing it:** add a key `PULL_TEST=1` to `prod:/shared` in Infisical, add an empty `PULL_TEST=` line to `/opt/stacks/caddy/.env`, and run `pull-secrets.sh --stack caddy --dry-run`: it lists `changed: PULL_TEST`. Delete the key in Infisical and the line from the file.

