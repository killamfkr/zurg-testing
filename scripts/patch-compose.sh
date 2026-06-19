#!/usr/bin/env bash
# Fix known-bad image tags in nordicnode TorBox-Media-Server compose files.
patch_compose_images() {
  local compose_file="$1"
  [[ -f "$compose_file" ]] || return 0
  sed -i \
    -e 's|ghcr.io/thephaseless/byparr:v1\.0\.0|ghcr.io/thephaseless/byparr:2.1.0|g' \
    -e 's|ghcr.io/thephaseless/byparr:v2\.0\.0|ghcr.io/thephaseless/byparr:2.1.0|g' \
    "$compose_file"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  for f in "$@"; do
    patch_compose_images "$f"
    echo "Patched: $f"
  done
fi
