#!/bin/bash
# ============================================================
#  Vaultwarden Stack Installer
#  Target: Debian 13 (Trixie)
#  Usage:  sudo bash vaultwarden-stack-setup.sh
#
#  Stacks (Default: VW + NPM + Portainer):
#    - Vaultwarden                   (always)
#    - Nginx Proxy Manager (NPM)     (Default: ja, 5s Timeout)
#    - Portainer CE                  (Default: ja, 5s Timeout)
#    - Tugtainer                     (Default: nein, 5s Timeout)
#
#  Bei NPM: Auswahl zwischen Subdomain- oder Wildcard-Zertifikat.
#  Bei Wildcard: certbot + interaktive Vorab-Pruefung.
# ============================================================

set -euo pipefail

# ----- Sanity ------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: muss als root laufen -> sudo bash $0"
  exit 1
fi

if [ -z "${SUDO_USER:-}" ] || [ "$SUDO_USER" = "root" ]; then
  echo "ERROR: Bitte aus einem normalen User-Account via 'sudo bash $0' starten."
  echo "       (SUDO_USER wird fuer die Docker-Gruppe gebraucht.)"
  exit 1
fi

if ! grep -q '^ID=debian' /etc/os-release 2>/dev/null; then
  echo "WARN: Skript ist fuer Debian 13 gebaut. Andere Distros koennten brechen."
  read -r -p "Trotzdem weiter? [j/N] " yn
  [[ "${yn,,}" == "j" || "${yn,,}" == "ja" || "${yn,,}" == "y" ]] || exit 1
fi

ORIG_USER="$SUDO_USER"
STACK_BASE="/opt/stacks"
NET_NAME="proxy-net"
SERVER_IP="$(hostname -I | awk '{print $1}')"

# ----- Helpers -----------------------------------------------

C_RED=$'\033[0;31m'; C_GRN=$'\033[0;32m'; C_YEL=$'\033[1;33m'
C_BLU=$'\033[0;34m'; C_RST=$'\033[0m'

log()  { printf "%s[*]%s %s\n" "$C_BLU" "$C_RST" "$*"; }
ok()   { printf "%s[OK]%s %s\n" "$C_GRN" "$C_RST" "$*"; }
warn() { printf "%s[!]%s %s\n" "$C_YEL" "$C_RST" "$*"; }
err()  { printf "%s[X]%s %s\n" "$C_RED" "$C_RST" "$*" >&2; }

ask_timed() {
  # $1=prompt $2=timeout $3=default(yes|no)
  local prompt="$1" timeout="$2" default="$3" answer label
  if [ "$default" = "yes" ]; then label="[J/n]"; else label="[j/N]"; fi
  printf "\n%s %s  (%ds Timeout, Default: %s): " "$prompt" "$label" "$timeout" "$default" >&2
  if read -r -t "$timeout" answer; then
    case "${answer,,}" in
      j|y|ja|yes)  echo "yes" ;;
      n|nein|no)   echo "no"  ;;
      "")          echo "$default" ;;
      *)           echo "$default" ;;
    esac
  else
    printf "\n%s[Timeout -> Default: %s]%s\n" "$C_YEL" "$default" "$C_RST" >&2
    echo "$default"
  fi
}

gen_token() { openssl rand -base64 48 | tr -d '\n=+/' | cut -c1-48; }

# ----- Banner + Menue ---------------------------------------

clear || true
cat <<'BANNER'
============================================================
  Vaultwarden Stack Installer  (Debian 13 + Docker)
============================================================
  Pflicht : Vaultwarden
  Optional: NPM (SSL/Reverse Proxy), Portainer, Tugtainer
============================================================
BANNER

INSTALL_NPM=$(ask_timed       "NPM (Nginx Proxy Manager) installieren?"  5 "yes")
INSTALL_PORTAINER=$(ask_timed "Portainer installieren?"                   5 "yes")
INSTALL_TUGTAINER=$(ask_timed "Tugtainer (Auto-Updater) installieren?"    5 "no")

CERT_TYPE="none"
WILDCARD_DOMAIN=""
VW_FQDN=""
VW_DOMAIN_VALUE=""
EXT_PROXY="no"

validate_fqdn() {
  local d="$1"
  [[ "$d" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]
}

ask_fqdn() {
  # $1 = prompt, $2 = optional default
  local prompt="$1" default="${2:-}" input
  while true; do
    if [ -n "$default" ]; then
      read -r -p "${prompt} [${default}]: " input
      input="${input:-$default}"
    else
      read -r -p "${prompt}: " input
    fi
    input="${input,,}"
    input="${input#https://}"
    input="${input#http://}"
    input="${input%%/*}"
    if validate_fqdn "$input"; then
      echo "$input"
      return 0
    else
      warn "Ungueltiger FQDN. Beispiel: vault.example.com"
    fi
  done
}

if [ "$INSTALL_NPM" = "yes" ]; then
  echo
  echo "SSL-Zertifikat Strategie:"
  echo "  1) Subdomain-Zertifikate pro Service  (Let's Encrypt HTTP-01 via NPM UI, kein extra Setup)"
  echo "  2) Wildcard-Zertifikat fuer Domain    (certbot + DNS-01, vorab-Check)"
  while true; do
    read -r -p "Auswahl [1/2]: " choice
    case "$choice" in
      1) CERT_TYPE="subdomain"; break ;;
      2) CERT_TYPE="wildcard";  break ;;
      *) echo "Bitte 1 oder 2." ;;
    esac
  done
fi

# ----- Wildcard Vorab-Check (10s prompts) -------------------

if [ "$CERT_TYPE" = "wildcard" ]; then
  echo
  echo "--- Wildcard-Zertifikat Vorbereitung ---"
  echo "Jede Antwort hat 10s Timeout, Default jeweils 'nein' -> Abbruch."

  prov=$(ask_timed "Hast du einen Public-DNS-Provider mit API (Cloudflare, Route53, Hetzner, ...)?" 10 "no")
  if [ "$prov" != "yes" ]; then
    err "Wildcard-Zertifikat braucht einen DNS-Provider mit API-Zugang."
    err "Ohne den geht's nicht -> Abbruch."
    exit 1
  fi

  creds=$(ask_timed "Hast du die API-Credentials (Token/Key) griffbereit?" 10 "no")
  if [ "$creds" != "yes" ]; then
    err "Credentials fehlen -> Abbruch."
    err "Hol dir das API-Token vom Provider und starte das Skript erneut."
    exit 1
  fi

  # dnsutils kommt gleich, hier reicht apt-get on-the-fly
  apt-get install -y -qq dnsutils >/dev/null 2>&1 || true

  while true; do
    read -r -p "Wie heisst deine Domain (FQDN, z.B. example.com): " WILDCARD_DOMAIN
    WILDCARD_DOMAIN="${WILDCARD_DOMAIN,,}"
    WILDCARD_DOMAIN="${WILDCARD_DOMAIN#https://}"
    WILDCARD_DOMAIN="${WILDCARD_DOMAIN#http://}"
    WILDCARD_DOMAIN="${WILDCARD_DOMAIN%%/*}"

    if [[ ! "$WILDCARD_DOMAIN" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
      warn "Ungueltiger Domain-Name. FQDN ohne Schema/Pfad eingeben."
      continue
    fi

    log "Pruefe ob ${WILDCARD_DOMAIN} registriert ist (NS-Records via 8.8.8.8)..."
    if dig +short NS "$WILDCARD_DOMAIN" @8.8.8.8 2>/dev/null | grep -q '.'; then
      ok "Domain ${WILDCARD_DOMAIN} ist registriert -> weiter."
      break
    else
      err "Domain ${WILDCARD_DOMAIN} scheint nicht registriert (keine NS-Records gefunden)."
      err "Du brauchst eine registrierte Domain in deinem Besitz."
      read -r -p "Andere Domain probieren? [J/n]: " retry
      [[ "${retry,,}" == "n" || "${retry,,}" == "nein" ]] && { err "Abbruch."; exit 1; }
    fi
  done
fi

# ----- FQDN fuer Vaultwarden bestimmen ----------------------
# Vaultwarden braucht DOMAIN passend zur oeffentlichen URL,
# sonst gibts CSRF/Origin-Probleme und Websocket-Issues.

echo
echo "--- Public URL fuer Vaultwarden ---"

if [ "$INSTALL_NPM" = "yes" ]; then
  # lokales NPM -> FQDN ist Pflicht
  if [ "$CERT_TYPE" = "wildcard" ] && [ -n "$WILDCARD_DOMAIN" ]; then
    VW_FQDN="$(ask_fqdn "Vaultwarden FQDN" "vault.${WILDCARD_DOMAIN}")"
  else
    VW_FQDN="$(ask_fqdn "Vaultwarden FQDN (z.B. vault.example.com)")"
  fi
  VW_DOMAIN_VALUE="https://${VW_FQDN}"
else
  # kein lokales NPM -> evtl. externer Proxy auf anderer Maschine
  read -r -p "Steht ein Reverse Proxy (NPM/Traefik/Caddy) auf einer anderen Maschine bereit? [j/N]: " ext_input
  case "${ext_input,,}" in
    j|y|ja|yes) EXT_PROXY="yes" ;;
    *)          EXT_PROXY="no"  ;;
  esac
  if [ "$EXT_PROXY" = "yes" ]; then
    VW_FQDN="$(ask_fqdn "Vaultwarden FQDN wie er extern erreichbar ist (z.B. vault.example.com)")"
    VW_DOMAIN_VALUE="https://${VW_FQDN}"
  else
    VW_DOMAIN_VALUE="http://${SERVER_IP}:8080"
  fi
fi
ok "DOMAIN wird gesetzt auf: ${VW_DOMAIN_VALUE}"

# ----- Voraussetzungen --------------------------------------

log "Apt-Update + Basispakete"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  ca-certificates curl gnupg lsb-release \
  openssl whois dnsutils

# ----- Docker installieren ----------------------------------

if ! command -v docker >/dev/null 2>&1; then
  log "Docker (offizielles Repo) installieren"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  ok "Docker installiert: $(docker --version)"
else
  ok "Docker bereits da: $(docker --version)"
fi

systemctl enable --now docker

if ! id -nG "$ORIG_USER" | grep -qw docker; then
  log "User '${ORIG_USER}' der Gruppe 'docker' hinzufuegen"
  usermod -aG docker "$ORIG_USER"
  warn "Wirksam erst nach Logout/Login von '${ORIG_USER}'."
fi

# ----- Shared Docker-Netz -----------------------------------

if ! docker network ls --format '{{.Name}}' | grep -qw "$NET_NAME"; then
  log "Docker-Netz '${NET_NAME}' anlegen"
  docker network create "$NET_NAME" >/dev/null
fi

mkdir -p "$STACK_BASE"

# ============================================================
#  Vaultwarden
# ============================================================

VW_DIR="$STACK_BASE/vaultwarden"
VW_TOKEN="$(gen_token)"

mkdir -p "$VW_DIR/data"

cat > "$VW_DIR/docker-compose.yml" <<EOF
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    environment:
      DOMAIN: "${VW_DOMAIN_VALUE}"
      SIGNUPS_ALLOWED: "true"
      ADMIN_TOKEN: "${VW_TOKEN}"
      WEBSOCKET_ENABLED: "true"
      LOG_LEVEL: "info"
      ROCKET_PORT: "80"
    volumes:
      - ./data:/data
    ports:
      - "8080:80"
    networks:
      - ${NET_NAME}

networks:
  ${NET_NAME}:
    external: true
EOF

chown -R "$ORIG_USER":"$ORIG_USER" "$VW_DIR"

log "Vaultwarden Container starten"
docker compose -f "$VW_DIR/docker-compose.yml" up -d
ok "Vaultwarden laeuft"

# ============================================================
#  Nginx Proxy Manager
# ============================================================

NPM_DIR="$STACK_BASE/npm"
if [ "$INSTALL_NPM" = "yes" ]; then
  mkdir -p "$NPM_DIR"/{data,letsencrypt}

  cat > "$NPM_DIR/docker-compose.yml" <<EOF
services:
  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: npm
    restart: unless-stopped
    ports:
      - "80:80"
      - "81:81"
      - "443:443"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    networks:
      - ${NET_NAME}

networks:
  ${NET_NAME}:
    external: true
EOF
  chown -R "$ORIG_USER":"$ORIG_USER" "$NPM_DIR"
  log "NPM Container starten"
  docker compose -f "$NPM_DIR/docker-compose.yml" up -d
  ok "NPM laeuft"
fi

# ============================================================
#  Portainer
# ============================================================

PT_DIR="$STACK_BASE/portainer"
if [ "$INSTALL_PORTAINER" = "yes" ]; then
  mkdir -p "$PT_DIR/data"

  cat > "$PT_DIR/docker-compose.yml" <<EOF
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    ports:
      - "9000:9000"
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/data
    networks:
      - ${NET_NAME}

networks:
  ${NET_NAME}:
    external: true
EOF
  chown -R "$ORIG_USER":"$ORIG_USER" "$PT_DIR"
  log "Portainer Container starten"
  docker compose -f "$PT_DIR/docker-compose.yml" up -d
  ok "Portainer laeuft"
fi

# ============================================================
#  Tugtainer
# ============================================================

TT_DIR="$STACK_BASE/tugtainer"
if [ "$INSTALL_TUGTAINER" = "yes" ]; then
  mkdir -p "$TT_DIR/data"

  cat > "$TT_DIR/docker-compose.yml" <<EOF
services:
  tugtainer:
    image: ghcr.io/quenary/tugtainer:1
    container_name: tugtainer
    restart: unless-stopped
    ports:
      - "9412:80"
    volumes:
      - ./data:/tugtainer
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - ${NET_NAME}

networks:
  ${NET_NAME}:
    external: true
EOF
  chown -R "$ORIG_USER":"$ORIG_USER" "$TT_DIR"
  log "Tugtainer Container starten"
  docker compose -f "$TT_DIR/docker-compose.yml" up -d
  ok "Tugtainer laeuft"
fi

# ============================================================
#  certbot fuer Wildcard
# ============================================================

if [ "$CERT_TYPE" = "wildcard" ]; then
  log "certbot installieren"
  apt-get install -y -qq certbot
  ok "certbot: $(certbot --version 2>&1 | head -1)"
fi

# ============================================================
#  Summary
# ============================================================

cat <<EOF

============================================================
${C_GRN} INSTALLATION FERTIG${C_RST}
============================================================

Server-IP: ${SERVER_IP}

VAULTWARDEN
  Direkt URL:   http://${SERVER_IP}:8080
  Public URL:   ${VW_DOMAIN_VALUE}
  Admin Panel:  ${VW_DOMAIN_VALUE}/admin
  Admin Token:  ${VW_TOKEN}
  Compose-Dir:  ${VW_DIR}
  Login:        Account selbst registrieren (Signups aktiv)
                Token NICHT verlieren -> steht auch in docker-compose.yml
EOF

if [ -n "$VW_FQDN" ]; then
cat <<EOF

  Reverse-Proxy Konfig fuer ${VW_FQDN}:
    - Scheme:           http
    - Forward Host/IP:  ${SERVER_IP}
    - Forward Port:     8080
    - Websockets:       AN  (Pflicht fuer Live-Sync und Admin-Panel!)
    - Block Exploits:   AN
    - SSL + Force SSL + HTTP/2:  AN
EOF
fi

if [ "$INSTALL_NPM" = "yes" ]; then
cat <<EOF

NGINX PROXY MANAGER
  Admin UI:     http://${SERVER_IP}:81
  Reverse:      Port 80 (HTTP) und 443 (HTTPS)
  Compose-Dir:  ${NPM_DIR}
  Default-Login: admin@example.com  /  changeme
                 -> BEIM ERSTEN LOGIN AENDERN
EOF
fi

if [ "$INSTALL_PORTAINER" = "yes" ]; then
cat <<EOF

PORTAINER
  URL (HTTPS):  https://${SERVER_IP}:9443
  URL (HTTP):   http://${SERVER_IP}:9000
  Compose-Dir:  ${PT_DIR}
  Login:        Admin-Account in den ersten 5 Min nach Start anlegen
EOF
fi

if [ "$INSTALL_TUGTAINER" = "yes" ]; then
cat <<EOF

TUGTAINER
  URL:          http://${SERVER_IP}:9412
  Compose-Dir:  ${TT_DIR}
  Login:        Beim ersten Login wird Passwort gesetzt
                Doku: https://github.com/Quenary/tugtainer
EOF
fi

if [ "$CERT_TYPE" = "subdomain" ]; then
cat <<EOF

SSL-STRATEGIE: Subdomain-Zertifikate
  -> In NPM unter "SSL Certificates -> Add Let's Encrypt"
     fuer jede Subdomain einzeln (vault.deine-domain.de etc.)
  -> Port 80 muss von aussen erreichbar sein (HTTP-01 Challenge)
EOF
elif [ "$CERT_TYPE" = "wildcard" ]; then
cat <<EOF

SSL-STRATEGIE: Wildcard fuer *.${WILDCARD_DOMAIN}
  certbot ist installiert. Naechste Schritte (manuell):

  1) DNS-Plugin fuer deinen Provider installieren, z.B. Cloudflare:
       apt install python3-certbot-dns-cloudflare

  2) API-Token sicher ablegen:
       mkdir -p /root/.secrets && chmod 700 /root/.secrets
       echo "dns_cloudflare_api_token = DEIN_TOKEN" > /root/.secrets/cf.ini
       chmod 600 /root/.secrets/cf.ini

  3) Zertifikat anfordern:
       certbot certonly \\
         --dns-cloudflare \\
         --dns-cloudflare-credentials /root/.secrets/cf.ini \\
         -d '*.${WILDCARD_DOMAIN}' -d '${WILDCARD_DOMAIN}'

  4) In NPM: SSL Certificates -> Add Custom Certificate
     Cert:  /etc/letsencrypt/live/${WILDCARD_DOMAIN}/fullchain.pem
     Key:   /etc/letsencrypt/live/${WILDCARD_DOMAIN}/privkey.pem

  5) Auto-Renewal pruefen: 'systemctl status certbot.timer'
EOF
fi

cat <<EOF

HINWEIS
  User '${ORIG_USER}' wurde der 'docker'-Gruppe hinzugefuegt.
  Damit Docker-CLI ohne sudo geht: einmal aus- und neu einloggen.

  Compose-Files liegen unter ${STACK_BASE}/<service>/docker-compose.yml
  Stack neu starten:  cd ${STACK_BASE}/<service> && docker compose up -d
  Stack stoppen:      cd ${STACK_BASE}/<service> && docker compose down

============================================================
EOF
