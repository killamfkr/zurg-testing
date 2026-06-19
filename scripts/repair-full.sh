#!/usr/bin/env bash
# Repair a partial install-full.sh run (fixes corrupted .env and restarts stack).
set -euo pipefail

if [[ -d /DATA/AppData/torbox-media-server-src/torbox-media-server ]]; then
  INSTALL_DIR="/DATA/AppData/torbox-media-server-src/torbox-media-server"
else
  INSTALL_DIR="/opt/torbox-media-server-src/torbox-media-server"
fi

REAL_USER="${SUDO_USER:-ubuntu}"
[[ "$REAL_USER" == "root" ]] && REAL_USER=$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}')
REAL_USER="${REAL_USER:-ubuntu}"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Run with sudo"
  exit 1
fi

ENV_FILE="${INSTALL_DIR}/.env"
[[ -f "$ENV_FILE" ]] || { echo "Not found: $ENV_FILE — run install-full.sh first"; exit 1; }

echo "==> Cleaning corrupted .env"
TMP="${ENV_FILE}.sanitized"
sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$ENV_FILE" | grep -E '^(#|[A-Z_][A-Z0-9_]*=)' >"$TMP"
mv "$TMP" "$ENV_FILE"
chmod 600 "$ENV_FILE"
chown "${REAL_USER}:${REAL_USER}" "$ENV_FILE" 2>/dev/null || true

echo "==> Opening ports on LAN"
sed -i -E 's/"127\.0\.0\.1:([0-9]+):\1"/"\1:\1"/g' "${INSTALL_DIR}/docker-compose.yml"

echo "==> Starting stack"
cd "$INSTALL_DIR"
if [[ -x ./manage.sh ]]; then
  sudo -u "$REAL_USER" ./manage.sh restart || sudo -u "$REAL_USER" docker compose --env-file .env up -d
else
  sudo -u "$REAL_USER" docker compose --env-file .env up -d
fi

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo
echo "Done. Open http://${IP:-localhost}:5055 (Seerr) or http://${IP:-localhost}:32400/web (Plex)"
echo "Passwords: cd ${INSTALL_DIR} && ./manage.sh keys"
