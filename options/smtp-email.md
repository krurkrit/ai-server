# Option: Email (SMTP) for all services

One email account sends mail for every app: Outline (notifications, email sign-in), Infisical (invites), Grafana (alerts), and Langfuse (invites, password reset). Each app's `.env` and `compose.yaml` already hold the lines below, commented out or empty, so email stays off until you fill in the values. Without it everything else works; only these emails aren't sent.

## Choosing a relay

Gmail, Brevo, and Mailjet are free at a small team's volume; SendGrid depends on your plan. None needs a company admin. Allowances change; check the provider's current terms before you rely on one.

| Relay | Free allowance | SMTP server | Sender | Notes |
|---|---|---|---|---|
| Gmail, a dedicated account (**recommended**) | About 500 emails a day | `smtp.gmail.com:587` | That Gmail address | No DNS needed; setup below |
| [Brevo](https://www.brevo.com/free-smtp-server/) | 300 emails a day | `smtp-relay.brevo.com:587` | Verify one sender address, or your domain with DNS | SMTP login and key from its dashboard |
| [Mailjet](https://www.mailjet.com/pricing/) | 6,000 a month, 200 a day | `in-v3.mailjet.com:587` | Verify one sender address, or your domain with DNS | Free emails carry a Mailjet logo |
| [SendGrid](https://sendgrid.com/en-us/pricing) (Twilio) | Depends on your plan (the permanent free plan has ended; new accounts get a trial) | `smtp.sendgrid.net:587` | Verify one sender address, or your domain with DNS | Use if you already have an account; username is literally `apikey`, password is an API key with Mail Send permission |

- Don't send "from" a company address through an outside relay: without SPF/DKIM records in the company DNS, the company's own mail filter treats those emails as spoofed (DMARC fails). Use the relay's own sender, a Gmail address, or a domain you control.
- A company Microsoft 365 mailbox usually can't be used: Microsoft has been retiring password-based SMTP sign-in for Exchange Online, so it needs the company mail admin to set up a relay.
- For Brevo, Mailjet, or SendGrid, take `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, and `SMTP_PASSWORD` from the provider's dashboard instead of the Gmail values below; the sender address is the one you verified there.

## The Gmail account

Use a **dedicated** Gmail account, not a personal one: an app password opens the whole mailbox (sending and reading), and the server's mail would fill your Sent folder. A Google Group can't be used — it has no mailbox to sign in to.

1. **Create the account** with a team-neutral name, and use a team phone number or a shared address for recovery, so it doesn't depend on one person.
2. **Create an app password** at [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords) while signed in as that account. If the page says app passwords aren't available, 2-Step Verification is off: turn it on first (Google Account → Security), then come back.
3. **Copy it right away.** Google shows an app password only once. If you're unsure of it later, delete it there and create a new one.
4. **Remove the spaces.** Google shows it as `abcd efgh ijkl mnop`; use it as `abcdefghijklmnop`.
5. **Watch the account's inbox** for a "Sign-in attempt blocked" or security alert email. A brand-new Gmail account sometimes blocks the first sign-in from a server until you confirm it was you, or until it has been used normally for a little while; sign in once at gmail.com and approve it.
6. Optionally, forward replies to a person or a group.

**Test the account from the server** before setting up any app; then a later failure is in the app's settings, not the account. Write a test message:
```bash
cat > /tmp/smtp-test.txt <<'EOF'
From: AI Server <your-gmail-address>
To: <your-own-address>
Subject: SMTP test from the AI server

If you can read this, Gmail SMTP works.
EOF
```
Send it. With only the address in `--user`, curl asks for the password, so it stays out of your shell history; the prompt shows nothing while you paste, so paste the app password once and press Enter:
```bash
curl --ssl-reqd --url smtp://smtp.gmail.com:587 \
  --user "<your-gmail-address>" \
  --mail-from "<your-gmail-address>" --mail-rcpt "<your-own-address>" \
  --upload-file /tmp/smtp-test.txt && echo "sent"
rm /tmp/smtp-test.txt
```

| Result | Meaning |
|---|---|
| `sent`, and the email arrives (check spam too) | The account works |
| `curl: (55) MAIL failed: 530` | `--ssl-reqd` is missing; Gmail requires an encrypted connection |
| `curl: (67) Login denied` | Wrong password: use the app password, without spaces (steps 2–4) |
| Hangs, then `Connection timed out` | Port 587 is blocked on this network; try `--url smtps://smtp.gmail.com:465` |

For Gmail's exact reason, add `-v` and look for the line starting with `< 5`: `535 5.7.8 BadCredentials` (wrong password), `534 5.7.9 Application-specific password required` (the normal password was used), or `534 5.7.14 … log in via your web browser` (approve the account at gmail.com, step 5).

## The values

Every app reads the same names, so with Infisical put them once in `prod:/shared`; `pull-secrets.sh` copies them into each stack's `.env`. Without Infisical, write them into each app's `.env` (Infisical's own `.env` always by hand).

| Value | Gmail |
|---|---|
| `SMTP_HOST` | `smtp.gmail.com` |
| `SMTP_PORT` | `587` (STARTTLS) |
| `SMTP_USERNAME` | the dedicated Gmail address (also used as the sender) |
| `SMTP_PASSWORD` | the 16-character app password, no spaces |

Gmail sends only as the account itself: the "From" address is always `SMTP_USERNAME`, or Gmail rewrites it.

## Per app

| App (step) | Turn it on in its `.env` | Then |
|---|---|---|
| Infisical (Step 5) | Uncomment the four `SMTP_` lines | `cd /opt/stacks/infisical && docker compose up -d` |
| Outline (Step 7) | Uncomment the SMTP block; it also needs `SMTP_SECURE=false` and `SMTP_FROM_EMAIL` (the same address) | `cd /opt/stacks/outline && docker compose up -d` |
| Grafana (Step 9) | Uncomment the `SMTP_` lines, including `SMTP_ENABLED=true` | `cd /opt/stacks/grafana && docker compose up -d` |
| Langfuse (Step 11) | Uncomment `SMTP_USERNAME` and `SMTP_CONNECTION_URL`; in the URL, write the `@` of the address as `%40` (with Infisical, leave the URL empty; see below) | `cd /opt/stacks/langfuse && docker compose up -d` |

With Infisical, the app-specific extras (`SMTP_ENABLED`, `SMTP_SECURE`, `SMTP_FROM_EMAIL`) go in that app's own folder (`prod:/grafana`, `prod:/outline`), then `pull-secrets.sh <stack>`.

**Langfuse with Infisical:** `pull-secrets.sh` builds `SMTP_CONNECTION_URL` itself, from `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_HOST`, and `SMTP_PORT` in `prod:/shared`, with the `@` of the address written as `%40` (`smtps://` for port 465). It does so when `/opt/stacks/langfuse/.env` has an `SMTP_CONNECTION_URL=` line (it may be empty) and the folder `prod:/langfuse` exists without that key. A new app password in `prod:/shared` then reaches Langfuse with the next `pull-secrets.sh`. Check without showing the password: `grep ^SMTP_CONNECTION_URL= /opt/stacks/langfuse/.env | sed 's/:[^:@]*@/:***@/'`. A URL you set in `prod:/langfuse` yourself is kept, except that a plain `@` in its address becomes `%40`. It may use Infisical references, which Infisical fills in when `pull-secrets.sh` reads them: `smtp://${prod.shared.SMTP_USERNAME}:${prod.shared.SMTP_PASSWORD}@${prod.shared.SMTP_HOST}:${prod.shared.SMTP_PORT}` gives the same URL as the one built for you.

## Check

- **Infisical:** invite a user; they get an email.
- **Outline:** comment on a document someone else follows; they get an email.
- **Grafana:** Alerting → Contact points → add an email contact point → **Test**. The alert rules themselves: [Alerts](alerts.md).
- **Langfuse:** invite a member to a project.

If nothing arrives: `docker logs <container> 2>&1 | grep -iE "smtp|mail" | tail` (`535` means a wrong address or app password). Ask colleagues to mark the first email "Not junk" (or ask IT to allow the sender), since Microsoft 365 is strict with outside automated mail.

---

**Related:**
- [Step 5: Infisical (secrets)](../ai-server-setup-guide.md#step-5-infisical-secrets) → Usage
- [Step 7: Outline (wiki)](../ai-server-setup-guide.md#step-7-outline-wiki) → Authentication
- [Step 9: Monitoring stack](../ai-server-setup-guide.md#step-9-monitoring-stack) → Install
- [Step 11: Langfuse (LLM tracing)](../ai-server-setup-guide.md#step-11-langfuse-llm-tracing) → Install
- [Step 22: Docker housekeeping](../ai-server-setup-guide.md#step-22-docker-housekeeping)
- [Option: Alerts](alerts.md)
- [Option: Email and Azure AD sign-in](outline-email-and-azure.md)
