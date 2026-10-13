*Copied from `ai-setup-for-software-development.md` in the ai-server repo.*

How the whole software team works with AI, from a requirement to code running in production: product owners and business analysts, developers, QA, and release. Most of it runs on the AI server; hosted models and third-party AI apps are used within the rules under [Third-party AI](#third-party-ai). Setting the services up is in the AI server setup guide (document "Self-Hosted AI Server Setup Guide"); this document only uses them. Addresses below use `<SERVER_HOST>` for the server name your admin gives you.

## Your team's stack

The rest of this page refers to these rows ("your test runner", "your hosting"); another team reuses the page by changing this table.

| Area | Tools |
|---|---|
| Requirements | PRDs (product requirements documents), with acceptance criteria |
| Code and CI | GitHub, GitHub Actions |
| Back end | .NET, C# |
| Front end | TypeScript (React, Angular, jQuery), Sass |
| Tests | `dotnet test` and `npm test` (unit), Playwright (end to end), Cucumber (Given/When/Then scenarios) |
| Hosting | Azure |
| Monitoring | Sentry (app errors), Azure DevOps Analytics (delivery), Langfuse (AI features) |

## Who uses what

| Role | Main tools | Where on this page |
|---|---|---|
| Product owner, business analyst | Open WebUI for PRDs and acceptance criteria; Outline | [The workflow](#the-workflow), step 1 |
| Developer | Claude Code or Codex through LiteLLM, Sourcebot, OpenHands | [The workflow](#the-workflow), steps 2 to 6 |
| QA | Open WebUI and agents for scenarios and Playwright tests | [Tests from the PRD](#tests-from-the-prd) |
| Release, DevOps | CI runner, deploy to Azure, Grafana | [Deploy to Azure](#deploy-to-azure) |
| Reviewer, tech lead | PR-Agent comments in pull requests | [AI review in pull requests](#ai-review-in-pull-requests) |

## What you get

| Service | Address | Use it for |
|---|---|---|
| Open WebUI | `https://<SERVER_HOST>:9485` | Chat with any model; write and review PRDs; ask about documents and specifications |
| LiteLLM | `https://<SERVER_HOST>:4000` | One OpenAI-compatible API for every model, used by your tools (Claude Code, Codex, VS Code) with your own key |
| Sourcebot | `https://<SERVER_HOST>:9460` | Search all company code; its MCP endpoint gives agents the same search |
| OpenHands | `http://<SERVER_IP>:3000` | An agent that works on a task by itself in a sandbox |
| Outline | `https://<SERVER_HOST>` | Team wiki, including the Services page with the current model list |
| Langfuse | `https://<SERVER_HOST>:9470` | Every model call: prompt, answer, time, tokens; also for LLM features you build |
| CI runner | GitHub, runner `ai-server` | Tests, security checks, and AI review on every pull request, run on the server |
| GlitchTip (if installed) | `https://<SERVER_HOST>:9475` | Errors from the apps you build, for apps not on Sentry |

### Other services on the server

Mostly for admins, but open to you; each signs in with your company account unless noted.

| Service | Address | What it is for | Sign-in |
|---|---|---|---|
| Infisical | `https://<SERVER_HOST>:8080` | Secrets for the server's `.env` files; ask the admin for access to a project | Own account, or Google if turned on |
| Portainer | `https://<SERVER_HOST>:9443` | Containers on the server: status, logs, restarts | Dex button |
| Grafana | `https://<SERVER_HOST>:9450` | Dashboards: CPU, GPU, memory, disk; is the GPU busy? | Dex button |
| Prometheus | `https://<SERVER_HOST>:9090` | The raw metrics behind Grafana | Sign-in gate |
| Qdrant | `https://<SERVER_HOST>:6333/dashboard` | Vector database: Open WebUI documents, collections for your own retrieval (RAG) | Sign-in gate; code reaches it from a container on the server, or with an API key (**Without the sign-in gate** (document "Option: Without the sign-in gate")) |
| Neo4j | `https://<SERVER_HOST>:7474`, bolt `<SERVER_HOST>:7687` | Graph database: the browser, or a driver from your code | Sign-in gate, then the database user; bolt: the database user only |
| Memgraph | `https://<SERVER_HOST>:9490`, bolt `<SERVER_HOST>:7688` | Graph database (Memgraph Lab), for graph analytics | Sign-in gate |

"Dex button" means the app's own **Continue with Dex** (or OAuth) button; "sign-in gate" means a Dex sign-in page before the app opens, shared by all gated apps.

## Get started (once)

1. **Reach the server:** the hosts-file line and the certificate import from the Services page in Outline (setup guide, Step 4).
2. **Sign in:** Outline, Open WebUI, Langfuse, and Grafana use your company Google account through Dex. Product owners, business analysts, and QA who do not code need only steps 1 and 2: Open WebUI and Outline work in the browser.
3. **Your LiteLLM key:** ask the admin for a personal virtual key (setup guide, Step 12: keys per developer). Never use or share the master key.
4. **Your tools:** point Claude Code, Codex, VS Code, T3 Code, or Orca at LiteLLM: **Developer tools** (document "Option: Developer tools"). For Node-based tools, also set `NODE_EXTRA_CA_CERTS` to the CA file.
5. **Code search in your agent:** add Sourcebot's MCP endpoint `https://<SERVER_HOST>:9460/api/mcp` to Claude Code or Codex (setup guide, Step 16: Connecting tools).

## The workflow

*Diagram: software development workflow — drag `development-workflow.png` here.*

1. **Requirements.** Write or improve the PRD with Open WebUI: paste the draft and ask for gaps, edge cases, and open questions; then ask for the acceptance criteria as Given/When/Then scenarios, which become the Cucumber tests. Keep the final PRD where the team and the agents read it (Outline, or with the code in `docs/`). For confidential requirements, use a local model ([Third-party AI](#third-party-ai)).
2. **Understand.** Search the code in Sourcebot (or let the agent do it through MCP). Ask questions about the PRD, specifications, or documents in Open WebUI (upload them, or use a shared knowledge collection).
3. **Plan.** Give the agent the PRD and ask for a plan before it edits anything (Claude Code: plan mode; Codex: ask for a plan first). Check the plan against the acceptance criteria; it is cheaper to fix than the code.
4. **Code with an agent.** Claude Code or Codex in your editor or terminal, through LiteLLM. Give it the task, the files, and how to test it (`dotnet test`, `npm test`, `npx playwright test`). For a self-contained task you do not need to watch, start it in OpenHands. Let the agent write the tests with the code, including the Cucumber steps for the scenarios from step 1.
5. **Test locally.** Run the unit tests and, for UI changes, the end-to-end tests. Read the diff yourself: you own the change, not the agent.
6. **Pull request.** Push a branch and open a pull request; describe what and why, and link the PRD. No secrets in code: keys go in `.env` files that are not committed, in GitHub secrets, or in Infisical.
7. **CI on the AI server.** The runner checks every pull request (setup guide, Step 18): unit and end-to-end tests, Gitleaks (secrets), Semgrep (insecure code), Trivy (vulnerable dependencies), and an AI review as comments (see [AI review in pull requests](#ai-review-in-pull-requests)). Fix what fails; apply or answer the review comments, and ask the reviewer with `/ask` when a comment is unclear.
8. **Merge.** Branch protection lets a pull request into `main` only when every check is green.
9. **Deploy to Azure.** A GitHub-hosted runner deploys, not the AI server: see [Deploy to Azure](#deploy-to-azure).
10. **Watch.** App errors in Sentry; delivery in Azure DevOps Analytics; for features that call models, every call in Langfuse, with time and cost. A bug or a new need starts again at step 1.

## Tests from the PRD

The acceptance criteria in the PRD become tests in three moves; QA and developers can each start any of them.

1. **Scenarios.** In Open WebUI, give the PRD and ask for Cucumber scenarios (a `.feature` file): one `Scenario` per acceptance criterion, plus the edge cases from the requirements step. Review them with the product owner; they are the agreed behavior.
2. **Steps.** Ask the coding agent to write the step definitions for the `.feature` file with Playwright, following the existing steps in the repository. Run them: new scenarios fail until the feature exists.
3. **Check in a browser.** With the Playwright MCP server added to Claude Code or Codex, the agent opens the app, clicks through a scenario, and reports what differs; use it to reproduce a bug or check a UI change before writing the test.

The CI runner runs the scenarios with the rest of the end-to-end tests on every pull request.

## Deploy to Azure

Pull request checks run on the AI server runner; the deploy runs on a **GitHub-hosted runner**. The AI server runner also runs pull request code and AI tools, so production credentials never go there. In the deploy workflow:

- `runs-on: ubuntu-latest` (GitHub-hosted; free minutes depend on the plan), never `[self-hosted, ai-server]`.
- Sign in to Azure with OpenID Connect (`azure/login` with a federated credential on an app registration): no Azure password or key stored in GitHub.
- A GitHub environment `production` with required reviewers holds the deploy until someone approves it.

```yaml
name: Deploy
on:
  push:
    branches: [main]
permissions:
  id-token: write
  contents: read
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: "9.0.x"
      - run: dotnet publish -c Release -o publish
      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      - uses: azure/webapps-deploy@v3
        with:
          app-name: ${{ vars.AZURE_WEBAPP_NAME }}
          package: publish
```

The example deploys a .NET app to App Service. For a front end, build it with `npm ci` and `npm run build` and deploy the build folder the same way, or to Static Web Apps. The four values are GitHub repository or environment variables, not secrets: OpenID Connect needs no secret.

## AI review in pull requests

Every new or updated pull request gets an AI review from PR-Agent, run on the AI server through LiteLLM: a summary, possible problems, and code suggestions, as comments. The repository needs the review workflow once: `.github/workflows/review.yml` from **AI code review (PR-Agent)** (document "Option: AI code review (PR-Agent)"), committed to the default branch, and the secret `PR_AGENT_LITELLM_KEY` (ask the admin for the key).

**Ask for more in a comment.** Start a pull request comment with a command; the answer appears as a new comment within a minute or two:

| Comment | You get |
|---|---|
| `/review` | A fresh review, e.g. after you pushed fixes |
| `/improve` | Code suggestions on the lines of the diff |
| `/describe` | A title and description written from the changes |
| `/ask How is the token refreshed here?` | An answer about the changes |
| `/update_changelog` | A suggested `CHANGELOG.md` entry |

- Only people with write access to the repository can start a command.
- Replies come from `github-actions`; commands queue behind running tests on the server.
- The model is set per repository in the workflow: a local one keeps the code on the server, `claude-sonnet-5.5-shared` reviews more deeply (billed to its key budget).
- Treat the review as a colleague's first pass: it catches a lot and is sometimes wrong; you decide.

## Which model for what

Model names are LiteLLM's (the Services page in Outline lists the current ones).

| Task | Model | Why |
|---|---|---|
| Everyday chat, quick questions | `local-model` / `gemma4-12b` | Fast, free, stays on the server |
| PRDs, acceptance criteria, scenarios | `claude-sonnet-5.5-shared`; `qwen3.6-35b-a3b` for confidential ones | Long documents and careful wording |
| Long files or documents | `qwen3.5-9b` | Most room for context |
| Harder reasoning or code, privately | `qwen3.6-35b-a3b` | Smarter, slower |
| Agent work (Claude Code, Codex, OpenHands) | `claude-sonnet-5.5-shared` | Reliable with long prompts and tools; billed to the company key under your budget |
| Agent work that must stay in-house | `qwen3.5-9b` | Small, clear tasks only |
| AI review in CI | `qwen3.5-9b` (in-house) or `claude-sonnet-5.5-shared` (deeper) | Set per repository |

Local models answer only while Ollama runs (not while the server runs vLLM); `local-model` and `gemma4-12b` always answer.

## Third-party AI

Where an AI runs decides what it may see. This table is a starting point: **your company policy decides it**, so ask the admin which row applies to your project.

| Where the AI runs | Examples | What it may see |
|---|---|---|
| Local models on the AI server | `local-model`, `qwen3.6-35b-a3b` | Everything, including confidential code and customer data |
| Hosted models through LiteLLM | `-shared` models: Claude, OpenAI, Azure OpenAI | Company code and documents not marked confidential; no customer personal data (the admin may mask it on the way: **Data protection for hosted models** (document "Option: Data protection for hosted models")) |
| Third-party apps on a company business account | 💲 GitHub Copilot Business, ChatGPT Business, Claude Team | The same as hosted models; business plans do not train on your data, but the calls bypass LiteLLM, so there is no budget and no Langfuse log |
| Personal accounts, free plans | Any | Nothing from the company |

- **Prefer LiteLLM.** Tools that can use it (Claude Code, Codex, VS Code: **Developer tools** (document "Option: Developer tools")) get every model with one key, a budget, and a log; VS Code Copilot Chat can send its chat through LiteLLM too.
- **Everything through LiteLLM is logged in Langfuse**, prompts included; admins can read them.
- **Your key has a budget** on hosted models; when it runs out, ask the admin.
- **Review what the agent wrote** before you push; CI checks catch a lot, not everything.

## Optional tools

Everything else that fits this workflow, grouped by step. **On server** = can run on the AI server (with the extra load), **cloud** = a hosted service (code or data leaves the company), **free** = no cost, **free plan** = limited free use (limits approximate; check the vendor).

### Coding

| Tool | Kind | Fits when | Notes |
|---|---|---|---|
| Claude Code, Codex (CLI and app), VS Code Copilot Chat, Continue, Cline | Your PC, through LiteLLM | Writing code with an agent | Setup: **Developer tools** (document "Option: Developer tools") |
| T3 Code, Orca | Your PC | Several agents in parallel, each in its own git worktree | Run Claude Code or Codex underneath; same setup |
| Claude Desktop | Your PC, through LiteLLM | Chat in a desktop app | Gateway setting; Claude models work best |
| Open WebUI | On server (installed) | Chat and documents in the browser | Step 17 |

### Tests

| Tool | Kind | Fits when | Compared with |
|---|---|---|---|
| **Vitest** | Free, runs in CI | JS/TS unit tests | Jest: slower, older; same API |
| **xUnit** via `dotnet test` | Free, runs in CI | .NET unit tests | NUnit, MSTest: same runner, pick one per solution |
| **Playwright** | Free, runs in CI | Browser end-to-end tests | Cypress (Chromium-family, slower in parallel), Selenium (older, flakier) |
| **Cucumber** (JS, with Playwright) / Reqnroll (.NET) | Free, runs in CI | Given/When/Then scenarios from the PRD ([Tests from the PRD](#tests-from-the-prd)) | SpecFlow: discontinued, Reqnroll replaces it for .NET |
| Playwright MCP | Free, your PC | An agent drives a browser to reproduce or check a UI change | Runs in Claude Code or Codex |
| BrowserStack, Sauce Labs | Cloud, free for open source | Real mobile devices and many browsers | Playwright covers desktop browsers |

### Code checks

| Tool | Kind | Finds | Compared with |
|---|---|---|---|
| **Gitleaks** | Free, runs in CI | Secrets in code | TruffleHog (verifies online), GitGuardian (cloud, free plan up to ~25 developers), GitHub secret scanning (free for public repos) |
| **Semgrep CE** | Free, runs in CI | Insecure or buggy code patterns | Semgrep AppSec Platform (cloud, free up to ~10 contributors, cross-file analysis), CodeQL (free for public repos), Snyk Code (free plan, limited tests) |
| **Trivy** | Free, runs in CI | Vulnerable dependencies, Docker images, Dockerfiles | Grype, OWASP Dependency-Check, Snyk Open Source (free plan, limited tests), Dependabot alerts (free on GitHub) |
| ESLint, Stylelint, `dotnet format` | Free, runs in CI | Style and likely bugs in TypeScript, Sass, and C# | Prettier (formatting only) |
| SonarQube Community Build | On another server (2–4 GB RAM) | Quality dashboard over time | SonarQube Cloud (free for public repos, private up to ~50k lines), Codacy (free for open source) |
| DefectDojo | On another server (2–4 GB RAM) | Collects all scanners' findings | GitHub code scanning (free for public repos) |

### Review

| Tool | Kind | Notes |
|---|---|---|
| **PR-Agent** | Free, runs in CI through LiteLLM | **AI code review (PR-Agent)** (document "Option: AI code review (PR-Agent)") |
| Claude Code GitHub Action | Free action, Claude usage billed | Reviews or fixes on request in a pull request; can use LiteLLM as its gateway |
| CodeRabbit | Cloud, free plan | PR summaries free; full review free for open source |
| Qodo Merge | Cloud, free plan | Hosted PR-Agent, limited reviews per month |

### Dependencies

| Tool | Kind | Notes |
|---|---|---|
| **Dependabot** | Free, built into GitHub | Update pull requests and security alerts |
| Renovate | Free, runs in CI | More control (grouping, schedules) |

### CI and deploy

| Tool | Kind | Notes |
|---|---|---|
| **Self-hosted runner** | On server (installed) | Step 18; free, reaches LiteLLM; pull request checks only |
| **GitHub-hosted runners** | Cloud, free plan (~2,000 min/month for private repos) | Deploys to Azure ([Deploy to Azure](#deploy-to-azure)); fallback for checks when the server is busy or down |
| GitLab CE, Gitea + Woodpecker | Self-hosted Git + CI | Only if the code moves off GitHub; GitLab needs 4–8 GB RAM |

### Errors in your apps

Your apps report to Sentry, and the team tracks delivery in Azure DevOps Analytics; both stay, and the server does not replace them. The options below are for new apps or a later move; GlitchTip takes the same Sentry SDK, so moving is a change of DSN.

| Tool | Kind | Notes |
|---|---|---|
| **Sentry** | Cloud (in use); self-hosted needs ~16 GB RAM (too heavy here) | Most complete |
| GlitchTip | On server (~0.5–1 GB) | **App error tracking (GlitchTip)** (document "Option: App error tracking (GlitchTip)"); uses the Sentry SDKs |
| Bugsink | On server (~0.3 GB) | Lighter, errors only |
| Grafana Tempo + OpenTelemetry | On server (~0.3–1 GB) | Request tracing in the existing Grafana |
| Grafana Cloud | Cloud, free plan (~10k metric series, ~50 GB logs/traces, 14 days) | If you prefer hosted |

### LLM features you build

| Tool | Kind | Notes |
|---|---|---|
| **Langfuse** | On server (installed) | Tracing, prompt management, datasets, and evaluations for apps that call models; point your app at LiteLLM and it is traced already |
| Opik | Self-hosted 4–8 GB (duplicates Langfuse); cloud free plan | Skip while Langfuse covers it |
| Langfuse Cloud | Cloud, free plan (~50k units/month, 30 days) | Only for projects outside this server |
