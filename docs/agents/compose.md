# Compose and config rules

Layout, naming, secrets, volumes, networks, ports, and health checks for every compose file, `.env`, and config file the guide writes out.

## Layout and naming

- Stacks live at `/opt/stacks/<stack>/` with `compose.yaml` and `.env`.
- Indent YAML (`compose.yaml`, `config.yaml`, `prometheus.yml`) with 2 spaces, never tabs. YAML rejects tab indentation. Tabs are only for Caddy files (see [caddy-and-ports.md](caddy-and-ports.md)).
- `.env` alone only feeds `${…}` in the compose file; it never reaches the container. List each container variable under `environment:`. Use `env_file: .env` only when the app reads many optional settings by their own names (Outline's `SMTP_*` / `AZURE_*`). Check the variable names against the app's upstream `.env.sample` or config source.
- Shared values (`SERVER_HOST`, `SERVER_IP`) live in `/opt/stacks/shared/.env`, written in Step 2. A stack that needs one gets its own copy of the line in its `.env`, shown as `SERVER_HOST=<from /opt/stacks/shared/.env>`; `sync-shared-env.sh` keeps the copies in step. Never make a stack read the shared file at runtime (no `env_file: ../shared/.env`, no `--env-file`): stacks stay self-contained. A new shared value needs a line in the shared file, the key in the script's `KEYS`, and the copy in each stack's `.env`.
- Single sign-on through Dex: every app gets its own Dex client (id, secret in `/opt/stacks/dex/.env`, redirect URI) in the Dex step, so the Dex config is written once. The browser-facing URL goes through Caddy (`https://${SERVER_HOST}:5556/dex/auth`); server-to-server calls go straight to `http://dex:5556/dex/...`, because apps don't trust the internal CA. An app that insists on discovery from the issuer URL (Langfuse) instead gets `extra_hosts: ["${SERVER_HOST}:${SERVER_IP}"]` plus the CA file mounted and named in `NODE_EXTRA_CA_CERTS` (or the app's equivalent). An app's SSO lines must be optional: `.env` switch or "leave these out if Dex is not deployed".
- Sign-in blocks in a file follow the defaults in a fixed order: Dex, email, Google, Azure (see [guide-structure.md](guide-structure.md#authentication-subsections)).
- No `<placeholder>` in a compose file, or in a config file that can read the environment (Dex `config.yaml` through `{{ getenv "NAME" }}` or `$NAME`; LiteLLM through `os.environ/NAME`). Each such value is a variable: a commented `# NAME=<what to put>` line in the stack `.env` (in the same order as in the config), a `NAME: ${NAME:-}` line under the service `environment:`, and the reference in the config. Uncommenting is then the only edit. Exceptions, because they are data rather than settings: Dex `staticPasswords` entries, Sourcebot `repos`, and LiteLLM model names.
- A config file mounted as a single file (`./config.yaml:/etc/...`) is pinned to the file the container started with; editors that save by replacing the file leave the container on the old copy. When the guide tells the reader to edit such a file later (Dex users, connectors), the apply command is `docker compose up -d --force-recreate <service>`, never `docker restart`.
- Secrets with Infisical (optional step):
  - Each stack's `.env` block in the guide doubles as the list of keys for Infisical folder `prod:/<stack>`; `pull-secrets.sh` matches the file to `prod:/shared` + `prod:/<stack>`, editing it in place (order and comments kept). Stacks never call Infisical at runtime.
  - Keep `.env` key names identical to what the guide shows, and avoid single quotes and `$` inside values (Infisical fills in `${prod.shared.KEY}` references when `pull-secrets.sh` reads them, and may treat any other `$` as a variable too; values with special characters are written as `KEY='value'`, plain ones unquoted).
  - Never move Infisical's start keys (`INFISICAL_DB_PASSWORD`, `INFISICAL_ENCRYPTION_KEY`, `INFISICAL_AUTH_SECRET`) into Infisical.
  - `pull-secrets.sh` treats Infisical's own `.env` like any stack (matched to `prod:/shared` + `prod:/infisical` when that folder exists), except that it always carries the start keys over from the current file and ignores them in Infisical.
- Dex `config.yaml` is rendered by gomplate at every start: `{{ … }}` anywhere in it, comments included, is executed. Use only `{{ getenv "NAME" }}` there; write Dex login-page template syntax (`{{ extra … }}`, `{{ issuer }}`) only in the HTML templates, never in the config file.
- Set `container_name:` explicitly: the bare service name, or `<service>-postgres` / `<service>-redis` / `<service>-<component>` for supporting containers.

## Volumes and networks

- Declare every named volume `external: true` and create it with `docker volume create <name>` right before the first `up -d`.
- Mount a named volume on every path the image declares as `VOLUME` (check with `docker image inspect <image> --format '{{json .Config.Volumes}}'`), even logs; otherwise Docker creates an anonymous volume with a hash for a name, which is hard to tell apart from data and gets left behind.
- `edge` is created with `-o com.docker.network.bridge.name=br-edge`. A stack with its own `default` network (databases kept off `edge`) names its bridge `br-<stack>` under `networks: default: driver_opts: com.docker.network.bridge.name:` (Linux allows at most 15 characters, so `br-` plus at most 12). Any procedure that removes and recreates `edge` must bring containers back with `docker compose up -d --force-recreate` (profile services with `--profile <name> … --force-recreate`): a plain `up -d` or `start` reuses containers that point at the removed network ID and fails with "network … not found".
- Each service reachable by another stack or by Caddy joins the external `edge` network. Supporting DBs stay on the stack's `default` network.
- Internal container-to-container URLs use plain `http://<container>:<port>` over `edge`. Never use Caddy's HTTPS for them.

## Ports

- No host `ports:` except in Caddy's compose, plus direct bolt ports (7687/7688) and OpenHands (3000: its browser connects straight to sandboxes on random ports, which Caddy cannot front). Optional test ports stay commented out.
- When a file lists several ports, order them by the guide's step order (or dependency order). A range shared by several steps goes where its first user's step falls.
- Caddy's `ports:` list has two commented groups: `# Default port of the service` first, then `# Assigned port (not the service default)`. Step order applies within each group.
- Port numbers themselves come from [caddy-and-ports.md](caddy-and-ports.md).

## Services

- Postgres uses the default `postgres` superuser (the backup scripts rely on it).
- Add health checks plus `depends_on: condition: service_healthy` where startup order matters. Check every 30s once healthy, and quickly only while starting: `interval: 30s`, `start_period: 60s`, `start_interval: 3s` (never more often than every 15s after the start period).
- GPU uses CDI syntax only: `devices: [nvidia.com/gpu=all]` in compose and `--device nvidia.com/gpu=all` on the CLI. Never `--gpus` or `deploy.resources.reservations.devices`.

## Comments inside files

- No `Step N` references. Name the service or file path instead (see [guide.md](guide.md)).
- A port comment names only the service(s) behind it (e.g. `# Portainer`). When the mapping is a range, add each service's port (e.g. `# Grafana 9450, Sourcebot 9460`). Explanations such as "own default, unique" or why a port is proxied belong in the guide's prose.

## YAML that parses

`tools/check.py` parses every `yaml` code block (needs PyYAML, from `tools/requirements.txt`) and flags tabs in indentation and a key repeated in one mapping (Docker Compose refuses those; PyYAML alone keeps the last one silently). Merge keys (`<<: *anchor`) are fine. A YAML fragment shown in a code block must still parse on its own.
