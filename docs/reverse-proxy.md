# Reverse Proxy Configuration

Vaultwarden needs its `DOMAIN` environment variable to exactly match the public URL through which clients connect. Mismatch causes CSRF errors at login and broken websocket connections (no live sync, broken admin panel).

The installer asks for this URL during setup. This document explains what to set in the proxy itself.

## Scenario A — Local NPM (installed by this script)

In NPM (`http://<server-ip>:81`), create a Proxy Host:

| Field              | Value                                  |
|--------------------|----------------------------------------|
| Domain Names       | `vault.<your-domain.tld>`              |
| Scheme             | `http`                                 |
| Forward Hostname   | `vaultwarden` (Docker DNS via shared network) or `<server-ip>` |
| Forward Port       | `80` (if using container DNS) or `8080` (via host IP) |
| Cache Assets       | off                                    |
| Block Common Exploits | **on**                              |
| Websockets Support | **on (required)**                      |
| Access List        | Publicly Accessible (or as desired)    |

On the **SSL** tab:

| Field                       | Value |
|-----------------------------|-------|
| SSL Certificate             | Request a new SSL Certificate (Let's Encrypt) |
| Force SSL                   | on    |
| HTTP/2 Support              | on    |
| HSTS Enabled                | on (only after confirming everything works) |
| Email for Let's Encrypt     | `your.email@example.com` |

Save. NPM will request the certificate via HTTP-01 challenge (port 80 must be reachable from the public internet).

## Scenario B — External Reverse Proxy on Another Machine

Vaultwarden is exposed on `<server-ip>:8080` on the Vaultwarden VM. On your other-VM reverse proxy (NPM, Traefik, Caddy, nginx, etc.), forward requests to that endpoint.

**NPM (external):**

| Field              | Value                                  |
|--------------------|----------------------------------------|
| Domain Names       | `vault.<your-domain.tld>`              |
| Scheme             | `http`                                 |
| Forward Hostname   | `<vaultwarden-vm-ip>`                  |
| Forward Port       | `8080`                                 |
| Websockets Support | **on (required)**                      |
| Block Common Exploits | on                                  |

Plus SSL tab as in Scenario A.

**Traefik (labels on Vaultwarden container — needs editing the script's compose file):**

```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.vaultwarden.rule=Host(`vault.<your-domain.tld>`)
  - traefik.http.routers.vaultwarden.entrypoints=websecure
  - traefik.http.routers.vaultwarden.tls.certresolver=letsencrypt
  - traefik.http.services.vaultwarden.loadbalancer.server.port=80
```

**Caddy (Caddyfile):**

```caddy
vault.<your-domain.tld> {
    reverse_proxy <vaultwarden-vm-ip>:8080
}
```

Caddy handles SSL automatically.

**Plain nginx (snippet):**

```nginx
server {
    listen 443 ssl http2;
    server_name vault.<your-domain.tld>;

    ssl_certificate     /etc/letsencrypt/live/<your-domain.tld>/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/<your-domain.tld>/privkey.pem;

    location / {
        proxy_pass http://<vaultwarden-vm-ip>:8080;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Websocket upgrade — required for live sync
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $http_upgrade;
    }
}
```

## Scenario C — No Reverse Proxy

Direct access via `http://<server-ip>:8080`. The installer sets `DOMAIN` accordingly.

> Caveat: Vaultwarden requires HTTPS for the official Bitwarden mobile and browser clients to function properly. WebCrypto (used for client-side encryption) is only available in secure contexts. HTTP access works for the admin panel and basic browser login, but mobile apps will refuse to connect. For any non-throwaway deployment, use a reverse proxy with HTTPS.

## Changing the DOMAIN Later

If you change your mind about the FQDN, edit the compose file and restart:

```bash
cd /opt/stacks/vaultwarden
sudo nano docker-compose.yml      # change the DOMAIN: line
sudo docker compose up -d
```

## Common Pitfalls

- **Websocket toggle off** → live sync stops working between clients, admin panel partially broken
- **DOMAIN with trailing slash** → CSRF errors; leave it as `https://vault.example.com` with no `/`
- **HTTP DOMAIN with HTTPS access** → broken redirects, set DOMAIN to whatever clients actually use
- **Mixed access patterns** (some clients use IP, some FQDN) → DOMAIN can only be one value; pick the public one and route all access through it
