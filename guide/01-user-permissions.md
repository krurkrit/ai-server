## Step 1: User permissions

Run this guide as your normal user, not as root. Commands that need root already start with `sudo`; after this step, `docker` and everything under `/opt/stacks` and `/opt/backups` work without it.

**Check:** `docker ps` works without `sudo`, and `ls -ld /opt/stacks /opt/backups` shows your user as owner — if both, skip.

Let your user run `docker`:
```bash
sudo usermod -aG docker $USER
newgrp docker
docker ps   # works without sudo
```
Membership in the `docker` group is effectively root access on this server (a container can mount any host path); only add users you would give `sudo` to.

Create the stack and backup folders, owned by your user (`/opt` itself belongs to root, so a plain `mkdir` there fails):
```bash
sudo install -d -o "$USER" -g "$USER" /opt/stacks /opt/backups
```
If they already exist and belong to root (from an earlier install done with `sudo`), take them over instead:
```bash
confirm "Make $USER the owner of everything under /opt/stacks and /opt/backups?" && sudo chown -R "$USER":"$USER" /opt/stacks /opt/backups
```
This only changes the stack files (compose, `.env`, config) and backups. Service data lives in Docker volumes under `/var/lib/docker` and is not touched.

Backup files that `update-stack.sh` writes through a container end up owned by root; deleting old backups later needs `sudo rm`.

