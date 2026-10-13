## Step 6: Dex (sign-in)

One sign-in for the whole server. Dex is a small sign-in service: you list users and passwords in its config file, and every app that supports it shows a "Sign in with Dex" button — Outline, Grafana, Portainer, Langfuse, Open WebUI, and the LiteLLM Admin UI (free for up to 5 users). Apps without their own sign-in support (Prometheus, the Qdrant dashboard, Neo4j Browser, Memgraph Lab) sit behind a **sign-in gate** (oauth2-proxy) that sends people to the same Dex login first. No SMTP relay or Azure admin rights needed.

What "single sign-on" means here: one account and password for every app. The four gated apps share one sign-in. The four apps with a Dex button each ask for the password once more, because Dex on its own doesn't remember a login between apps. Once a Microsoft (or Google, Auth0) connector is enabled ([Outside sign-in](options/dex-outside-sign-in.md)), that provider remembers the login, and the button signs people in without asking again.

Skip this step to keep every app on its own login; each later step says which lines to leave out.

**Check:** `dex`, `oauth2-proxy`.

### Clean reinstall

Removes Dex and the sign-in gate as if they had never been installed. Skip it for a first install. **Every app that signs in through Dex stops working** until Dex is back; the gated apps (Prometheus, Qdrant, Neo4j Browser, Memgraph Lab) answer with an error. People keep their accounts in each app (matched by email), so they sign in as before once Dex returns. Each line asks first.
```bash
confirm "Stop and remove Dex and the sign-in gate?" && cd /opt/stacks/dex && docker compose down; cd ~
confirm "Delete Dex data (volume dex_data: sessions and signing keys)?" && docker volume rm dex_data
confirm "Delete /opt/stacks/dex (.env with every client secret, config.yaml with the users)?" && rm -rf /opt/stacks/dex
confirm "Delete its Caddy files (dex.caddy, and the gate 00-sso.caddy that the gated apps import)?" && rm -f /opt/stacks/caddy/conf.d/dex.caddy /opt/stacks/caddy/conf.d/00-sso.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the Dex and gate images?" && docker image rm ghcr.io/dexidp/dex:latest quay.io/oauth2-proxy/oauth2-proxy:latest
```
With `00-sso.caddy` gone, Caddy refuses the gated apps' files (`import sso` unknown) until it is written again; reinstall Dex before reloading Caddy, or use [Without the sign-in gate](options/without-sign-in-gate.md). A new `.env` means new client secrets: copy each one into its app again (the `*_OIDC_SECRET` lines of the later steps).

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -E '^(dex|oauth2-proxy)$'
docker volume ls -q | grep -x dex_data
ls -d /opt/stacks/dex /opt/stacks/caddy/conf.d/dex.caddy /opt/stacks/caddy/conf.d/00-sso.caddy 2>/dev/null
```

### Install

**Caddy set up before Dex was in this guide?** Add its port first: [Upgrading an older install](options/upgrade-older-install.md#caddy-ports-for-later-services).

```bash
mkdir -p /opt/stacks/dex
```

`/opt/stacks/dex/.env`:
```env
SERVER_HOST=<from /opt/stacks/shared/.env>
OUTLINE_OIDC_SECRET=<openssl rand -hex 32>     # Outline uses the same value
GRAFANA_OIDC_SECRET=<openssl rand -hex 32>     # Grafana uses the same value
PORTAINER_OIDC_SECRET=<openssl rand -hex 32>   # entered in the Portainer web UI
LANGFUSE_OIDC_SECRET=<openssl rand -hex 32>    # Langfuse uses the same value
LITELLM_OIDC_SECRET=<openssl rand -hex 32>     # LiteLLM Admin UI uses the same value
OPENWEBUI_OIDC_SECRET=<openssl rand -hex 32>   # Open WebUI uses the same value
GATE_OIDC_SECRET=<openssl rand -hex 32>        # the sign-in gate (oauth2-proxy)
GATE_COOKIE_SECRET=<openssl rand -hex 16>      # -hex 16, not 32: must be exactly 32 characters
# Outside sign-in providers (optional, see the guide options: Google sign-in, outside sign-in); fill in only when you enable one
# GOOGLE_CLIENT_ID=<Google client ID>               # the same Google client as Infisical; with Infisical from prod:/shared
# GOOGLE_CLIENT_SECRET=<Google client secret>
# MS_CLIENT_ID=<Application (client) ID>
# MS_CLIENT_SECRET=<Azure client secret value>
# MS_TENANT_ID=<Directory (tenant) ID>
# ENTRA_GUEST_CLIENT_ID=<Application (client) ID in the tenant you administer>
# ENTRA_GUEST_CLIENT_SECRET=<client secret from the tenant you administer>
# ENTRA_GUEST_TENANT_ID=<Directory (tenant) ID of the tenant you administer>
# AUTH0_ISSUER=https://<your-tenant>.auth0.com/     # exactly as Auth0 shows it, with the trailing slash
# AUTH0_CLIENT_ID=<Auth0 client ID>
# AUTH0_CLIENT_SECRET=<Auth0 client secret>
```
`GATE_COOKIE_SECRET` is the odd one out: oauth2-proxy accepts only 16, 24, or 32 characters, so it takes `openssl rand -hex 16`. A 64-character value (from `-hex 32`) makes the `oauth2-proxy` container restart with "cookie_secret must be 16, 24, or 32 bytes". Check it with `grep ^GATE_COOKIE_SECRET= /opt/stacks/dex/.env | cut -d= -f2 | tr -d '\n' | wc -c` (expect `32`).

Make a password hash for each user (Caddy from Step 3 has the tool; it asks for the password twice):
```bash
docker exec -it caddy caddy hash-password
```
Copy the last line, the one starting with `$2a$`. Don't pipe this command into anything (e.g. `| tr`): the pipe hides the password prompts, so it looks stuck.

And a unique ID for each user:
```bash
cat /proc/sys/kernel/random/uuid
```

`/opt/stacks/dex/config.yaml` — Dex fills in `{{ getenv "SERVER_HOST" }}` from its environment each time it starts:
```yaml
issuer: https://{{ getenv "SERVER_HOST" }}:5556/dex

storage:
  type: sqlite3
  config:
    file: /var/dex/dex.db

web:
  http: 0.0.0.0:5556

oauth2:
  skipApprovalScreen: true

# Custom login page: off until you uncomment it (see the guide option: custom login page)
# frontend:
#   dir: /srv/dex/web-custom
#   theme: custom
#   issuer: "AI Server"   # page title, and the heading "Log in to AI Server"
#   extra:                # your own values for custom templates (see the guide option: custom login page)
#     helpText: "Trouble signing in? Contact the server admin."
#     helpURL: "https://{{ getenv "SERVER_HOST" }}"

enablePasswordDB: true

# One client per app. Listing an app that is not deployed yet does no harm.
staticClients:
  - id: outline
    name: Outline
    secretEnv: OUTLINE_OIDC_SECRET
    redirectURIs:
      - https://{{ getenv "SERVER_HOST" }}/auth/oidc.callback
  - id: grafana
    name: Grafana
    secretEnv: GRAFANA_OIDC_SECRET
    redirectURIs:
      - https://{{ getenv "SERVER_HOST" }}:9450/login/generic_oauth
  - id: portainer
    name: Portainer
    secretEnv: PORTAINER_OIDC_SECRET
    redirectURIs:
      - https://{{ getenv "SERVER_HOST" }}:9443
  - id: langfuse
    name: Langfuse
    secretEnv: LANGFUSE_OIDC_SECRET
    redirectURIs:
      - https://{{ getenv "SERVER_HOST" }}:9470/api/auth/callback/custom
  - id: litellm
    name: LiteLLM
    secretEnv: LITELLM_OIDC_SECRET
    redirectURIs:
      - https://{{ getenv "SERVER_HOST" }}:4000/sso/callback
  - id: open-webui
    name: Open WebUI
    secretEnv: OPENWEBUI_OIDC_SECRET
    redirectURIs:
      - https://{{ getenv "SERVER_HOST" }}:9485/oauth/oidc/callback
  - id: sso-gate
    name: Sign-in gate
    secretEnv: GATE_OIDC_SECRET
    redirectURIs:   # one per app behind the gate
      - https://{{ getenv "SERVER_HOST" }}:9090/oauth2/callback
      - https://{{ getenv "SERVER_HOST" }}:6333/oauth2/callback
      - https://{{ getenv "SERVER_HOST" }}:7474/oauth2/callback
      - https://{{ getenv "SERVER_HOST" }}:9490/oauth2/callback

# One entry per user. Email must be unique; Outline uses it to identify the person.
staticPasswords:
  - email: "admin@example.internal"
    username: "admin"
    preferredUsername: "admin"
    hash: "<output of caddy hash-password>"
    userID: "<output of /proc/sys/kernel/random/uuid>"

# Outside sign-in providers: off until you uncomment one (see the guide options: Google sign-in, outside sign-in).
# Each adds a button on the Dex sign-in page, next to the username and password form.
# connectors:
#   - type: google
#     id: google
#     name: Google
#     config:
#       clientID: {{ getenv "GOOGLE_CLIENT_ID" }}
#       clientSecret: $GOOGLE_CLIENT_SECRET
#       redirectURI: https://{{ getenv "SERVER_HOST" }}:5556/dex/callback
#       # hostedDomains: [domain.com]    # allow only accounts of your Google Workspace domain
#   - type: microsoft
#     id: microsoft
#     name: Microsoft
#     config:
#       clientID: {{ getenv "MS_CLIENT_ID" }}
#       clientSecret: $MS_CLIENT_SECRET
#       tenant: {{ getenv "MS_TENANT_ID" }}
#       redirectURI: https://{{ getenv "SERVER_HOST" }}:5556/dex/callback
#   # Microsoft through a tenant you administer, with colleagues invited as guests (see the guide option)
#   - type: oidc
#     id: entra-guests
#     name: Microsoft
#     config:
#       issuer: https://login.microsoftonline.com/{{ getenv "ENTRA_GUEST_TENANT_ID" }}/v2.0
#       clientID: {{ getenv "ENTRA_GUEST_CLIENT_ID" }}
#       clientSecret: $ENTRA_GUEST_CLIENT_SECRET
#       redirectURI: https://{{ getenv "SERVER_HOST" }}:5556/dex/callback
#       scopes: [openid, profile, email]
#       insecureSkipEmailVerified: true   # Entra sends no email_verified claim
#   - type: oidc
#     id: auth0
#     name: Auth0
#     config:
#       issuer: {{ getenv "AUTH0_ISSUER" }}
#       clientID: {{ getenv "AUTH0_CLIENT_ID" }}
#       clientSecret: $AUTH0_CLIENT_SECRET
#       redirectURI: https://{{ getenv "SERVER_HOST" }}:5556/dex/callback
#       scopes: [openid, profile, email]
```

`/opt/stacks/dex/compose.yaml`:
```yaml
services:
  dex:
    image: ghcr.io/dexidp/dex:latest
    container_name: dex
    restart: unless-stopped
    command: ["dex", "serve", "/etc/dex/config.yaml"]
    environment:
      SERVER_HOST: ${SERVER_HOST}
      OUTLINE_OIDC_SECRET: ${OUTLINE_OIDC_SECRET}
      GRAFANA_OIDC_SECRET: ${GRAFANA_OIDC_SECRET}
      PORTAINER_OIDC_SECRET: ${PORTAINER_OIDC_SECRET}
      LANGFUSE_OIDC_SECRET: ${LANGFUSE_OIDC_SECRET}
      LITELLM_OIDC_SECRET: ${LITELLM_OIDC_SECRET}
      OPENWEBUI_OIDC_SECRET: ${OPENWEBUI_OIDC_SECRET}
      GATE_OIDC_SECRET: ${GATE_OIDC_SECRET}
      # Outside sign-in providers; empty until set in .env
      GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID:-}
      GOOGLE_CLIENT_SECRET: ${GOOGLE_CLIENT_SECRET:-}
      MS_CLIENT_ID: ${MS_CLIENT_ID:-}
      MS_CLIENT_SECRET: ${MS_CLIENT_SECRET:-}
      MS_TENANT_ID: ${MS_TENANT_ID:-}
      ENTRA_GUEST_CLIENT_ID: ${ENTRA_GUEST_CLIENT_ID:-}
      ENTRA_GUEST_CLIENT_SECRET: ${ENTRA_GUEST_CLIENT_SECRET:-}
      ENTRA_GUEST_TENANT_ID: ${ENTRA_GUEST_TENANT_ID:-}
      AUTH0_ISSUER: ${AUTH0_ISSUER:-}
      AUTH0_CLIENT_ID: ${AUTH0_CLIENT_ID:-}
      AUTH0_CLIENT_SECRET: ${AUTH0_CLIENT_SECRET:-}
    volumes:
      - ./config.yaml:/etc/dex/config.yaml:ro
      - dex_data:/var/dex
      # - ./web:/srv/dex/web-custom:ro   # custom login page (optional)
    networks: [edge]

  # Sign-in gate for apps without their own sign-in. Caddy asks it before letting a request through.
  oauth2-proxy:
    image: quay.io/oauth2-proxy/oauth2-proxy:latest
    container_name: oauth2-proxy
    restart: unless-stopped
    environment:
      OAUTH2_PROXY_PROVIDER: oidc
      OAUTH2_PROXY_PROVIDER_DISPLAY_NAME: Dex
      OAUTH2_PROXY_CLIENT_ID: sso-gate
      OAUTH2_PROXY_CLIENT_SECRET: ${GATE_OIDC_SECRET}
      OAUTH2_PROXY_COOKIE_SECRET: ${GATE_COOKIE_SECRET}
      OAUTH2_PROXY_COOKIE_SECURE: "true"
      OAUTH2_PROXY_EMAIL_DOMAINS: "*"
      OAUTH2_PROXY_SCOPE: openid email profile
      # The browser reaches Dex through Caddy; the gate calls Dex directly (it does not trust the internal CA)
      OAUTH2_PROXY_OIDC_ISSUER_URL: https://${SERVER_HOST}:5556/dex
      OAUTH2_PROXY_SKIP_OIDC_DISCOVERY: "true"
      OAUTH2_PROXY_LOGIN_URL: https://${SERVER_HOST}:5556/dex/auth
      OAUTH2_PROXY_REDEEM_URL: http://dex:5556/dex/token
      OAUTH2_PROXY_OIDC_JWKS_URL: http://dex:5556/dex/keys
      OAUTH2_PROXY_WHITELIST_DOMAINS: ${SERVER_HOST}:*
      OAUTH2_PROXY_HTTP_ADDRESS: 0.0.0.0:4180
      OAUTH2_PROXY_REVERSE_PROXY: "true"
      OAUTH2_PROXY_SET_XAUTHREQUEST: "true"
      OAUTH2_PROXY_SKIP_PROVIDER_BUTTON: "true"
      OAUTH2_PROXY_UPSTREAMS: static://202
    depends_on: [dex]
    networks: [edge]

networks:
  edge:
    external: true

volumes:
  dex_data:
    external: true
```
```bash
docker volume create dex_data

cd /opt/stacks/dex && docker compose up -d
```

```bash
cat > /opt/stacks/caddy/conf.d/dex.caddy <<'EOF'
https://{$SERVER_HOST}:5556 {
	tls internal
	reverse_proxy dex:5556
}
EOF
cat > /opt/stacks/caddy/conf.d/00-sso.caddy <<'EOF'
# Sign-in gate, used by a site as: import sso <container>:<port>
(sso) {
	handle /oauth2/* {
		reverse_proxy oauth2-proxy:4180
	}
	handle {
		forward_auth oauth2-proxy:4180 {
			uri /oauth2/auth
			copy_headers X-Auth-Request-User X-Auth-Request-Email
			@signin status 401
			handle_response @signin {
				redir * /oauth2/sign_in?rd={scheme}://{hostport}{uri}
			}
		}
		reverse_proxy {args[0]}
	}
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
- Like Outline, Dex answers on `SERVER_HOST` only: its `issuer` is one fixed address.
- `00-sso.caddy` defines the gate once; the `00-` keeps it first when Caddy loads `conf.d/`. Apps behind the gate (Steps 9, 14, 15) use `import sso <container>:<port>` in place of `reverse_proxy`, and answer on `SERVER_HOST` only, because the sign-in cookie belongs to one address.
- The gate lets in anyone who can sign in to Dex. Internal traffic between containers (e.g. Grafana reading `http://prometheus:9090`) never passes Caddy, so it isn't gated.

**Check the result.** Every line must match the table:
```bash
docker inspect -f '{{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}' dex oauth2-proxy
docker inspect -f '{{.Name}}  networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' dex oauth2-proxy
docker inspect dex --format '{{range .Mounts}}mount {{.Destination}} <- {{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}}{{println}}{{end}}'
docker inspect oauth2-proxy --format '{{range .Config.Env}}{{println .}}{{end}}' | grep ^OAUTH2_PROXY_COOKIE_SECRET= | cut -d= -f2 | tr -d '\n' | wc -c
docker exec dex grep -c "^  - id:" /etc/dex/config.yaml
curl -sv https://${SERVER_HOST}:5556/dex/.well-known/openid-configuration -o /dev/null 2>&1 | grep -E "issuer:|HTTP/"
```

| Line | Expected |
|---|---|
| state | both `running`, `restart=unless-stopped`; images `ghcr.io/dexidp/dex:latest`, `quay.io/oauth2-proxy/oauth2-proxy:latest` |
| networks | `edge` for both |
| `mount` | `/etc/dex/config.yaml <- /opt/stacks/dex/config.yaml`, `/var/dex <- dex_data` |
| `wc -c` | `32`: the gate cookie secret's length (the gate refuses any other; the value is not shown) |
| `grep -c` | the number of clients in `config.yaml` (one per app, plus `sso-gate`) |
| `curl` | `issuer: CN=Caddy Local Authority …` and `HTTP/2 200` |

**Verify:**
```bash
curl -k https://${SERVER_HOST}:5556/dex/.well-known/openid-configuration
```
Expect JSON whose `issuer` is `https://<SERVER_HOST>:5556/dex`. If Dex keeps restarting, `docker logs dex` names the config line it rejects. The gate is checked when the first gated app is deployed (Step 9): opening Prometheus should show the Dex login first.

### Authentication

Dex is where people actually sign in; every app behind it trusts Dex. Its sign-in page shows one button per method, listed in this order in `config.yaml`:

**Dex local users** (free, default): usernames and passwords in `staticPasswords`. Works without any outside account or internet access; keep at least your own entry as a fallback when outside providers are on.

**Managing users:** `config.yaml` is the user list, so unlike other config files it's meant to change: add, edit, or remove an entry under `staticPasswords`, then `cd /opt/stacks/dex && docker compose up -d --force-recreate dex`. Recreate, don't just restart: `config.yaml` is mounted as a single file, and editors that save by replacing the file (vim, for one) leave a running container looking at the old copy, so a restart reloads stale settings. Check with `docker exec dex grep email /etc/dex/config.yaml`. A new password is a new `hash`. Removing someone from Dex stops new sign-ins; also suspend them in Outline (Settings → Members), since their current Outline session stays valid until it expires. Users can't reset their own password; you change the hash.

**Google Account** (free): a **Google** button through the `google` connector, so company Google accounts work in every app behind Dex at once. Needs `SERVER_HOST` under a real domain. See [Google sign-in](options/google-sign-in.md).

**Azure** (free): a **Microsoft** button through the `microsoft` connector (people in your tenant) or `entra-guests` (colleagues invited as guests into a tenant you administer). Registering the app may need a tenant admin. See [Outside sign-in](options/dex-outside-sign-in.md), which also covers Auth0.

Apps match people by email, so someone who signs in with Google one day and Microsoft the next stays one user as long as both give the same address.

### Options

- [Custom login page](options/dex-custom-login-page.md) — your own name, logo, the Inter font, and your own HTML for the sign-in page.

### Test

1. **Discovery:** `curl -sk https://${SERVER_HOST}:5556/dex/.well-known/openid-configuration` prints JSON with `"issuer":"https://<SERVER_HOST>:5556/dex"`.
2. **A password sign-in:** after Step 7, Outline's **Continue with Dex** shows Dex's sign-in page; a user from `staticPasswords` signs in and lands in Outline.
3. **The gate:** after Step 9, `curl -skI https://${SERVER_HOST}:9090 | head -3` shows a `302` to `/oauth2/sign_in`; in a browser, Prometheus asks for the Dex sign-in first.
4. **Outside providers** (if turned on): the Dex page shows **Google** or **Microsoft**, and signing in with it reaches the app.

