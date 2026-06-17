# TorBox Media Center + Plex

A Docker setup to mount your [TorBox](https://torbox.app/) library as a virtual filesystem for Plex, Jellyfin, Emby, Infuse, and other media players. This replaces the previous Real-Debrid + zurg + rclone stack with [TorBox Media Center](https://github.com/torbox-app/torbox-media-center), TorBox's official mounting solution.

## Why TorBox Media Center instead of zurg?

[zurg](https://github.com/debridmediamanager/zurg-testing) is built specifically for Real-Debrid and does not support TorBox. TorBox Media Center is the official alternative and provides:

- Native TorBox support (torrents, usenet, and web downloads)
- No rclone or custom WebDAV server required
- Automatic organization into `movies/` and `series/` folders
- FUSE virtual filesystem for Plex, or STRM files for Jellyfin/Emby

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
| `MOUNT_HOST_PATH` | Host path exposed to Plex | `/mnt/torbox` |
| `ENABLE_METADATA` | Organize files into movies/series folders | `true` |
| `MOUNT_REFRESH_TIME` | Refresh interval: `slowest` (24h) to `instant` (6min) | `fast` (2h) |

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

If Plex runs in Docker, map the **host** mount path into the Plex container:

```bash
-v /mnt/torbox:/torbox-media-center
```

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
