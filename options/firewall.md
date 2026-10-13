# Option: Firewall

Part of [Before you start](../ai-server-setup-guide.md#before-you-start). Limits who can reach the server to your office network (and VPN). The guide keeps the server internal-only; this makes the server enforce it, instead of relying on the network around it.

## What is open

Everything Docker publishes listens on all of the server's addresses:

| Port | Service |
|---|---|
| 22 | SSH (not Docker) |
| 80, 443 | Caddy (Outline) |
| 4000, 5556, 6333, 7474, 8080, 9090, 9443, 9450–9499 | Caddy (LiteLLM, Dex, Qdrant, Neo4j Browser, Infisical, Prometheus, Portainer, the shared block) |
| 7687, 7688 | Neo4j and Memgraph bolt (direct) |
| 3000 | OpenHands (plain HTTP, direct) |
| random, while a task runs | OpenHands sandboxes |

List what really listens: `sudo ss -tlnp`.

**Docker bypasses `ufw`.** Ports that Docker publishes are opened in the kernel's firewall by Docker itself, ahead of `ufw`'s rules, so `ufw deny 3000` has no effect on them. Docker's own hook for this is the `DOCKER-USER` chain, which is checked before its rules; the steps below put the office-only rule there, through `ufw`'s own files so it survives reboots.

## Set it up

Work from a second SSH session left open, so a mistake does not lock you out. Fill in two values: your office (and VPN) network, e.g. `192.168.1.0/24`, and the server's network card, e.g. `eno1` (`ip -br link`).

1. **`ufw` for the host's own ports** (SSH):
   ```bash
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw allow from <OFFICE_SUBNET> to any port 22 proto tcp
   confirm "Turn on ufw now (SSH stays open for <OFFICE_SUBNET> only)?" && sudo ufw enable
   ```
2. **Docker's published ports:** add this block at the **end** of `/etc/ufw/after.rules` (after its last `COMMIT`):
   ```
   # Docker published ports: only the office network may reach them
   *filter
   :DOCKER-USER - [0:0]
   -A DOCKER-USER -i <EXT_IF> -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
   -A DOCKER-USER -i <EXT_IF> -s <OFFICE_SUBNET> -j RETURN
   -A DOCKER-USER -i <EXT_IF> -j DROP
   -A DOCKER-USER -j RETURN
   COMMIT
   ```
   It only filters traffic coming in on the network card (`-i <EXT_IF>`); traffic between containers is untouched. Add one more `-s … -j RETURN` line per extra network (e.g. the VPN range).
3. **Apply:**
   ```bash
   confirm "Reload ufw with the Docker rules?" && sudo ufw reload
   ```

## Check

From the server:
```bash
sudo ufw status verbose
sudo iptables -L DOCKER-USER -n -v
```
`ufw` shows `Status: active` with the SSH rule; `DOCKER-USER` lists the three rules for `<EXT_IF>`, and their counters grow as people use the services.

From a PC in the office: Outline, Grafana, and the other addresses still open. From outside the office network (another subnet, or a phone on mobile data with the VPN off): they time out. On Windows: `Test-NetConnection <SERVER_IP> -Port 4000`.

## Undo

```bash
confirm "Turn ufw off?" && sudo ufw disable
```
Then delete the `DOCKER-USER` block from `/etc/ufw/after.rules` and restart Docker (`sudo systemctl restart docker`) to drop the rules from the kernel.

---

**Related:**
- [Before you start](../ai-server-setup-guide.md#before-you-start)
