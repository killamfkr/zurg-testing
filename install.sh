#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/killamfkr/zurg-testing/main}"

if [[ -d /DATA ]]; then
  APP_DIR="${APP_DIR:-/DATA/AppData/torbox-media-center}"
  MOUNT_HOST_PATH="${MOUNT_HOST_PATH:-/DATA/Media/torbox}"
else
  APP_DIR="${APP_DIR:-/opt/torbox-media-center}"
  MOUNT_HOST_PATH="${MOUNT_HOST_PATH:-/mnt/torbox}"
fi

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  die "Run as root: curl -fsSL .../install.sh | sudo TORBOX_API_KEY=your_key bash"
fi

if [[ -z "${TORBOX_API_KEY:-}" ]]; then
  if [[ -t 0 ]]; then
    read -rp "TorBox API key (from https://torbox.app/settings): " TORBOX_API_KEY
  else
    read -rp "TorBox API key (from https://torbox.app/settings): " TORBOX_API_KEY < /dev/tty
  fi
fi
[[ -n "${TORBOX_API_KEY:-}" ]] || die "TORBOX_API_KEY is required"

log "Installing dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl ca-certificates fuse3 >/dev/null 2>&1 \
  || apt-get install -y -qq curl ca-certificates fuse >/dev/null

modprobe fuse 2>/dev/null || true

if ! command -v docker >/dev/null 2>&1; then
  log "Docker not found, installing"
  curl -fsSL https://get.docker.com | sh
fi

if ! command -v casaos >/dev/null 2>&1 && [[ "${INSTALL_CASAOS:-0}" == "1" ]]; then
  log "CasaOS not found, installing"
  curl -fsSL https://get.casaos.io | bash
fi

log "Creating directories at $APP_DIR"
mkdir -p "$APP_DIR" "$MOUNT_HOST_PATH"

log "Downloading docker-compose.yml"
curl -fsSL "$REPO_RAW/docker-compose.yml" -o "$APP_DIR/docker-compose.yml"

cat > "$APP_DIR/.env" <<EOF
TORBOX_API_KEY=${TORBOX_API_KEY}
MOUNT_METHOD=${MOUNT_METHOD:-fuse}
MOUNT_PATH=/torbox
ENABLE_METADATA=${ENABLE_METADATA:-false}
RAW_MODE=false
MOUNT_REFRESH_TIME=${MOUNT_REFRESH_TIME:-normal}
MOUNT_HOST_PATH=${MOUNT_HOST_PATH}
EOF

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  die "docker compose is not available"
fi

log "Starting TorBox Media Center"
cd "$APP_DIR"
"${COMPOSE[@]}" pull
"${COMPOSE[@]}" up -d

sleep 5
if ! docker ps --filter name=torbox-media-center --filter status=running -q | grep -q .; then
  die "Container failed to start. Run: docker logs torbox-media-center"
fi

log "Installation complete"
echo
echo "Media mount: $MOUNT_HOST_PATH"
echo "Plex movies:   $MOUNT_HOST_PATH/movies"
echo "Plex TV shows: $MOUNT_HOST_PATH/series  (only populated when ENABLE_METADATA=true)"
echo
echo "Note: folders stay empty until you have playable videos cached in TorBox."
echo "Force first sync:  cd $APP_DIR && ${COMPOSE[*]} restart"
echo "Run diagnostics:   curl -fsSL $REPO_RAW/scripts/diagnose.sh | sudo bash"
echo
echo "Recent logs:"
docker logs --tail 15 torbox-media-center 2>&1 | sed 's/^/  /'
