## Step 2: Shared network, settings

**Check:** `docker network ls --filter name=^edge$` — if `edge` is listed, skip the network. `ls /opt/stacks/shared/.env` — if it exists, skip the settings file.

**Shared network.** Create the `edge` network once; Caddy and every app join it to reach each other:
```bash
docker network create -o com.docker.network.bridge.name=br-edge edge
```
The option names the network's bridge `br-edge` on the server (as in `ip -br link`) instead of a random `br-<id>`.

**Recreating `edge` later** (to rename its bridge, or after it was removed): every container on it must then be recreated with `docker compose up -d --force-recreate`. A plain `up -d` or `start` reuses the old container, which still points at the removed network, and fails with "network … not found". See [Upgrading an older install](options/upgrade-older-install.md#edge-network).

**Readable cable names (optional).** Docker connects each container to a network with a cable named `veth<random>`, so `ip -br link` lists dozens of meaningless names. `docker-veth-name.sh` renames them after their container (`veth-ol` for Outline, `veth-ol-pg` for its database, `veth-sb2` for Sourcebot on its second network, and so on). Run it from `~/ai-server` ([Helper scripts](options/helper-scripts.md)):
```bash
sudo ~/ai-server/docker-veth-name.sh
ip -br link | grep veth-
```
The names do not last: Docker gives a container new cables each time it is created or restarted, so run the script again after an update, a restart, or a reboot. Renaming changes only the name, not how containers reach each other. `~/ai-server/docker-veth-name.sh -h` shows the short name rules.

**Shared settings.** `/opt/stacks/shared/.env` is the one place for values every stack uses (see "Before you start"):
```bash
mkdir -p /opt/stacks/shared
```

`/opt/stacks/shared/.env`:
```env
SERVER_HOST=<server-IP-or-DNS-name>   # the IP, unless the name has an internal DNS record
SERVER_IP=<server-IP>
```
Each later step copies these two lines into its own `.env` where it needs them. Nothing reads this file at runtime; the stacks stay self-contained.

Link `sync-shared-env.sh` from `~/ai-server` into the folder ([Helper scripts](options/helper-scripts.md)); `pull-secrets.sh` runs it from there:
```bash
ln -sf ~/ai-server/sync-shared-env.sh /opt/stacks/shared/sync-shared-env.sh
```

**Changing a value later:** edit `/opt/stacks/shared/.env`, preview, then apply:
```bash
/opt/stacks/shared/sync-shared-env.sh --dry-run
/opt/stacks/shared/sync-shared-env.sh
```
It updates `SERVER_HOST` / `SERVER_IP` in every `/opt/stacks/*/.env` that already has them (it never adds lines), saves each old file as `.env.bak-<timestamp>`, asks before changing anything, and recreates only the stacks that changed (a reload isn't enough: the values are fixed into each container when it's created). In `llm-runtime` and `graphdb` it recreates only what was running. After a change, users open the new address; the CA certificate stays the same. Add `--debug` to see every stack and key it checks, and why a stack is left alone. With Infisical (Step 5), `pull-secrets.sh` runs this script for you.

