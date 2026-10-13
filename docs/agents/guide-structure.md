# Guide structure (`guide/*.md`)

How the guide is put together: step files and numbering, the overview tables, the service step layout, sign-in sections, and the Outline export. Read it when adding, removing, or renumbering a step, changing a step's sections or the tables, or editing the export; the wording rules are in [guide.md](guide.md).

## Step files

- A new step is a new `guide/NN-<name>.md`, starting with `## Step NN: <Name>`; `tools/check.py` fails when a file's number and its heading disagree. Renumbering a step renames its file (and every later one that shifts).

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

- Every step with a service people or tools sign in to has `### Authentication` right after the install is verified (the `**Verify:**` that the service loads), and before how to use it. How-to-use content (first setup inside the app, data sources, indexing, tracing notes) goes under `### Usage` after it, or under its own H3 (e.g. `### Connecting tools (MCP)`); then `### Options`, and `### Test` last (see Service step layout). Step text before it only says what the deployment needs (e.g. "pick a method before starting it").
- It opens with the service's own login (the default), then one paragraph per method in this order: **Dex**, **Google Account**, **Azure**. Infisical lists only **Google Account**. Extra methods (email magic link, Auth0) come after.
- Each method says free or paid; mark paid ones with 💲 (e.g. "💲 paid (Business Edition)"). For apps behind Dex, Google and Azure come through Dex's connectors; mention the app's own direct login only as an alternative.
- In the files themselves, sign-in blocks follow the same order after the defaults: Dex, then email, then Google, then Azure (Dex connectors: Google, Microsoft, entra-guests, then others).

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
