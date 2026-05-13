# Wildcard Certificate Workflow

The installer can pre-install `certbot` for a wildcard certificate workflow (covering `*.<your-domain.tld>` and `<your-domain.tld>`). The actual certificate request is left manual because the DNS plugin and credentials are provider-specific.

## Why Wildcard?

A wildcard cert covers an unlimited number of subdomains under one domain. Handy if you self-host many services (`vault.`, `dns.`, `rmm.`, `cloud.`, …) and don't want to manage a Let's Encrypt request per subdomain.

Wildcards require the DNS-01 challenge — Let's Encrypt validates ownership by asking you to place a TXT record at `_acme-challenge.<your-domain.tld>`. That's why an API-capable DNS provider is required.

## Supported Providers

Any provider with a certbot DNS plugin works. The most common:

| Provider     | apt package                              |
|--------------|------------------------------------------|
| Cloudflare   | `python3-certbot-dns-cloudflare`         |
| Route 53     | `python3-certbot-dns-route53`            |
| DigitalOcean | `python3-certbot-dns-digitalocean`       |
| Google Cloud | `python3-certbot-dns-google`             |
| RFC 2136     | `python3-certbot-dns-rfc2136`            |
| Linode       | `python3-certbot-dns-linode`             |
| Gandi        | community plugin (pip install certbot-plugin-gandi) |
| Hetzner      | community plugin (pip install certbot-dns-hetzner)  |

Substitute the plugin in all commands below.

## Step-by-Step (Cloudflare Example)

### 1. Install the DNS plugin

```bash
sudo apt install -y python3-certbot-dns-cloudflare
```

### 2. Create an API token

In the Cloudflare dashboard → My Profile → API Tokens → Create Token.

Use the **Edit zone DNS** template, scoped to the specific zone you want to certify. Copy the token (shown once).

### 3. Store the token securely

```bash
sudo mkdir -p /root/.secrets
sudo chmod 700 /root/.secrets
echo "dns_cloudflare_api_token = <your-api-token>" | sudo tee /root/.secrets/cf.ini
sudo chmod 600 /root/.secrets/cf.ini
```

### 4. Request the certificate

```bash
sudo certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /root/.secrets/cf.ini \
  -d "*.<your-domain.tld>" -d "<your-domain.tld>" \
  --email "your.email@example.com" \
  --agree-tos --no-eff-email
```

certbot will:
1. Request a challenge from Let's Encrypt
2. Use your API token to place the validation TXT record
3. Wait for DNS propagation (default 10s; add `--dns-cloudflare-propagation-seconds 60` for slower providers)
4. Confirm validation and download the cert

Cert files end up in `/etc/letsencrypt/live/<your-domain.tld>/`:
- `fullchain.pem` — certificate + intermediate chain
- `privkey.pem` — private key

### 5. Use in NPM

In NPM → SSL Certificates → Add SSL Certificate → **Custom**:

| Field                  | Value                                                  |
|------------------------|--------------------------------------------------------|
| Name                   | `wildcard-<your-domain.tld>`                           |
| Certificate Key        | upload `/etc/letsencrypt/live/<your-domain.tld>/privkey.pem` |
| Certificate            | upload `/etc/letsencrypt/live/<your-domain.tld>/fullchain.pem` |
| Intermediate Cert      | (leave blank — bundled in fullchain)                   |

Then assign this cert to each Proxy Host on its SSL tab.

NPM does not auto-renew custom certs. See renewal section below.

### 6. Auto-Renewal

certbot installs a systemd timer:

```bash
sudo systemctl status certbot.timer
sudo systemctl list-timers | grep certbot
```

Renewal happens automatically when certs are within 30 days of expiry. To test a renewal dry-run:

```bash
sudo certbot renew --dry-run
```

If NPM is consuming the cert files, you need to nudge NPM to re-read them after renewal. Add a renewal hook:

```bash
sudo mkdir -p /etc/letsencrypt/renewal-hooks/deploy
sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-npm.sh > /dev/null <<'EOF'
#!/bin/bash
docker restart npm
EOF
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-npm.sh
```

This restarts the NPM container after every successful renewal so it picks up the new cert.

## Troubleshooting

- **`unauthorized` from certbot** → API token lacks zone permissions
- **`challenge did not pass: DNS problem`** → DNS hasn't propagated yet; increase `--dns-*-propagation-seconds`
- **`Some challenges have failed`** with `NXDOMAIN` → the domain doesn't exist or DNS isn't authoritative for that zone yet
- **Cert valid but NPM still serves old one** → restart NPM container after renewal (see hook above)
