*Copied from `options/outline-email-and-azure.md` in the ai-server repo; import it as a document named "Option: Email and Azure AD sign-in".*

Part of Step 7: Outline (document "Self-Hosted AI Server Setup Guide"). Outline's `.env` already contains both blocks, commented out. Dex sign-in keeps working alongside either.

## Email (SMTP)

Set up the relay once for every app: **Email (SMTP) for all services** (document "Option: Email (SMTP) for all services"). For Outline, uncomment the SMTP block in its `.env` and fill it in (with Infisical: the shared values come from `prod:/shared`; add `SMTP_FROM_EMAIL` and `SMTP_SECURE=false` under `prod:/outline`), then `cd /opt/stacks/outline && docker compose up -d`.

SMTP also turns on Outline's email sign-in next to the Dex button. To keep Dex as the only way in, turn email sign-in off in Outline under Settings → Authentication.

## Azure AD sign-in

Outline's own Azure AD sign-in, without Dex. It needs an app registration in your Microsoft tenant, which often needs its admin.
1. At entra.microsoft.com, App registrations → **New registration** → **this organizational directory only**; Redirect URI (Web): `https://<SERVER_HOST>/auth/azure.callback`.
2. Create a client secret and copy its value, plus the Application (client) ID.
3. In `/opt/stacks/outline/.env`, uncomment the `AZURE_*` lines and fill them in, then `cd /opt/stacks/outline && docker compose up -d`.

Outline allows one sign-in per provider type; to give every app Microsoft sign-in at once, use Microsoft through Dex instead (**Outside sign-in** (document "Option: Outside sign-in")).

---

**Related:**
- Step 7: Outline (wiki) (document "Self-Hosted AI Server Setup Guide") → Authentication
