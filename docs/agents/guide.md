# Guide rules (`guide/*.md`)

How the guide, the option pages, and the team guide are written: wording, commands, links, options; read it for every edit. Adding, removing, or renumbering a step, its layout and tables, sign-in sections, and the Outline export are in [guide-structure.md](guide-structure.md).

## Where the guide lives

- Edit the guide in `guide/`: one file per step (`guide/12-litellm-gateway.md` is Step 12), plus `00-overview.md` (intro and the tables), `00-prerequisite.md`, and `99-design-decisions.md`. Open only the part you change.
- `ai-server-setup-guide.md` is the joined copy for people and the export; it is generated (`python tools/build-guide.py`, run by every tool) and never edited.
- Links inside a part are written as in the joined guide: repo-root paths (`options/<file>.md`, `diagrams/<name>.svg`) and its anchors (`#step-6-dex-sign-in`), also to other parts. `tools/check.py` checks them in the joined guide and reports each problem in its part.

## Generic and reusable

- No hostnames, IPs, usernames, or "current state" of any particular server. Use `<SERVER_HOST>` in prose, URLs, and ad-hoc commands, `${SERVER_HOST}` in compose files, and `{$SERVER_HOST}` in Caddy files. `SERVER_HOST` is the name (or the IP when there's no name). When an example needs a real domain (e.g. for Google sign-in), use `ai.domain.com` and `domain.com`. Write a folder in Infisical as `prod:/<name>` (environment, colon, path), never a bare `/<name>`, and a folder on the server always in full (`/opt/stacks/<stack>/`), so the two can't be confused; scripts print `$ENV_SLUG:/<name>`. `SERVER_IP` appears only where a raw IP is required: Caddy's `default_sni`, the second address in Caddy site blocks, the hosts-file line, and verify commands that test IP access.
- Every step starts by checking that service's current state (check-first). The reader then installs, migrates, or skips. Any subset of steps must work on its own.

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
- No checklists (`- [ ]`) anywhere: a check the reader would tick is a script check (`server-test.sh`, `server-status.sh`) or a numbered Test item. Ticks in Outline would also be saved into the shared guide.

## Write each file once

- No step edits a file created by an earlier step. Write each file once, complete, at its step.
- Decide optional features when the file is written (e.g. "leave this block out if Langfuse isn't deployed"), not in a later "now go back and add…".
- If a later service must feed an earlier one, reorder the steps instead (that is why Langfuse comes before LiteLLM).
- Two deliberate exceptions, because they hold data rather than setup: the Outline "Services" page (content inside an app), and in `/opt/stacks/dex/config.yaml` the `staticPasswords` user list plus the commented `connectors:` entries (turned on when a provider becomes available).

## Options (`options/*.md`)

- A step keeps its main path. Anything the reader chooses between — an alternative path (clean reinstall, no sign-in gate), an extra (outside sign-in providers, Key Vault sync, hosted models), or an upgrade for older installs — lives in its own file in `options/`, linked from the step with a short line (`**Option:** [Title](options/<file>.md) — what it does`).
- Each option file starts with `# Option: <Title>` (the H1 is also its Outline document name), then a line linking back to its step (`[Step N: Name](../ai-server-setup-guide.md#<anchor>)`). Headings inside follow the guide's rules (H2 ≤ 32 characters, and so on).
- The guide's rules apply to option files too: no `Step N` or apostrophes inside code blocks, `confirm` on destructive commands, generic placeholders. `Step N` in their prose must be updated when steps are renumbered (`grep -rn "Step [0-9]" options/`).
- Each option file ends with `---` and a **Related:** list linking back to every guide section that links to it (with the subsection, e.g. `[Step 5: Infisical (secrets)](../ai-server-setup-guide.md#step-5-infisical-secrets) → Authentication`) and to other option pages that link to it. Never edit it by hand: after changing option links, run `python tools/update-option-related.py`, then rebuild the export.
- A file the guide writes once still holds an option's lines commented out (e.g. Dex connectors); the option file explains how to turn them on.
- New or renamed option files need nothing in the export script: it exports every `options/*.md` and rewrites links to them.

## Team guide (`ai-setup-for-software-development.md`)

- For the software team using the server (product, developers, QA, release), not for setting it up: it links to the guide's steps and option pages for setup instead of repeating them. The guide's rules apply (generic, no `Step N` in code blocks, no apostrophes in code blocks). Its Optional tools tables mark each tool on server, cloud, free, or free plan, with approximate limits.
- Its "Your team's stack" table names the team's tools (languages, test tools, hosting, monitoring); the rest of the page refers to it, so another team reuses the page by changing that table. Product names are fine there; server names and IPs are not.
- Its numbered workflow and `diagrams/development-workflow.svg` change together (see [diagrams.md](diagrams.md)).
- The "Third-party AI" table is a starting point for company policy, not a rule of this repo; keep it marked as such.
