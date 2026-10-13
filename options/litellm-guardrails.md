# Option: Data protection for hosted models

Part of [Step 12: LiteLLM (gateway)](../ai-server-setup-guide.md#step-12-litellm-gateway). With hosted models ([Hosted models](litellm-hosted-models.md)), prompts leave the server. This option masks personal data, such as email addresses and phone numbers, before a prompt goes out, or blocks the request, using Microsoft Presidio (free, MIT) as a LiteLLM guardrail. Local models do not need it: their prompts stay on the server.

## What it does and does not do

- **Masks** what Presidio recognizes, e.g. `somchai@domain.com` becomes `<EMAIL_ADDRESS>` before the model sees it, or **blocks** the request (for card numbers, say).
- Recognition is pattern- and language-based: good at emails, phone numbers, card and account numbers, IP addresses; names and addresses only in the languages Presidio has models for (English by default). It is a safety net, not a guarantee; tell users what not to paste.
- It adds a little delay to each request it checks.
- Secret detection (API keys in prompts) is a LiteLLM Enterprise guardrail (💲) and is not set up here.

## Set it up

1. **Two Presidio containers in the LiteLLM stack.** Add them under `services:` in `/opt/stacks/litellm/compose.yaml`; they stay on the stack's own network, LiteLLM reaches them by name:
   ```yaml
     presidio-analyzer:
       image: mcr.microsoft.com/presidio-analyzer:latest
       container_name: litellm-presidio-analyzer
       restart: unless-stopped
       networks: [default]

     presidio-anonymizer:
       image: mcr.microsoft.com/presidio-anonymizer:latest
       container_name: litellm-presidio-anonymizer
       restart: unless-stopped
       networks: [default]
   ```
   And under the `litellm` service's `environment:`:
   ```yaml
         PRESIDIO_ANALYZER_API_BASE: http://presidio-analyzer:3000
         PRESIDIO_ANONYMIZER_API_BASE: http://presidio-anonymizer:3000
   ```
2. **The guardrail** at the end of `/opt/stacks/litellm/config.yaml`:
   ```yaml
   guardrails:
     - guardrail_name: mask-personal-data
       litellm_params:
         guardrail: presidio
         mode: pre_call                 # before the prompt goes to the model
         presidio_language: en
         pii_entities_config:
           EMAIL_ADDRESS: MASK
           PHONE_NUMBER: MASK
           IP_ADDRESS: MASK
           IBAN_CODE: MASK
           CREDIT_CARD: BLOCK
         default_on: true               # every request; remove to let clients opt in
   ```
   With `default_on: true` every request is checked, local ones too (harmless, a little slower). Without it, a client opts in per request with `"guardrails": ["mask-personal-data"]` in the body.
3. **Start:**
   ```bash
   cd /opt/stacks/litellm && docker compose up -d && docker compose up -d --force-recreate litellm
   ```

## Check

```bash
docker ps --filter name=litellm-presidio --format '{{.Names}}  {{.Status}}'
curl -k https://${SERVER_HOST}:4000/v1/chat/completions \
  -H "Authorization: Bearer <a virtual key>" -H "Content-Type: application/json" \
  -d '{"model":"local-model","messages":[{"role":"user","content":"Repeat exactly: my email is test.user@domain.com"}]}'
```
Both Presidio containers are `Up`, and the answer repeats `<EMAIL_ADDRESS>` instead of the address. In Langfuse, the trace shows the masked prompt. A card number such as `4111 1111 1111 1111` in the prompt gets an error naming `CREDIT_CARD` instead of an answer.

I have not confirmed `default_on` outside LiteLLM's examples for your version: if the address comes back unmasked, add `"guardrails": ["mask-personal-data"]` to the request and check `docker logs litellm 2>&1 | grep -i presidio`.

## Remove

Delete the `guardrails:` block and the two `PRESIDIO_*` lines, then:
```bash
cd /opt/stacks/litellm && docker compose up -d --force-recreate litellm
confirm "Remove the Presidio containers?" && docker rm -f litellm-presidio-analyzer litellm-presidio-anonymizer
```
and delete their two service blocks from `compose.yaml`.

---

**Related:**
- [Step 12: LiteLLM (gateway)](../ai-server-setup-guide.md#step-12-litellm-gateway) → Clean reinstall, Install
- [Option: Hosted models](litellm-hosted-models.md)
