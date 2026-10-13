# Option: Alerts

Part of [Step 9: Monitoring stack](../ai-server-setup-guide.md#step-9-monitoring-stack). Grafana emails you when something goes wrong: a service stops answering, its certificate stops renewing, the disk fills up, memory runs out, or the GPU runs hot. Prometheus already collects the server's numbers; a small **blackbox exporter** adds checks of each address the way a browser opens it (HTTPS, answer, certificate, speed). Everything is free and runs on the AI server.

It cannot report the whole server being off: then Grafana is off too. Someone notices that one; the alerts cover everything else.

## Before you start

- **Email in Grafana:** the `SMTP_*` lines in `/opt/stacks/grafana/.env`, including `SMTP_ENABLED=true` ([Email (SMTP) for all services](smtp-email.md)).
- **Monitoring stack (Step 9)** running, with the Prometheus data source in Grafana.

## 1. Blackbox exporter

Its own stack, on `edge`, internal only. It opens the server's addresses by name, so it gets the name (`extra_hosts`) and Caddy's CA, like Langfuse.
```bash
mkdir -p /opt/stacks/blackbox-exporter
```
`/opt/stacks/blackbox-exporter/.env`:
```env
SERVER_HOST=<from /opt/stacks/shared/.env>
SERVER_IP=<from /opt/stacks/shared/.env>
```
`/opt/stacks/blackbox-exporter/blackbox.yml`:
```yaml
modules:
  # An address counts as up when it answers at all: sign-in redirects (302) and
  # login prompts (401, 403) mean the service and Caddy work.
  web:
    prober: http
    timeout: 10s
    http:
      valid_status_codes: [200, 301, 302, 303, 307, 308, 401, 403]
      follow_redirects: false
      preferred_ip_protocol: ip4
      tls_config:
        ca_file: /certs/caddy-root-ca.crt
```
`/opt/stacks/blackbox-exporter/compose.yaml`:
```yaml
services:
  blackbox-exporter:
    image: prom/blackbox-exporter:latest
    container_name: blackbox-exporter
    restart: unless-stopped
    command: ["--config.file=/etc/blackbox/blackbox.yml"]
    extra_hosts:
      - "${SERVER_HOST}:${SERVER_IP}"
    volumes:
      - ./blackbox.yml:/etc/blackbox/blackbox.yml:ro
      - /opt/stacks/caddy/caddy-root-ca.crt:/certs/caddy-root-ca.crt:ro
    networks: [edge]

networks:
  edge:
    external: true
```
```bash
cd /opt/stacks/blackbox-exporter && docker compose up -d
```
Check one address by hand (`probe_success 1` is good):
```bash
docker run --rm --network edge curlimages/curl -s "http://blackbox-exporter:9115/probe?module=web&target=https://${SERVER_HOST}" | grep -E "^probe_success|^probe_http_status_code"
```

## 2. Prometheus probes them

Add this job at the end of `scrape_configs:` in `/opt/stacks/prometheus/prometheus.yml`. Prometheus cannot read `.env`, so write your `SERVER_HOST` and `SERVER_IP` in place of the placeholders; leave out the services you have not deployed.
```yaml
  - job_name: web
    metrics_path: /probe
    params:
      module: [web]
    static_configs:
      - targets:
          - https://<SERVER_HOST>                                          # Outline
          - https://<SERVER_HOST>:8080                                     # Infisical
          - https://<SERVER_HOST>:5556/dex/.well-known/openid-configuration # Dex
          - https://<SERVER_HOST>:9443                                     # Portainer
          - https://<SERVER_HOST>:9450/api/health                          # Grafana
          - https://<SERVER_HOST>:9090                                     # Prometheus (sign-in gate)
          - https://<SERVER_HOST>:9460                                     # Sourcebot
          - https://<SERVER_HOST>:9470                                     # Langfuse
          - https://<SERVER_HOST>:4000/health/liveliness                   # LiteLLM
          - https://<SERVER_HOST>:7474                                     # Neo4j Browser (sign-in gate)
          - https://<SERVER_HOST>:9490                                     # Memgraph Lab (sign-in gate)
          - http://<SERVER_IP>:3000                                        # OpenHands
          - https://<SERVER_HOST>:9485/health                              # Open WebUI
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115

  # The LLM runtime: only one of the two runs at a time (switch-llm.sh), so the alert
  # rule looks at both together. Internal addresses, over edge.
  - job_name: llm-runtime
    metrics_path: /probe
    params:
      module: [web]
    static_configs:
      - targets:
          - http://ollama:11434            # Ollama
          - http://vllm:8000/health        # vLLM
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115
```
The vector database (Qdrant) is left out on purpose.
```bash
cd /opt/stacks/prometheus && docker compose up -d --force-recreate prometheus
```
In Prometheus (`https://<SERVER_HOST>:9090/targets`), the `web` and `llm-runtime` jobs list every address as UP (UP means the probe ran; whether the service answered is `probe_success`, used below).

## 3. Where alerts go

In Grafana (`admin`): **Alerting → Contact points → + Add contact point**: name `Admins`, integration **Email**, the addresses to notify, **Test** (an email arrives), **Save**. Then **Alerting → Notification policies** → the default policy → **Edit**: contact point `Admins`, and under **Timing options**:

| Setting | Value | Meaning |
|---|---|---|
| Group wait | `30s` | How long to wait after a first alert, to send it together with others that start at the same time |
| Group interval | `5m` | How soon a new alert joins an email already sent for the same group |
| Repeat interval | `4h` | **How often an alert that is still firing is emailed again**, until it is fixed. Shorter (`1h`) for more reminders, longer (`12h`, `24h`) for fewer |

When the problem is fixed, Grafana sends one "Resolved" email by itself. To stop reminders for a while without fixing it (planned work), **Alerting → Silences → + New silence**, matching e.g. `alertname = Service down`, for the duration of the work.

## 4. The alert rules

**Alerting → Alert rules → + New alert rule**, once per row. For each: query **Prometheus** in **Code** mode with the query below; Grafana adds **Reduce: Last** and a **Threshold**: set the threshold as in the table; folder `AI server`, evaluation group `every-minute` (1m); the pending period from the table; **Save rule and exit**.

| Rule | Query | Threshold | Pending | Means |
|---|---|---|---|---|
| Service down | `probe_success{job="web"}` | **Is below 1** | 15m | An address does not answer for 15 minutes (the alert names it in `instance`) |
| LLM runtime down | `max(probe_success{job="llm-runtime"})` | **Is below 1** | 15m | Neither Ollama nor vLLM answers. One of them being off is normal; a switch takes a minute or two |
| Certificate not renewing | `(probe_ssl_earliest_cert_expiry - time()) / 3600` | **Is below 1** | 5m | Caddy renews its internal certificates every few hours; less than an hour left means renewal fails |
| Disk almost full | `100 * (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})` | **Is above 85** | 1h | `/` over 85% for an hour (add a rule per extra disk) |
| Memory almost full | `100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)` | **Is above 90** | 30m | RAM over 90% for 30 minutes |
| GPU hot | `DCGM_FI_DEV_GPU_TEMP` | **Is above 85** | 5m | GPU over 85 °C |
| Exporter down | `up{job=~"node-exporter\|dcgm-exporter\|web\|llm-runtime"}` | **Is below 1** | 5m | Prometheus no longer gets the numbers the other rules need |

The certificate rule watches the short-lived certificates Caddy issues for each address; its own root (in Step 4) lasts 10 years and is not what this checks.

## Check

1. **Contact point:** the **Test** in section 3 sent an email.
2. **A real alert:** stop one service for a few minutes, e.g. `docker stop sourcebot`. After 15 minutes (the pending period), Alerting → Alert rules shows **Service down** as Firing; before that it shows Pending for `https://<SERVER_HOST>:9460`, and an email arrives. `docker start sourcebot`; a "Resolved" email follows within a few minutes. To test faster, set the rule's pending period to `1m` for the test and back to `15m` afterwards.
3. **The others** stay Normal; a rule in **Error** or **No data** has a query that returns nothing (check its exporter in Prometheus → Targets).

## Remove

Delete the rules (Alerting → Alert rules), the `web` job from `prometheus.yml` (then recreate Prometheus), and:
```bash
confirm "Stop and remove the blackbox exporter?" && cd /opt/stacks/blackbox-exporter && docker compose down; cd ~
confirm "Delete the folder /opt/stacks/blackbox-exporter?" && rm -rf /opt/stacks/blackbox-exporter
```

---

**Related:**
- [Step 9: Monitoring stack](../ai-server-setup-guide.md#step-9-monitoring-stack) → Usage
- [Option: Email (SMTP) for all services](smtp-email.md)
