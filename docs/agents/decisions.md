# Decision log

Why the guide is the way it is, so a change does not undo a choice by accident. Newest first. Before reversing one, ask the user; when a new choice is made, add it here with the reason.

| Decision | Why | Where |
|---|---|---|
| The team guide covers the whole software team (product, developers, QA, release), with the team's stack in one table | Every role uses the server; one table keeps the page reusable by another team | `ai-setup-for-software-development.md` |
| Deploys run on GitHub-hosted runners with OpenID Connect to Azure; the AI server runner does pull request checks only | The AI server runner runs pull request code and AI tools, so production credentials never go there | `ai-setup-for-software-development.md` → Deploy to Azure |
| Third-party AI in tiers: local models see everything, hosted models through LiteLLM and company business accounts see non-confidential work, personal accounts nothing | A default the user may tighten; company policy decides | `ai-setup-for-software-development.md` → Third-party AI |
| The Outline export fills in `SERVER_HOST` / `SERVER_IP` only when they are set in the environment; the repo copy is always generic | Readers in Outline get ready-to-run commands, while the repo stays reusable and free of server names | `tools/build-outline-export.py`; `docs/agents/guide.md` → Outline export |
| No checklists; checks are scripts (`server-test.sh`, `server-status.sh`) or numbered Test items | A script reports pass or fail on its own; ticks in Outline would be saved into the shared guide | Step 21; `docs/agents/guide.md` |
| Apps already on Sentry (and work tracked in Azure DevOps) keep them; GlitchTip is an option for later, not installed by default | Existing tools work and are paid for; the same Sentry SDK means moving later is a DSN change | `options/glitchtip.md`; `ai-setup-for-software-development.md` |
| Comment commands for AI review run as an `issue_comment` workflow on the self-hosted runner, not a GitHub App | A GitHub App needs a webhook GitHub can reach; the server is internal-only, and the runner only connects outward | `options/pr-agent.md` |
| Every service step has the same layout: Clean reinstall, Install (with Check the result), the topic parts, Test | Each service can be removed, installed, and verified on its own, with expected values to compare | `docs/agents/guide.md` → Service step layout |
| Scripts live in `scripts/` in the repo, and in `~/ai-server` on the server, linked into stack folders where needed | One copy of each script; updating means replacing files in one folder | `options/helper-scripts.md` |
| Shell commands use `${SERVER_HOST}` / `${SERVER_IP}` | Commands copy and run once the shared file is loaded | `docs/agents/guide.md` → Commands |
| Development-server defaults: no volume backups (`backup-config.sh` keeps configuration and the Infisical and Outline databases), Prometheus 30 days, Docker logs 10 MB × 3, health checks every 30 s after start | The server is for development; disk and CPU go to the models | Steps 2, 9, 20; `docs/agents/compose.md` |
| OpenHands runs on plain HTTP, opened by IP, outside Caddy | Its browser connects straight to sandbox containers on random ports that Caddy cannot front; HSTS from Outline forces HTTPS on the server name | Step 16 |
| `pull-secrets.sh` reads Infisical with references filled in (`--expand=true`) and keeps keys missing from Infisical unless asked | References (`${prod.shared.KEY}`) work as users expect; removing a key by surprise breaks a stack | Step 5; `scripts/pull-secrets.sh` |
| Each stack network has a bridge name (`br-edge`, `br-<stack>`) | Readable names in `ip -br link` and monitoring | Step 2; `docs/agents/compose.md` |
| Model names in LiteLLM are family, version, size (`qwen3.8-27b`), never the runtime; `local-model` means whatever runs now; `-shared` marks hosted models on the company key | Names stay right when a model moves runtime; users see what costs money | Step 12; `options/litellm-hosted-models.md` |
| Open WebUI is the chat app for everyone | Free OIDC through Dex, uses LiteLLM and the existing Qdrant, few extra containers | Step 17 |
| No `<placeholder>` in compose or env-reading config files; values come from `.env` | Uncommenting is the only edit; nothing to fill in by hand in two places | `docs/agents/compose.md` |
| Sign-in through Dex for every app that supports it; Infisical takes Google directly | One account everywhere without paid SSO; Infisical's OIDC is paid | Steps 5, 6 |
| Caddy is append-only: its two files are written once, each service adds one `conf.d` file | No step edits an earlier step's file | `docs/agents/caddy-and-ports.md` |
| Free versions only; paid features marked 💲 and not depended on | The guide must work without licenses | `AGENTS.md` |
