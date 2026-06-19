#!/usr/bin/env bash
# Fix decypharr unhealthy / failed to start on CasaOS.
set -euo pipefail

if [[ -d /DATA/AppData/torbox-media-server-src/torbox-media-server ]]; then
  INSTALL_DIR="/DATA/AppData/torbox-media-server-src/torbox-media-server"
else
  INSTALL_DIR="/opt/torbox-media-server-src/torbox-media-server"
fi

REAL_USER="${SUDO_USER:-ubuntu}"
[[ "$REAL_USER" == "root" ]] && REAL_USER=$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}')
REAL_USER="${REAL_USER:-ubuntu}"
PUID="$(id -u "$REAL_USER")"
PGID="$(id -g "$REAL_USER")"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Run with sudo"
  exit 1
fi

ENV_FILE="${INSTALL_DIR}/.env"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE"; exit 1; }
[[ -f "$COMPOSE_FILE" ]] || { echo "Missing $COMPOSE_FILE"; exit 1; }

get_env() {
  local key="$1" file="$2"
  grep -E "^${key}=" "$file" | head -1 | cut -d= -f2- | tr -d '"'
}

MOUNT_DIR="$(get_env MOUNT_DIR "$ENV_FILE")"
CONFIG_DIR="$(get_env CONFIG_DIR "$ENV_FILE")"
DATA_DIR="$(get_env DATA_DIR "$ENV_FILE")"
MOUNT_DIR="${MOUNT_DIR:-/DATA/Media/torbox-media}"
CONFIG_DIR="${CONFIG_DIR:-${INSTALL_DIR}/configs}"
DATA_DIR="${DATA_DIR:-${INSTALL_DIR}/data}"

echo "==> Cleaning .env"
TMP="${ENV_FILE}.sanitized"
sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$ENV_FILE" | grep -E '^(#|[A-Z_][A-Z0-9_]*=)' >"$TMP"
mv "$TMP" "$ENV_FILE"
chmod 600 "$ENV_FILE"
chown "${REAL_USER}:${REAL_USER}" "$ENV_FILE" 2>/dev/null || true

echo "==> Preparing mount path: $MOUNT_DIR"
mkdir -p "$MOUNT_DIR" "$DATA_DIR/media/movies" "$DATA_DIR/media/tv" "$DATA_DIR/downloads/radarr" "$DATA_DIR/downloads/sonarr"
mkdir -p "${CONFIG_DIR}/decypharr"
chown -R "${PUID}:${PGID}" "$MOUNT_DIR" "$DATA_DIR" "${CONFIG_DIR}/decypharr" 2>/dev/null || true
chmod -R u+rwX "${CONFIG_DIR}/decypharr" 2>/dev/null || true

echo "==> FUSE mount propagation"
fusermount -uz "$MOUNT_DIR" 2>/dev/null || true
findmnt -n "$MOUNT_DIR" >/dev/null 2>&1 || mount --bind "$MOUNT_DIR" "$MOUNT_DIR"
mount --make-shared "$MOUNT_DIR" 2>/dev/null || true
modprobe fuse 2>/dev/null || true

echo "==> Patching compose (images, healthchecks, decypharr volume)"
sed -i \
  -e 's|ghcr.io/thephaseless/byparr:v1\.0\.0|ghcr.io/thephaseless/byparr:2.1.0|g' \
  -e 's|ghcr.io/sirrobot01/decypharr:v2\.0|ghcr.io/sirrobot01/decypharr:v2.3|g' \
  -e 's|"127\.0\.0\.1:\([0-9]*\):\1"|"\1:\1"|g' \
  "$COMPOSE_FILE"

# Decypharr v2 needs the whole /app dir (for rclone.conf), not just config.json file mount.
sed -i 's|${CONFIG_DIR}/decypharr/config.json:/app/config.json|${CONFIG_DIR}/decypharr:/app|g' "$COMPOSE_FILE"

cat >"${INSTALL_DIR}/docker-compose.override.yml" <<'EOF'
services:
  decypharr:
    healthcheck:
      disable: true
  byparr:
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8191/health || wget -qO- http://localhost:8191/health || exit 1"]
      interval: 15s
      timeout: 15s
      retries: 10
      start_period: 120s
  radarr:
    depends_on:
      decypharr:
        condition: service_started
  sonarr:
    depends_on:
      decypharr:
        condition: service_started
  plex:
    depends_on:
      decypharr:
        condition: service_started
  jellyfin:
    depends_on:
      decypharr:
        condition: service_started
EOF

echo "==> Restarting stack (decypharr first)"
cd "$INSTALL_DIR"
docker compose --env-file .env down 2>/dev/null || true
docker rm -f decypharr byparr prowlarr radarr sonarr seerr plex jellyfin 2>/dev/null || true

sudo -u "$REAL_USER" docker compose --env-file .env pull decypharr byparr
sudo -u "$REAL_USER" docker compose --env-file .env up -d decypharr
echo "Waiting 60s for decypharr to mount TorBox..."
sleep 60

if ! docker ps --filter name=decypharr --filter status=running -q | grep -q .; then
  echo "ERROR: decypharr still not running. Last logs:"
  docker logs --tail 40 decypharr 2>&1 || true
  exit 1
fi

sudo -u "$REAL_USER" docker compose --env-file .env up -d

echo
echo "==> Container status"
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'decypharr|byparr|prowlarr|radarr|sonarr|seerr|plex' || true

echo
echo "==> Recent decypharr logs"
docker logs --tail 20 decypharr 2>&1 | sed 's/^/  /'

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo
echo "If decypharr is running, open:"
echo "  Decypharr: http://${IP:-localhost}:8282"
echo "  Seerr:     http://${IP:-localhost}:5055"
echo "  Plex:      http://${IP:-localhost}:32400/web"
