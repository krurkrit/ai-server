## Design decisions

1. **Sign-in through Dex** — one account for every app, managed on this server, so no SMTP relay or Azure admin rights are needed. Email and Microsoft/Google/Auth0 sign-in are options on top.
2. **Caddy is append-only** — its two files are written once in Step 3; each service adds one `conf.d` file. That's why Caddy comes before every service it fronts.
3. **Langfuse before LiteLLM** — so LiteLLM's config is written once with tracing already wired.
4. **Portainer and Neo4j Browser go through Caddy** on their own default ports, so they get the trusted CA instead of a self-signed cert or plain HTTP.
5. **Neo4j + Memgraph both run** — they don't share the GPU; Ollama and vLLM do, so only one of those runs at a time.
6. **GitHub MCP runs per client**, not as a hosted service; developer tools reach the server through LiteLLM and Sourcebot's MCP endpoint.
