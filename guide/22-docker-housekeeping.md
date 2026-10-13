## Step 22: Docker housekeeping

`docker-cleanup.sh` (in `~/ai-server`, [Helper scripts](options/helper-scripts.md)) lists what Docker keeps that nothing uses and asks per kind before removing it: stopped OpenHands sandboxes, stopped containers outside any stack, networks no container uses, anonymous (hash-named) volumes no container uses, dangling images, and the build cache; with `--images` also images no container uses. It never touches running containers, named volumes, or `edge`, so the data of every stack stays, also of stacks that are stopped. Preview first:
```bash
~/ai-server/docker-cleanup.sh --dry-run
~/ai-server/docker-cleanup.sh
```
It shows `docker system df` before and after. Named volumes no container uses are only listed: a volume counts as unused whenever its container is stopped, so check each one first. Never remove `portainer_data` or the data volume of a stack you still use.

**Automatic, by email.** A weekly report of what could be removed, and a monthly clean-up (stopped sandboxes, stray containers, unused networks and anonymous volumes, old and unused images, build cache; never named volumes or `edge`). It mails through the `SMTP_*` settings already in `/opt/stacks/shared/.env` (from `prod:/shared`) or `/opt/stacks/grafana/.env` ([Email (SMTP) for all services](options/smtp-email.md)); `CLEANUP_EMAIL_TO` sends it elsewhere. Add to your crontab (`crontab -e`):
```
# Docker clean-up: report every Monday 08:00, remove on the 1st of each month 08:30
0 8 * * 1   $HOME/ai-server/docker-cleanup.sh --dry-run --images --email >/dev/null 2>&1
30 8 1 * *  $HOME/ai-server/docker-cleanup.sh --yes --images --email >/dev/null 2>&1
```
Test the mail once by hand: `~/ai-server/docker-cleanup.sh --dry-run --email`. Removed images download again when a stack needs them (`update-stack.sh`, `switch-llm.sh vllm`), which can take a while for vLLM.

Remove a confirmed leftover by name:
```bash
confirm "Delete volume <name>? This is permanent." && docker volume rm <name>
confirm "Delete image <name>?" && docker image rm <name>
```
**Don't run `docker system prune -a --volumes` or `docker volume prune`.** Pruning ignores `external: true` and deletes any volume whose container happens to be stopped.

