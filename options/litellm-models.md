# Option: Adding or removing a model

Part of [Step 12: LiteLLM (gateway)](../ai-server-setup-guide.md#step-12-litellm-gateway) and [Step 13: Ollama / vLLM runtime](../ai-server-setup-guide.md#step-13-ollama--vllm-runtime). A model lives in three places: the runtime that runs it (Ollama, or vLLM for one model), LiteLLM's `/opt/stacks/litellm/config.yaml` where clients find it by name, and the Outline "Services" page where users read about it (Step 19). Change all three together.

## Rules for names

- **A name is what clients type.** Renaming or removing one breaks every client that uses it. Add the new name first, remove the old one only after users have switched.
- **Family and version, then size, lowercase with dashes**, written the way the maker writes the version: `gemma4-12b`, `qwen3.8-27b`. No spaces or brackets, and never the runtime: a model can move to another runtime later.
- **One name, one model.** A name listed for both runtimes (like `gemma4-12b`) must point to the same model on both; otherwise users get a different model depending on which runtime runs.
- `local-model` means "whatever runs now". OpenHands and similar tools use it, so changing what it points to changes their model too.

## Add a model on Ollama

1. **Check it fits** the GPU. A 4-bit model needs about 0.6 GB per billion parameters, plus 2–5 GB for context: on 16 GB, up to about 14B for a dense model or about 20B for a mixture-of-experts model. A larger one still runs, partly on the CPU: slower, and it needs free RAM (see [Models](../ai-server-setup-guide.md#models)). Find the exact tag in the [Ollama library](https://ollama.com/library).
2. **Pull it:**
   ```bash
   docker exec ollama ollama pull <tag>
   ```
3. **List it in `/opt/stacks/litellm/config.yaml`**, under `model_list`, with a one-line comment on what it is for:
   ```yaml
     # <Model>: <what it is for> (Ollama only)
     - model_name: <name>
       litellm_params:
         model: openai/<tag>
         api_base: http://ollama:11434/v1
         api_key: none
   ```
4. **Recreate LiteLLM**, which reads the file only at start:
   ```bash
   cd /opt/stacks/litellm && docker compose up -d --force-recreate litellm
   ```
5. **Test it** through LiteLLM, then see how much of it runs on the GPU (`100% GPU` is best; `25%/75% CPU/GPU` means it spills to the CPU):
   ```bash
   curl -k https://${SERVER_HOST}:4000/v1/chat/completions \
     -H "Authorization: Bearer <LITELLM_MASTER_KEY>" -H "Content-Type: application/json" \
     -d '{"model":"<name>","messages":[{"role":"user","content":"Say OK"}]}'
   docker exec ollama ollama ps
   ```
6. **Add a row to the Services page** in Outline: name, what it is for, speed, and "Ollama only".

A model that spills to the CPU answers slowly; raise the timeouts of LiteLLM and of clients such as OpenHands if its answers get cut off.

## Remove a model

1. **Check who uses it.** In Langfuse, filter recent traces by model; tell users before it goes.
2. **Delete its entry** from `/opt/stacks/litellm/config.yaml` and recreate LiteLLM:
   ```bash
   cd /opt/stacks/litellm && docker compose up -d --force-recreate litellm
   ```
3. **Free the disk space** on Ollama, then check what is left:
   ```bash
   confirm "Delete model <tag> from Ollama?" && docker exec ollama ollama rm <tag>
   docker exec ollama ollama list
   ```
4. **Remove its row** from the Services page.

## Change the vLLM model

vLLM runs exactly one model.
1. Set `VLLM_MODEL` (and `VLLM_MAX_MODEL_LEN`, see the sizing notes in Step 13) in `/opt/stacks/llm-runtime/.env`.
2. In `/opt/stacks/litellm/config.yaml`, change `model:` of every entry with `api_base: http://vllm:8000/v1` to `openai/<new VLLM_MODEL>`. If the new model is not the one behind the same name on Ollama, give its entry its own name instead (see [Rules for names](#rules-for-names)).
3. Start vLLM with the new model; the first start downloads it:
   ```bash
   /opt/stacks/llm-runtime/switch-llm.sh vllm
   docker logs -f vllm
   ```
4. Recreate LiteLLM (as above) and test the name with the `curl` command above.
5. Update the Services page.

## Change what local-model means

Change `model:` in both `local-model` entries of `/opt/stacks/litellm/config.yaml`, one per runtime, to the same model, then recreate LiteLLM. Clients keep calling `local-model` and need no change; tell users, since its answers change.

## Check

| Check | Expected |
|---|---|
| `curl -sk https://${SERVER_HOST}:4000/v1/models -H "Authorization: Bearer <LITELLM_MASTER_KEY>"` | Every name in `config.yaml`, including Ollama-only ones while vLLM runs |
| The `curl` test above with the new name | A short answer |
| `docker exec ollama ollama ps` right after the test | The model, ideally `100% GPU` |
| `docker logs litellm 2>&1 \| tail` | No error about `config.yaml` |

---

**Related:**
- [Step 12: LiteLLM (gateway)](../ai-server-setup-guide.md#step-12-litellm-gateway) → Install
- [Step 13: Ollama / vLLM runtime](../ai-server-setup-guide.md#step-13-ollama--vllm-runtime) → Install
