# TorBox Media Server for CasaOS

One-command installers for [TorBox](https://torbox.app/) on Ubuntu with [CasaOS](https://github.com/IceWhaleTech/CasaOS).

## Recommended: all-in-one complete stack

Installs everything and wires it together automatically:

**Plex** · **Seerr** (request movies/TV) · **Radarr** · **Sonarr** · **Prowlarr** · **Decypharr** (TorBox bridge) · **Byparr**

Based on [nordicnode/TorBox-Media-Server](https://github.com/nordicnode/TorBox-Media-Server) — request a movie in Seerr, TorBox caches it, Plex streams it. No local storage.

```bash
curl -fsSL https://raw.githubusercontent.com/killamfkr/zurg-testing/main/install-full.sh | sudo TORBOX_API_KEY=your_api_key_here bash
```

Optional Plex claim token (links Plex to your account on first boot):

```bash
curl -fsSL https://raw.githubusercontent.com/killamfkr/zurg-testing/main/install-full.sh | sudo TORBOX_API_KEY=your_key TORBOX_PLEX_CLAIM=claim-xxxxx bash
```

Get a claim token at [plex.tv/claim](https://www.plex.tv/claim/) (expires in 4 minutes).

### After install — open these URLs

| Service | URL | Purpose |
| --- | --- | --- |
| Seerr | `http://YOUR-IP:5055` | Browse and request movies/TV |
| Plex | `http://YOUR-IP:32400/web` | Watch your library |
| Radarr | `http://YOUR-IP:7878` | Movie automation |
| Sonarr | `http://YOUR-IP:8989` | TV automation |
| Prowlarr | `http://YOUR-IP:9696` | Torrent indexers |
| Decypharr | `http://YOUR-IP:8282` | TorBox download bridge |

Manage the stack:

```bash
torbox-media-server status
torbox-media-server restart
torbox-media-server logs
cd /DATA/AppData/torbox-media-server-src/torbox-media-server && ./manage.sh keys
```

Install location: `/DATA/AppData/torbox-media-server-src/torbox-media-server`

---

## Simple mount only (not recommended)

The lightweight installer only mounts existing TorBox files. It has known issues with CasaOS FUSE and metadata rate limits. Use the **all-in-one** installer above instead.

```bash
curl -fsSL https://raw.githubusercontent.com/killamfkr/zurg-testing/main/install.sh | sudo TORBOX_API_KEY=your_api_key_here bash
```

---

## Legacy: TorBox Media Center only

A Docker setup to mount your TorBox library for Plex using [TorBox Media Center](https://github.com/torbox-app/torbox-media-center).

## Quick start with Docker (Plex)

1. Clone this repo
2. Copy `.env.example` to `.env` and add your TorBox API key from [torbox.app/settings](https://torbox.app/settings)
3. Create the mount directory: `sudo mkdir -p /mnt/torbox`
4. Start the stack: `docker compose up -d`
5. Point Plex at `/mnt/torbox/movies` and `/mnt/torbox/series`

Your media appears at `/mnt/torbox` on the host. If you change `.env`, restart with `docker compose restart torbox-media-center`.

## Configuration

All settings live in `.env`. See `.env.example` for the available options.

| Variable | Description | Default |
| --- | --- | --- |
| `TORBOX_API_KEY` | Your TorBox API key (required) | — |
| `MOUNT_METHOD` | `fuse` for Plex/VLC/Infuse, `strm` for Jellyfin/Emby | `fuse` |
| `MOUNT_PATH` | Path inside the container | `/torbox` |
| `MOUNT_HOST_PATH` | Host path exposed to Plex | `/DATA/Media/torbox` on CasaOS, `/mnt/torbox` otherwise |
| `ENABLE_METADATA` | Split TV into `series/` via metadata API | `false` (all videos go to `movies/`) |
| `MOUNT_REFRESH_TIME` | Refresh interval: `slowest` (24h) to `instant` (6min) | `normal` (3h) |

### FUSE vs STRM

- **FUSE** (default): Mounts virtual files directly. Use this for Plex on Linux.
- **STRM**: Creates small `.strm` pointer files. Use this for Jellyfin, Emby, or Windows.

For FUSE on Docker, the compose file already sets the required `SYS_ADMIN` capability and `/dev/fuse` device mapping.

## Plex library updates

Unlike zurg, TorBox Media Center does not trigger scripts when your library changes. Instead:

1. Set `MOUNT_REFRESH_TIME` in `.env` to control how often new downloads appear
2. Enable **Scan my library automatically** in Plex settings
3. Optionally run `scripts/plex_scan_all.sh` on a cron schedule to force Plex scans after each refresh

Edit `scripts/plex_scan_all.sh` with your Plex URL and token before using it.

For manual partial scans of specific folders, use `scripts/plex_update.sh`.

## Plex Docker volume mapping

If Plex runs in Docker on CasaOS, map the host mount path into the Plex container:

```bash
-v /DATA/Media/torbox:/torbox-media-center
```

On a standard Linux install, use `/mnt/torbox` instead.

Then add Plex libraries pointing to `/torbox-media-center/movies` and `/torbox-media-center/series`.

## Systemd (optional)

To start the stack on boot:

```bash
sudo cp lib/systemd/system/torbox-media-center.service /etc/systemd/system/
# Edit WorkingDirectory in the unit file to match where you cloned this repo
sudo systemctl daemon-reload
sudo systemctl enable --now torbox-media-center
```

## Migrating from Real-Debrid + zurg

| Old (zurg) | New (TorBox) |
| --- | --- |
| `config.yml` with RD token | `.env` with `TORBOX_API_KEY` |
| zurg WebDAV + rclone mount | TorBox Media Center FUSE mount |
| `/mnt/zurg` | `/mnt/torbox` |
| Custom directory filters in `config.yml` | Automatic `movies/` and `series/` via metadata |
| `on_library_update` hook | Scheduled Plex scans or automatic Plex scanning |

## Troubleshooting

### Metadata rate-limit loop (429 / retrying)

TorBox's metadata API rate-limits heavily. If logs show `429` or `Retrying`, set `ENABLE_METADATA=false` and restart.

### "Metadata scanning is enabled" but CasaOS shows false

**This is a bug in TorBox Media Center.** In their source code, that warning prints on every startup unless both metadata and raw mode are enabled together. It does **not** mean your setting was ignored.

Verify the real value inside the running container:

```bash
docker exec torbox-media-center printenv ENABLE_METADATA
```

If it prints `false`, metadata is off — ignore the startup warning.

### Files inside container but empty on host (CasaOS FUSE issue)

FUSE mounts often work inside the Docker container but do not propagate to the host path CasaOS shows you. Check both:

```bash
docker exec torbox-media-center ls /torbox/movies/
ls /DATA/Media/torbox/movies/
```

If the first has files but the second is empty, fix the CasaOS volume to use `:rshared`:

```
/DATA/Media/torbox:/torbox:rshared
```

Run the CasaOS-specific fix:

```bash
curl -fsSL https://raw.githubusercontent.com/killamfkr/zurg-testing/main/scripts/fix-casaos.sh | sudo bash
```

### Empty `movies` or `series` folders

Files **should** appear if you have playable, cached videos in your TorBox account at [torbox.app](https://torbox.app).

Common causes:

1. **Nothing cached on TorBox yet** — Add and cache torrents/downloads on TorBox first. Empty account = empty folders.
2. **First sync still running** — Check progress:
   ```bash
   docker logs -f torbox-media-center
   ```
   Force a refresh:
   ```bash
   docker restart torbox-media-center
   ```
3. **Wrong folder name** — TV shows go in `series/`, not `tv/`.
4. **Metadata scanning issues** — Our default is `ENABLE_METADATA=false`, which puts **all** videos in `movies/` and leaves `series/` empty. To split movies vs TV, set `ENABLE_METADATA=true` in `.env` and restart (can be slow and hit API rate limits).
5. **Bad API key** — Regenerate at [torbox.app/settings](https://torbox.app/settings), update `.env`, then restart.

On CasaOS, your `.env` is at `/DATA/AppData/torbox-media-center/.env` and media at `/DATA/Media/torbox/`.

Run the diagnostic script:

```bash
curl -fsSL https://raw.githubusercontent.com/killamfkr/zurg-testing/main/scripts/diagnose.sh | sudo bash
```

Quick manual checks:

```bash
ls -la /DATA/Media/torbox/
ls -la /DATA/Media/torbox/movies/
docker logs --tail 50 torbox-media-center
```

### Other issues

Check container logs:

```bash
docker logs -f torbox-media-center
```

If the FUSE mount fails, verify your host supports FUSE and that Docker has `SYS_ADMIN` and `/dev/fuse` access (already configured in `docker-compose.yml`).

Force an immediate library refresh:

```bash
docker compose restart torbox-media-center
```

## Links

- [TorBox Media Center docs](https://torbox-app-torbox-media-center.mintlify.app/)
- [TorBox API docs](https://api.torbox.app/)
- [Plex setup guide](https://torbox-app-torbox-media-center.mintlify.app/guides/plex)
- [Jellyfin/Emby setup guide](https://torbox-app-torbox-media-center.mintlify.app/guides/jellyfin-emby)
