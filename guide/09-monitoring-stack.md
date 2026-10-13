## Step 9: Monitoring stack

**Check:** `grafana`, `prometheus`, `node-exporter`, `dcgm-exporter`.

### Clean reinstall

Removes the four monitoring stacks as if they had never been installed. Skip it for a first install. **Dashboards, Grafana users and settings, and all collected metrics are lost** with the volumes. The options on top (Alerts, Central logs) have their own Remove parts. Each line asks first.
```bash
confirm "Stop and remove Grafana, Prometheus, Node Exporter, and dcgm-exporter?" && for s in grafana prometheus node-exporter dcgm-exporter; do (cd /opt/stacks/$s && docker compose down); done
confirm "Delete dashboards, Grafana users, and all metrics (volumes grafana_data, prometheus_data)?" && docker volume rm grafana_data prometheus_data
confirm "Delete the four stack folders and the Caddy files grafana.caddy and prometheus.caddy?" && rm -rf /opt/stacks/grafana /opt/stacks/prometheus /opt/stacks/node-exporter /opt/stacks/dcgm-exporter /opt/stacks/caddy/conf.d/grafana.caddy /opt/stacks/caddy/conf.d/prometheus.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the four images (downloaded again on the next install)?" && docker image rm grafana/grafana:latest prom/prometheus:latest prom/node-exporter:latest nvcr.io/nvidia/k8s/dcgm-exporter:latest
```

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -E '^(grafana|prometheus|node-exporter|dcgm-exporter)$'
docker volume ls -q | grep -E '^(grafana|prometheus)_data$'
ls -d /opt/stacks/grafana /opt/stacks/prometheus /opt/stacks/node-exporter /opt/stacks/dcgm-exporter 2>/dev/null
```

### Install

An older combined stack at `/opt/stacks/monitoring` may exist. Check:
```bash
docker inspect prometheus --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' 2>/dev/null
```
If it prints `/opt/stacks/monitoring`, back up anything worth keeping, then take it down:
```bash
confirm "Tear down the old combined /opt/stacks/monitoring stack? (containers only; volumes are kept)" && cd /opt/stacks/monitoring && docker compose down
```

```bash
mkdir -p /opt/stacks/{grafana,prometheus,node-exporter,dcgm-exporter}
```

`/opt/stacks/grafana/.env`:
```env
SERVER_HOST=<from /opt/stacks/shared/.env>
GRAFANA_ADMIN_PASSWORD=CHANGE_ME
# Sign-in through Dex; set GRAFANA_SSO=false and leave the secret out if Dex is not deployed
GRAFANA_SSO=true
GRAFANA_OIDC_SECRET=<GRAFANA_OIDC_SECRET from /opt/stacks/dex/.env>
# Optional email (see the guide option: email for all services); with Infisical these come from prod:/shared
# SMTP_ENABLED=true            # alert emails
# SMTP_HOST=smtp.gmail.com
# SMTP_PORT=587
# SMTP_USERNAME=<the dedicated gmail address>
# SMTP_PASSWORD=<16-character app password>
```

`/opt/stacks/grafana/compose.yaml`:
```yaml
services:
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
      GF_SERVER_ROOT_URL: https://${SERVER_HOST}:9450
      # Look and time zone for everyone who has not picked their own (profile -> Preferences)
      GF_USERS_DEFAULT_THEME: system                 # dark, light, or system (follows the computer)
      GF_DATE_FORMATS_DEFAULT_TIMEZONE: Asia/Bangkok # an IANA time zone, or browser (the time zone of each viewer)
      # Sign-in through Dex: the browser goes through Caddy, Grafana itself calls Dex directly
      GF_AUTH_GENERIC_OAUTH_ENABLED: ${GRAFANA_SSO:-false}
      GF_AUTH_GENERIC_OAUTH_NAME: Dex
      GF_AUTH_GENERIC_OAUTH_CLIENT_ID: grafana
      GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET: ${GRAFANA_OIDC_SECRET:-}
      GF_AUTH_GENERIC_OAUTH_SCOPES: openid email profile
      GF_AUTH_GENERIC_OAUTH_AUTH_URL: https://${SERVER_HOST}:5556/dex/auth
      GF_AUTH_GENERIC_OAUTH_TOKEN_URL: http://dex:5556/dex/token
      GF_AUTH_GENERIC_OAUTH_API_URL: http://dex:5556/dex/userinfo
      GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP: "true"
      # Email for alerts: off unless SMTP_ENABLED=true in .env
      GF_SMTP_ENABLED: ${SMTP_ENABLED:-false}
      GF_SMTP_HOST: ${SMTP_HOST:-smtp.gmail.com}:${SMTP_PORT:-587}
      GF_SMTP_USER: ${SMTP_USERNAME:-}
      GF_SMTP_PASSWORD: ${SMTP_PASSWORD:-}
      GF_SMTP_FROM_ADDRESS: ${SMTP_USERNAME:-}
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana.ini:/etc/grafana/grafana.ini:ro
    networks: [edge]

networks:
  edge:
    external: true

volumes:
  grafana_data:
    external: true
```

`/opt/stacks/grafana/grafana.ini` — Grafana's own settings, all left at their defaults; uncomment a line to change it:
```ini
# Settings set under environment: in compose.yaml win over this file, so they are not repeated here:
# [server], [security], [auth.generic_oauth], [smtp], and the default theme and time zone.
# Keep secrets out of this file.

[users]
# Role for people who sign in through Dex for the first time: Viewer, Editor, or Admin
# auto_assign_org_role = Viewer

[dashboards]
# Fastest refresh a dashboard may use
# min_refresh_interval = 5s
```

**Grafana settings:** each setting can live in `grafana.ini` (`[section]` + `key`) or in an environment variable named `GF_<SECTION>_<KEY>`, with dots written as `_`. For example `[auth.generic_oauth] enabled` is `GF_AUTH_GENERIC_OAUTH_ENABLED`. The variable wins when both are set. Values that come from `.env` (passwords, the server name, sign-in, email) are variables in `compose.yaml`, and the default theme and time zone are written there directly; everything else goes in `grafana.ini`. Create the file before the first `up -d`: if it's missing, Docker creates an empty folder named `grafana.ini` and Grafana won't start. Grafana reads the file only at start, so after an edit run `cd /opt/stacks/grafana && docker compose up -d --force-recreate grafana`. Check with `docker exec grafana cat /etc/grafana/grafana.ini`. The full list of settings is in Grafana's documentation under "Configure Grafana". **Older install?** Grafana set up without `grafana.ini`: see [Upgrading an older install](options/upgrade-older-install.md#grafana).

**Option:** [Email (SMTP) for all services](options/smtp-email.md) — one Gmail account sends mail for every app; the lines are already in this step's files, commented out.

`/opt/stacks/prometheus/prometheus.yml` (`.yml`, not `.yaml`: it's the path the Prometheus image reads by default, `/etc/prometheus/prometheus.yml`, and the name its docs use):
```yaml
global:
  scrape_interval: 30s            # how often each target is read
scrape_configs:
  - job_name: node-exporter
    static_configs: [{ targets: ["node-exporter:9100"] }]
  - job_name: dcgm-exporter
    static_configs: [{ targets: ["dcgm-exporter:9400"] }]
  - job_name: litellm            # shows DOWN unless the LiteLLM Enterprise Prometheus callback is enabled
    static_configs: [{ targets: ["litellm:4000"] }]
```

`/opt/stacks/prometheus/compose.yaml`:
```yaml
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    # The two start options of the image, plus how long to keep data: 30 days, at most 5 GB
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --storage.tsdb.retention.time=30d
      - --storage.tsdb.retention.size=5GB
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    networks: [edge]

networks:
  edge:
    external: true

volumes:
  prometheus_data:
    external: true
```

**How much Prometheus keeps:** it reads each target every 30 seconds (`scrape_interval`), enough to see GPU load from model answers, and keeps 30 days, enough for a development server (`90d` to compare a month with the ones before). Old data is deleted when it is 30 days old or the data passes 5 GB, whichever comes first; with the targets here it stays near 0.5 GB. `command:` replaces the image's start options, which is why it repeats the image's own two (`--config.file`, `--storage.tsdb.path`) before the retention ones. To change a value, edit the file and run `cd /opt/stacks/prometheus && docker compose up -d --force-recreate prometheus`; check under Status → Runtime & Build Information (`https://<SERVER_HOST>:9090/status`). With a 30-second interval, Grafana `rate()` panels need a window of at least 2 minutes (`rate(...[2m])`).

`/opt/stacks/node-exporter/compose.yaml`:
```yaml
services:
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    # Report the host name of the server (Nodename in Grafana), not the container ID
    uts: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro,rslave
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
      # Off by default; adds process, thread, and PID counts (System Processes in Grafana)
      - '--collector.processes'
    networks: [edge]

networks:
  edge:
    external: true
```

`/opt/stacks/dcgm-exporter/compose.yaml`:
```yaml
services:
  dcgm-exporter:
    image: nvcr.io/nvidia/k8s/dcgm-exporter:latest
    container_name: dcgm-exporter
    restart: unless-stopped
    devices:
      - nvidia.com/gpu=all
    networks: [edge]

networks:
  edge:
    external: true
```

```bash
docker volume create grafana_data
docker volume create prometheus_data

cd /opt/stacks/grafana        && docker compose up -d
cd /opt/stacks/prometheus     && docker compose up -d
cd /opt/stacks/node-exporter  && docker compose up -d
cd /opt/stacks/dcgm-exporter  && docker compose up -d
```

Front Grafana and Prometheus through Caddy (the exporters stay internal):
```bash
cat > /opt/stacks/caddy/conf.d/grafana.caddy <<'EOF'
https://{$SERVER_HOST}:9450, https://{$SERVER_IP}:9450 {
	tls internal
	reverse_proxy grafana:3000
}
EOF
cat > /opt/stacks/caddy/conf.d/prometheus.caddy <<'EOF'
https://{$SERVER_HOST}:9090 {
	tls internal
	import sso prometheus:9090
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```

**Check the result.** Every line must match the table:
```bash
docker inspect -f '{{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}' grafana prometheus node-exporter dcgm-exporter
docker inspect -f '{{.Name}}  networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}  uts={{.HostConfig.UTSMode}}' grafana prometheus node-exporter dcgm-exporter
docker inspect -f '{{.Name}}{{range .Mounts}}  {{.Destination}} <- {{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}}{{end}}' grafana prometheus
docker inspect prometheus --format '{{join .Args " "}}'
docker exec grafana sh -c 'echo "root URL: $GF_SERVER_ROOT_URL, Dex: $GF_AUTH_GENERIC_OAUTH_ENABLED, theme: $GF_USERS_DEFAULT_THEME"'
docker exec node-exporter hostname
curl -sk "https://${SERVER_HOST}:9450/api/health"; echo
curl -sv https://${SERVER_HOST}:9450 -o /dev/null 2>&1 | grep -E "issuer:|HTTP/"
```

| Line | Expected |
|---|---|
| state | all four `running`, `restart=unless-stopped` |
| networks | `edge` for all four; `node-exporter` with `uts=host` |
| mounts | Grafana: `/var/lib/grafana <- grafana_data`, `/etc/grafana/grafana.ini <- /opt/stacks/grafana/grafana.ini`; Prometheus: `/etc/prometheus/prometheus.yml <- /opt/stacks/prometheus/prometheus.yml`, `/prometheus <- prometheus_data` |
| Prometheus args | include `--storage.tsdb.retention.time=30d` and `--storage.tsdb.retention.size=5GB` |
| Grafana environment | `root URL: https://<SERVER_HOST>:9450`, `Dex: true` (with Dex), your theme |
| `hostname` | the server host name (not a container ID) |
| `api/health` | JSON with `"database": "ok"` |
| `curl` | `issuer: CN=Caddy Local Authority …` and `HTTP/2 200` (or `302` to the login) |

**Verify:** `https://<SERVER_HOST>:9090/targets` first shows the Dex login (with the gate), then node-exporter and dcgm-exporter UP (litellm stays DOWN, which is expected).

### Authentication

**Grafana** keeps its local `admin` login.

**Dex** (free): the `GF_AUTH_GENERIC_OAUTH_*` lines, switched by `GRAFANA_SSO` in `.env`. With Dex, Grafana's login page gets a "Sign in with Dex" button; people who sign in that way join as Viewers (change it with `auto_assign_org_role` in `grafana.ini`), and the local `admin` can promote them (Administration → Users). The local `admin` login keeps working. Sign-in through Dex works on `https://<SERVER_HOST>:9450` (Grafana's root URL); the IP address still serves the local login.

The `GF_AUTH_GENERIC_OAUTH_*` lines need no editing; they connect Grafana to the `grafana` client already in Dex's `config.yaml`:

| Line | Value | Meaning |
|---|---|---|
| `ENABLED` | `${GRAFANA_SSO:-false}` | On or off, from `GRAFANA_SSO` in `.env` |
| `NAME` | `Dex` | The button text: "Sign in with Dex" |
| `CLIENT_ID` | `grafana` | Matches `- id: grafana` in Dex `config.yaml` |
| `CLIENT_SECRET` | `${GRAFANA_OIDC_SECRET:-}` | Equals `GRAFANA_OIDC_SECRET` in `/opt/stacks/dex/.env` |
| `SCOPES` | `openid email profile` | Asks Dex for the email address and name |
| `AUTH_URL` | `https://${SERVER_HOST}:5556/dex/auth` | Opened by the browser, so through Caddy |
| `TOKEN_URL`, `API_URL` | `http://dex:5556/dex/...` | Called by Grafana itself, straight over `edge` |
| `ALLOW_SIGN_UP` | `"true"` | Creates the Grafana user at the first sign-in |

`GF_SERVER_ROOT_URL` matters too: Grafana sends people back to `<root URL>/login/generic_oauth`, which must match the `grafana` entry under `redirectURIs` in Dex `config.yaml`.

To turn it on:
1. `grep ^GRAFANA_OIDC_SECRET= /opt/stacks/dex/.env` and copy the value.
2. In `/opt/stacks/grafana/.env`, set `GRAFANA_SSO=true` and `GRAFANA_OIDC_SECRET=` that value. With Infisical, give `GRAFANA_OIDC_SECRET` the same value in `prod:/dex` and `prod:/grafana`, then run `pull-secrets.sh`.
3. `cd /opt/stacks/grafana && docker compose up -d`
4. Check: `docker exec grafana printenv GF_AUTH_GENERIC_OAUTH_ENABLED GF_SERVER_ROOT_URL` prints `true` and `https://<SERVER_HOST>:9450`.
5. Open `https://<SERVER_HOST>:9450`, click **Sign in with Dex**, sign in, and you're back in Grafana as a Viewer. Sign in as `admin` to make yourself Admin (Administration → Users).

| Symptom | Cause |
|---|---|
| No "Sign in with Dex" button | `GRAFANA_SSO` isn't `true`, or Grafana wasn't recreated |
| Dex says "Unregistered redirect_uri" | Grafana was opened by IP, or `SERVER_HOST` differs between the Dex and Grafana `.env` (run `sync-shared-env.sh`) |
| Back in Grafana with "Login failed" | `GRAFANA_OIDC_SECRET` differs between the Dex and Grafana `.env` |

The reason behind a failure: `docker logs grafana 2>&1 | grep -i oauth | tail`.

**Google Account** (free): through Dex's Google connector, with nothing to change here. Grafana's own Google login (`GF_AUTH_GOOGLE_*`) is also free.

**Azure** (free): through Dex's Microsoft connector, with nothing to change here. Grafana's own Azure AD login (`GF_AUTH_AZUREAD_*`) is also free.

**Prometheus** has no login of its own:
- **Dex** (free): it sits behind the sign-in gate from Step 6, so people sign in through Dex first. No Dex? See [Without the sign-in gate](options/without-sign-in-gate.md).
- **Google Account** (free) and **Azure** (free): through Dex. The gate offers whatever Dex offers, so turning on Google or Microsoft in Dex covers Prometheus too. oauth2-proxy could also use Google or Azure directly (free), but then every gated app skips Dex.

### Usage

In Grafana (`https://<SERVER_HOST>:9450`, user `admin`), add Prometheus as a data source (Connections → Data sources → Prometheus) with URL `http://prometheus:9090`, and set its **Scrape interval** to `30s` to match `prometheus.yml`. Then import two ready-made dashboards (Dashboards → New → Import, enter the ID, pick the Prometheus data source): `1860` Node Exporter Full (CPU, memory, disks, network) and `12239` NVIDIA DCGM Exporter (GPU). Import by ID needs the server to reach `grafana.com`; otherwise download the JSON from `https://grafana.com/grafana/dashboards/<ID>` on your PC and upload it on the same page.

**Option:** [Alerts](options/alerts.md) — email when a service stops answering, a certificate stops renewing, or the disk, memory, or GPU temperature crosses a limit (blackbox exporter and Grafana alert rules).

**Option:** [Central logs](options/central-logs.md) — every container's logs in Grafana (Loki and Alloy), searchable and kept 30 days.

**Option:** [Node Exporter Full panels](options/node-exporter-full-panels.md) — what each panel shows, which ones stay empty and why, what turning on more costs, and which to keep.

### Test

1. **Targets:** `https://<SERVER_HOST>:9090/targets` (after the Dex sign-in) shows `node-exporter` and `dcgm-exporter` UP.
2. **Data flows:** in Prometheus, the query `up` lists both with value `1`; `DCGM_FI_DEV_GPU_TEMP` returns the GPU temperature.
3. **Grafana:** sign in with Dex; Connections → Data sources → Prometheus → **Save & test** says it works; a dashboard (e.g. Node Exporter Full) shows CPU, memory, and disk with recent values.
4. **Email** (if set up): Alerting → Contact points → the email contact point → **Test** sends a mail.

