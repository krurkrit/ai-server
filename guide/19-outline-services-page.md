## Step 19: Outline services page

The one step you come back to: it's content inside Outline, not config. Create a "Services" document in Outline and add a line each time you deploy a service:
```
- Outline:      https://<SERVER_HOST>
- Infisical:    https://<SERVER_HOST>:8080
- Portainer:    https://<SERVER_HOST>:9443
- Grafana:      https://<SERVER_HOST>:9450
- Prometheus:   https://<SERVER_HOST>:9090
- Sourcebot:    https://<SERVER_HOST>:9460
- Langfuse:     https://<SERVER_HOST>:9470
- LiteLLM:      https://<SERVER_HOST>:4000
- Qdrant:       https://<SERVER_HOST>:6333
- Neo4j:        https://<SERVER_HOST>:7474
- Memgraph Lab: https://<SERVER_HOST>:9490
- OpenHands:    http://<SERVER_IP>:3000
- Open WebUI:   https://<SERVER_HOST>:9485
```

**Say how to sign in to each service** next to its link: "Google (through Dex)" for the apps behind Dex, and **Own login** for the others, with the reason, so users know why they need a separate account: Infisical (Dex sign-in needs an Infisical Enterprise license; Google sign-in is free), Sourcebot (SSO requires a Sourcebot Enterprise license), LiteLLM (an API key from the admin; Admin UI through Dex is free for up to 5 users since v1.76.0, more need a LiteLLM Enterprise license).

**AI models on the same page,** so users know which name to pick and what works while vLLM runs. Copy the table, and update it when you change `/opt/stacks/litellm/config.yaml`:

| Model name | What it is | Use for | Speed | Works on |
|---|---|---|---|---|
| `local-model` | Whatever runs now (Gemma 4 12B) | Default; tools that should not care | Fast | Always |
| `gemma4-12b` | Gemma 4 12B | Everyday chat and code; reads images | Fast | Ollama and vLLM |
| `qwen3.5-9b` | Qwen3.5 9B | Long documents and large files (most context) | Fastest | Ollama only |
| `gemma4-26b-a4b` | Gemma 4 26B A4B | Better answers, short context (~8k tokens) | Fast | Ollama only |
| `qwen3.6-35b-a3b` | Qwen3.6 35B A3B | Harder reasoning and code | Medium | Ollama only |
| `qwen3.8-27b` | Qwen3.8 27B | Best answers for occasional hard questions | Slow | Ollama only |

Add for users: the API address `https://<SERVER_HOST>:4000` (OpenAI-compatible) and how to get an API key; that "Ollama only" models fail while the server runs vLLM (`./switch-llm.sh status` shows which); and that switching between models takes a few seconds the first time, because only one is kept in GPU memory.

**Share the CA certificate on the same page** so new users can trust every service:
1. Copy `caddy-root-ca.crt` (made in Step 4) to your PC, and get its fingerprint:
   ```bash
   openssl x509 -in /opt/stacks/caddy/caddy-root-ca.crt -noout -fingerprint -sha256
   ```
2. Drag the `.crt` file into the "Services" document; Outline stores it as a downloadable attachment. Paste the fingerprint next to it, so users can check they got the right file (Windows shows it under the certificate's Details → Thumbprint, as SHA-1; compare with `-sha1` instead of `-sha256` there).
3. Add the import steps from Step 4 below it.

A new user sees one certificate warning the first time they open Outline, before they've imported the certificate. That's expected; they continue once, download, import, and restart the browser.

Only share `root.crt`. **Never** share `root.key` from the same Caddy folder — anyone with it can issue certificates your clients will trust. The root certificate is valid for 10 years; it only changes if Caddy's `caddy_data` volume is lost, and then you re-share the new one.

