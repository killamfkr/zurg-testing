#!/usr/bin/env bash
# CasaOS all-in-one installer for TorBox Media Server (nordicnode stack).
# Installs: Decypharr, Prowlarr, Radarr, Sonarr, Seerr, Byparr, Plex/Jellyfin
set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/nordicnode/TorBox-Media-Server.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

apt_safe_update() {
  export DEBIAN_FRONTEND=noninteractive
  # Broken third-party repos (e.g. deb.libre.computer expired GPG) kill apt update on some CasaOS boxes.
  for broken in /etc/apt/sources.list.d/librecomputer.list /etc/apt/sources.list.d/librecomputer.list.save; do
    if [[ -f "$broken" ]]; then
      mv "$broken" "${broken}.disabled" 2>/dev/null || true
      log "Disabled broken apt repo: $(basename "$broken")"
    fi
  done
  apt-get update -qq 2>/dev/null || apt-get update -qq --allow-releaseinfo-change 2>/dev/null || true
}

apt_safe_install() {
  apt_safe_update
  apt-get install -y -qq "$@" 2>/dev/null \
    || apt-get install -y "$@" \
    || die "Failed to install packages: $*"
}

# nordicnode setup.sh sometimes writes colored log lines into .env on CasaOS terminals.
sanitize_env_file() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0
  local tmp="${env_file}.sanitized"
  sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$env_file" | grep -E '^(#|[A-Z_][A-Z0-9_]*=)' >"$tmp" || true
  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"
    die ".env is missing or unreadable at $env_file"
  fi
  mv "$tmp" "$env_file"
  chmod 600 "$env_file"
  chown "${REAL_USER}:${REAL_USER}" "$env_file" 2>/dev/null || true
}

start_stack() {
  sanitize_env_file "${INSTALL_DIR}/.env"
  if [[ -x "${INSTALL_DIR}/manage.sh" ]]; then
    sudo -u "$REAL_USER" bash -c "cd '${INSTALL_DIR}' && ./manage.sh restart" \
      || sudo -u "$REAL_USER" bash -c "cd '${INSTALL_DIR}' && docker compose --env-file .env up -d"
  else
    sudo -u "$REAL_USER" bash -c "cd '${INSTALL_DIR}' && docker compose --env-file .env up -d"
  fi
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  die 'Run as root: curl -fsSL .../install-full.sh | sudo TORBOX_API_KEY=your_key bash'
fi

REAL_USER="${SUDO_USER:-}"
if [[ -z "$REAL_USER" || "$REAL_USER" == "root" ]]; then
  REAL_USER=$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}')
fi
REAL_USER="${REAL_USER:-ubuntu}"

if [[ -z "${TORBOX_API_KEY:-}" ]]; then
  if [[ -t 0 ]]; then
    read -rp "TorBox API key (https://torbox.app/settings): " TORBOX_API_KEY
  else
    read -rp "TorBox API key (https://torbox.app/settings): " TORBOX_API_KEY < /dev/tty
  fi
fi
[[ -n "${TORBOX_API_KEY:-}" ]] || die "TORBOX_API_KEY is required"

if [[ -d /DATA ]]; then
  SRC_DIR="/DATA/AppData/torbox-media-server-src"
  MOUNT_DIR="/DATA/Media/torbox-media"
else
  SRC_DIR="/opt/torbox-media-server-src"
  MOUNT_DIR="/mnt/torbox-media"
fi
INSTALL_DIR="${SRC_DIR}/torbox-media-server"

log "Preparing system for ${REAL_USER}"
apt_safe_install git curl ca-certificates jq openssl
apt-get install -y -qq fuse3 2>/dev/null || apt-get install -y -qq fuse 2>/dev/null || true
modprobe fuse 2>/dev/null || true

if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker"
  curl -fsSL https://get.docker.com | sh
fi
usermod -aG docker "$REAL_USER" 2>/dev/null || true

if ! command -v casaos >/dev/null 2>&1 && [[ "${INSTALL_CASAOS:-0}" == "1" ]]; then
  log "Installing CasaOS"
  curl -fsSL https://get.casaos.io | bash
fi

log "Stopping old TorBox Media Center install (if any)"
docker rm -f torbox-media-center 2>/dev/null || true
if [[ -f /DATA/AppData/torbox-media-center/docker-compose.yml ]]; then
  (cd /DATA/AppData/torbox-media-center && docker compose down 2>/dev/null) || true
fi

mkdir -p "$(dirname "$SRC_DIR")" "$MOUNT_DIR"
chown -R "$REAL_USER:$REAL_USER" "$(dirname "$SRC_DIR")" 2>/dev/null || true

log "Fetching TorBox Media Server (${UPSTREAM_REPO})"
if [[ -d "$SRC_DIR/.git" ]]; then
  sudo -u "$REAL_USER" git -C "$SRC_DIR" fetch origin "$UPSTREAM_BRANCH" --depth 1
  sudo -u "$REAL_USER" git -C "$SRC_DIR" reset --hard "origin/${UPSTREAM_BRANCH}"
else
  sudo -u "$REAL_USER" git clone --depth 1 --branch "$UPSTREAM_BRANCH" "$UPSTREAM_REPO" "$SRC_DIR"
fi
chmod +x "$SRC_DIR/setup.sh"

# nordicnode pins byparr:v1.0.0 which no longer exists on ghcr.io
sed -i 's|ghcr.io/thephaseless/byparr:v1\.0\.0|ghcr.io/thephaseless/byparr:2.1.0|g' "$SRC_DIR/docker-compose.yml"

log "Running full stack setup (this takes several minutes)"
set +e
sudo -u "$REAL_USER" env \
  TORBOX_API_KEY="${TORBOX_API_KEY}" \
  TORBOX_MEDIA_SERVER="${TORBOX_MEDIA_SERVER:-plex}" \
  TORBOX_PLEX_CLAIM="${TORBOX_PLEX_CLAIM:-}" \
  TORBOX_MOUNT_DIR="${MOUNT_DIR}" \
  TORBOX_START_SERVICES=true \
  bash -c "cd '$SRC_DIR' && ./setup.sh --yes"
setup_status=$?
set -e
if [[ $setup_status -ne 0 ]]; then
  die "setup.sh failed (exit $setup_status)"
fi

[[ -f "$INSTALL_DIR/docker-compose.yml" ]] || die "Setup failed — $INSTALL_DIR/docker-compose.yml not found"

log "Fixing .env and starting services"
sanitize_env_file "${INSTALL_DIR}/.env"

log "Opening services on LAN (CasaOS default)"
sed -i -E 's/"127\.0\.0\.1:([0-9]+):\1"/"\1:\1"/g' "$INSTALL_DIR/docker-compose.yml"
chown "$REAL_USER:$REAL_USER" "$INSTALL_DIR/docker-compose.yml"

start_stack

SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
SERVER_IP="${SERVER_IP:-localhost}"

ln -sf "$INSTALL_DIR/manage.sh" /usr/local/bin/torbox-media-server 2>/dev/null || true

log "Installation complete"
cat <<EOF

TorBox Media Server is running.

Open in your browser (replace IP if needed):

  Seerr (request movies/TV):  http://${SERVER_IP}:5055
  Plex:                       http://${SERVER_IP}:32400/web
  Radarr (movies):            http://${SERVER_IP}:7878
  Sonarr (TV):                http://${SERVER_IP}:8989
  Prowlarr (indexers):        http://${SERVER_IP}:9696
  Decypharr (TorBox bridge):  http://${SERVER_IP}:8282

Install directory: ${INSTALL_DIR}
Manage stack:      torbox-media-server status
                   torbox-media-server restart
                   torbox-media-server logs

Admin passwords:   cd ${INSTALL_DIR} && ./manage.sh keys

Next steps:
  1. Open Seerr and complete the setup wizard (connects to Plex/Radarr/Sonarr)
  2. Search for a movie in Seerr and request it — it should appear in Plex
  3. Prowlarr already has a default indexer; add more in Settings if needed

Note: This stack runs via Docker/systemd, not inside the CasaOS app store UI.
EOF
