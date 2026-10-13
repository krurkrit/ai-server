## Step 15: Neo4j + Memgraph

Neither uses the GPU, so both run together.

**Check:** `neo4j`, `memgraph`.

### Clean reinstall

Removes Neo4j and Memgraph as if they had never been installed. Skip it for a first install. **Every graph is lost** with the volumes. Neo4j sets `NEO4J_PASSWORD` only on its first start with an empty volume, so after a reinstall the password in `.env` applies again. Each line asks first.
```bash
confirm "Stop and remove Neo4j and Memgraph?" && cd /opt/stacks/graphdb && docker compose --profile "*" down; cd ~
confirm "Delete every graph (volumes neo4j_data, neo4j_logs, memgraph_data)?" && docker volume rm neo4j_data neo4j_logs memgraph_data
confirm "Delete /opt/stacks/graphdb (.env, compose.yaml, the graphdb.sh link) and the Caddy files neo4j.caddy, memgraph.caddy?" && rm -rf /opt/stacks/graphdb /opt/stacks/caddy/conf.d/neo4j.caddy /opt/stacks/caddy/conf.d/memgraph.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the Neo4j and Memgraph images?" && docker image rm neo4j:5 memgraph/memgraph-platform:latest
```

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -E '^(neo4j|memgraph)$'
docker volume ls -q | grep -E '^(neo4j_data|neo4j_logs|memgraph_data)$'
ls -d /opt/stacks/graphdb 2>/dev/null
```

### Install

```bash
mkdir -p /opt/stacks/graphdb
```

`/opt/stacks/graphdb/.env`:
```env
NEO4J_PASSWORD=CHANGE_ME        # at least 8 characters
```

`/opt/stacks/graphdb/compose.yaml`:
```yaml
services:
  neo4j:
    image: neo4j:5
    container_name: neo4j
    profiles: ["neo4j"]
    restart: unless-stopped
    ports:
      - "7687:7687"   # bolt
    environment:
      NEO4J_AUTH: neo4j/${NEO4J_PASSWORD}
    volumes:
      - neo4j_data:/data
      - neo4j_logs:/logs   # the image declares both; named, so no anonymous volume appears
    networks: [edge]

  memgraph:
    image: memgraph/memgraph-platform:latest
    container_name: memgraph
    profiles: ["memgraph"]
    restart: unless-stopped
    ports:
      - "7688:7687"   # bolt, remapped off the Neo4j port 7687
    volumes: [memgraph_data:/var/lib/memgraph]
    networks: [edge]

networks:
  edge:
    external: true

volumes:
  neo4j_data:
    external: true
  neo4j_logs:
    external: true
  memgraph_data:
    external: true
```
The web UIs (Neo4j Browser, Memgraph Lab) have no host ports; Caddy fronts them. The bolt ports are published directly because bolt isn't HTTP.

Link `graphdb.sh` from `~/ai-server` into the stack folder ([Helper scripts](options/helper-scripts.md)), then start both:
```bash
docker volume create neo4j_data
docker volume create neo4j_logs
docker volume create memgraph_data

ln -sf ~/ai-server/graphdb.sh /opt/stacks/graphdb/graphdb.sh
cd /opt/stacks/graphdb
./graphdb.sh both       # default — starts and keeps both running
./graphdb.sh status     # or: neo4j / memgraph / stop, if you ever want to isolate one
```
```bash
cat > /opt/stacks/caddy/conf.d/neo4j.caddy <<'EOF'
# Neo4j Browser runs in the browser and opens its database connection as a WebSocket to this
# same address (bolt+s://SERVER_HOST:7474); those go to the bolt port, the rest to the web UI.
# Written out instead of import sso, which allows only one target; same sign-in gate.
https://{$SERVER_HOST}:7474 {
	tls internal
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
		@bolt {
			header Connection *Upgrade*
			header Upgrade websocket
		}
		reverse_proxy @bolt neo4j:7687
		reverse_proxy neo4j:7474
	}
}
EOF
cat > /opt/stacks/caddy/conf.d/memgraph.caddy <<'EOF'
https://{$SERVER_HOST}:9490 {
	tls internal
	import sso memgraph:3000
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
**Check the result.** Every line must match the table:
```bash
/opt/stacks/graphdb/graphdb.sh status
docker inspect -f '{{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}  networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' neo4j memgraph
docker inspect -f '{{.Name}}{{range .Mounts}}  {{.Destination}} <- {{.Name}}{{end}}' neo4j memgraph
docker port neo4j 7687; docker port memgraph 7687
docker exec neo4j cypher-shell -u neo4j -p "$(grep ^NEO4J_PASSWORD= /opt/stacks/graphdb/.env | cut -d= -f2-)" "RETURN 1 AS ok"
curl -skI https://${SERVER_HOST}:7474 | head -1; curl -skI https://${SERVER_HOST}:9490 | head -1
```

| Line | Expected |
|---|---|
| `status` | both running |
| state | both `running`, `restart=unless-stopped`, images `neo4j:5` and `memgraph/memgraph-platform:latest`, `networks=edge` |
| mounts | `neo4j`: `/data <- neo4j_data`, `/logs <- neo4j_logs`; `memgraph`: `/var/lib/memgraph <- memgraph_data`. A long hash instead of a name is an anonymous volume: give that path a named volume, as for Neo4j's logs |
| `docker port` | `0.0.0.0:7687` (Neo4j) and `0.0.0.0:7688` (Memgraph): the bolt ports for drivers |
| `cypher-shell` | `ok` / `1`: the password in `.env` works |
| `curl -skI` | `HTTP/2 302` twice: the sign-in gate is in front of both web UIs |

**Verify:** `https://<SERVER_HOST>:7474` and `https://<SERVER_HOST>:9490` show the Dex login first (or pass straight through if you already signed in), then Neo4j Browser and Memgraph Lab. In Neo4j Browser's connect form, set **Connect URL** to `bolt+s://<SERVER_HOST>:7474` (not the suggested `neo4j://localhost:7687`), user `neo4j`, password `NEO4J_PASSWORD`. A browser page cannot open the unencrypted bolt port 7687, and `neo4j://` asks the server for addresses that point to `localhost`; the `bolt+s` connection goes through Caddy, encrypted and behind the same sign-in. Drivers connect to `<SERVER_HOST>:7687` (Neo4j) and `<SERVER_HOST>:7688` (Memgraph).

### Authentication

Neo4j keeps its own database login (`neo4j` / `NEO4J_PASSWORD`), asked in Neo4j Browser and by drivers. Memgraph Lab has no login of its own.

**Dex** (free): both web UIs sit behind the sign-in gate from Step 6, in front of the database login. The bolt ports are not gated. No Dex? See [Without the sign-in gate](options/without-sign-in-gate.md).

**Google Account** (free) and **Azure** (free): through Dex. The gate offers whatever Dex offers, so turning on Google or Microsoft in Dex covers both web UIs too. oauth2-proxy could also use Google or Azure directly (free), but then every gated app skips Dex.

### Test

1. **Neo4j Browser:** `https://<SERVER_HOST>:7474`, the Dex sign-in, then connect with `bolt+s://<SERVER_HOST>:7474`, user `neo4j`; run `RETURN 1` and get `1`.
2. **Memgraph Lab:** `https://<SERVER_HOST>:9490`, the Dex sign-in, connect; run `RETURN 1;` and get `1`.
3. **A driver from a PC** (the bolt ports): e.g. Python `neo4j` package, `GraphDatabase.driver("bolt://<SERVER_HOST>:7687", auth=("neo4j", "<password>"))` runs `RETURN 1`; the same with port `7688` for Memgraph.
4. **Data survives a restart:** `CREATE (:Test {name: "x"})` in Neo4j Browser, `./graphdb.sh stop`, `./graphdb.sh both`, `MATCH (n:Test) RETURN n` still finds it; delete it with `MATCH (n:Test) DELETE n`.

