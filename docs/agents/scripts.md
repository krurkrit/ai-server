# Script rules (`scripts/*.sh`)

Where the helper scripts live, how they behave and report, their manual and `-h`, and bash hygiene.

## Placement and paths

- In the repo, every script lives in `scripts/`. On the server, all scripts live in `~/ai-server` (copied from the repo's `scripts/` folder, or pasted from the Outline export's appendix). Scripts needed inside a stack folder are linked there with `ln -sf`: `sync-shared-env.sh` → `/opt/stacks/shared/`, `pull-secrets.sh` → `/opt/stacks/infisical/`, `switch-llm.sh` → `/opt/stacks/llm-runtime/`, `graphdb.sh` → `/opt/stacks/graphdb/`; the others run from `~/ai-server` (`docker-veth-name.sh` with `sudo`; `docker-cleanup.sh` for housekeeping, which never removes named volumes or `edge`). The table of which script goes where lives only in [options/helper-scripts.md](../../options/helper-scripts.md) (the guide's "Before you start" has the copy steps and links to it); a new script gets a row there and an entry in the export's `SCRIPTS`.
- A script never relies on its own location: it may run from `~/ai-server`, through a link, or from `PATH`. Find stack folders through `STACKS_DIR` (default `/opt/stacks`), not `dirname "$0"`.
- Stacks are at `/opt/stacks/<stack>`. Backups go to `/opt/backups/<stack>/<YYYYmmdd-HHMMSS>/` (`<svc>.sql` from `pg_dumpall`, plus `<volume>.tar.gz`).

## Behavior

- Be profile-aware. `llm-runtime` (ollama/vllm) and `graphdb` (neo4j/memgraph) use Compose profiles. Use `docker compose --profile "*"` for `ps`, `config`, `pull`, and `down`. Restart only the services that were running before (`ps --services --status running`), so Ollama and vLLM never run together.
- Status output uses Ubuntu-style markers via the helpers in `server-status.sh`: `[  OK  ]` green, `[ WARN ]` yellow, `[FAILED]` red, `[  --  ]` plain (not installed). Color only when stdout is a terminal (`[[ -t 1 ]]`) and `NO_COLOR` is unset. Not-installed services are `--`, not `FAILED`, since the guide is also used on partial installs. The guide's pre-flight `chk` helper uses the same markers.
- `server-status.sh` prints `SCRIPT_VERSION` (a date) first, so an outdated copy on the server is easy to spot. Set it to the current date whenever the script changes.
- `server-status.sh` checks more than containers: when the guide adds a setting or file that can silently be wrong (Docker daemon settings, Infisical `pull.env` and sync, the Dex gate cookie length, the exported CA certificate), add a check for it.
- `pull-secrets.sh` and `sync-shared-env.sh` share one output style: a blank line, then `<stack>:` and indented `changed:` / `added:` / `REMOVED:` lines; then `To update: …`, `(--dry-run: nothing changed)`, the `[y/N]` prompt, `Recreating <stack>:`, and `Done. Old files are saved as .env.bak-<timestamp>; …`. Problems are `NOTICE:` lines. No `==` banners.
- Both take `--dry-run` and `--debug`. Debug lines go to stderr as `[debug] …` and never show a secret value (`SERVER_HOST` / `SERVER_IP` are not secret). `pull-secrets.sh` forwards both flags when it runs `sync-shared-env.sh`, along with `SHARED_ENV` and `SYNC_SKIP_STACKS`.
- Any script that overwrites data asks for confirmation first. `server-status.sh` and `server-test.sh` are read-only; `server-test.sh` may call a model and leave a Langfuse trace, nothing more.
- `server-status.sh` answers "does it run", `server-test.sh` answers "does it work" (the server-side part of each service Test). A new service gets a section in both, in step order. Secrets that `server-test.sh` needs are read from the container (`docker exec <c> printenv`) and passed on stdin or through the environment, never as command arguments.

## Manual and -h

- Every script starts with a man-page-style comment block right after the shebang: NAME, SYNOPSIS, DESCRIPTION, OPTIONS (always with `-h, --help`), then EXAMPLES, FILES, ENVIRONMENT, SEE ALSO as they apply. Each line starts with `# `; the block ends at the first empty line.
- Right after it, the same `-h` / `--help` snippet in every script prints that block (through `less -FRX` on a terminal). It runs before any argument check, so `-h` always works. Keep the manual in step with the options and behavior whenever a script changes.
- A wrong or missing argument prints one `Usage: … (manual: $0 -h)` line and exits 1.

## Content

- No `Step N` in comments or messages; name the service or stack instead (e.g. "LLM runtime not deployed yet").
- No apostrophes in comments or messages ("does not", "the guide deployment order"); a lone `'` mis-highlights the rest of the script in some viewers. See [guide.md](guide.md).
- Lists of services, stacks, or ports follow the guide's step order. Use indexed arrays, not associative arrays (`declare -A` iterates in hash order).

## Bash hygiene

- Use `set -euo pipefail` where practical.
- Don't let a trailing `[[ … ]] && …` be the last command (under `set -e` that makes the script's exit status fail).
- `docker ps … || fallback` never falls back, because `docker ps` succeeds with empty output. Capture the output and use `${VAR:-default}`.
- Check syntax with `bash -n scripts/*.sh` after editing.
- Scripts are embedded in the Outline export as heredocs. They must not contain a line that is exactly `SCRIPT_EOF`, or any ```` ``` ````. After editing, regenerate the export (see [guide.md](guide-structure.md#outline-export)).
