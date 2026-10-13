## Prerequisite: Docker and NVIDIA

The same commands install on a fresh box and upgrade an existing one.

### Pre-flight check

One line per item, marked green `[  OK  ]` or red `[FAILED]` like Ubuntu boot messages. `server-status.sh` runs the same checks.
```bash
chk() { local out; if out=$(eval "$2" 2>/dev/null) && [ -n "$out" ]; then printf '\e[32m[  OK  ]\e[0m %-15s %s\n' "$1" "$out"; else printf '\e[31m[FAILED]\e[0m %-15s %s\n' "$1" "${3:-not found}"; fi; }

chk "OS"            'lsb_release -ds'
chk "Docker"        'docker --version'
chk "Compose"       'docker compose version --short'
chk "Kernel module" 'grep -m1 NVRM /proc/driver/nvidia/version | grep -oE "(Open )?Kernel Module|[0-9]+\.[0-9]+\.[0-9]+" | paste -sd" "'
chk "Driver pkgs"   'dpkg -l | grep -E "^ii +(nvidia-(driver|headless|utils)|linux-modules-nvidia)-" | tr -s " " | cut -d" " -f2 | paste -sd" "'
chk "nvidia-smi"    'nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader'
chk "Toolkit"       'nvidia-ctk --version | head -1'
chk "CDI spec"      'date -r /etc/cdi/nvidia.yaml "+generated %F %R"'
chk "GPU in Docker" 'docker run --rm --device nvidia.com/gpu=all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi --query-gpu=name --format=csv,noheader' "container cannot see the GPU"
```

| Output shows | Do |
|---|---|
| Every line `[  OK  ]` | Skip to Step 1 |
| `Docker` or `Compose` not found | Docker section |
| `Kernel module` and `Driver pkgs` not found | Driver section → install |
| `Kernel module` shows a version, `nvidia-smi` not found | Driver section → "If `nvidia-smi` isn't found" |
| `nvidia-smi` version differs from `Kernel module` | Reboot (driver updated but old module still loaded); if it persists, [clean driver reinstall](options/preq-clean-reinstall.md#reinstall-the-nvidia-driver) |
| `Toolkit` or `CDI spec` not found, or CDI spec older than the last driver change | Toolkit section |
| Only `GPU in Docker` is `[FAILED]` | [Clean driver reinstall](options/preq-clean-reinstall.md#reinstall-the-nvidia-driver) |

**Starting completely fresh, or recovering a broken install?** See [Clean reinstall](options/preq-clean-reinstall.md): wipe all Docker data, remove Docker, the NVIDIA driver, or the Container Toolkit completely.

### Docker Engine + Compose plugin

**Check:** `docker --version && docker compose version`. Both print a version → already installed; the install command below also upgrades in place.

Add Docker's apt repository (safe to re-run):
```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
```

Install or upgrade:
```bash
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

**Verify:**
```bash
docker run hello-world
docker --version
docker compose version
```

To pin a specific version:
```bash
apt-cache madison docker-ce | awk '{ print $3 }'   # list available versions
sudo apt-get install -y docker-ce=<version-string> docker-ce-cli=<version-string> containerd.io docker-buildx-plugin docker-compose-plugin
```

### NVIDIA driver

**Check:**
```bash
nvidia-smi --query-gpu=driver_version --format=csv,noheader
dpkg -l | grep -E '^ii\s+(nvidia-driver-|nvidia-headless-|linux-modules-nvidia-|nvidia-utils-)'
```
The `dpkg` list is what's actually installed. A `--gpgpu` install shows `nvidia-headless-*` and no `nvidia-driver-*` line; that's expected. If `dpkg` shows nothing but `nvidia-smi` works, the driver came from NVIDIA's `.run` installer; do a [clean driver reinstall](options/preq-clean-reinstall.md#reinstall-the-nvidia-driver).

**Reading package names** (e.g. `nvidia-headless-no-dkms-595-server-open`):

| Part | Meaning |
|---|---|
| `595` | Driver branch |
| `-server` | Server branch, longer support — use this on a headless box |
| `-open` | Open kernel modules — use for Turing (RTX 20-series/T4) and newer; leave off for older GPUs |

Check your GPU and list the drivers available for it:
```bash
nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader
sudo ubuntu-drivers list --gpgpu
```

**Install** (headless compute driver; use the exact string from `list` above):
```bash
sudo ubuntu-drivers install --gpgpu nvidia:595-server-open
confirm "Reboot the server now?" && sudo reboot
```

**Verify:** both show the version you installed, with no errors.
```bash
nvidia-smi
cat /proc/driver/nvidia/version
```

**If `nvidia-smi` isn't found:** the `nvidia-utils-<version>-server` package is missing. Find the build that matches your driver version (from `/proc/driver/nvidia/version`) and install exactly that. Ignore the shell's "can be installed with…" hint; it's often stale.
```bash
sudo apt update
apt-cache madison nvidia-utils-<version>-server   # e.g. nvidia-utils-595-server
sudo apt install nvidia-utils-<version>-server=<exact-version-string-from-madison>
```
If no matching build exists, do a [clean driver reinstall](options/preq-clean-reinstall.md#reinstall-the-nvidia-driver).

### NVIDIA Container Toolkit

**Check:** `nvidia-ctk --version` prints a version → installed. The command below also upgrades in place. Purging `*nvidia*` for the driver removes the toolkit too, so reinstall it after a driver reinstall. To remove it completely, see [Clean reinstall](options/preq-clean-reinstall.md#remove-the-container-toolkit).

Add NVIDIA's apt repository (safe to re-run):
```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
```

Install, configure Docker, and generate the CDI spec:
```bash
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```
Re-run the `cdi generate` line whenever the driver or toolkit changes.

**Verify:**
```bash
docker run --rm --device nvidia.com/gpu=all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi
```
A GPU table means the whole chain works.

**Always use the CDI form** (`--device nvidia.com/gpu=all`, or `devices: [nvidia.com/gpu=all]` in compose). `--gpus all` and Compose's `deploy.resources.reservations.devices` can fail with `AMD CDI spec not found` on some Docker/toolkit versions.

### Docker daemon settings

Two settings in `/etc/docker/daemon.json` that this server needs:
- **`"userland-proxy": false`** — the kernel forwards published ports instead of one `docker-proxy` process per port. Caddy publishes 60+ ports (most of 9450–9499 are reserved for later services), which would otherwise mean 100+ processes and up to ~1 GB of RAM; with this setting the reserved ports cost nothing.
- **Log rotation** — Docker keeps container logs forever by default; this keeps at most 5 files of 10 MB per container, older ones compressed. For ~5 users, that holds about 1–3 weeks of logs for the busiest containers (LiteLLM, the LLM runtime, Langfuse) and months for the rest; worst case ~1.75 GB of disk for all containers together.

**Check:** `cat /etc/docker/daemon.json` — if it already has `"userland-proxy": false` and the `log-opts` below, skip.

The NVIDIA Container Toolkit (above) wrote its own entry into this file, so merge the settings in rather than overwriting it (a copy of the old file is kept as `daemon.json.bak`):
```bash
sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak 2>/dev/null
confirm "Merge these settings into /etc/docker/daemon.json?" && sudo python3 - <<'EOF'
import json, os
path = "/etc/docker/daemon.json"
cfg = json.load(open(path)) if os.path.exists(path) else {}
cfg["userland-proxy"] = False
cfg["log-driver"] = "json-file"
cfg["log-opts"] = {"max-size": "10m", "max-file": "3", "compress": "true"}
json.dump(cfg, open(path, "w"), indent=2)
print(json.dumps(cfg, indent=2))
EOF
confirm "Restart Docker now? Every running container stops briefly and starts again." && sudo systemctl restart docker
```
The printed file should still contain the `nvidia` runtime entry next to the new settings.

**Verify:**
```bash
pgrep -c docker-proxy                          # 0 (or no output) once containers are running
docker info --format '{{.LoggingDriver}}'      # json-file
```
The log limits apply to containers created from now on. Containers that already exist keep their old (unlimited) logs until they're recreated — at their next `update-stack.sh` or `docker compose up -d --force-recreate`.

**Reading logs:** use `docker logs`, which reads all of a container's files, compressed ones included — e.g. `docker logs --since 2h litellm`, or `docker logs --since 24h langfuse-web 2>&1 | grep -i error`. Portainer shows them too.

**Sizing the limit:** rotation is by size, not time, so a week of logs needs `max-size × max-file ≥ daily volume × 7`. After a day or two, list the largest logs and divide each by the days since that container started:
```bash
sudo sh -c 'for f in /var/lib/docker/containers/*/*-json.log; do printf "%8s  %s\n" "$(du -h "$f" | cut -f1)" "$(docker inspect --format "{{.Name}}" "$(basename "$(dirname "$f")")")"; done | sort -h | tail -8'
```
The guide keeps at most 3 files of 10 MB per container (about 30 MB each, roughly 1 GB for all of them), enough for a development server; for a week of a busy container, raise `max-file` (to 5–10) in `/etc/docker/daemon.json` and restart Docker. For a strict time limit (e.g. audits), use the `journald` log driver with a 7-day retention instead.

