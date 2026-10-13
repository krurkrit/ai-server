# Option: Developer tools

Part of [Step 12: LiteLLM (gateway)](../ai-server-setup-guide.md#step-12-litellm-gateway) and [Step 16: OpenHands (agent)](../ai-server-setup-guide.md#step-16-openhands-agent). How to point the AI tools on a developer's PC at the server: VS Code, Claude Code (terminal, VS Code extension, Claude Desktop), Codex (CLI and desktop app), T3 Code, and Orca. Each section covers LiteLLM first, then a direct connection to Ollama or vLLM.

## Which connection to use

| | Through LiteLLM (normal) | Direct to Ollama or vLLM (testing) |
|---|---|---|
| Address | `https://<SERVER_HOST>:4000` | `http://<SERVER_HOST>:11434` (Ollama), `http://<SERVER_HOST>:8000` (vLLM) |
| Key | Your own LiteLLM virtual key | None: anyone on the network can use it |
| Models | Every name in LiteLLM's `config.yaml`, local and hosted | Only what that runtime runs (`ollama list`, or `VLLM_MODEL`) |
| Traced in Langfuse, limits, budgets | Yes | No |
| Server change needed | None | Open the port first: [Direct test ports](llm-direct-test-ports.md); close it again when done |

Use LiteLLM. Go direct only to test a runtime on its own, for a short time.

## Before you start

On each developer's PC:
1. **The server name and certificate:** the hosts-file line and the Caddy CA import from Step 4 (the Services page in Outline has both). Not needed for a direct connection, which is plain HTTP.
2. **Your own LiteLLM virtual key** from the admin (Admin UI → Virtual Keys); never the master key.
3. **Node-based tools** (Claude Code, its VS Code extension) do not use the Windows or macOS certificate store. Point them at the CA file as well, or they fail with `self-signed certificate in certificate chain`:
   ```bash
   setx NODE_EXTRA_CA_CERTS "C:\certs\caddy-root-ca.crt"
   ```
   On macOS or Linux, add `export NODE_EXTRA_CA_CERTS=$HOME/certs/caddy-root-ca.crt` to your shell profile. Open a new terminal (and restart the apps) afterwards.

Model names below (`claude-sonnet-5.5-shared`, `qwen3.5-9b`, ...) are the `model_name` values in LiteLLM's `config.yaml`; see the Services page for the current list.

## Claude Code CLI

**Through LiteLLM:** put this in `~/.claude/settings.json` (Windows: `%USERPROFILE%\.claude\settings.json`). The settings file reaches every place Claude Code runs, including T3 Code and Orca:
```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://<SERVER_HOST>:4000",
    "ANTHROPIC_AUTH_TOKEN": "<your LiteLLM virtual key>",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-5.5-shared",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4.5-shared",
    "NODE_EXTRA_CA_CERTS": "C:\\certs\\caddy-root-ca.crt",
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1"
  }
}
```
- Switch models in a session with `/model <name>`, or start with `claude --model <name>`. Model discovery adds LiteLLM's names to the `/model` list, but only those containing `claude` or `anthropic` (`claude-sonnet-5.5-shared`): local models (`qwen3.5-9b`) never appear there, so type their name, or map the built-in Sonnet and Haiku entries to them with `ANTHROPIC_DEFAULT_SONNET_MODEL` and `ANTHROPIC_DEFAULT_HAIKU_MODEL` (the picker then still says Sonnet, but runs your model).
- **Local models only** (nothing leaves the server): set both `..._SONNET_MODEL` and `..._HAIKU_MODEL` to a local name such as `qwen3.5-9b`; the Haiku one runs background tasks and would otherwise still go to Claude. Also add `"CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1"`, since local models reject some fields Claude Code sends to Claude.
- Check with `/status`: `Anthropic base URL` shows the server, and `Auth token` names `ANTHROPIC_AUTH_TOKEN`.
- Never put the key in a project's `.claude/settings.json`; that file is committed.

**Direct to Ollama** (Ollama 0.14 or later speaks Claude Code's API itself; the key is ignored):
```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://<SERVER_HOST>:11434",
    "ANTHROPIC_AUTH_TOKEN": "ollama",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "qwen3.5:9b",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "qwen3.5:9b",
    "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1"
  }
}
```
Here model names are Ollama tags (`qwen3.5:9b`), not LiteLLM names.

**Direct to vLLM:** the same with `"ANTHROPIC_BASE_URL": "http://<SERVER_HOST>:8000"` and the model as in `VLLM_MODEL`. vLLM only handles tool calls when started with `--enable-auto-tool-choice` and a `--tool-call-parser` that matches the model, which the guide's vLLM command does not set; without them Claude Code cannot use its tools on vLLM.

## Claude Code in VS Code

The Claude Code extension checks its login before it reads `~/.claude/settings.json`, so set the same values in VS Code itself: **Preferences: Open User Settings (JSON)**, then:
```json
{
  "claudeCode.environmentVariables": [
    { "name": "ANTHROPIC_BASE_URL", "value": "https://<SERVER_HOST>:4000" },
    { "name": "ANTHROPIC_AUTH_TOKEN", "value": "<your LiteLLM virtual key>" },
    { "name": "NODE_EXTRA_CA_CERTS", "value": "C:\\certs\\caddy-root-ca.crt" }
  ]
}
```
For a direct connection, use the values from the direct examples above.

## Claude Desktop

Claude Desktop does not read `ANTHROPIC_BASE_URL` or `settings.json`; it has its own gateway setting, which covers its Chat, Cowork, and Code sessions:
1. **Help → Troubleshooting → Enable Developer Mode** (the app restarts with a **Developer** menu).
2. **Developer → Configure Third-Party Inference**: set the inference provider to **Gateway**, the base URL to `https://<SERVER_HOST>:4000`, the credential to **Static API key**, and the key to your LiteLLM virtual key.
3. **Models in the picker:** either let the app read LiteLLM's `/v1/models` (model discovery), or give a fixed list in the same form (`inferenceModels`): one entry per LiteLLM name, the first one the default, each with a readable label, e.g. `{"name": "qwen3.5-9b", "labelOverride": "Qwen3.5 9B (local)"}`. A Claude name can also carry `"anthropicFamilyTier": "sonnet"` so that Code sessions asking for Sonnet get it.
4. Restart the app; it reads this only at launch. `Gateway was unreachable` means the address or certificate is wrong: test with the `curl` under [Check](#check).

While a gateway is set, Claude Desktop cannot use Anthropic-hosted cloud environments or Remote Control. A direct connection to Ollama or vLLM is not supported here; use LiteLLM.

## Codex CLI and Codex app

The Codex CLI and the Codex desktop app share `~/.codex/config.toml` (Windows: `%USERPROFILE%\.codex\config.toml`). Codex speaks only the Responses API (`wire_api = "responses"`; older guides with `"chat"` no longer work).

**Through LiteLLM**, which serves the Responses API at `/v1/responses`:
```toml
model = "claude-sonnet-5.5-shared"
model_provider = "litellm"

[model_providers.litellm]
name = "LiteLLM"
base_url = "https://<SERVER_HOST>:4000/v1"
env_key = "LITELLM_API_KEY"
wire_api = "responses"
```
Set the key as a user environment variable, so desktop apps (Codex app, T3 Code, Orca) see it too, then open a new terminal:
```bash
setx LITELLM_API_KEY "<your LiteLLM virtual key>"
```
Switch models with `codex -m <name>`, or change `model` in the file; the model picker of Codex shows its own OpenAI list, not LiteLLM's names. If long agent turns stop halfway, raise `stream_idle_timeout_ms` in the provider block.

**Direct to Ollama** (the provider ID `ollama` is reserved, so use another one):
```toml
model = "qwen3.5:9b"
model_provider = "server-ollama"

[model_providers.server-ollama]
name = "Ollama on the AI server"
base_url = "http://<SERVER_HOST>:11434/v1"
wire_api = "responses"
```
A Codex error that the server does not support Responses means Ollama is too old; update it (`update-stack.sh llm-runtime`).

**Direct to vLLM:** the same with `base_url = "http://<SERVER_HOST>:8000/v1"` and `model` as in `VLLM_MODEL`; the tool-call note under Claude Code applies here too.

## VS Code Copilot Chat

VS Code can add the server as a **Custom Endpoint** model provider, for Chat and agent mode:
1. Chat view → model picker → **Manage Language Models** → **Add Models** → **Custom Endpoint**.
2. Enter a group name, a display name, and your LiteLLM virtual key; choose the API type **Chat Completions**.
3. In the `chatLanguageModels.json` that opens, add one entry per model (each then shows in the model picker under its display name), with `"vendor": "customendpoint"`, `"id"` the LiteLLM name (e.g. `gemma4-12b`), `"url": "https://<SERVER_HOST>:4000/v1/chat/completions"`, `"toolCalling": true` for agent mode, and its token limits (32768 for the local models).

Direct: the same with `"url": "http://<SERVER_HOST>:11434/v1/chat/completions"` (Ollama, `id` an Ollama tag) or `"http://<SERVER_HOST>:8000/v1/chat/completions"` (vLLM), and any key.

Limits: code completions, semantic search, and embeddings still need GitHub Copilot; on Copilot Business or Enterprise an admin must allow **Bring Your Own Language Model Key in VS Code**. VS Code uses the operating system certificate store, so the Step 4 import is enough. Extensions such as Continue or Cline take the same base URL (`https://<SERVER_HOST>:4000/v1`) and key directly.

## T3 Code and Orca

T3 Code and Orca do not call models themselves: they run Claude Code and Codex on your PC, each task in its own git worktree. Set up [Claude Code CLI](#claude-code-cli) (the settings file) and [Codex](#codex-cli-and-codex-app) (`config.toml` plus the `LITELLM_API_KEY` user variable), restart the app, and choose Claude Code or Codex in it. Every agent then goes through LiteLLM, or directly to Ollama or vLLM if that is what you set up.

Their usage and rate-limit panels are built for Claude and OpenAI subscriptions and show little through LiteLLM; usage per key is in LiteLLM's Admin UI (**Usage**) and in Langfuse. T3 Chat (the web chat at t3.chat) is a different product: it runs on T3's servers, which cannot reach this server.

## Local models in agent tools

Claude Code and Codex send long prompts (often 20k tokens and more) and rely on tool calls. On a 16 GB GPU:
- `qwen3.5-9b` works best: it has room for the context. `qwen3.6-35b-a3b` is smarter but tight on context and slow over many steps; `qwen3.8-27b` is too slow for agents.
- Ollama must give the model enough context: the guide sets `OLLAMA_CONTEXT_LENGTH=32768` (Step 13). With Ollama's 4k default the model never sees its instructions.
- Expect local models to handle small, clear tasks (explain code, a small edit, a test) and to struggle with long multi-step work. Use the Claude or OpenAI models for that, and local models when code must not leave the server.

## Check

| Check | Expected |
|---|---|
| `curl -sk https://${SERVER_HOST}:4000/v1/models -H "Authorization: Bearer <your virtual key>"` | The model names your key may use |
| Claude Code: `/status` | `Anthropic base URL` is the server; `Auth token` names `ANTHROPIC_AUTH_TOKEN` |
| A prompt in the tool | An answer; the call appears in Langfuse and under your key in LiteLLM (**Usage**) |
| `docker exec ollama ollama ps` on the server, during a local-model call | The model, ideally `100% GPU` |

| Error | Cause |
|---|---|
| `self-signed certificate` or `SSL certificate verification failed` | CA not imported (Step 4), or `NODE_EXTRA_CA_CERTS` missing for Claude Code |
| `401` | Wrong or missing virtual key, or the key is in the wrong variable |
| `model not found` / `No deployments available` | The name is not in LiteLLM's `config.yaml`, or it is an Ollama-only model while vLLM runs |
| `400` naming unknown fields, `context_management`, or `thinking` | A local model behind Claude Code: set `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1` |
| Connection refused on `:11434` or `:8000` | The direct port is closed: [Direct test ports](llm-direct-test-ports.md) |

---

**Related:**
- [Step 12: LiteLLM (gateway)](../ai-server-setup-guide.md#step-12-litellm-gateway) → Install
- [Step 16: OpenHands (agent)](../ai-server-setup-guide.md#step-16-openhands-agent) → Connecting tools (MCP)
- [Option: Direct test ports](llm-direct-test-ports.md)
