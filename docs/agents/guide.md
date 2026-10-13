# Guide rules (`ai-server-setup-guide.md`)

How the guide, the option pages, and the team guide are written: structure, step layout, commands, headings, links, and the Outline export.

## Generic and reusable

- No hostnames, IPs, usernames, or "current state" of any particular server. Use `<SERVER_HOST>` in prose, URLs, and ad-hoc commands, `${SERVER_HOST}` in compose files, and `{$SERVER_HOST}` in Caddy files. `SERVER_HOST` is the name (or the IP when there's no name). When an example needs a real domain (e.g. for Google sign-in), use `ai.domain.com` and `domain.com`. Write a folder in Infisical as `prod:/<name>` (environment, colon, path), never a bare `/<name>`, and a folder on the server always in full (`/opt/stacks/<stack>/`), so the two can't be confused; scripts print `$ENV_SLUG:/<name>`. `SERVER_IP` appears only where a raw IP is required: Caddy's `default_sni`, the second address in Caddy site blocks, the hosts-file line, and verify commands that test IP access.
- Every step starts by checking that service's current state (check-first). The reader then installs, migrates, or skips. Any subset of steps must work on its own.

## Step order and numbering

- Order steps by dependency and number them with whole numbers only (Prerequisite, then 1…N). A step may depend only on earlier steps, except for forward references that are harmless at runtime (e.g. a Prometheus scrape target that shows DOWN until its service exists).
- The document reads in step order. The "Steps at a glance", "Service status check", "Resource usage", and "Access map" tables use the same order and numbering.
- Renumbering or renaming a step means updating every `Step N` reference in the guide's prose, the per-stack list in the Update workflow step, and every link to its heading anchor (`#step-n-…`): the "Steps at a glance" table links each step, and option files link back to their step.
- `Step N` references belong in prose only, never inside a code block (compose, `.env`, config, Caddy, shell). Inside files, name the service or the file path instead (e.g. "from `/opt/stacks/litellm/.env`", "leave this out if Langfuse isn't deployed"). Files get copied to the server, and step numbers there go stale on renumbering.

## Tables

- "Service status check" has one row per container: Step, Service, Container, Needs. The prerequisite row's step is `Preq` (also in "Steps at a glance").
- "Resource usage" (right after it) has the same rows without the container: Step, Service, CPU, RAM, Disk.
  - One total row last: **Total without models** (RAM and disk summed min to max; one LLM runtime counted for RAM, both runtime images for disk).
  - Model weights are never in the service rows; they live in the **Models** subsection: columns Model (name only) | Runtime (`O` Ollama, `v` vLLM, `O/v` both) | Next-Lower OpenAI | Disk | VRAM Used | Context (est.) | Note (short; starts with the Ollama tag and/or vLLM model ID).
  - Rows are models that run on the guide's 16 GB GPU and have a score on the Artificial Analysis Intelligence Index, best first. Models without a score are left out (pick the largest ranked model that fits instead). "Next-Lower OpenAI" is the closest OpenAI model (reasoning and non-reasoning variants alike) with a lower score on that same index, compared across every reasoning setting of every OpenAI model (newest families included).
  - Read each score from the model or variant page itself (`artificialanalysis.ai/models/<model>-<setting>`), not from a leaderboard summary. Take every score from that one index, never mix sources or index versions, and give the date.
- In "Service status check", "Resource usage", and "Access map", a row whose step number equals the row above leaves the Step cell blank. No note explains it; it reads clearly as is.

## Service step layout

Each service step follows one layout, so every service can be removed, installed, and tested on its own (every service step, from Caddy on, follows it; a new service step does too):
1. `## Step N: <Service>`, a short intro (what it is, anything risky), and the `**Check:**` line (containers to look for).
2. `### Clean reinstall`: removes the service as if never installed. Containers (`docker compose down`, plus any containers the service starts itself), named volumes, the stack folder, its Caddy file, optional images; each destructive line `confirm`-gated and named in its prompt. Then what to undo outside the server (LiteLLM key, Infisical folder, Dex client), and commands that print nothing when it is all gone.
3. `### Install`: numbered steps (prerequisites such as keys, folder and files, start, **check the result**, first setup in the app), then the **Verify:** line. "Check the result" is a block of `docker inspect` / `curl` lines plus a table of the expected output, covering: container name, state, restart policy, image; networks; mounts (named volumes only, no hash-named ones); published ports and extra hosts; each named volume; environment values that matter (secrets as a length only); name resolution from inside the container for the services it calls; access from the server and by the address users open; and, for apps behind Caddy, the certificate (`curl -sv https://<SERVER_HOST>:<port> -o /dev/null 2>&1 | grep -E "subject:|issuer:"`, issuer `Caddy Local Authority`).
4. The other H3s, as now: `### Authentication` (below), `### Usage` or a topic H3, `### Options`.
5. `### Test` last: short functional checks, each one layer further (connection, a simple use, a real task). A long error table or troubleshooting goes to an option page (`options/<service>-test.md`), linked from the Test part. A test that works from the server also goes into `scripts/server-test.sh` (and its row in the guide's server test table); the Test part keeps what only a browser or GitHub can show.

## Authentication subsections

- No checklists (`- [ ]`) anywhere: a check the reader would tick is a script check (`server-test.sh`, `server-status.sh`) or a numbered Test item. Ticks in Outline would also be saved into the shared guide.
- Every step with a service people or tools sign in to has `### Authentication` right after the install is verified (the `**Verify:**` that the service loads), and before how to use it. How-to-use content (first setup inside the app, data sources, indexing, tracing notes) goes under `### Usage` after it, or under its own H3 (e.g. `### Connecting tools (MCP)`); then `### Options`, and `### Test` last (see Service step layout). Step text before it only says what the deployment needs (e.g. "pick a method before starting it").
- It opens with the service's own login (the default), then one paragraph per method in this order: **Dex**, **Google Account**, **Azure**. Infisical lists only **Google Account**. Extra methods (email magic link, Auth0) come after.
- Each method says free or paid; mark paid ones with 💲 (e.g. "💲 paid (Business Edition)"). For apps behind Dex, Google and Azure come through Dex's connectors; mention the app's own direct login only as an alternative.
- In the files themselves, sign-in blocks follow the same order after the defaults: Dex, then email, then Google, then Azure (Dex connectors: Google, Microsoft, entra-guests, then others).

## Team guide (`ai-setup-for-software-development.md`)

- For the software team using the server (product, developers, QA, release), not for setting it up: it links to the guide's steps and option pages for setup instead of repeating them. The guide's rules apply (generic, no `Step N` in code blocks, no apostrophes in code blocks). Its Optional tools tables mark each tool on server, cloud, free, or free plan, with approximate limits.
- Its "Your team's stack" table names the team's tools (languages, test tools, hosting, monitoring); the rest of the page refers to it, so another team reuses the page by changing that table. Product names are fine there; server names and IPs are not.
- Its numbered workflow and `diagrams/development-workflow.svg` change together (see [diagrams.md](diagrams.md)).
- The "Third-party AI" table is a starting point for company policy, not a rule of this repo; keep it marked as such.

## Options (`options/*.md`)

- A step keeps its main path. Anything the reader chooses between — an alternative path (clean reinstall, no sign-in gate), an extra (outside sign-in providers, Key Vault sync, hosted models), or an upgrade for older installs — lives in its own file in `options/`, linked from the step with a short line (`**Option:** [Title](options/<file>.md) — what it does`).
- Each option file starts with `# Option: <Title>` (the H1 is also its Outline document name), then a line linking back to its step (`[Step N: Name](../ai-server-setup-guide.md#<anchor>)`). Headings inside follow the guide's rules (H2 ≤ 32 characters, and so on).
- The guide's rules apply to option files too: no `Step N` or apostrophes inside code blocks, `confirm` on destructive commands, generic placeholders. `Step N` in their prose must be updated when steps are renumbered (`grep -rn "Step [0-9]" options/`).
- Each option file ends with `---` and a **Related:** list linking back to every guide section that links to it (with the subsection, e.g. `[Step 5: Infisical (secrets)](../ai-server-setup-guide.md#step-5-infisical-secrets) → Authentication`) and to other option pages that link to it. Never edit it by hand: after changing option links, run `python tools/update-option-related.py`, then rebuild the export.
- A file the guide writes once still holds an option's lines commented out (e.g. Dex connectors); the option file explains how to turn them on.
- New or renamed option files need nothing in the export script: it exports every `options/*.md` and rewrites links to them.

## Write each file once

- No step edits a file created by an earlier step. Write each file once, complete, at its step.
- Decide optional features when the file is written (e.g. "leave this block out if Langfuse isn't deployed"), not in a later "now go back and add…".
- If a later service must feed an earlier one, reorder the steps instead (that is why Langfuse comes before LiteLLM).
- Two deliberate exceptions, because they hold data rather than setup: the Outline "Services" page (content inside an app), and in `/opt/stacks/dex/config.yaml` the `staticPasswords` user list plus the commented `connectors:` entries (turned on when a provider becomes available).

## Commands

- A command that acts on a list from another command uses `… | xargs -r <command>`, not `<command> $(…)`: an empty list then does nothing instead of failing (`docker rm` with no names is an error).
- Shell commands use `${SERVER_HOST}` / `${SERVER_IP}`, not `<SERVER_HOST>`, so they copy and run once the variables are loaded ("Before you start" shows how). Keep `<SERVER_HOST>` in prose addresses to open, in files that cannot read variables (`prometheus.yml`, JSON, TOML), and in text inside single quotes, where the shell does not expand it.

- Gate every destructive command with the `confirm` helper defined in "Before you start": `confirm "<what it does>" && <command>`.
- Destructive means stop/rm a container, delete a volume or image, prune, purge a package, or `down`. Installs, `up -d`, `docker volume create`, and read-only checks aren't gated.

## Content

- Free versions only. Mark Enterprise/paid features as such and don't depend on them (e.g. LiteLLM SSO, LiteLLM Prometheus metrics).
- Verify third-party config against upstream. When a compose file follows a vendor's official compose (e.g. Langfuse), keep its required env vars. Check upstream before changing image major versions.
- Keep diagram notes out of the guide. Don't mention fonts, colors, layout, styling, or any external theme or design-system name. Image alt text describes content only. This is about how the diagrams are drawn; styling that is part of the setup itself (e.g. the Dex login page theme and its font) belongs in the guide like any other option.
- No apostrophes inside code blocks (placeholders, comments, `.env` values): some viewers treat a lone `'` as the start of a shell string and mis-highlight everything after it. Write `<server-hostname>`, not `<server's-hostname>`; "is not", not "isn't"; "the LiteLLM callback", not "LiteLLM's callback". Paired quotes that are real shell syntax (`<<'EOF'`, `awk '…'`) are fine.
- Headings use a colon, not a dash, after the prefix: `## Step N: Name`, `## Prerequisite: …`, `### Optional: …`.
- Heading length limit: H2 ≤ 32 characters (text after `## `, including `Step N: `), and 2 fewer per level down (H3 ≤ 30, H4 ≤ 28, …). Detail that doesn't fit goes in the first line under the heading, not in the heading.

## Outline export

`outline-export/ai-server-setup-guide.md` is the copy of the guide for importing into Outline, and `outline-export/options/*.md` are the option files, each imported as its own document. Never edit it by hand. After every change to the guide or to any `*.sh`, regenerate it with `python tools/build-outline-export.py`. The export differs from the guide in these ways:

- The H1 title becomes a note (Outline takes the title from the document name).
- SVG images become "drag `<name>.png` here" placeholders.
- "Copy … from this repo" sentences point to the appendix instead.
- Links to `options/*.md` (and, in option files, back to the guide) become the target document's name, since repo links don't resolve in Outline.
- An **Appendix: Scripts** section is added with each script as a paste-ready `cat > <path> <<'SCRIPT_EOF'` block.

The script fails if the guide's wording no longer matches. When you reword a "from this repo" sentence, add a new script, or add a new diagram, update `REPLACEMENTS`, `SCRIPTS`, or `DIAGRAMS` (guide) / `DEV_DIAGRAMS` (team guide) in the script.

With `SERVER_HOST` and `SERVER_IP` set in the environment, the export fills in the real values: `<SERVER_HOST>` / `<SERVER_IP>` everywhere, `${SERVER_HOST}` / `${SERVER_IP}` in prose and shell commands, but not in compose, `.env`, or config files, heredoc bodies, or the script appendix, where `${...}` is a variable the file reads. That export is for one server: the user builds it for their Outline; agents and `tools/check.py` always build without the variables, so the export in the repo stays generic.

The PNGs in `outline-export/` are renders of the SVGs. Re-render them whenever a diagram changes.

