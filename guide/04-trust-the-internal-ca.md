## Step 4: Trust the internal CA

Do this once on each client machine.

```bash
cd /opt/stacks/caddy
docker compose exec caddy cat /data/caddy/pki/authorities/local/root.crt > caddy-root-ca.crt
```
Copy `caddy-root-ca.crt` to each client and import it:
- **Windows:** `certmgr.msc` → Trusted Root Certification Authorities → Import
- **macOS:** open the file → Keychain Access → set "Always Trust"
- **Linux:** `sudo cp caddy-root-ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates`
- **Firefox:** Settings → Privacy & Security → Certificates → View Certificates → Import

One import covers every service on this server, including ones not deployed yet.

