# Option: Sync to Azure Key Vault

Part of [Step 5: Infisical](../ai-server-setup-guide.md#step-5-infisical-secrets). Infisical stays the source: it copies a folder's secrets into an Azure key vault and keeps them updated. Free in self-hosted Infisical, and set up entirely in its web UI; no files on the server change.

1. In Azure (usually needs whoever administers the subscription): create a **Key Vault** (needs an Azure subscription; Key Vault is billed per operation, which is small for this use). Create an app registration with a client secret, then on the key vault → Access control (IAM) → assign it the **Key Vault Secrets Officer** role.
2. In Infisical: Organization → **App Connections** → Add → **Azure Key Vault** → method **Client Secret**, with the tenant ID, client ID, and secret from step 1.
3. In the project → **Integrations → Secret Syncs** → Add → **Azure Key Vault**: pick environment Production and the folder (e.g. `/outline`, which this guide writes as `prod:/outline`), the connection, and the vault URL (`https://<vault-name>.vault.azure.net`). On the first sync, choose whether Infisical or the vault wins for secrets that exist in both.
4. Key Vault names allow only letters, digits, and `-`, so a key like `OUTLINE_DB_PASSWORD` can't keep its underscores there. Check the names in the vault after the first sync and adjust the sync's naming option if needed.

---

**Related:**
- [Step 5: Infisical (secrets)](../ai-server-setup-guide.md#step-5-infisical-secrets) → Usage
