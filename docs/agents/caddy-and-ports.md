# Caddy and port rules

How Caddy files are written and reloaded, which port each service gets, and how ports are published.

## Caddy is append-only

- Step 3 writes `Caddyfile` (a global `default_sni {$SERVER_IP}`, needed because clients connecting by IP send no SNI; a `:9500` health block on both addresses; and `import conf.d/*.caddy`) and `compose.yaml`, which publishes 5556, 9443, 9090, 4000, 6333, 7474 (own defaults), then 9500, 443, and 9450–9499 (assigned) up front, and passes `SERVER_HOST` and `SERVER_IP` from `.env` into the container via `environment:`. Neither file is ever edited again.
- Each later service adds exactly one `conf.d/<svc>.caddy` using `https://{$SERVER_HOST}:<port>, https://{$SERVER_IP}:<port> { tls internal; reverse_proxy <container>:<internal-port> }`, so it answers on the name and the IP. Exceptions: Dex, Outline, and Langfuse list only `{$SERVER_HOST}`, because each is bound to one URL (Dex `issuer`, Outline `URL`, Langfuse `NEXTAUTH_URL`). A repeated address (no hostname, so both variables hold the IP) is allowed inside one site block; the same address in two different blocks is an "ambiguous site definition" error, so never add a separate IP-only block.
- Sign-in gate: `conf.d/00-sso.caddy` (written in the Dex step) defines the `(sso)` snippet; the `00-` makes it load before the sites that import it. An app without its own login uses `import sso <container>:<port>` in place of `reverse_proxy`, lists `{$SERVER_HOST}` only (the sign-in cookie belongs to one address), and needs its `https://<SERVER_HOST>:<port>/oauth2/callback` in the Dex `sso-gate` client. Each gated step also says how to write the file without the gate.
- Indent Caddy files with tabs (what `caddy fmt` expects); spaces trigger a "not formatted" warning on every reload.
- After adding the file, reload with `docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile`.

## Port scheme

| Port | Use |
|---|---|
| 443 | Outline |
| 5556 | Dex |
| 9443 | Portainer (Caddy proxies to `portainer:9000`) |
| 9090 | Prometheus |
| 4000 | LiteLLM |
| 6333 | Qdrant (gRPC 6334 internal only) |
| 7474 | Neo4j Browser |
| 7687 / 7688 | Neo4j / Memgraph bolt (direct) |
| 9450–9499 | Shared category blocks (below) |
| 9500 | Caddy health |

A service's own default port comes first, whenever nothing else in the guide uses it. Only services that would collide on a shared default (3000) take a slot in category blocks of 5 within 9450–9499 (blocks start at 9450, 9455, …, 9495). A newly added service with a free default port gets that port added to Step 3's Caddy `ports:` list (so fresh installs publish it up front) plus a row in the "Caddy ports for later services" table of `options/upgrade-older-install.md`, for servers whose Caddy predates it (Infisical and Dex are the examples).

| Block | Category | Service |
|---|---|---|
| 9450 | Monitoring | Grafana |
| 9460 | Code Intelligence | Sourcebot |
| 9470 | LLM Observability | Langfuse |
| 9480 | AI Agents | Free (OpenHands runs on its own port 3000, outside Caddy) |
| 9485 | AI Chat | Open WebUI |
| 9490 | Graph DB Dashboards | Memgraph Lab |
| 9475 | App monitoring | GlitchTip (option) |
| 9455, 9465, 9495 | Free | — |

`tools/check.py` enforces one owner per host port: a port is published by one compose service only (commented-out `ports:` lines count, since uncommenting publishes them), served by one Caddy file only, and every port a Caddy site uses is in the caddy service's `ports:` list. An option that rewrites the same service or the same Caddy file is an alternative, not a clash.

A new port also needs a row in the guide's "Access map" and, if drawn, a label in `diagrams/architecture-access-map.svg`.
