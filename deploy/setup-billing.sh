#!/usr/bin/env bash
# Adds the billing app to an already running advaitamaa.com server, and redeploys it.
# Expects this repo cloned as <inventory checkout>/billing, so the stack lives in ../../deploy.
# Checks the subdomain's DNS, adds the billing settings to the stack's .env once, then builds
# and starts the billing services. The website and inventory services keep running.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
STACK="$(cd "$HERE/../../deploy" 2>/dev/null && pwd || true)"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
grn() { printf '\033[32m%s\033[0m\n' "$*"; }

[ "$(id -u)" = 0 ] || { red "Run as root: sudo ./setup-billing.sh"; exit 1; }
[ -n "$STACK" ] && [ -f "$STACK/docker-compose.yml" ] || { red "Clone this repo inside the inventory checkout, as ./billing (next to its deploy/ folder)."; exit 1; }
[ -f "$STACK/.env" ] || { red "$STACK/.env not found. Set up the main stack first (deploy/setup.sh)."; exit 1; }
cd "$STACK"

# 1. Billing settings in the stack's .env (added once; existing values are kept).
grep -q '^BILLING_DOMAIN=' .env || echo 'BILLING_DOMAIN=billing.advaitamaa.com' >> .env
grep -q '^BILLING_JWT_SECRET=' .env || echo "BILLING_JWT_SECRET=$(openssl rand -hex 32)" >> .env
DOMAIN=$(grep '^BILLING_DOMAIN=' .env | cut -d= -f2)

# 2. DNS must already point at this server, or the certificate cannot be issued.
SERVER_IP=$(curl -fsS https://api.ipify.org || true)
[ -n "$SERVER_IP" ] || { red "Could not detect this server's public IP."; exit 1; }
ip=$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1; exit}' || true)
if [ "$ip" != "$SERVER_IP" ]; then
  red "DNS: $DOMAIN -> ${ip:-no record} (expected $SERVER_IP)"
  red "Add an A record for it, wait for it to resolve, then re-run."
  exit 1
fi
grn "DNS OK: $DOMAIN -> $ip"

# 3. Build and start.
COMPOSE=(docker compose -f docker-compose.yml -f "$HERE/docker-compose.billing.yml" --env-file .env)
"${COMPOSE[@]}" up -d --build billing-db-init billing-migrate billing-backend billing-web
"${COMPOSE[@]}" up -d caddy   # recreated to load the billing site

# 4. Wait for HTTPS on the billing hostname.
echo "Waiting for the SSL certificate (can take up to ~2 minutes)..."
for _ in $(seq 1 40); do
  if curl -fsSIo /dev/null --max-time 5 "https://$DOMAIN" 2>/dev/null; then
    grn "Billing is live: https://$DOMAIN  (create your account from the Sign up page)"
    exit 0
  fi
  sleep 5
done
red "Not ready yet: $DOMAIN - check: ${COMPOSE[*]} logs caddy billing-backend"
exit 1
