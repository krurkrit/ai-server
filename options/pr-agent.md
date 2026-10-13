# Option: AI code review (PR-Agent)

Part of [Step 18: CI runner (GitHub)](../ai-server-setup-guide.md#step-18-ci-runner-github). Every pull request gets an AI review: a summary, likely problems, and suggested changes, as comments on the pull request. PR-Agent (open source, by Qodo) runs as a job on the server's runner and asks the models through LiteLLM, so a local model keeps the code in-house, or a hosted one (e.g. `claude-sonnet-5.5-shared`) gives deeper reviews. Each call shows in Langfuse.

## Set it up

1. **A LiteLLM key for reviews**, limited to the models you allow (a budget too, for hosted models):
   ```bash
   curl -k https://${SERVER_HOST}:4000/key/generate \
     -H "Authorization: Bearer <LITELLM_MASTER_KEY>" -H "Content-Type: application/json" \
     -d '{"key_alias":"pr-agent","models":["qwen3.5-9b","claude-sonnet-5.5-shared"],"max_budget":20,"budget_duration":"30d"}'
   ```
2. **The key as a GitHub secret:** organization or repository → Settings → Secrets and variables → Actions → **New secret** `PR_AGENT_LITELLM_KEY`.
3. **The review workflow.** Add `.github/workflows/review.yml` to the repository. It reviews every new or updated pull request, and answers comment commands (see Comment commands below):
   ```yaml
   name: AI review
   on:
     pull_request:
       types: [opened, reopened, ready_for_review, synchronize]
     issue_comment:
       types: [created]
   permissions:
     contents: read
     issues: write
     pull-requests: write

   jobs:
     ai-review:
       # Pull request events, or a comment starting with / on a pull request by someone with
       # write access (never the bots own replies)
       if: >-
         github.event_name == 'pull_request' ||
         (github.event.issue.pull_request &&
          startsWith(github.event.comment.body, '/') &&
          github.event.sender.type != 'Bot' &&
          contains(fromJSON('["OWNER","MEMBER","COLLABORATOR"]'), github.event.comment.author_association))
       runs-on: [self-hosted, ai-server]
       env:
         # LiteLLM on the server, reached over edge (the job runs inside the runner container)
         OPENAI__API_BASE: http://litellm:4000/v1
         OPENAI__KEY: ${{ secrets.PR_AGENT_LITELLM_KEY }}
         # A LiteLLM model name, with the openai/ prefix; custom_model_max_tokens is required
         # for names PR-Agent does not know, and must fit the model context
         CONFIG__MODEL: openai/qwen3.5-9b
         CONFIG__FALLBACK_MODELS: '["openai/qwen3.5-9b"]'
         CONFIG__CUSTOM_MODEL_MAX_TOKENS: "24000"
         CONFIG__DUPLICATE_EXAMPLES: "true"
         GITHUB__USER_TOKEN: ${{ secrets.GITHUB_TOKEN }}
         # The pull request, from either event; the comment text is passed as data, never as code
         PR_URL: ${{ github.event.pull_request.html_url || github.event.issue.pull_request.html_url }}
         COMMENT: ${{ github.event.comment.body }}
       steps:
         - run: python3 -m pip install --quiet --user pr-agent
         - name: Run PR-Agent
           run: |
             if [ "$GITHUB_EVENT_NAME" = "pull_request" ]; then
               python3 -m pr_agent.cli --pr_url "$PR_URL" review
               python3 -m pr_agent.cli --pr_url "$PR_URL" improve
               exit 0
             fi
             line=$(printf '%s' "$COMMENT" | head -n 1)
             cmd=${line%% *}
             arg=${line#"$cmd"}
             case "$cmd" in
               /review|/improve|/describe|/update_changelog)
                 python3 -m pr_agent.cli --pr_url "$PR_URL" "${cmd#/}" ;;
               /ask)
                 python3 -m pr_agent.cli --pr_url "$PR_URL" ask "$arg" ;;
               *)
                 echo "Not a PR-Agent command: $cmd" ;;
             esac
   ```
   For a hosted model, set `CONFIG__MODEL: openai/claude-sonnet-5.5-shared` (and the fallback), and `CONFIG__CUSTOM_MODEL_MAX_TOKENS: "100000"`. To review only on request, delete the `pull_request:` trigger and its `types:` line.

## Comment commands

In a pull request, write a comment that starts with the command. The runner picks it up within seconds, and the answer appears as a new comment (from `github-actions`):

| Comment | Does |
|---|---|
| `/review` | A review: summary, effort, possible issues, security concerns |
| `/improve` | Code suggestions, each on its line of the diff |
| `/describe` | Writes the pull request title and description from the changes |
| `/ask Why is the cache cleared here?` | Answers a question about the changes |
| `/update_changelog` | Adds the change to `CHANGELOG.md` (suggested, as a comment) |

Only people with write access (owner, member, collaborator) can start a command; other comments and the bot's own replies are ignored. Each command is one job on the runner, so it waits behind running tests, and uses the model in `CONFIG__MODEL` (a local model loads into the GPU first).

**Why not a GitHub App:** a GitHub App answers comments through a webhook, which GitHub has to reach over the internet; this server is internal-only. The runner fetches its jobs from GitHub instead (outbound only), so comment commands work without exposing anything. The differences: replies come from `github-actions` instead of an app with its own name, and each repository needs the workflow file (an organization can share it through a workflow template).

## Which model

| Model | Review quality | Speed | Cost | Code leaves the server |
|---|---|---|---|---|
| `qwen3.5-9b` (local) | Basic: style, obvious bugs, summaries | Fast | Free | No |
| `qwen3.6-35b-a3b` (local) | Better, misses subtle issues | Slow on a big diff | Free | No |
| `claude-sonnet-5.5-shared` | Good: logic, security, design | Fast | Tokens, under the key budget | Yes |

Local models need the context set in Step 13 (`OLLAMA_CONTEXT_LENGTH`) to hold the diff; keep `CONFIG__CUSTOM_MODEL_MAX_TOKENS` below it. A review queues behind other jobs on the runner and loads its model into the GPU, which pushes out the one people are using.

## Check

Open a pull request with a small change. Within a few minutes the `ai-review` job turns green and the pull request gets two comments: a review (summary, possible issues) and code suggestions. The calls show in Langfuse and under the key `pr-agent` in LiteLLM (**Usage**).

| Symptom | Cause |
|---|---|
| `401` in the job log | Wrong `PR_AGENT_LITELLM_KEY`, or the key does not allow the model |
| `Name or service not known: litellm` | The job did not run on the server's runner (`runs-on`), or the runner is not on `edge` |
| A comment command does nothing | It does not start the comment (first line), the commenter has no write access, or the workflow file is not on the default branch (GitHub runs `issue_comment` workflows from there) |
| No comments, job green | `permissions: pull-requests: write` missing, or the organization limits `GITHUB_TOKEN` to read-only (Settings → Actions → General → Workflow permissions) |
| Answers cut off or empty | The diff is larger than `CONFIG__CUSTOM_MODEL_MAX_TOKENS` or the model context; raise both, or use a hosted model |

---

**Related:**
- [Step 18: CI runner (GitHub)](../ai-server-setup-guide.md#step-18-ci-runner-github) → Usage
