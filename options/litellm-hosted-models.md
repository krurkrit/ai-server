# Option: Hosted models

Part of [Step 12: LiteLLM](../ai-server-setup-guide.md#step-12-litellm-gateway). Hosted models (Claude, OpenAI, Azure OpenAI) sit next to the local ones in LiteLLM's model list, so clients keep one address, every call is traced in Langfuse, and the provider key stays on the server. LiteLLM's files in Step 12 already hold everything, commented out: the keys in `.env`, the lines that pass them on in `compose.yaml`, and the models in `config.yaml`.

## Turning one on

1. **Get a key** from the provider: Claude at `console.anthropic.com` (Settings → API keys), OpenAI at `platform.openai.com` (API keys), Azure OpenAI in the Azure portal (your Azure OpenAI resource → Keys and Endpoint). Each is billed per call to that account.
2. **Put it in `/opt/stacks/litellm/.env`:** uncomment its line (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or both `AZURE_OPENAI_*`) and fill it in. With Infisical, add it to `prod:/litellm` instead and run `/opt/stacks/infisical/pull-secrets.sh --stack litellm`.
3. **Check `compose.yaml`:** a LiteLLM installed from an older version of the guide lacks the four `ANTHROPIC_API_KEY` … `AZURE_OPENAI_API_BASE` lines under `environment:`; copy them from Step 12.
4. **Uncomment the model** in `/opt/stacks/litellm/config.yaml` (keep the indentation). For OpenAI, fill in the model ID as listed in OpenAI's model docs and a name in the guide's pattern; for Azure, your deployment name.
5. **Recreate LiteLLM:** `cd /opt/stacks/litellm && docker compose up -d --force-recreate litellm`.
6. **Test** with the name you chose (see [Check](#check)), then add it to the Services page in Outline, marked as hosted and paid.

Names follow the same pattern as the local models: family and version, lowercase with dashes. A model on the company key ends in `-shared` (`claude-sonnet-5.5-shared`), so users see that the company pays; the same model without the suffix (`claude-sonnet-5.5`) runs on the caller own key (see [Users with their own key](#users-with-their-own-key)). Prompts sent to a hosted model leave the server; tell users which models are local and which are not, and consider [Data protection for hosted models](litellm-guardrails.md).

## Claude (Anthropic)

```yaml
  - model_name: claude-sonnet-5.5-shared
    litellm_params:
      model: anthropic/claude-sonnet-5-5
      api_key: os.environ/ANTHROPIC_API_KEY
  - model_name: claude-haiku-4.5-shared
    litellm_params:
      model: anthropic/claude-haiku-4-5-20251001
      api_key: os.environ/ANTHROPIC_API_KEY
```
Sonnet for most work, Haiku for quick and cheap calls. Other Claude models work the same way with their model ID from Anthropic's model list.

## OpenAI

```yaml
  - model_name: <openai-model-name>-shared
    litellm_params:
      model: openai/<openai-model-id>
      api_key: os.environ/OPENAI_API_KEY
```
`<openai-model-id>` is the ID from OpenAI's model list; `<openai-model-name>` is the name clients use, in the same pattern, plus `-shared`.

## Azure OpenAI

```yaml
  - model_name: azure-gpt-shared
    litellm_params:
      model: azure/<deployment-name>
      api_base: os.environ/AZURE_OPENAI_API_BASE
      api_key: os.environ/AZURE_OPENAI_API_KEY
      api_version: "2024-06-01"
```
The deployment name stays in the file: it names the model, like a local model tag.

## Budgets per developer

Hosted models cost money per call, so give each developer their own LiteLLM **virtual key** instead of the master key, and set a budget on it. LiteLLM knows the providers' prices and stops a key when its budget is used up; local models count as $0. A model too new for LiteLLM's price list also counts as $0 until LiteLLM is updated, so check the first calls under **Usage**.

In the Admin UI (`https://<SERVER_HOST>:4000/ui`, master key): **Virtual Keys** → **Create New Key**, with the developer's name, the models they may use, and a budget. Or with the API:
```bash
curl -k https://${SERVER_HOST}:4000/key/generate \
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>" -H "Content-Type: application/json" \
  -d '{"key_alias":"<name>","user_id":"<email>","models":["local-model","claude-sonnet-5.5-shared"],"max_budget":20,"budget_duration":"30d"}'
```
`max_budget` is in US dollars; `budget_duration` resets it, here every 30 days. The key is shown once. Revoke it with `/key/delete` (`{"key_aliases":["<name>"]}`) or in the Admin UI. Usage per key is under **Usage** in the Admin UI, and in Langfuse in each trace's metadata.

## Users with their own key

A developer who pays with their own Claude or OpenAI key can still go through LiteLLM, so their calls are traced in Langfuse. These models have no suffix: the same model as the `-shared` one, but without a key on the server. Uncomment their blocks in `config.yaml` and recreate LiteLLM:
```yaml
  - model_name: claude-sonnet-5.5
    litellm_params:
      model: anthropic/claude-sonnet-5-5
      configurable_clientside_auth_params: ["api_key"]
  - model_name: <openai-model-name>
    litellm_params:
      model: openai/<openai-model-id>
      configurable_clientside_auth_params: ["api_key"]
```
Any other Claude or OpenAI model works the same way: its model ID, no `api_key`, and `configurable_clientside_auth_params: ["api_key"]`; name it like the company-key model without `-shared`. The caller then sends two keys: their LiteLLM virtual key as usual, and their own provider key as `api_key` in the request body. In Python, with the OpenAI SDK:
```python
client.chat.completions.create(
    model="claude-sonnet-5.5",
    messages=[{"role": "user", "content": "Say OK"}],
    extra_body={"api_key": "<their own Claude key>"},
)
```
For OpenAI, the same with `model="<openai-model-name>"` and their own OpenAI key.
- **Allow only `api_key`, never `api_base`:** a caller who can choose the address could send the call, and any key in it, to their own server. LiteLLM blocks `api_base` from callers by default; keep it that way.
- **Not every tool can send the extra key.** Scripts and the OpenAI or Anthropic SDKs can; many IDEs and chat apps cannot, and for them a company key with a budget is simpler.
- **Prompts are stored in Langfuse**, also for calls paid with a personal key, and the server's admins can read them. Tell users before they route private work through it.
- Someone who only wants tracing can also skip LiteLLM: send traces from their own code straight to Langfuse with the Langfuse SDK and a key of a Langfuse project.

## Check

| Check | Expected |
|---|---|
| `docker exec litellm printenv ANTHROPIC_API_KEY \| wc -c` | More than 1 (the key arrived; the value is not shown) |
| `curl -sk https://${SERVER_HOST}:4000/v1/models -H "Authorization: Bearer <LITELLM_MASTER_KEY>"` | The hosted model names next to the local ones |
| The `curl` test from Step 13 with `"model":"claude-sonnet-5.5-shared"` | A short answer |
| Langfuse → Traces | The call, with its cost |
| `docker logs litellm 2>&1 \| grep -i -E "error\|auth" \| tail` | No authentication errors from the provider |

---

**Related:**
- [Resource usage](../ai-server-setup-guide.md#resource-usage) → Models
- [Step 12: LiteLLM (gateway)](../ai-server-setup-guide.md#step-12-litellm-gateway) → Install
- [Option: Data protection for hosted models](litellm-guardrails.md)
