## Step 8: Portainer (Docker UI)

**Check:** `portainer`.

### Clean reinstall

Removes Portainer as if it had never been installed. Skip it for a first install, and for an existing install that you only move into this layout (migrate it instead, under Install). **Its users, environments, and settings are lost** with the volume; the containers it shows are not touched. Each line asks first.
```bash
confirm "Stop and remove the Portainer container?" && cd /opt/stacks/portainer && docker compose down; cd ~
confirm "Delete Portainer users and settings (volume portainer_data)? The next start shows the setup wizard" && docker volume rm portainer_data
confirm "Delete /opt/stacks/portainer and its Caddy file?" && rm -rf /opt/stacks/portainer /opt/stacks/caddy/conf.d/portainer.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the Portainer image (downloaded again on the next install)?" && docker image rm portainer/portainer-ce:lts
```
After a reinstall, open `https://<SERVER_HOST>:9443` within 5 minutes to create the admin (Portainer locks the setup after that; `docker restart portainer` reopens it), and set up Dex sign-in again (Authentication).

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -x portainer
docker volume ls -q | grep portainer
ls -d /opt/stacks/portainer /opt/stacks/caddy/conf.d/portainer.caddy 2>/dev/null
```

### Install

An existing install holds real data (users, environments), so migrate it; don't reinstall. See how it runs now:
```bash
docker inspect portainer --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}'
```
- **"no such object"** → fresh install; follow the step.
- **Empty** (bare `docker run`) → migrate: the compose file below reuses the existing `portainer_data` volume.
- **A path** → already Compose-managed; make sure its `portainer_data` volume is `external: true` and it has no `ports:` of its own.

```bash
mkdir -p /opt/stacks/portainer
```
`/opt/stacks/portainer/compose.yaml`:
```yaml
services:
  portainer:
    image: portainer/portainer-ce:lts
    container_name: portainer
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks: [edge]

networks:
  edge:
    external: true

volumes:
  portainer_data:
    external: true
```
No `ports:`. Caddy serves `:9443` and proxies to Portainer's internal HTTP port `9000`, so the browser sees the trusted CA, not Portainer's self-signed cert.

`docker volume create` is a no-op if `portainer_data` already exists; it never resets it. Skip the `confirm` line on a fresh install.
```bash
docker volume create portainer_data

confirm "Stop and remove the existing Portainer container? (its data volume is untouched)" && docker rm -f portainer
cd /opt/stacks/portainer && docker compose up -d
```
If an earlier deploy without `external: true` created an empty duplicate volume, remove it:
```bash
docker volume ls | grep portainer
confirm "Remove the empty duplicate volume portainer_portainer_data? (real one is portainer_data, untouched)" && docker volume rm portainer_portainer_data
```
```bash
cat > /opt/stacks/caddy/conf.d/portainer.caddy <<'EOF'
https://{$SERVER_HOST}:9443, https://{$SERVER_IP}:9443 {
	tls internal
	reverse_proxy portainer:9000
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
**Check the result.** Every line must match the table:
```bash
docker inspect portainer --format 'name={{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}'
docker inspect portainer --format 'networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}  ports={{range $p, $b := .NetworkSettings.Ports}}{{if $b}}{{$p}} {{end}}{{end}}'
docker inspect portainer --format '{{range .Mounts}}mount {{.Destination}} <- {{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}}{{println}}{{end}}'
docker volume ls -q | grep portainer
curl -sv https://${SERVER_HOST}:9443 -o /dev/null 2>&1 | grep -E "issuer:|HTTP/"
```

| Line | Expected |
|---|---|
| `name=` | `/portainer  state=running  restart=unless-stopped`, image `portainer/portainer-ce:lts` |
| `networks=` | `edge`, and `ports=` empty (nothing published; Caddy fronts it) |
| `mount` | `/data <- portainer_data` and `/var/run/docker.sock <- /var/run/docker.sock` |
| `volume ls` | `portainer_data` only (no `portainer_portainer_data` duplicate) |
| `curl` | `issuer: CN=Caddy Local Authority …` and `HTTP/2 200` |

**Verify:** `https://<SERVER_HOST>:9443` shows your existing login (not the setup wizard) with a trusted padlock.

### Authentication

Portainer keeps its local `admin` login; each method below adds an OAuth button.

**Dex** (free): set in Portainer's web UI, no file change: Settings → Authentication → **OAuth** → provider **Custom**, then:

| Field | Value |
|---|---|
| Client ID | `portainer` |
| Client secret | `PORTAINER_OIDC_SECRET` from `/opt/stacks/dex/.env` |
| Authorization URL | `https://<SERVER_HOST>:5556/dex/auth` |
| Access token URL | `http://dex:5556/dex/token` |
| Resource URL | `http://dex:5556/dex/userinfo` |
| Redirect URL | `https://<SERVER_HOST>:9443` |
| User identifier | `email` |
| Scopes | `openid email profile` |

Turn on **Automatic user provisioning** so a person's first sign-in creates their Portainer user (a standard user; promote admins under Users). Without it, sign-in fails for anyone without a Portainer user yet, even though the Dex log shows `login successful`: Portainer just returns to its login page. Keep the local `admin` login as a fallback.

**Google Account** (free): through Dex's Google connector, with nothing to change here. Portainer's built-in Google preset is 💲 paid (Business Edition), and Community Edition takes only one OAuth provider, so Dex is how several providers share it.

**Azure** (free): through Dex's Microsoft connector, with nothing to change here. Portainer's built-in Microsoft preset is 💲 paid (Business Edition).

### Test

1. **Sign-in:** `https://<SERVER_HOST>:9443` shows your login (not the setup wizard); with Dex, **Login with OAuth** signs you in.
2. **It sees Docker:** Home → the local environment lists the server's containers (`caddy`, `outline`, …) as running.
3. **An action works:** open a container's **Logs** (e.g. `caddy`): recent lines appear.

