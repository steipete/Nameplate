#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [[ "$(xcode-select -p)" == *CommandLineTools* && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Prefer the designed master (Icon-master.png); fall back to the programmatic
# render for bootstrap.
if [[ -f "$ROOT/Icon-master.png" ]]; then
  cp "$ROOT/Icon-master.png" "$TMP/icon_1024.png"
else
  swift Scripts/render_icon.swift "$TMP/icon_1024.png"
fi

ICONSET="$TMP/Icon.iconset"
mkdir -p "$ICONSET"
for px in 16 32 128 256 512; do
  sips -z "$px" "$px" "$TMP/icon_1024.png" --out "$ICONSET/icon_${px}x${px}.png" >/dev/null
  double=$((px * 2))
  sips -z "$double" "$double" "$TMP/icon_1024.png" --out "$ICONSET/icon_${px}x${px}@2x.png" >/dev/null
done

iconutil --convert icns --output "$ROOT/Icon.icns" "$ICONSET"
echo "wrote Icon.icns"
