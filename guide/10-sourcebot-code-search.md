## Step 10: Sourcebot (code search)

**Check:** `sourcebot`, `sourcebot-postgres`, `sourcebot-redis`.

### Clean reinstall

Removes Sourcebot as if it had never been installed. Skip it for a first install. Its users, settings, and search index are lost with the volumes; the index rebuilds from the repositories on the next install. Each line asks first.
```bash
confirm "Stop and remove the Sourcebot containers?" && cd /opt/stacks/sourcebot && docker compose down; cd ~
confirm "Delete users, settings, and the index (volumes sourcebot_pg_data, sourcebot_redis_data, sourcebot_data)?" && docker volume rm sourcebot_pg_data sourcebot_redis_data sourcebot_data
confirm "Delete /opt/stacks/sourcebot (.env, config.json) and its Caddy file?" && rm -rf /opt/stacks/sourcebot /opt/stacks/caddy/conf.d/sourcebot.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the Sourcebot image (downloaded again on the next install)?" && docker image rm docker.sourcebot.dev/sourcebot-dev/sourcebot:latest
```
Revoke its GitHub token on GitHub if Sourcebot is gone for good.

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -E '^sourcebot(-postgres|-redis)?$'
docker volume ls -q | grep -E '^sourcebot_'
ls -d /opt/stacks/sourcebot /opt/stacks/caddy/conf.d/sourcebot.caddy 2>/dev/null
```

### Install

**Older install?** See [Upgrading an older install](options/upgrade-older-install.md#sourcebot) (no `config.json` or `sourcebot_data` volume).

```bash
mkdir -p /opt/stacks/sourcebot
```

`/opt/stacks/sourcebot/.env`:
```env
SERVER_HOST=<from /opt/stacks/shared/.env>
SOURCEBOT_DB_PASSWORD=<openssl rand -hex 24>
SOURCEBOT_AUTH_SECRET=<openssl rand -base64 33>
SOURCEBOT_ENCRYPTION_KEY=<openssl rand -base64 24>
GITHUB_TOKEN=<read-only token for the repos to index; leave empty for public repos only>
```

`/opt/stacks/sourcebot/config.json` — the repositories to index:
```json
{
  "$schema": "https://raw.githubusercontent.com/sourcebot-dev/sourcebot/main/schemas/v3/index.json",
  "connections": {
    "github": {
      "type": "github",
      "repos": ["<owner>/<repo>"],
      "token": { "env": "GITHUB_TOKEN" }
    }
  }
}
```
List repositories under `repos`, or index whole accounts with `"orgs": ["<org>"]` / `"users": ["<user>"]`. GitLab, Gitea, Bitbucket, and plain Git URLs work the same way with their own `type` (see Sourcebot's docs). Sourcebot re-reads this file on its own, so adding a repo later needs no restart.

`/opt/stacks/sourcebot/compose.yaml` (Sourcebot's official compose, with this guide's conventions):
```yaml
services:
  sourcebot-postgres:
    image: postgres:17
    container_name: sourcebot-postgres
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: ${SOURCEBOT_DB_PASSWORD}
      POSTGRES_DB: sourcebot
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 30s          # once healthy; fast checks only while starting:
      start_period: 60s
      start_interval: 3s
      timeout: 3s
      retries: 10
    volumes: [sourcebot_pg_data:/var/lib/postgresql/data]
    networks: [default]

  sourcebot-redis:
    image: redis:7
    container_name: sourcebot-redis
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 30s          # once healthy; fast checks only while starting:
      start_period: 60s
      start_interval: 3s
      timeout: 10s
      retries: 10
    volumes: [sourcebot_redis_data:/data]
    networks: [default]

  sourcebot:
    image: docker.sourcebot.dev/sourcebot-dev/sourcebot:latest
    container_name: sourcebot
    restart: unless-stopped
    environment:
      CONFIG_PATH: /data/config.json
      AUTH_URL: https://${SERVER_HOST}:9460
      AUTH_SECRET: ${SOURCEBOT_AUTH_SECRET}
      SOURCEBOT_ENCRYPTION_KEY: ${SOURCEBOT_ENCRYPTION_KEY}
      DATABASE_URL: postgresql://postgres:${SOURCEBOT_DB_PASSWORD}@sourcebot-postgres:5432/sourcebot
      REDIS_URL: redis://sourcebot-redis:6379
      GITHUB_TOKEN: ${GITHUB_TOKEN:-}
    volumes:
      - ./config.json:/data/config.json:ro
      - sourcebot_data:/data          # search index and cloned repos
    depends_on:
      sourcebot-postgres: { condition: service_healthy }
      sourcebot-redis: { condition: service_healthy }
    networks: [default, edge]

networks:
  default:
    driver_opts:
      com.docker.network.bridge.name: br-sourcebot
  edge:
    external: true

volumes:
  sourcebot_pg_data:
    external: true
  sourcebot_redis_data:
    external: true
  sourcebot_data:
    external: true
```
```bash
docker volume create sourcebot_pg_data
docker volume create sourcebot_redis_data
docker volume create sourcebot_data

cd /opt/stacks/sourcebot && docker compose up -d
```
```bash
cat > /opt/stacks/caddy/conf.d/sourcebot.caddy <<'EOF'
https://{$SERVER_HOST}:9460 {
	tls internal
	reverse_proxy sourcebot:3000
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
Sourcebot answers on `SERVER_HOST` only: its `AUTH_URL` is one fixed address.

**Check the result.** Every line must match the table:
```bash
docker inspect -f '{{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}' sourcebot sourcebot-postgres sourcebot-redis
docker inspect -f '{{.Name}}  networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' sourcebot sourcebot-postgres sourcebot-redis
docker inspect -f '{{.Name}}  health={{.State.Health.Status}}' sourcebot-postgres sourcebot-redis
docker inspect -f '{{.Name}}{{range .Mounts}}  {{.Destination}} <- {{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}}{{end}}' sourcebot sourcebot-postgres sourcebot-redis
docker exec sourcebot sh -c 'echo "AUTH_SECRET: ${#AUTH_SECRET} characters, encryption key: ${#SOURCEBOT_ENCRYPTION_KEY} characters, GitHub token: ${#GITHUB_TOKEN} characters, AUTH_URL: $AUTH_URL"'
curl -sv https://${SERVER_HOST}:9460 -o /dev/null 2>&1 | grep -E "issuer:|HTTP/"
```

| Line | Expected |
|---|---|
| state | all three `running`, `restart=unless-stopped`; images `sourcebot-dev/sourcebot:latest`, `postgres:17`, `redis:7` |
| networks | `sourcebot`: `edge sourcebot_default`; the other two: `sourcebot_default` only |
| health | `healthy` for both |
| mounts | `sourcebot`: `/data/config.json <- /opt/stacks/sourcebot/config.json` and `/data <- sourcebot_data`; `sourcebot_pg_data`, `sourcebot_redis_data` on the other two |
| environment | `AUTH_SECRET: 44 characters`, `encryption key: 32 characters`, a GitHub token length (0 only for public repositories), `AUTH_URL: https://<SERVER_HOST>:9460` |
| `curl` | `issuer: CN=Caddy Local Authority …` and `HTTP/2 200` (or a `30x` redirect) |

**Verify:** `https://<SERVER_HOST>:9460` loads; create the owner account on first visit.

### Authentication

Sourcebot keeps its own login: email and password, with the owner account created on the first visit.

**Dex**, **Google Account**, and **Azure**: 💲 paid. Single sign-on is a Sourcebot Enterprise feature, so none of them is set up here.

### Usage

Indexing starts on its own (`docker logs -f sourcebot`); a search finds code once the repos are indexed. Its MCP endpoint (`/api/mcp`) is used in Step 16.

### Test

1. **Sign-in:** `https://<SERVER_HOST>:9460` asks for the owner account on the first visit, then signs in. From Sourcebot v6, activate it once (Settings → License; free for up to 5 users).
2. **Indexing:** `docker logs sourcebot 2>&1 | grep -i -E "index|error" | tail` shows each repository from `config.json` indexed, with no `404` or `401` (those mean the GitHub token cannot see the repository).
3. **A search:** search for a function name you know; results come from the right repository and file.
4. **MCP** (for agents): `curl -sk -o /dev/null -w "%{http_code}\n" https://${SERVER_HOST}:9460/api/mcp` answers (not `000`); an agent with it configured finds code by name.

