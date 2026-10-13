## Step 13: Ollama / vLLM runtime

Ollama and vLLM share the GPU, so only one runs at a time.

**Check:** `ollama`, `vllm`.

### Clean reinstall

Removes Ollama and vLLM as if they had never been installed. Skip it for a first install. LiteLLM, OpenHands, and Open WebUI get no answers from local models until it is back. The model volumes hold large downloads; keep them for a reinstall unless you want the disk space back. Each line asks first.
```bash
confirm "Stop and remove Ollama and vLLM?" && cd /opt/stacks/llm-runtime && docker compose --profile "*" down; cd ~
confirm "Delete every downloaded model (volumes ollama_data, vllm_hf_cache; tens of GB to download again)?" && docker volume rm ollama_data vllm_hf_cache
confirm "Delete /opt/stacks/llm-runtime (.env, compose.yaml, the switch-llm.sh link)?" && rm -rf /opt/stacks/llm-runtime
confirm "Delete the Ollama and vLLM images (about 14 GB together)?" && docker image rm ollama/ollama:latest vllm/vllm-openai:latest
```
Revoke the Hugging Face token (huggingface.co → Settings → Access Tokens) if vLLM is gone for good.

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -E '^(ollama|vllm)$'
docker volume ls -q | grep -E '^(ollama_data|vllm_hf_cache)$'
ls -d /opt/stacks/llm-runtime 2>/dev/null
```

### Install

```bash
mkdir -p /opt/stacks/llm-runtime
```

`/opt/stacks/llm-runtime/.env`:
```env
VLLM_MODEL=google/gemma-4-12B-it-qat-w4a16-ct   # Hugging Face model ID; must match the vLLM entries in LiteLLM config.yaml and fit the GPU
VLLM_MAX_MODEL_LEN=16384                 # longest context vLLM reserves memory for; see the Models table
HF_TOKEN=                                # Hugging Face read token, for models that need their license accepted (Gemma does)
OLLAMA_CONTEXT_LENGTH=32768              # tokens Ollama gives each model; its default (4k on GPUs under 24 GB) silently cuts off agent tools such as Claude Code and Codex
```

**Sizing a model to your GPU** (`nvidia-smi --query-gpu=name,memory.total --format=csv`):
- Weights: about 2 GB per billion parameters unquantized, about 0.6 GB per billion at 4-bit (AWQ/GPTQ, Ollama's `q4` tags).
- Keep 20–30% of VRAM free for context.
- Rough fits: 16 GB → 14B 4-bit or 7B unquantized; 24 GB → up to ~32B 4-bit; 48 GB+ → 70B 4-bit.
- Suggested Qwen models, their sizes, and what happens with a 30B model on a 16 GB GPU: [Models](#models).
- vLLM takes 90% of VRAM by default, which is why Ollama and vLLM can't run together.

`/opt/stacks/llm-runtime/compose.yaml`:
```yaml
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    profiles: ["ollama"]
    restart: unless-stopped
    devices:
      - nvidia.com/gpu=all
    environment:
      OLLAMA_CONTEXT_LENGTH: ${OLLAMA_CONTEXT_LENGTH:-32768}
    volumes: [ollama_data:/root/.ollama]
    networks: [edge]
    # OPTIONAL — direct host access for testing, bypasses LiteLLM entirely.
    # Uncomment to let anything on the VPN hit Ollama directly (no API key,
    # no budget/rate limiting — LiteLLM controls do not apply here).
    # Comment back out when done testing.
    # ports:
    #   - "11434:11434"

  vllm:
    image: vllm/vllm-openai:latest
    container_name: vllm
    profiles: ["vllm"]
    restart: unless-stopped
    devices:
      - nvidia.com/gpu=all
    ipc: host                               # vLLM needs large shared memory for its worker processes
    environment:
      HF_TOKEN: ${HF_TOKEN:-}
    command: ["--model", "${VLLM_MODEL}", "--max-model-len", "${VLLM_MAX_MODEL_LEN:-16384}"]
    volumes: [vllm_hf_cache:/root/.cache/huggingface]
    networks: [edge]
    # OPTIONAL — same trade-off as Ollama above: direct, unauthenticated
    # access for testing. Comment back out when done.
    # ports:
    #   - "8000:8000"

networks:
  edge:
    external: true

volumes:
  ollama_data:
    external: true
  vllm_hf_cache:
    external: true
```
Neither runtime has a host port or a Caddy route. LiteLLM and other containers reach them over `edge`.

Link `switch-llm.sh` from `~/ai-server` into the stack folder ([Helper scripts](options/helper-scripts.md)), then start Ollama:
```bash
docker volume create ollama_data
docker volume create vllm_hf_cache

ln -sf ~/ai-server/switch-llm.sh /opt/stacks/llm-runtime/switch-llm.sh
cd /opt/stacks/llm-runtime
./switch-llm.sh ollama    # or: vllm / status / stop
```
**The Ollama models:** pull the ones named in LiteLLM's config:
```bash
docker exec ollama ollama pull gemma4:12b
docker exec ollama ollama pull qwen3-embedding:0.6b
# The other models listed in LiteLLM config.yaml (about 64 GB in total; pull only the ones you try)
docker exec ollama ollama pull qwen3.5:9b
docker exec ollama ollama pull gemma4:26b
docker exec ollama ollama pull qwen3.6:35b-a3b
docker exec ollama ollama pull qwen3.8:27b
```
**The vLLM model** has no pull command: vLLM downloads `VLLM_MODEL` from Hugging Face on its first start (about 10 GB for Gemma 4 12B) into the `vllm_hf_cache` volume, and reuses it after that. Gemma needs its license accepted first: sign in at huggingface.co, open `https://huggingface.co/google/gemma-4-12B-it-qat-w4a16-ct`, accept the license, create a read token (Settings → Access Tokens), and put it in `HF_TOKEN=` in `/opt/stacks/llm-runtime/.env`. Then start vLLM once to download and test it, and switch back to Ollama:
```bash
cd /opt/stacks/llm-runtime
./switch-llm.sh vllm
docker logs -f vllm      # wait for "Application startup complete", then Ctrl+C
./switch-llm.sh ollama
```
A `401` or `403` in the log means the license or token is missing; `CUDA out of memory` means the model or `VLLM_MAX_MODEL_LEN` is too large for the GPU. The next `./switch-llm.sh vllm` starts in about a minute, without downloading again.

To add, remove, or change a model later: [Adding or removing a model](options/litellm-models.md).

**Check the result.** Every line must match the table:
```bash
/opt/stacks/llm-runtime/switch-llm.sh status
docker inspect -f '{{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}  networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' ollama
docker inspect ollama --format '{{range .Mounts}}mount {{.Destination}} <- {{.Name}}{{println}}{{end}}  devices={{range .HostConfig.Devices}}{{.PathOnHost}} {{end}}'
docker exec ollama nvidia-smi -L
docker exec ollama sh -c 'echo "context: $OLLAMA_CONTEXT_LENGTH"'
docker exec ollama ollama list
docker exec litellm getent hosts ollama
```

| Line | Expected |
|---|---|
| `status` | `Ollama: Up …`, `vLLM: not running` (only one runs at a time) |
| `ollama` | `state=running  restart=unless-stopped`, image `ollama/ollama:latest`, `networks=edge` |
| `mount` | `/root/.ollama <- ollama_data`, and `devices=nvidia.com/gpu=all` |
| `nvidia-smi -L` | your GPU, e.g. `GPU 0: NVIDIA …`: the container sees it |
| `context` | `32768` (or the value in `.env`) |
| `ollama list` | every model named in LiteLLM's `config.yaml` that you pulled, plus `qwen3-embedding:0.6b` |
| `getent` | an address for `ollama`: LiteLLM can reach it |

With vLLM running instead (`switch-llm.sh vllm`): `vllm` is `running` with `/root/.cache/huggingface <- vllm_hf_cache`, `docker exec vllm nvidia-smi -L` shows the GPU, and `docker logs vllm 2>&1 | grep -m1 "Application startup complete"` prints a line.

**Verify through LiteLLM:**
```bash
curl -k https://${SERVER_HOST}:4000/v1/chat/completions \
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>" -H "Content-Type: application/json" \
  -d '{"model":"local-model","messages":[{"role":"user","content":"Say OK"}]}'
```

**Option:** [Direct test ports](options/llm-direct-test-ports.md) — reach Ollama or vLLM from outside Docker for testing, bypassing LiteLLM.

### Authentication

Ollama and vLLM have no login and no browser UI. They stay internal on `edge`; people and tools reach them through LiteLLM and its keys.

### Test

1. **Through LiteLLM:** the `curl` above returns an answer from `local-model`.
2. **On the GPU:** right after that call, `docker exec ollama ollama ps` lists the model with `100% GPU` (a `CPU/GPU` split means it does not fit; see [Models](#models)).
3. **Embeddings:** `docker exec ollama ollama run qwen3-embedding:0.6b "test" >/dev/null && echo OK` prints `OK`.
4. **The switch:** `./switch-llm.sh vllm`, wait for `Application startup complete` (`docker logs -f vllm`), repeat test 1 (`local-model` now answers from vLLM), then `./switch-llm.sh ollama`.

