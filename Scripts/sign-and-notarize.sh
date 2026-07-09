#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Nameplate"
APP_IDENTITY="${APP_IDENTITY:-Developer ID Application: Peter Steinberger (Y5PE65HELJ)}"
APP_BUNDLE="Nameplate.app"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"

# notarytool and stapler require full Xcode, not CommandLineTools.
if [[ "$(xcode-select -p)" == *CommandLineTools* && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app
fi
ZIP_NAME="Nameplate-${MARKETING_VERSION}.zip"

# mac-release exports the 1Password field labels verbatim; accept both shapes.
APP_STORE_CONNECT_API_KEY_P8="${APP_STORE_CONNECT_API_KEY_P8:-${private_key_p8:-}}"
APP_STORE_CONNECT_KEY_ID="${APP_STORE_CONNECT_KEY_ID:-${key_id:-}}"
APP_STORE_CONNECT_ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:-${issuer_id:-}}"
if [[ -z "$APP_STORE_CONNECT_API_KEY_P8" || -z "$APP_STORE_CONNECT_KEY_ID" || -z "$APP_STORE_CONNECT_ISSUER_ID" ]]; then
  echo "Missing App Store Connect credentials (private_key_p8 / key_id / issuer_id)." >&2
  exit 1
fi
KEY_FILE=$(mktemp /tmp/nameplate-api-key.XXXXXX.p8)
NOTARIZE_ZIP=$(mktemp -u /tmp/NameplateNotarize.XXXXXX.zip)
trap 'rm -f "$KEY_FILE" "$NOTARIZE_ZIP"' EXIT
echo "$APP_STORE_CONNECT_API_KEY_P8" | sed 's/\\n/\n/g' > "$KEY_FILE"

./Scripts/package_app.sh release

DITTO_BIN=${DITTO_BIN:-/usr/bin/ditto}
"$DITTO_BIN" -c -k --keepParent --sequesterRsrc "$APP_BUNDLE" "$NOTARIZE_ZIP"

echo "Submitting for notarization"
xcrun notarytool submit "$NOTARIZE_ZIP" \
  --key "$KEY_FILE" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait

echo "Stapling ticket"
xcrun stapler staple "$APP_BUNDLE"

"$DITTO_BIN" -c -k --keepParent --sequesterRsrc "$APP_BUNDLE" "$ZIP_NAME"

spctl -a -t exec -vv "$APP_BUNDLE"
stapler validate "$APP_BUNDLE"

# Stable-name copy so releases/latest/download/Nameplate.zip always works.
cp "$ZIP_NAME" "Nameplate.zip"

DMG_NAME="Nameplate-${MARKETING_VERSION}.dmg"
echo "Building $DMG_NAME"
DMG_STAGE=$(mktemp -d /tmp/nameplate-dmg.XXXXXX)
trap 'rm -f "$KEY_FILE" "$NOTARIZE_ZIP"; rm -rf "$DMG_STAGE"' EXIT
"$DITTO_BIN" "$APP_BUNDLE" "$DMG_STAGE/$APP_BUNDLE"
rm -f "$DMG_NAME"
create-dmg \
  --volname "$APP_NAME" \
  --volicon "Icon.icns" \
  --background "assets/dmg-background.tiff" \
  --window-size 660 428 \
  --icon-size 128 \
  --icon "$APP_BUNDLE" 165 190 \
  --app-drop-link 495 190 \
  --hide-extension "$APP_BUNDLE" \
  --no-internet-enable \
  --codesign "$APP_IDENTITY" \
  "$DMG_NAME" "$DMG_STAGE"

echo "Notarizing $DMG_NAME"
xcrun notarytool submit "$DMG_NAME" \
  --key "$KEY_FILE" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait
xcrun stapler staple "$DMG_NAME"
spctl -a -t open --context context:primary-signature -vv "$DMG_NAME"

# Stable-name copy so releases/latest/download/Nameplate.dmg always works.
cp "$DMG_NAME" "Nameplate.dmg"

echo "Done: $ZIP_NAME + $DMG_NAME"
