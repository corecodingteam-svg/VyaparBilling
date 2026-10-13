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

# 3. Back up the billing database before anything changes. Migrations cannot be undone, so this dump is the way back
#    (restore: see "Rolling back" in the README). The ten most recent dumps are kept.
POSTGRES_USER=$(grep '^POSTGRES_USER=' .env | cut -d= -f2)
if docker compose -f docker-compose.yml --env-file .env exec -T postgres psql -U "$POSTGRES_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = 'billing'" 2>/dev/null | grep -q 1; then
  mkdir -p /var/backups/billing
  DUMP="/var/backups/billing/billing-$(date +%Y%m%d-%H%M%S).dump"
  docker compose -f docker-compose.yml --env-file .env exec -T postgres pg_dump -U "$POSTGRES_USER" -Fc billing > "$DUMP"
  [ -s "$DUMP" ] || { red "The database backup is empty; stopping before any change."; rm -f "$DUMP"; exit 1; }
  ls -1t /var/backups/billing/billing-*.dump 2>/dev/null | tail -n +11 | xargs -r rm -f
  grn "Database backed up: $DUMP ($(du -h "$DUMP" | cut -f1))"
else
  echo "No billing database yet (first deploy): nothing to back up."
fi

# 4. Build and start.
COMPOSE=(docker compose -f docker-compose.yml -f "$HERE/docker-compose.billing.yml" --env-file .env)
"${COMPOSE[@]}" up -d --build billing-db-init billing-migrate billing-backend billing-web
"${COMPOSE[@]}" up -d caddy   # recreated to load the billing site

# 5. Wait for HTTPS on the billing hostname.
echo "Waiting for the SSL certificate (can take up to ~2 minutes)..."
for _ in $(seq 1 40); do
  if curl -fsSIo /dev/null --max-time 5 "https://$DOMAIN" 2>/dev/null; then
    grn "Billing is live: https://$DOMAIN  (create your account from the Sign up page)"
    # The API answers and the shop route reaches the backend (404 = reached, shop not open).
    curl -fsS --max-time 5 "https://$DOMAIN/health" >/dev/null && grn "API health: ok" || red "API health check failed: ${COMPOSE[*]} logs billing-backend"
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "https://$DOMAIN/store/none"); echo "Shop route: HTTP $code (404 expected until a shop is opened)"
    exit 0
  fi
  sleep 5
done
red "Not ready yet: $DOMAIN - check: ${COMPOSE[*]} logs caddy billing-backend"
exit 1
