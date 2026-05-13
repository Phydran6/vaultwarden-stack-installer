# Setup Walkthrough

Step-by-step guide for running the installer on a fresh Debian 13 VM.

## Prerequisites

- Debian 13 (Trixie) installed and reachable
- A regular user account (not root) with `sudo` privileges
- Outbound internet access on the VM

## Step 1 — Get the Script

```bash
# As your non-root user
wget https://raw.githubusercontent.com/<your-username>/vaultwarden-stack-installer/main/vaultwarden-stack-setup.sh
chmod +x vaultwarden-stack-setup.sh
```

Or clone the repo:

```bash
git clone https://github.com/<your-username>/vaultwarden-stack-installer.git
cd vaultwarden-stack-installer
```

## Step 2 — Run It

```bash
sudo bash vaultwarden-stack-setup.sh
```

You will see:

1. **Banner + stack overview**
2. **Three component questions (5-second timeouts each):**
   - `NPM (Nginx Proxy Manager) installieren? [J/n]` — Default: **yes**
   - `Portainer installieren? [J/n]` — Default: **yes**
   - `Tugtainer (Auto-Updater) installieren? [j/N]` — Default: **no**
3. **If NPM was selected — SSL strategy choice** (no timeout, requires explicit selection):
   - `1` → Subdomain certificates (Let's Encrypt HTTP-01 via NPM web UI)
   - `2` → Wildcard certificate (certbot + DNS-01 challenge)
4. **If Wildcard — pre-flight checks** (10-second timeouts):
   - DNS provider with API available? (default: no → abort)
   - API credentials ready? (default: no → abort)
   - Domain name input + NS-record check
5. **Public URL configuration** (no timeout):
   - If local NPM: prompts for Vaultwarden FQDN (with a sensible default if wildcard was chosen)
   - If no local NPM: asks whether a reverse proxy lives on another machine; if yes, prompts for FQDN; if no, falls back to `http://<server-ip>:8080`
6. **Installation phase**:
   - apt update + base packages
   - Docker CE from official repo
   - User added to `docker` group
   - Shared Docker network created
   - Compose files written and stacks started
7. **Final summary** with all URLs, ports, admin tokens, and proxy-host hints

## Step 3 — Verify

After the script finishes, verify each running stack:

```bash
docker ps
```

You should see one container per enabled service, all with `Up X seconds`.

Check Vaultwarden specifically:

```bash
docker logs vaultwarden 2>&1 | head -20
```

Look for `Rocket has launched` or similar startup confirmation.

## Step 4 — First Login

Open Vaultwarden in your browser at the URL shown in the summary. The first user to register becomes effectively the primary account. Once your account is created, consider disabling further signups:

```bash
cd /opt/stacks/vaultwarden
sudo nano docker-compose.yml      # set SIGNUPS_ALLOWED: "false"
sudo docker compose up -d
```

## Step 5 — Re-login for Docker Group

The user who ran `sudo bash` was added to the `docker` group, but the change is only picked up at next login. Either log out and back in, or `newgrp docker` in the current shell.

## Re-running the Script

Running the script a second time is safe-ish but not idempotent in every aspect. It will:

- Detect existing Docker and skip the install
- Detect the existing `proxy-net` network and skip creation
- Overwrite any existing `docker-compose.yml` files under `/opt/stacks/` with newly-generated ones (regenerating Admin Tokens)

If you need to preserve customizations, back up `/opt/stacks/` first.

## Uninstall / Cleanup

```bash
cd /opt/stacks/vaultwarden && sudo docker compose down -v
cd /opt/stacks/npm         && sudo docker compose down -v
cd /opt/stacks/portainer   && sudo docker compose down -v
cd /opt/stacks/tugtainer   && sudo docker compose down -v
sudo rm -rf /opt/stacks
sudo docker network rm proxy-net
```
