*Copied from `options/preq-clean-reinstall.md` in the ai-server repo; import it as a document named "Option: Clean reinstall".*

Part of the Prerequisite (document "Self-Hosted AI Server Setup Guide") of the setup guide. Normal installs and upgrades don't need any of this; use it to start completely fresh or to recover a broken install. Every destructive line asks first (`confirm`, defined in the guide's "Before you start").

## Wipe Docker clean

**Destructive.** Only for starting completely fresh or recovering a broken state. For routine cleanup use Step 22.

`external: true` doesn't protect volumes here: once their containers are gone, removing all volumes deletes them. Check what you'd lose first, and back up anything worth keeping (e.g. `update-stack.sh portainer`):
```bash
~/ai-server/server-status.sh
docker volume ls
```
```bash
confirm "Stop and remove ALL containers on this host?" && docker ps -aq | xargs -r docker stop
confirm "Actually remove them now?" && docker ps -aq | xargs -r docker rm
confirm "Remove ALL Docker images on this host?" && docker images -aq | xargs -r docker rmi -f
confirm "Remove ALL Docker volumes on this host — THIS DELETES DATA, including external:true volumes?" && docker volume ls -q | xargs -r docker volume rm
confirm "Remove all custom Docker networks (e.g. edge)?" && docker network prune -f

docker ps -a; docker images -a; docker volume ls; docker network ls   # all should be empty
```
Then continue from Step 1 as a fresh install.

## Remove Docker completely

Only for a broken install; normal upgrades don't need it. Afterwards, install Docker again as in the Prerequisite.

```bash
sudo systemctl stop docker
confirm "Purge Docker packages (docker-ce, containerd, buildx, compose plugin)?" && sudo apt --purge remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
sudo apt autoremove -y
confirm "DESTROY all containers, images, volumes, and networks by deleting /var/lib/docker and /var/lib/containerd?" && sudo rm -rf /var/lib/docker /var/lib/containerd
```

## Reinstall the NVIDIA driver

Do this when switching branch (open ↔ closed, desktop ↔ server), when the driver came from NVIDIA's `.run` installer, or when no `nvidia-utils` build matches the loaded driver. Mixed installs cause a missing `nvidia-smi` and toolkit problems.

Remove the current driver:

```bash
confirm "Stop ollama/vllm/dcgm-exporter containers to free the GPU?" && docker ps --filter "name=ollama" --filter "name=vllm" --filter "name=dcgm-exporter" -q | xargs -r docker stop

confirm "Purge ALL nvidia-* packages?" && sudo apt --purge remove '*nvidia*' -y
sudo apt autoremove -y
confirm "Delete the stale CDI spec (/etc/cdi/nvidia.yaml)?" && sudo rm -f /etc/cdi/nvidia.yaml
confirm "Reboot the server now?" && sudo reboot
```
After the reboot, both of these should print nothing:
```bash
dpkg -l | grep -i nvidia
lsmod | grep nvidia
```

Then install it again with the **Install** block in the guide's NVIDIA driver section. In one go, when you already know the version:

```bash
confirm "Purge ALL nvidia-* packages for a full clean reinstall?" && sudo apt --purge remove '*nvidia*' -y
sudo apt autoremove -y
sudo ubuntu-drivers install --gpgpu nvidia:<version>-server-open
confirm "Reboot the server now?" && sudo reboot
```

Purging `*nvidia*` removes the Container Toolkit too; reinstall it afterwards as in the guide's NVIDIA Container Toolkit section.

## Remove the Container Toolkit

```bash
confirm "Purge the NVIDIA Container Toolkit packages?" && sudo apt --purge remove nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1 -y
sudo apt autoremove -y
confirm "Delete the CDI spec (/etc/cdi/nvidia.yaml)?" && sudo rm -f /etc/cdi/nvidia.yaml
```

Afterwards, install it again as in the guide's NVIDIA Container Toolkit section.

---

**Related:**
- Prerequisite: Docker and NVIDIA (document "Self-Hosted AI Server Setup Guide") → Pre-flight check, NVIDIA driver, NVIDIA Container Toolkit
