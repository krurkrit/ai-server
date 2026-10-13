*Copied from `options/without-sign-in-gate.md` in the ai-server repo; import it as a document named "Option: Without the sign-in gate".*

For servers without Dex (Step 6 (document "Self-Hosted AI Server Setup Guide") skipped), or for an app that must be reachable by scripts from other machines. Write the app's Caddy file like this instead of the `import sso` version in its step: it answers on both addresses, and Caddy passes requests straight through.

| App (step) | Caddy file | Address line | In place of `import sso …` |
|---|---|---|---|
| Prometheus (Step 9) | `conf.d/prometheus.caddy` | `https://{$SERVER_HOST}:9090, https://{$SERVER_IP}:9090 {` | `reverse_proxy prometheus:9090` |
| Qdrant (Step 14) | `conf.d/qdrant.caddy` | `https://{$SERVER_HOST}:6333, https://{$SERVER_IP}:6333 {` | `reverse_proxy qdrant:6333` |
| Neo4j Browser (Step 15) | `conf.d/neo4j.caddy` | `https://{$SERVER_HOST}:7474, https://{$SERVER_IP}:7474 {` | Instead of the two `handle` blocks: the `@bolt` matcher, `reverse_proxy @bolt neo4j:7687`, and `reverse_proxy neo4j:7474` (Neo4j Browser connects with `bolt+s://` through it) |
| Memgraph Lab (Step 15) | `conf.d/memgraph.caddy` | `https://{$SERVER_HOST}:9490, https://{$SERVER_IP}:9490 {` | `reverse_proxy memgraph:3000` |

Example, Prometheus:
```bash
cat > /opt/stacks/caddy/conf.d/prometheus.caddy <<'EOF'
https://{$SERVER_HOST}:9090, https://{$SERVER_IP}:9090 {
	tls internal
	reverse_proxy prometheus:9090
}
EOF
docker compose -f /opt/stacks/caddy/compose.yaml exec caddy caddy reload --config /etc/caddy/Caddyfile
```
Without the gate, anyone who can reach the server opens these apps. Prometheus has no login at all; Neo4j Browser and Memgraph Lab still ask for the database login; keep the server internal-only.

## Qdrant with an API key

For scripts and agents on other machines, which can't pass a browser sign-in. Use the ungated Caddy file above, and require a key in Qdrant instead: add this to `qdrant`'s service in `/opt/stacks/qdrant/compose.yaml` when writing it, and `QDRANT_API_KEY=<openssl rand -hex 32>` to `/opt/stacks/qdrant/.env`:
```yaml
    environment:
      QDRANT__SERVICE__API_KEY: ${QDRANT_API_KEY}
```
Clients then send the header `api-key: <QDRANT_API_KEY>`. Containers on `edge` need it too (`http://qdrant:6333`), and the dashboard asks for it.

---

**Related:**
- Step 6: Dex (sign-in) (document "Self-Hosted AI Server Setup Guide") → Clean reinstall
- Step 9: Monitoring stack (document "Self-Hosted AI Server Setup Guide") → Authentication
- Step 14: Qdrant (vector DB) (document "Self-Hosted AI Server Setup Guide") → Authentication
- Step 15: Neo4j + Memgraph (document "Self-Hosted AI Server Setup Guide") → Authentication
