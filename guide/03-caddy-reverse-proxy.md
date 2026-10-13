## Step 3: Caddy (reverse proxy)

**Check:** `caddy`.

### Clean reinstall

Removes Caddy as if it had never been installed. Skip it for a first install. Without Caddy no service is reachable from outside. Each line asks first; read the last two before answering.
```bash
confirm "Stop and remove the Caddy container?" && cd /opt/stacks/caddy && docker compose down; cd ~
confirm "Delete the image (downloaded again on the next install)?" && docker image rm caddy:2
confirm "Delete the CA and certificates of Caddy (volume caddy_data)? Every client must then import the new CA again" && docker volume rm caddy_data
confirm "Delete /opt/stacks/caddy, including every service file in conf.d (each step must write its file again)?" && rm -rf /opt/stacks/caddy
```
To reinstall Caddy only and keep the services' routes and the clients' trust, answer no to the last two.

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -x caddy
docker volume ls -q | grep -x caddy_data
ls -d /opt/stacks/caddy 2>/dev/null
```

### Install

**Older install?** See [Upgrading an older install](options/upgrade-older-install.md) (no `SERVER_HOST` in `/opt/stacks/caddy/.env`, or ports missing for services added later).

How Caddy is set up:
- `Caddyfile` and `compose.yaml` are written once, here, and never edited again. `compose.yaml` already publishes every port the guide uses.
- Each later service adds one file, `conf.d/<service>.caddy`, then reloads Caddy (no restart).

```bash
mkdir -p /opt/stacks/caddy/conf.d
```

`/opt/stacks/caddy/Caddyfile`:
```
{
	default_sni {$SERVER_IP}
}

https://{$SERVER_HOST}:9500, https://{$SERVER_IP}:9500 {
	tls internal
	respond "Caddy OK" 200
}

import conf.d/*.caddy
```
- `default_sni` is required. Clients connecting by IP send no TLS server name, so without it every request by IP fails with `tlsv1 alert internal error`. Clients using the hostname send it, and get the certificate for the name.
- Each site lists both addresses, so it answers on the name and on the IP. With no hostname, both variables hold the IP; Caddy accepts the repeated address.
- The `:9500` block is a health check. It also makes Caddy create its CA right away, which Step 4 needs.
- Keep `import conf.d/*.caddy` as the last line. Without it no service is served.

`/opt/stacks/caddy/.env` (both lines from `/opt/stacks/shared/.env`):
```env
SERVER_HOST=<from /opt/stacks/shared/.env>
SERVER_IP=<from /opt/stacks/shared/.env>
```

`/opt/stacks/caddy/compose.yaml`:
```yaml
services:
  caddy:
    image: caddy:2
    container_name: caddy
    restart: unless-stopped
    environment:
      SERVER_HOST: ${SERVER_HOST}
      SERVER_IP: ${SERVER_IP}
    ports:
      # Default port of the service
      - "8080:8080"           # Infisical
      - "5556:5556"           # Dex
      - "9443:9443"           # Portainer
      - "9090:9090"           # Prometheus
      - "4000:4000"           # LiteLLM
      - "6333:6333"           # Qdrant
      - "7474:7474"           # Neo4j Browser
      # Assigned port (not the service default)
      - "9500:9500"           # Caddy health check
      - "443:443"             # Outline
      - "9450-9499:9450-9499" # Grafana 9450, Sourcebot 9460, Langfuse 9470, Open WebUI 9485, Memgraph Lab 9490
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./conf.d:/etc/caddy/conf.d
      - caddy_data:/data
    networks: [edge]

networks:
  edge:
    external: true

volumes:
  caddy_data:
    external: true
```

```bash
docker volume create caddy_data

cd /opt/stacks/caddy && docker compose up -d
```

**Check the result.** Every line must match the table:
```bash
docker inspect caddy --format 'name={{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}'
docker inspect caddy --format 'networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'
docker inspect caddy --format '{{range .Mounts}}mount {{.Destination}} <- {{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}}{{println}}{{end}}'
docker port caddy 443; docker port caddy 9450
docker volume inspect caddy_data --format 'volume={{.Name}}  driver={{.Driver}}'
docker exec caddy printenv SERVER_HOST SERVER_IP
curl -sv https://${SERVER_HOST}:9500 -o /dev/null 2>&1 | grep -E "issuer:|HTTP/"
```

| Line | Expected |
|---|---|
| `name=` | `/caddy  state=running  restart=unless-stopped`, image `caddy:2` |
| `networks=` | `edge` |
| `mount` | `/etc/caddy/Caddyfile <- /opt/stacks/caddy/Caddyfile`, `/etc/caddy/conf.d <- /opt/stacks/caddy/conf.d`, `/data <- caddy_data` |
| `docker port` | `0.0.0.0:443` and `0.0.0.0:9450` (plus `[::]` lines): the ports are published |
| `volume=` | `caddy_data  driver=local` |
| `printenv` | your `SERVER_HOST` and `SERVER_IP` |
| `curl` | `issuer: CN=Caddy Local Authority …` and `HTTP/2 200` |

**Verify:**
```bash
curl -k https://${SERVER_HOST}:9500
curl -k https://${SERVER_IP}:9500
```
Expect `Caddy OK` from both. If the first fails with "Could not resolve host", the name isn't in this server's hosts file or DNS yet (see "Before you start"). Otherwise check the container got both values (empty means `.env` is missing), that the Caddyfile is valid, and the log:
```bash
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy printenv SERVER_HOST SERVER_IP
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy validate --config /etc/caddy/Caddyfile
docker logs caddy 2>&1 | grep -iE "error|certificate" | tail -20
```

**Adding a service to Caddy** (every later step uses this pattern):
```bash
cat > /opt/stacks/caddy/conf.d/<service>.caddy <<'EOF'
https://{$SERVER_HOST}:<PORT>, https://{$SERVER_IP}:<PORT> {
	tls internal
	reverse_proxy <container-name>:<container-port>
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
A `502` afterwards means Caddy works but the service behind it isn't up; check `docker logs <container-name>`. Exceptions to this pattern list only `https://{$SERVER_HOST}…`, because their sign-in works on one fixed address: Infisical, Dex, Outline, Sourcebot, Langfuse, and the apps behind the sign-in gate.

### Test

1. **Both addresses:** `curl -k https://${SERVER_HOST}:9500` and `curl -k https://${SERVER_IP}:9500` print `Caddy OK`.
2. **A route reloads:** `docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile` prints nothing (no error).
3. **From a PC:** after Step 4 (CA imported), `https://<SERVER_HOST>:9500` opens in a browser with a padlock and shows `Caddy OK`.

