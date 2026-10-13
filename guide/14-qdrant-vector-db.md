## Step 14: Qdrant (vector DB)

Adds semantic search next to Sourcebot's keyword search. Ollama creates the embeddings (`qwen3-embedding:0.6b`); Qdrant stores and searches them on CPU.

**Check:** `qdrant`.

### Clean reinstall

Removes Qdrant as if it had never been installed. Skip it for a first install. **Every collection is lost** with the volume, including the documents Open WebUI stored; they have to be uploaded and indexed again. Each line asks first.
```bash
confirm "Stop and remove the Qdrant container?" && cd /opt/stacks/qdrant && docker compose down; cd ~
confirm "Delete every collection (volume qdrant_data)?" && docker volume rm qdrant_data
confirm "Delete /opt/stacks/qdrant and its Caddy file?" && rm -rf /opt/stacks/qdrant /opt/stacks/caddy/conf.d/qdrant.caddy && docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
confirm "Delete the Qdrant image (downloaded again on the next install)?" && docker image rm qdrant/qdrant:latest
```

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -x qdrant
docker volume ls -q | grep -x qdrant_data
ls -d /opt/stacks/qdrant /opt/stacks/caddy/conf.d/qdrant.caddy 2>/dev/null
```

### Install

```bash
mkdir -p /opt/stacks/qdrant
```

`/opt/stacks/qdrant/compose.yaml`:
```yaml
services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    volumes: [qdrant_data:/qdrant/storage]
    networks: [edge]
    # gRPC (6334) is a raw binary protocol like the Neo4j bolt port, so Caddy
    # does not front it. Only exposed if something outside Docker needs it
    # directly; uncomment to test:
    # ports:
    #   - "6334:6334"

networks:
  edge:
    external: true

volumes:
  qdrant_data:
    external: true
```
```bash
docker volume create qdrant_data

cd /opt/stacks/qdrant && docker compose up -d
```
```bash
cat > /opt/stacks/caddy/conf.d/qdrant.caddy <<'EOF'
https://{$SERVER_HOST}:6333 {
	tls internal
	import sso qdrant:6333
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
**Check the result.** Every line must match the table:
```bash
docker inspect qdrant --format 'name={{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}'
docker inspect qdrant --format 'networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}  ports={{range $p, $b := .NetworkSettings.Ports}}{{if $b}}{{$p}} {{end}}{{end}}'
docker inspect qdrant --format '{{range .Mounts}}mount {{.Destination}} <- {{.Name}}{{println}}{{end}}'
docker run --rm --network edge curlimages/curl -s http://qdrant:6333/healthz; echo
curl -skI https://${SERVER_HOST}:6333/dashboard | head -1
curl -sv https://${SERVER_HOST}:6333 -o /dev/null 2>&1 | grep -E "issuer:"
```

| Line | Expected |
|---|---|
| `name=` | `/qdrant  state=running  restart=unless-stopped`, image `qdrant/qdrant:latest` |
| `networks=` | `edge`, and `ports=` empty (Caddy fronts it; gRPC 6334 stays internal) |
| `mount` | `/qdrant/storage <- qdrant_data` |
| `healthz` | `healthz check passed` |
| `curl -skI` | `HTTP/2 302`: the sign-in gate sends the browser to Dex first |
| `issuer` | `CN=Caddy Local Authority …` |

**Verify** from inside Docker (the gate only applies to traffic through Caddy):
```bash
docker run --rm --network edge curlimages/curl -s http://qdrant:6333/collections
```
A fresh install returns `{"result":{"collections":[]},...}`. In a browser, `https://<SERVER_HOST>:6333/dashboard` shows the Dex login first, then the dashboard.

### Authentication

Qdrant has no login of its own.

**Dex** (free): the dashboard and API sit behind the sign-in gate from Step 6. The gate is for people with a browser. Scripts and agents on other machines can't pass it; run them in a container on `edge` (they use `http://qdrant:6333` directly), or see [Without the sign-in gate](options/without-sign-in-gate.md#qdrant-with-an-api-key) for Qdrant with an API key instead.

**Google Account** (free) and **Azure** (free): through Dex. The gate offers whatever Dex offers, so turning on Google or Microsoft in Dex covers this app too. oauth2-proxy could also use Google or Azure directly (free), but then every gated app skips Dex.

### Usage

**Not included:** indexing. Filling Qdrant needs your own script that chunks files, gets embeddings from Ollama (`/api/embeddings`, or LiteLLM's `local-embed`), and upserts them (`PUT /collections/<name>/points`).

### Test

1. **The API, from inside Docker:** the `collections` call above returns a list (empty on a fresh install).
2. **Write and read a point** (a throwaway collection):
   ```bash
   docker run --rm --network edge curlimages/curl -s -X PUT http://qdrant:6333/collections/test -H "Content-Type: application/json" -d '{"vectors":{"size":3,"distance":"Cosine"}}'
   docker run --rm --network edge curlimages/curl -s -X PUT http://qdrant:6333/collections/test/points -H "Content-Type: application/json" -d '{"points":[{"id":1,"vector":[0.1,0.2,0.3]}]}'
   docker run --rm --network edge curlimages/curl -s -X POST http://qdrant:6333/collections/test/points/search -H "Content-Type: application/json" -d '{"vector":[0.1,0.2,0.3],"limit":1}'
   confirm "Delete the test collection?" && docker run --rm --network edge curlimages/curl -s -X DELETE http://qdrant:6333/collections/test
   ```
   The search returns point `1` with a score near `1.0`.
3. **The dashboard:** `https://<SERVER_HOST>:6333/dashboard` asks for the Dex sign-in, then shows the collections (after Step 17, Open WebUI's appear once a document is uploaded).

