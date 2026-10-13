## Step 18: CI runner (GitHub)

Runs your GitHub repositories' workflow jobs on this server: tests, security checks, and AI review on every pull request. Jobs on the server reach LiteLLM, so reviews can use the local models and code stays in-house, and they use no GitHub minutes. The runner starts job containers through the host's Docker socket, so a workflow can control every container on this host: **connect it to private repositories only**; on a public repository, anyone's pull request could run code here. How the team uses it: [AI setup for software development](ai-setup-for-software-development.md).

**Check:** `github-runner`.

### Clean reinstall

Removes the runner as if it had never been installed. Skip it for a first install. Each line asks first.
```bash
confirm "Stop and remove the runner container?" && cd /opt/stacks/github-runner && docker compose down; cd ~
confirm "Delete the stack folder /opt/stacks/github-runner (settings and job work folders)?" && sudo rm -rf /opt/stacks/github-runner
confirm "Delete the runner image (downloaded again on the next install)?" && docker image rm myoung34/github-runner:latest
```
On GitHub: remove the runner from the list (organization or repository → Settings → Actions → Runners → `ai-server` → Remove) if it still shows, and delete its access token (your profile → Settings → Developer settings → Fine-grained tokens). Delete the Infisical folder `prod:/github-runner` if you used one.

Check that nothing is left; each command prints nothing:
```bash
docker ps -a --format '{{.Names}}' | grep -x github-runner
ls -d /opt/stacks/github-runner 2>/dev/null
```

### Install

1. **A GitHub token for the runner**, so it can register itself (again after every job, see `EPHEMERAL`). Your profile → Settings → Developer settings → **Fine-grained tokens** → Generate:
   - **For a whole organization** (every repository in it): Resource owner = the organization; Organization permissions → **Self-hosted runners: Read and write**.
   - **For one repository:** Resource owner = its owner; Only select repositories → the repository; Repository permissions → **Administration: Read and write**.
   Copy the token (shown once). An organization may need to approve it (Settings → Personal access tokens → Pending requests).

2. **The stack folder and its files:**
   ```bash
   mkdir -p /opt/stacks/github-runner/work
   ```
   `/opt/stacks/github-runner/.env` (with Infisical, the folder `prod:/github-runner`):
   ```env
   RUNNER_SCOPE=org                     # org: every repository of ORG_NAME; repo: only REPO_URL
   ORG_NAME=<GitHub organization>       # with RUNNER_SCOPE=org
   # REPO_URL=https://github.com/<owner>/<repository>   # with RUNNER_SCOPE=repo
   GITHUB_RUNNER_TOKEN=<the fine-grained token>
   ```
   `/opt/stacks/github-runner/compose.yaml`:
   ```yaml
   services:
     github-runner:
       image: myoung34/github-runner:latest
       container_name: github-runner
       restart: unless-stopped
       environment:
         RUNNER_SCOPE: ${RUNNER_SCOPE}
         ORG_NAME: ${ORG_NAME:-}
         REPO_URL: ${REPO_URL:-}
         ACCESS_TOKEN: ${GITHUB_RUNNER_TOKEN}
         RUNNER_NAME: ai-server
         LABELS: ai-server                  # workflows pick it with runs-on: [self-hosted, ai-server]
         EPHEMERAL: "true"                  # a fresh runner for every job: nothing left from the last one
         DISABLE_AUTO_UPDATE: "true"        # updates come with update-stack.sh
         # Job folders at the same path inside and outside the container, so containers a job
         # starts through the host Docker see the same files
         RUNNER_WORKDIR: /opt/stacks/github-runner/work
       volumes:
         - /var/run/docker.sock:/var/run/docker.sock
         - /opt/stacks/github-runner/work:/opt/stacks/github-runner/work
       # One job at a time (one runner), and a cap so a test run cannot starve the models
       mem_limit: 6g
       cpus: 4
       networks: [edge]                     # jobs reach LiteLLM as http://litellm:4000

   networks:
     edge:
       external: true
   ```
   The cap covers jobs that run inside the runner; containers a job starts itself (scanners, Playwright) take their own `--memory` flag, as in the example workflow.

3. **Start it:**
   ```bash
   cd /opt/stacks/github-runner && docker compose up -d
   ```

4. **Check the result.** Every line must match the table:
   ```bash
   docker inspect github-runner --format 'name={{.Name}}  state={{.State.Status}}  restart={{.HostConfig.RestartPolicy.Name}}  image={{.Config.Image}}'
   docker inspect github-runner --format 'networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'
   docker inspect github-runner --format '{{range .Mounts}}mount {{.Destination}} <- {{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}}{{println}}{{end}}'
   docker inspect github-runner --format 'memory={{.HostConfig.Memory}}  cpus={{.HostConfig.NanoCpus}}'
   docker exec github-runner sh -c 'echo "token: ${#ACCESS_TOKEN} characters, scope: $RUNNER_SCOPE, labels: $LABELS"'
   docker exec github-runner getent hosts litellm
   docker logs github-runner 2>&1 | grep -E "Listening for Jobs|Runner successfully added|error" | tail -5
   ```

   | Line | Expected |
   |---|---|
   | `name=` | `/github-runner  state=running  restart=unless-stopped`, image `myoung34/github-runner:latest` |
   | `networks=` | `edge` |
   | `mount` | `/var/run/docker.sock <- /var/run/docker.sock` and `/opt/stacks/github-runner/work <- /opt/stacks/github-runner/work` (same path both sides) |
   | `memory=` | `6442450944  cpus=4000000000` (6 GB, 4 cores) |
   | Environment | `token: 93 characters` (fine-grained tokens are about that long), your scope, `labels: ai-server` |
   | `getent` | an address for `litellm` |
   | Log | `Runner successfully added` and `Listening for Jobs`, no `error` |

   On GitHub: the organization or repository → Settings → Actions → **Runners** lists `ai-server` as **Idle**.

**Verify:** the runner shows as Idle on GitHub, and a workflow with `runs-on: [self-hosted, ai-server]` runs on it (see Test below).

### Authentication

The runner has no web page or login. It signs in to GitHub with its token, and only repositories in its scope can send it jobs. Workflows reach LiteLLM with a virtual key stored as a GitHub secret (see the AI review option), never the master key.

### Usage

**A workflow per repository.** Add `.github/workflows/ci.yml` to each repository; it runs on every pull request and on pushes to `main`. Keep the jobs the repository needs, delete the rest:
```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]

jobs:
  # Security checks: secrets, insecure code, vulnerable dependencies. Each tool runs as its own
  # container with a memory cap; the job folder has the same path on the host (see compose.yaml).
  checks:
    runs-on: [self-hosted, ai-server]
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0                    # full history, so Gitleaks also checks earlier commits
      - name: Secrets (Gitleaks)
        run: docker run --rm --memory 1g -v "$PWD:/repo" ghcr.io/gitleaks/gitleaks:latest detect --source /repo --redact --no-banner
      - name: Code patterns (Semgrep)
        run: docker run --rm --memory 2g -v "$PWD:/src" -w /src semgrep/semgrep semgrep scan --config p/default --metrics=off --error
      - name: Dependencies and Dockerfiles (Trivy)
        run: docker run --rm --memory 2g -v "$PWD:/src" -v trivy_cache:/root/.cache aquasec/trivy:latest fs --scanners vuln,misconfig --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 /src

  # Unit tests: .NET
  test-dotnet:
    runs-on: [self-hosted, ai-server]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: "9.0.x"
      - run: dotnet test --logger "console;verbosity=normal"

  # Unit tests: JavaScript / TypeScript (Vitest)
  test-js:
    runs-on: [self-hosted, ai-server]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "22"
      - run: npm ci
      - run: npx vitest run

  # End-to-end in real browsers (Playwright), in its own container with the browsers inside
  e2e:
    runs-on: [self-hosted, ai-server]
    needs: [test-js]
    container:
      image: mcr.microsoft.com/playwright:v1.56.0-noble   # match the Playwright version in package.json
      options: --memory 4g --ipc=host
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npx playwright test
```

**Make the checks required.** Repository → Settings → Branches → add a rule for `main`: **Require a pull request before merging**, and **Require status checks to pass** with the jobs above (`checks`, `test-dotnet`, `test-js`, `e2e`). Then nothing reaches `main` without passing tests and checks.

- **One job at a time:** jobs queue on GitHub and run one after another; a pull request's checks take a few minutes each. Long queues mean adding a second runner (a copy of the stack with another `RUNNER_NAME`), at the cost of more CPU and RAM next to the models.
- **Images used by jobs** (Playwright, scanners) stay on the server between runs; `docker-cleanup.sh` (Step 22) removes them when unused.
- **AI review on pull requests:** [AI code review (PR-Agent)](options/pr-agent.md) adds a review job that uses LiteLLM.

**Option:** [AI code review (PR-Agent)](options/pr-agent.md) — AI review comments on every pull request, from a local or hosted model through LiteLLM.

**Option:** [App error tracking (GlitchTip)](options/glitchtip.md) — errors of the apps you build, with the Sentry SDKs (about 1 GB of RAM); for later, apps already on Sentry keep it.

### Test

1. **A job runs here.** In a test repository, push a branch with this `.github/workflows/runner-test.yml` and open a pull request:
   ```yaml
   name: Runner test
   on: [pull_request]
   jobs:
     hello:
       runs-on: [self-hosted, ai-server]
       steps:
         - run: echo "Hello from $(hostname)"; docker version --format '{{.Server.Version}}'
   ```
   The job turns green within a minute; its log shows the Docker version (the job can use Docker). Meanwhile `docker logs github-runner 2>&1 | tail` shows the job running.
2. **The checks work.** In the same pull request, add a file `leak.txt` with a fake GitHub token (`token = "ghp_1a2B3c4D5e6F7g8H9i0J1k2L3m4N5o6P7q8R"`) and the `checks` job: it fails on Gitleaks. Remove the file: it passes.

| Symptom | Cause |
|---|---|
| Job stays "Waiting for a runner" | Labels differ (`runs-on` must include `ai-server`), the repository is outside the runner's scope, or the runner is offline (`docker logs github-runner`) |
| Log: `Could not get a registration token` / `401` | Token expired, wrong permission, or awaiting the organization's approval |
| Scanner step: `no such file or directory` for `/repo` | The work folder is not mounted at the same path inside and outside the container |
| A job is killed (`exit code 137`) | It hit a memory cap; raise `mem_limit` or the step's `--memory` |

