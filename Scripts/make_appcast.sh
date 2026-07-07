#!/usr/bin/env bash
# Regenerates appcast.xml from release zips in ./release/.
# Usage: Scripts/make_appcast.sh
# Expects: Nameplate-<version>.zip files in ./release, Sparkle EdDSA private
# key in the login keychain (generate_keys), see also 1Password item
# "Nameplate Sparkle EdDSA".
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

GENERATE_APPCAST=".build/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [[ ! -x "$GENERATE_APPCAST" ]]; then
  echo "generate_appcast missing — run 'swift build' first to fetch Sparkle." >&2
  exit 1
fi

"$GENERATE_APPCAST" \
  --download-url-prefix "https://github.com/steipete/Nameplate/releases/download/" \
  --link "https://github.com/steipete/Nameplate" \
  -o "$ROOT/appcast.xml" \
  "$ROOT/release"

echo "wrote appcast.xml"
