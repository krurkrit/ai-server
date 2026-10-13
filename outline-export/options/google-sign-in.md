*Copied from `options/google-sign-in.md` in the ai-server repo; import it as a document named "Option: Google sign-in".*

Part of Step 5: Infisical (document "Self-Hosted AI Server Setup Guide") and Step 6: Dex (document "Self-Hosted AI Server Setup Guide"). Both stacks already contain the lines below, commented out or empty.

People sign in everywhere with their company Google account:
- **Every app behind Dex** (Outline, Grafana, Portainer, Langfuse, and the gated apps): Dex gets a **Google** button next to its local passwords.
- **Infisical**: its own **Continue with Google** button. Infisical can't use Dex: that would need its OIDC sign-in, which is paid; its Google login is free.

One Google client serves both. Everything here is free: the Google Cloud project and the OAuth client need no billing account and cost nothing per sign-in. (Google's separate Identity Platform product is paid; you don't need it.)

## Why keep Dex

Most apps could talk to Google directly, but Dex in between is less work and safer:
- One redirect address in Google instead of one per app, and the domain limit (`hostedDomains`) set once instead of per app.
- Local Dex passwords keep working for people without a company Google account, and as a fallback when Google or the internet is unreachable.
- Adding Microsoft or another provider later changes only Dex; the apps stay as they are.

## Choosing the server name

`SERVER_HOST` must be a name under a real domain your company owns, e.g. `ai.domain.com`.

Google checks each redirect address as text against the public list of domain endings (publicsuffix.org): `ai.domain.com` passes because `.com` is on the list; `ai.internal` and IP addresses fail. Google never looks the name up or connects to it (only the browser does), so the name can live only in your internal DNS or hosts files.
- The server name and the sign-in accounts are separate: a server at `ai.domain.com` can sign in accounts of another company domain (e.g. `@otherdomain.com`).
- Use a domain your company owns. With a domain someone else owns or could register, any PC without the hosts-file entry would follow the sign-in redirect to that outsider, together with the one-time sign-in code.
- Check the name is unused publicly (`nslookup ai.domain.com` should find nothing), and tell whoever runs the domain that you use it internally.
- To switch `SERVER_HOST` to the new name, see "Changing the name or IP later" in the guide. Apps that answer on `SERVER_HOST` only stop answering on the old name, so change every hosts file at the same time.

## The Google client

1. At console.cloud.google.com, signed in with a company Google account, create a project (e.g. `ai-server-sign-in`), then APIs & Services → **OAuth consent screen**, user type:
   - **Internal**: only accounts of your Google Workspace (e.g. `@domain.com`). Any user of that Workspace can choose it, no Workspace admin needed, and it skips Google's app review and test-user limit. If the Workspace admin has blocked project creation or outside sign-in apps, this needs them after all.
   - **External**: any Google account. While the app is in testing, only listed test users (up to 100) can sign in; **Publish app** lifts that, with no Google review, because sign-in asks only for name and email. Anyone with a Google account then gets past Google; Dex `hostedDomains`, Infisical sign-up settings, and each app's own approval decide who gets in.
2. Credentials → Create credentials → **OAuth client ID** → type **Web application** → Authorized redirect URIs (leave out the one you don't turn on):
   ```
   https://<SERVER_HOST>:5556/dex/callback
   https://<SERVER_HOST>:8080/api/v1/sso/google
   ```
3. Copy the **Client ID** and **Client secret**.

## One name for both

Dex and Infisical read the client as `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` from their `.env` (Infisical's `compose.yaml` passes them on under the names Infisical expects). So each value is kept once:
- **With Infisical:** put both in `prod:/shared`. Keys from `prod:/shared` only update a `.env` that already has them, so each of the two `.env` files needs the lines once, e.g. `GOOGLE_CLIENT_ID=` and `GOOGLE_CLIENT_SECRET=` with no value; `pull-secrets.sh` fills them in from then on. The other stacks never get them. Infisical's own `.env` is only updated when the folder `prod:/infisical` exists; create it (it may stay empty). From then on, keys in that `.env` that are in neither `prod:/shared` nor `prod:/infisical` (e.g. hand-written `SMTP_*`) show as `REMOVED` and are asked about; move them to `prod:/infisical`, or answer N. The three start keys are never affected.
- **Without Infisical:** write the same two lines, with values, into `/opt/stacks/dex/.env` and `/opt/stacks/infisical/.env`.

A new client secret is then changed in one place (`prod:/shared`), followed by `pull-secrets.sh`.

## Turning it on in Dex

1. In `/opt/stacks/dex/.env`, uncomment `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` (see One name for both). Dex installed from an older version of this guide: check that `/opt/stacks/dex/compose.yaml` lists both under `environment:` (`GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID:-}`, and the same for the secret); add any that is missing.
2. In `/opt/stacks/dex/config.yaml`, uncomment `connectors:` and the `google` entry (keep the indentation). `clientID` and `clientSecret` already read the two values from the environment; older copies of the file have `clientID: <Google client ID>`, which you change to `clientID: {{ getenv "GOOGLE_CLIENT_ID" }}`. For Workspace accounts only, also uncomment `hostedDomains` and set your account domain, e.g. `[domain.com]`.
3. `cd /opt/stacks/dex && docker compose up -d --force-recreate dex` (picks up the new values and the edited config).
4. Sign out of Outline and sign in again: the Dex page shows a **Google** button next to the password form.

Apps match people by email, so someone who used a Dex password with the same address keeps their Outline, Grafana, Portainer, and Langfuse accounts. Keep at least your own `staticPasswords` entry as a fallback.

## Turning it on in Infisical

1. In `/opt/stacks/infisical/.env`, uncomment `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` (see One name for both).
2. In `/opt/stacks/infisical/compose.yaml`, under `infisical:` → `environment:`, the two Google lines must read as below. A file written from an older version of the guide has none, or reads `${CLIENT_ID_GOOGLE_LOGIN:-}`; change them:
   ```yaml
         CLIENT_ID_GOOGLE_LOGIN: ${GOOGLE_CLIENT_ID:-}
         CLIENT_SECRET_GOOGLE_LOGIN: ${GOOGLE_CLIENT_SECRET:-}
   ```
3. `cd /opt/stacks/infisical && docker compose up -d` (with Infisical, `pull-secrets.sh` already recreated it)
4. Sign out: the login page shows **Continue with Google**.

## Who can sign in

- **Same email, same account.** An existing Infisical user who signs in with Google whose address matches their Infisical email keeps the same account. If the first admin was created with another address, keep signing in as that admin with email and password, and invite your Google address to the organization.
- **Internal consent screen:** only your Workspace accounts get through Google.
- **External consent screen:** set `hostedDomains` in Dex. In Infisical, turn user sign-ups off in the Server Admin console (or limit them to your email domain), and invite people instead.
- **Fallback:** keep one Dex password and the Infisical admin email and password, in case Google sign-in breaks.

## Check

Sign in with Google as a second user, once through Dex (e.g. Outline) and once on Infisical. If it fails:

| Error | Cause |
|---|---|
| `redirect_uri_mismatch` (from Google) | The redirect URI in Google differs from the address in use, including the port (`:5556` for Dex, `:8080` for Infisical) |
| `org_internal` (from Google) | Internal consent screen, and the account is outside your Workspace |
| No Google button on the Dex page | The connector is still commented out, or Dex was restarted instead of recreated: `docker exec dex grep -A3 "type: google" /etc/dex/config.yaml` |
| Dex rejects the account after Google | `hostedDomains` lists another domain than the account address |
| No Google button on Infisical | The values are empty in the container: `docker exec infisical printenv CLIENT_ID_GOOGLE_LOGIN` |

Logs: `docker logs dex 2>&1 | grep -i google | tail` and `docker logs infisical 2>&1 | grep -i google | tail`.

---

**Related:**
- Before you start (document "Self-Hosted AI Server Setup Guide")
- Step 5: Infisical (secrets) (document "Self-Hosted AI Server Setup Guide") → Authentication
- Step 6: Dex (sign-in) (document "Self-Hosted AI Server Setup Guide") → Authentication
- **Option: Outside sign-in** (document "Option: Outside sign-in")
