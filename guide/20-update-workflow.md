## Step 20: Update workflow

`update-stack.sh` and `restore-stack.sh` run from `~/ai-server` ([Helper scripts](options/helper-scripts.md)). Use `update-stack.sh` instead of a bare `docker compose pull && up -d`. It backs up the stack's Postgres databases and volumes to `/opt/backups/<stack>/<timestamp>/`, then pulls and recreates. In `llm-runtime` and `graphdb` it restarts only what was running.

```bash
~/ai-server/update-stack.sh outline
~/ai-server/update-stack.sh outline --skip-backup   # skip backup if no schema/data change expected
```
**A development server without volume backups:** always add `--skip-backup`; old backups from earlier updates can be deleted: `confirm "Delete all stack backups in /opt/backups?" && sudo rm -rf /opt/backups/*`. Instead, `backup-config.sh` keeps what it takes to install everything again: every file in `/opt/stacks` (compose files, `.env`, configs, Caddy files, the CA), the helper scripts, the Docker daemon and firewall settings, your crontab, and the Infisical and Outline databases (secrets, documents). No volumes. It keeps the newest 14 in `/opt/backups/config/`, readable by you only, since they hold every secret:
```bash
~/ai-server/backup-config.sh --dry-run
~/ai-server/backup-config.sh
```
Daily, in your crontab (`crontab -e`):
```
0 2 * * *   $HOME/ai-server/backup-config.sh >/dev/null 2>&1
```
Copy `/opt/backups/config` off the server now and then (a NAS, another PC); a backup on the same disk does not survive the disk. To reinstall from it: unpack `stacks.tar.gz` and `scripts.tar.gz`, create the volumes, start the stacks in step order, and replay a database into its fresh container, e.g. `gunzip -c outline.sql.gz | docker exec -i outline-postgres psql -U postgres`.

**Start a stack fresh** (all its data gone, its settings kept), e.g. Langfuse when its traces should go: `reset-stack.sh` empties every volume of the stack and starts it again; it asks you to type the stack name first.
```bash
~/ai-server/reset-stack.sh --dry-run langfuse
~/ai-server/reset-stack.sh langfuse
```
Langfuse then creates its admin user, project, and API keys again from its `.env`, so LiteLLM keeps sending traces with the same keys.
Stacks: `caddy`, `infisical`, `dex`, `outline`, `portainer`, `grafana`, `prometheus`, `node-exporter`, `dcgm-exporter`, `sourcebot`, `langfuse`, `litellm`, `llm-runtime`, `qdrant`, `graphdb`, `openhands`, `open-webui`, `github-runner`.

**Restore:** `~/ai-server/restore-stack.sh <stack-name> <timestamp>`. It asks first, stops the stack, restores the volumes, and restarts what was running. Add `--sql` to also replay the `.sql` dumps; only needed if a volume tarball is missing or damaged. List backups with `ls /opt/backups/<stack-name>/`.

