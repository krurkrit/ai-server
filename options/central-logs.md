# Option: Central logs

Part of [Step 9: Monitoring stack](../ai-server-setup-guide.md#step-9-monitoring-stack). Collects the logs of every container into Loki, so you search them all in Grafana (Explore) instead of running `docker logs` container by container, and they survive a container being recreated. Grafana Alloy reads the logs from Docker and sends them to Loki. Both are free (AGPL), run internal-only on `edge`, and need no Caddy route: Grafana is the window onto them.

## Set it up

1. **Folder, volume, files:**
   ```bash
   mkdir -p /opt/stacks/loki
   docker volume create loki_data
   ```
   `/opt/stacks/loki/loki.yaml`, keeping 30 days:
   ```yaml
   auth_enabled: false
   server:
     http_listen_port: 3100
   common:
     path_prefix: /loki
     storage:
       filesystem:
         chunks_directory: /loki/chunks
         rules_directory: /loki/rules
     replication_factor: 1
     ring:
       kvstore:
         store: inmemory
   schema_config:
     configs:
       - from: 2026-01-01
         store: tsdb
         object_store: filesystem
         schema: v13
         index:
           prefix: index_
           period: 24h
   limits_config:
     retention_period: 30d
   compactor:
     working_directory: /loki/compactor
     retention_enabled: true
     delete_request_store: filesystem
   ```
   `/opt/stacks/loki/config.alloy`, one log stream per container, labelled with its container and stack names:
   ```
   discovery.docker "containers" {
     host = "unix:///var/run/docker.sock"
   }

   discovery.relabel "containers" {
     targets = []
     rule {
       source_labels = ["__meta_docker_container_name"]
       regex         = "/(.*)"
       target_label  = "container"
     }
     rule {
       source_labels = ["__meta_docker_container_label_com_docker_compose_project"]
       target_label  = "stack"
     }
   }

   loki.source.docker "containers" {
     host          = "unix:///var/run/docker.sock"
     targets       = discovery.docker.containers.targets
     relabel_rules = discovery.relabel.containers.rules
     forward_to    = [loki.write.local.receiver]
   }

   loki.write "local" {
     endpoint {
       url = "http://loki:3100/loki/api/v1/push"
     }
   }
   ```
   `/opt/stacks/loki/compose.yaml`:
   ```yaml
   services:
     loki:
       image: grafana/loki:3
       container_name: loki
       restart: unless-stopped
       command: ["-config.file=/etc/loki/loki.yaml"]
       volumes:
         - ./loki.yaml:/etc/loki/loki.yaml:ro
         - loki_data:/loki
       networks: [edge]

     alloy:
       image: grafana/alloy:latest
       container_name: loki-alloy
       restart: unless-stopped
       command: ["run", "/etc/alloy/config.alloy", "--storage.path=/var/lib/alloy/data"]
       volumes:
         - ./config.alloy:/etc/alloy/config.alloy:ro
         - /var/run/docker.sock:/var/run/docker.sock:ro
       depends_on: [loki]
       networks: [edge]

   networks:
     edge:
       external: true

   volumes:
     loki_data:
       external: true
   ```
2. **Start:**
   ```bash
   cd /opt/stacks/loki && docker compose up -d
   ```
3. **Grafana data source:** Connections → Data sources → **Add data source** → **Loki**, URL `http://loki:3100`, **Save & test**.

Disk use depends on how chatty the containers are; with the Docker log limits of the guide, expect a few hundred MB to a few GB for 30 days. Change `retention_period` to keep more or less, then `docker compose up -d --force-recreate loki`.

## Check and use

```bash
docker ps --filter name=loki --format '{{.Names}}  {{.Status}}'
docker logs loki-alloy 2>&1 | grep -i -E "error|level=warn" | tail -5
```
Both `Up`, no errors. In Grafana → **Explore** → Loki, run `{stack="outline"}` (one stack) or `{container="litellm"} |= "error"` (one container, lines with "error"); within a minute of starting, every running container has a stream.

Useful queries:

| Query | Shows |
|---|---|
| `{container=~".+"} \|= "error"` | Errors from every container |
| `{stack="dex"}` | Sign-in problems (Dex and the gate) |
| `sum by (container) (count_over_time({container=~".+"} \|= "error" [1h]))` | Errors per container in the last hour (as a graph) |

## Remove

```bash
confirm "Stop and remove Loki and Alloy?" && cd /opt/stacks/loki && docker compose down; cd ~
confirm "Delete all collected logs (volume loki_data)?" && docker volume rm loki_data
confirm "Delete the folder /opt/stacks/loki?" && rm -rf /opt/stacks/loki
```
Then delete the Loki data source in Grafana. Docker keeps its own (limited) logs either way.

---

**Related:**
- [Step 9: Monitoring stack](../ai-server-setup-guide.md#step-9-monitoring-stack) → Usage
