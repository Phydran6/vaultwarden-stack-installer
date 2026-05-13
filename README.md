# Vaultwarden Stack Installer

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/Phydran6/vaultwarden-stack-installer?style=flat)](https://github.com/Phydran6/vaultwarden-stack-installer/stargazers)
[![GitHub issues](https://img.shields.io/github/issues/Phydran6/vaultwarden-stack-installer)](https://github.com/Phydran6/vaultwarden-stack-installer/issues)

**[GitHub Repository](https://github.com/Phydran6/vaultwarden-stack-installer)** · [Setup Guide](docs/setup.md) · [Reverse Proxy](docs/reverse-proxy.md) · [Wildcard Cert](docs/wildcard-cert.md) · [Changelog](CHANGELOG.md) · [License](LICENSE)

---

> One-shot installer script for a self-hosted Vaultwarden password manager and an optional supporting Docker stack on Debian 13.

This script automates a clean Vaultwarden deployment on a fresh Debian 13 VM, with optional add-ons for SSL/reverse proxy, container management, and automated updates. All interactive prompts have sensible defaults with timeouts so the script can run hands-off if desired.

## Features

- Vaultwarden via Docker Compose (Bitwarden-compatible server)
- Optional Nginx Proxy Manager (NPM) for SSL termination and reverse proxy
- Optional Portainer CE for container management UI
- Optional [Tugtainer](https://github.com/Quenary/tugtainer) for automated container updates
- Optional certbot for wildcard certificate workflow
- Auto-detects need for external reverse proxy and configures `DOMAIN` accordingly
- Random Admin Token generated per install
- All stacks placed under `/opt/stacks/<service>/` with their own `docker-compose.yml`
- Shared external Docker network for clean inter-stack routing

## Requirements

- Debian 13 (Trixie) — fresh VM recommended
- A non-root user with `sudo` privileges
- Internet access for package downloads
- For wildcard SSL: a registered domain and DNS provider with API access

## Quick Start

```bash
# From your sudo-capable user account on the target VM
wget https://raw.githubusercontent.com/<your-username>/vaultwarden-stack-installer/main/vaultwarden-stack-setup.sh
sudo bash vaultwarden-stack-setup.sh
```

The script will:

1. Run sanity checks (root, OS, sudo user)
2. Show an interactive menu (5-second timeouts):
   - Install NPM? (default: yes)
   - Install Portainer? (default: yes)
   - Install Tugtainer? (default: no)
3. If NPM selected: ask for SSL strategy (subdomain or wildcard)
4. If wildcard: 10-second pre-flight checks for DNS provider + credentials, then domain registration check
5. Ask for Vaultwarden public FQDN (or detect that a reverse proxy lives on another machine)
6. Install Docker (official repo), all selected services, and certbot if needed
7. Print a summary with all URLs, ports, and admin credentials

## What Gets Installed

| Service     | Default | Port(s)         | Purpose                          |
|-------------|---------|-----------------|----------------------------------|
| Vaultwarden | yes     | 8080            | Password manager (Bitwarden API) |
| NPM         | yes     | 80, 81, 443     | SSL + reverse proxy              |
| Portainer   | yes     | 9000, 9443      | Container management UI          |
| Tugtainer   | no      | 9412            | Automated container updates      |
| certbot     | on-demand | -             | Wildcard SSL certificates        |

## Project Structure

```
vaultwarden-stack-installer/
├── README.md                    # this file
├── CHANGELOG.md                 # version history
├── LICENSE                      # MIT
├── vaultwarden-stack-setup.sh   # the installer
└── docs/
    ├── setup.md                 # detailed walkthrough
    ├── reverse-proxy.md         # NPM / external proxy configuration
    └── wildcard-cert.md         # certbot wildcard certificate workflow
```

## Post-Install

- Vaultwarden Admin Panel: `<DOMAIN>/admin` — login with the generated Admin Token (also stored in `/opt/stacks/vaultwarden/docker-compose.yml`)
- NPM default credentials: `admin@example.com` / `changeme` — **change immediately on first login**
- Portainer: create the admin account within 5 minutes of container start (Portainer locks down otherwise)
- Tugtainer: see [project docs](https://github.com/Quenary/tugtainer) for first-login behavior

For reverse-proxy configuration of Vaultwarden see [docs/reverse-proxy.md](docs/reverse-proxy.md).

## Security Notes

- The Admin Token is generated as a plain random string. Vaultwarden also supports Argon2-hashed tokens; consider upgrading post-install for production use (`docker exec -it vaultwarden /vaultwarden hash`).
- Signups are enabled by default (`SIGNUPS_ALLOWED=true`). Disable in `docker-compose.yml` after creating your account if you don't want others to register.
- The user running the script is added to the `docker` group. Re-login is required for the change to take effect.

## Contributing

Issues and PRs welcome. Please keep documentation free of personal hostnames, IPs, and identifiers — use placeholders consistently.

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

Developed with assistance from Claude (Anthropic).
