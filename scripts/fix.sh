#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/killamfkr/zurg-testing/main}"

if [[ -d /DATA/AppData/torbox-media-center ]]; then
  APP_DIR="/DATA/AppData/torbox-media-center"
  MOUNT_PATH="/DATA/Media/torbox"
else
  APP_DIR="/opt/torbox-media-center"
  MOUNT_PATH="/mnt/torbox"
fi

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Run with sudo"
  exit 1
fi

echo "==> Fixing TorBox Media Center (disabling broken metadata scanning)"

mkdir -p "$APP_DIR" "$MOUNT_PATH"

# Preserve API key from existing .env if present
API_KEY="${TORBOX_API_KEY:-}"
if [[ -z "$API_KEY" && -f "$APP_DIR/.env" ]]; then
  API_KEY=$(grep '^TORBOX_API_KEY=' "$APP_DIR/.env" | cut -d= -f2-)
fi
[[ -n "$API_KEY" ]] || { echo "ERROR: No API key found. Set TORBOX_API_KEY=your_key"; exit 1; }

curl -fsSL "$REPO_RAW/docker-compose.yml" -o "$APP_DIR/docker-compose.yml"

cat > "$APP_DIR/.env" <<EOF
TORBOX_API_KEY=${API_KEY}
MOUNT_METHOD=fuse
MOUNT_PATH=/torbox
ENABLE_METADATA=false
RAW_MODE=false
MOUNT_REFRESH_TIME=normal
MOUNT_HOST_PATH=${MOUNT_PATH}
EOF

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
else
  COMPOSE=(docker-compose)
fi

cd "$APP_DIR"
"${COMPOSE[@]}" down 2>/dev/null || true
docker rm -f torbox-media-center 2>/dev/null || true
"${COMPOSE[@]}" pull
"${COMPOSE[@]}" up -d --force-recreate

echo "==> Waiting for sync (30s)..."
sleep 30

echo "==> Container env:"
docker exec torbox-media-center printenv ENABLE_METADATA MOUNT_METHOD MOUNT_PATH 2>/dev/null | sed 's/^/  /'

echo "==> Recent logs:"
docker logs --tail 20 torbox-media-center 2>&1 | sed 's/^/  /'

echo "==> Mount contents:"
ls -la "$MOUNT_PATH" 2>/dev/null | sed 's/^/  /' || true
if [[ -d "$MOUNT_PATH/movies" ]]; then
  echo "  movies/: $(find "$MOUNT_PATH/movies" -type f 2>/dev/null | wc -l) files"
fi

if docker logs torbox-media-center 2>&1 | grep -q "Metadata scanning is enabled"; then
  echo
  echo "WARNING: Metadata still enabled. CasaOS may be overriding settings."
  echo "In CasaOS: open torbox-media-center > Settings > Environment"
  echo "Set ENABLE_METADATA=false, save, and restart the app."
else
  echo
  echo "Done. Point Plex at: $MOUNT_PATH/movies"
fi
