# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-05-13

### Added
- Interactive installer script for Vaultwarden on Debian 13
- Optional Nginx Proxy Manager (NPM) deployment
- Optional Portainer CE deployment
- Optional Tugtainer deployment for automated container updates
- Two SSL strategies when NPM is selected:
  - Subdomain certificates via Let's Encrypt HTTP-01 in NPM UI
  - Wildcard certificate via certbot + DNS-01 (manual provider setup)
- 10-second pre-flight check for wildcard workflow (DNS provider, credentials, domain registration)
- Automatic Vaultwarden `DOMAIN` env configuration based on deployment scenario:
  - Local NPM with FQDN prompt
  - External reverse proxy on another machine with FQDN prompt
  - No proxy at all → direct IP:port
- FQDN input validation and sanitization (strips schema and path)
- Shared external Docker network (`proxy-net`) for inter-stack routing
- Random Admin Token generation per install
- All compose files placed under `/opt/stacks/<service>/`
- Final summary with all service URLs, ports, login info, and proxy-host configuration hints
- Configuration tips for NPM Proxy Host (websockets, force SSL)

### Security
- Sudo user is added to the `docker` group (requires re-login)
- All service ownership chowned to the original sudo user
