*Copied from `options/dex-outside-sign-in.md` in the ai-server repo; import it as a document named "Option: Outside sign-in".*

Part of Step 6: Dex (document "Self-Hosted AI Server Setup Guide"). Dex's `.env`, `compose.yaml`, and `config.yaml` already contain everything below, commented out; turning a provider on means uncommenting it.

Dex can also let people sign in with an account they already have. Each provider needs a client ID and secret from that provider's console, and every one uses the same callback address:
```
https://<SERVER_HOST>:5556/dex/callback
```
Only the browser follows this address, so an internal name works — except for Google (**Google sign-in** (document "Option: Google sign-in")).

| Provider | Company admin needed? | Account data lives | Notes |
|---|---|---|---|
| Auth0 | No — you create your own Auth0 account | Auth0 cloud | Adds self-service password reset, MFA, and social sign-in |
| Google | No — any Google account can create the project | Google | `SERVER_HOST` must be a name under a real domain, e.g. `ai.domain.com` (a hosts-file entry is enough); an IP or a made-up name like `ai.internal` is rejected |
| Microsoft (Azure AD / Entra ID) | Often — depends on your tenant | Your Microsoft 365 tenant | Blocked if the tenant stops users from registering apps or requires admin consent |

In every case Dex needs outbound HTTPS to the provider (it exchanges the sign-in code server to server). Local Dex users keep working alongside.

## Auth0

No admin needed.
1. At manage.auth0.com, create a tenant if you have none, then Applications → Create Application → **Regular Web Application**.
2. Settings → **Allowed Callback URLs**: the callback address above. Save.
3. Copy the **Domain**, **Client ID**, and **Client Secret**. The Dex `issuer` is `https://<Domain>/`, with the trailing slash.
4. Users must verify their email in Auth0 before Dex accepts them.

## Google

See **Google sign-in** (document "Option: Google sign-in"): choosing a server name Google accepts, the Google client, and turning it on in Dex and Infisical together.

## Microsoft (Azure AD)

May need an admin.
1. At entra.microsoft.com, App registrations → **New registration**. Supported account types: **this organizational directory only**. Redirect URI: platform **Web**, the callback address above.
2. Certificates & secrets → **New client secret**; copy its **Value** right away (it is shown once).
3. From Overview, copy the **Application (client) ID** and **Directory (tenant) ID**.
4. If registration is blocked, or sign-in later says the app "needs admin approval", your tenant requires an admin; send them these steps — or use the guest route below.

Dex's `microsoft` connector uses the Microsoft sign-in name (userPrincipalName) as the email. That's the real address for people in the tenant itself, but not for guests (see below).

## Microsoft via your own tenant

When you're not an admin of your company's tenant, but are of another one, e.g. a `*.onmicrosoft.com` tenant): register the app there and invite colleagues as guests. They still sign in with their own company account and password; your tenant only vouches for them.
1. In **your** tenant: App registrations → New registration → **this organizational directory only**, Redirect URI (Web): the callback address above. Create a client secret; copy the Application (client) ID and your Directory (tenant) ID.
2. Token configuration → **Add optional claim** → token type **ID** → `email`. Without it, guests arrive without their real address.
3. Users → **Invite external user** for each colleague, using their company email. They accept the invitation once.
4. Use the commented `entra-guests` connector (not `microsoft`): it reads the `email` claim, which for a guest is their real company address — so Outline and the other apps match them to the right account. With the `microsoft` connector, a guest's email would look like `name_company.com#EXT#@yourtenant.onmicrosoft.com`.
5. If a guest can't accept the invitation or sign in, the company tenant may block collaboration with outside tenants (its cross-tenant access settings); that part needs their admin after all.

Guests up to Microsoft's free monthly-active-user allowance cost nothing; check Microsoft's current External ID pricing if you invite many.

## Turning a provider on

1. In `/opt/stacks/dex/.env`, uncomment that provider's lines (`MS_*`, `ENTRA_GUEST_*`, or `AUTH0_*`) and fill them in. With Infisical, add them to `prod:/dex` and run `/opt/stacks/infisical/pull-secrets.sh --stack dex`.
2. In `/opt/stacks/dex/config.yaml`, uncomment `connectors:` and that provider's entry (keep the indentation). Nothing to fill in there: it reads every value from the environment. Dex installed from an older version of this guide: check that `compose.yaml` lists the provider's variables under `environment:`, and that the entry reads `{{ getenv "…" }}` instead of `<…>`; copy both from the guide.
3. `cd /opt/stacks/dex && docker compose up -d --force-recreate dex` (picks up both the new secret and the edited config).
4. Open Outline, sign out, and check the Dex page shows the new button. Outline matches people by email, so someone who already signed in with a Dex password keeps the same Outline account when they switch to, e.g., Microsoft with the same address.

---

**Related:**
- Step 6: Dex (sign-in) (document "Self-Hosted AI Server Setup Guide") → Authentication
- **Option: Email and Azure AD sign-in** (document "Option: Email and Azure AD sign-in")
