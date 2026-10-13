# Option: Direct test ports

Part of [Step 13: Ollama / vLLM](../ai-server-setup-guide.md#step-13-ollama--vllm-runtime). For testing from outside Docker only (a laptop, a script on the host). The runtimes then answer without an API key and without LiteLLM's limits or tracing, so close the port again when done.

In `/opt/stacks/llm-runtime/compose.yaml`, uncomment the running runtime's `ports:` block, then recreate only that runtime:
```bash
cd /opt/stacks/llm-runtime
docker compose --profile "*" up -d $(docker compose --profile "*" ps --services --status running)   # recreates only the running one
```
```bash
curl http://${SERVER_HOST}:11434/api/tags        # Ollama
curl http://${SERVER_HOST}:8000/v1/models        # vLLM
```
Comment the `ports:` block out again and re-run the same `up -d` line when done.

To point Claude Code, Codex, or VS Code straight at an open port, see [Developer tools](developer-tools.md) → Direct to Ollama or vLLM.

---

**Related:**
- [Step 13: Ollama / vLLM runtime](../ai-server-setup-guide.md#step-13-ollama--vllm-runtime) → Install
- [Option: Developer tools](developer-tools.md)
