#!/usr/bin/env bash
set -euo pipefail

if [[ -d /DATA/AppData/torbox-media-center ]]; then
  APP_DIR="/DATA/AppData/torbox-media-center"
  MOUNT_PATH="/DATA/Media/torbox"
else
  APP_DIR="/opt/torbox-media-center"
  MOUNT_PATH="/mnt/torbox"
fi

echo "=== TorBox Media Center diagnostics ==="
echo

if ! docker ps -a --format '{{.Names}}' | grep -qx torbox-media-center; then
  echo "Container not found. Is it installed?"
  exit 1
fi

echo "Container status:"
docker ps -a --filter name=torbox-media-center --format '  {{.Status}}'
echo

if [[ -f "$APP_DIR/.env" ]]; then
  echo "Config ($APP_DIR/.env):"
  grep -E '^(MOUNT_METHOD|ENABLE_METADATA|MOUNT_REFRESH_TIME|MOUNT_HOST_PATH)=' "$APP_DIR/.env" | sed 's/^/  /'
  if grep -q 'your_api_key_here' "$APP_DIR/.env" 2>/dev/null; then
    echo "  WARNING: API key still looks like a placeholder"
  fi
else
  echo "WARNING: .env not found at $APP_DIR/.env"
fi
echo

echo "Mount directory ($MOUNT_PATH):"
if [[ -d "$MOUNT_PATH" ]]; then
  ls -la "$MOUNT_PATH" 2>/dev/null | sed 's/^/  /' || echo "  (cannot list — permission issue?)"
  for sub in movies series; do
    if [[ -d "$MOUNT_PATH/$sub" ]]; then
      count=$(find "$MOUNT_PATH/$sub" -type f 2>/dev/null | wc -l)
      echo "  $sub/: $count files"
    else
      echo "  $sub/: folder does not exist yet"
    fi
  done
else
  echo "  WARNING: mount path does not exist"
fi
echo

echo "Recent container logs:"
docker logs --tail 30 torbox-media-center 2>&1 | sed 's/^/  /'
echo

echo "=== What to check ==="
echo "1. Do you have finished/cached videos at https://torbox.app ?"
echo "2. With ENABLE_METADATA=false, all videos go in movies/ (series/ stays empty)."
echo "3. Force a sync: cd $APP_DIR && docker compose restart"
echo "4. Watch live logs: docker logs -f torbox-media-center"
