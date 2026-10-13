*Copied from `options/helper-scripts.md` in the ai-server repo; import it as a document named "Option: Helper scripts".*

Part of Before you start (document "Self-Hosted AI Server Setup Guide"). All helper scripts live in one folder in your home directory on the server, `~/ai-server`. The few that must sit in a stack folder are linked there, so there is one copy of each script, and updating means replacing the files in `~/ai-server`.

## Where each script goes

| Script | Linked into | Why there | Set up in |
|---|---|---|---|
| `server-status.sh` | — | Run from `~/ai-server` | Any time |
| `server-test.sh` | — | Run from `~/ai-server` | Step 21, any time |
| `sync-shared-env.sh` | `/opt/stacks/shared/` | `pull-secrets.sh` runs it from there | Step 2 |
| `docker-veth-name.sh` | — | Run from `~/ai-server` with `sudo` | Step 2 (optional) |
| `pull-secrets.sh` | `/opt/stacks/infisical/` | The guide runs it as `/opt/stacks/infisical/pull-secrets.sh` | Step 5 |
| `switch-llm.sh` | `/opt/stacks/llm-runtime/` | Next to the runtime it switches | Step 13 |
| `graphdb.sh` | `/opt/stacks/graphdb/` | Next to the databases it starts | Step 15 |
| `update-stack.sh`, `restore-stack.sh` | — | Run from `~/ai-server` | Step 20 |
| `backup-config.sh`, `reset-stack.sh` | — | Run from `~/ai-server` | Step 20 |
| `docker-cleanup.sh` | — | Run from `~/ai-server` | Step 22 |

The scripts find the stack folders themselves (`/opt/stacks`, or `STACKS_DIR` if set), so each works from `~/ai-server`, through its link, or from any folder.

## First install

Copying the scripts to `~/ai-server` and making them executable is in the guide, under Helper scripts in Before you start (document "Self-Hosted AI Server Setup Guide"). Without the repo on your PC, paste each script's block from the appendix of the guide's Outline copy into a shell on the server instead; each writes its file into `~/ai-server`.

Each step links its script into the stack folder it creates (the table above). To link them all at once, when the folders already exist:
```bash
ln -sf ~/ai-server/sync-shared-env.sh /opt/stacks/shared/sync-shared-env.sh
ln -sf ~/ai-server/pull-secrets.sh    /opt/stacks/infisical/pull-secrets.sh
ln -sf ~/ai-server/switch-llm.sh      /opt/stacks/llm-runtime/switch-llm.sh
ln -sf ~/ai-server/graphdb.sh         /opt/stacks/graphdb/graphdb.sh
```
`ln -sf` replaces an old copy of the script at that place with the link.

## Run them without the path

Optional: add `~/ai-server` to your `PATH`, so `update-stack.sh outline` or `server-status.sh` works from any folder:
```bash
echo 'export PATH="$HOME/ai-server:$PATH"' >> ~/.bashrc
source ~/.bashrc
```
`sudo` does not use your `PATH`; keep the full path there (`sudo ~/ai-server/docker-veth-name.sh`).

## Update the scripts

Copy the new versions over the old ones; the links follow automatically, nothing to re-link:
```bash
scp scripts/*.sh <user>@${SERVER_HOST}:ai-server/
```
Then on the server, `chmod +x ~/ai-server/*.sh` (only needed for a new script) and `~/ai-server/server-status.sh`: its first line shows `SCRIPT_VERSION`, a date, to confirm the new copy is in use.

## Check the links

```bash
ls -l /opt/stacks/shared/sync-shared-env.sh /opt/stacks/infisical/pull-secrets.sh /opt/stacks/llm-runtime/switch-llm.sh /opt/stacks/graphdb/graphdb.sh
```
Each line should end in `-> /home/<user>/ai-server/<script>`. A line without `->` is an old copy, not a link; replace it with the `ln -sf` line above. `No such file or directory` means that stack is not deployed yet, or the link is missing.

A link points into your home directory, so another admin running the scripts needs read access to `~/ai-server` (or their own copy and links).

---

**Related:**
- Before you start (document "Self-Hosted AI Server Setup Guide")
- Step 2: Shared network, settings (document "Self-Hosted AI Server Setup Guide")
- Step 5: Infisical (secrets) (document "Self-Hosted AI Server Setup Guide") → Usage
- Step 13: Ollama / vLLM runtime (document "Self-Hosted AI Server Setup Guide") → Install
- Step 15: Neo4j + Memgraph (document "Self-Hosted AI Server Setup Guide") → Install
- Step 20: Update workflow (document "Self-Hosted AI Server Setup Guide")
- Step 22: Docker housekeeping (document "Self-Hosted AI Server Setup Guide")
