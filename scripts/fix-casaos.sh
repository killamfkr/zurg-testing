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

CASAOS_APP=""
for dir in /var/lib/casaos/apps/*/; do
  [[ -f "${dir}docker-compose.yml" ]] || continue
  if grep -qi 'torbox-media-center' "${dir}docker-compose.yml" 2>/dev/null; then
    CASAOS_APP="${dir%/}"
    break
  fi
done

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Run with sudo"
  exit 1
fi

echo "=== CasaOS TorBox fix ==="
echo

API_KEY="${TORBOX_API_KEY:-}"
if [[ -z "$API_KEY" && -f "$APP_DIR/.env" ]]; then
  API_KEY=$(grep '^TORBOX_API_KEY=' "$APP_DIR/.env" | cut -d= -f2-)
fi
if [[ -z "$API_KEY" && -n "$CASAOS_APP" && -f "$CASAOS_APP/docker-compose.yml" ]]; then
  API_KEY=$(grep -oP 'TORBOX_API_KEY[=:]\s*\K[^"'\''[:space:]]+' "$CASAOS_APP/docker-compose.yml" | head -1 || true)
fi
[[ -n "$API_KEY" ]] || { echo "ERROR: Could not find TorBox API key"; exit 1; }

mkdir -p "$APP_DIR" "$MOUNT_PATH"

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

if [[ -n "$CASAOS_APP" ]]; then
  echo "Found CasaOS app at: $CASAOS_APP"
  cp "$APP_DIR/docker-compose.yml" "$CASAOS_APP/docker-compose.yml"
  echo "Updated CasaOS compose file."
else
  echo "No CasaOS app folder found (will use $APP_DIR only)."
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
else
  COMPOSE=(docker-compose)
fi

docker rm -f torbox-media-center 2>/dev/null || true

if [[ -n "$CASAOS_APP" ]]; then
  cd "$CASAOS_APP"
else
  cd "$APP_DIR"
fi

"${COMPOSE[@]}" pull
"${COMPOSE[@]}" up -d --force-recreate

echo
echo "Waiting 45s for file processing..."
sleep 45

echo
echo "=== IMPORTANT: TorBox log bug ==="
echo "TorBox ALWAYS prints 'Metadata scanning is enabled' on startup."
echo "That message is WRONG when ENABLE_METADATA=false. Ignore it."
echo

echo "=== Inside container (FUSE mount) ==="
docker exec torbox-media-center ls -la /torbox/ 2>/dev/null | sed 's/^/  /' || echo "  (cannot list)"
docker exec torbox-media-center ls -la /torbox/movies/ 2>/dev/null | sed 's/^/  /' || echo "  (movies empty inside container)"
MOVIES_IN=$(docker exec torbox-media-center find /torbox/movies -type f 2>/dev/null | wc -l)
echo "  files in /torbox/movies: $MOVIES_IN"

echo
echo "=== On host ==="
ls -la "$MOUNT_PATH/" 2>/dev/null | sed 's/^/  /' || true
ls -la "$MOUNT_PATH/movies/" 2>/dev/null | sed 's/^/  /' || true
HOST_FILES=$(find "$MOUNT_PATH/movies" -type f 2>/dev/null | wc -l)
echo "  files on host: $HOST_FILES"

echo
echo "=== Recent logs ==="
docker logs --tail 25 torbox-media-center 2>&1 | sed 's/^/  /'

echo
if [[ "$MOVIES_IN" -gt 0 && "$HOST_FILES" -eq 0 ]]; then
  echo "DIAGNOSIS: Files exist inside container but NOT on host."
  echo "This is a FUSE mount propagation issue in CasaOS Docker."
  echo
  echo "Fix: In CasaOS, edit torbox-media-center compose volume to:"
  echo "  ${MOUNT_PATH}:/torbox:rshared"
  echo "And ensure these are set: SYS_ADMIN, /dev/fuse, apparmor:unconfined"
  echo
  echo "Or map Plex to the same container mount instead of the host path."
elif [[ "$MOVIES_IN" -eq 0 ]]; then
  echo "DIAGNOSIS: No files inside container yet."
  echo "Check: Are torrents CACHED (not just added) on torbox.app?"
  echo "Only .mp4 and .mkv files are supported."
else
  echo "SUCCESS: Files found. Point Plex at: ${MOUNT_PATH}/movies"
fi
