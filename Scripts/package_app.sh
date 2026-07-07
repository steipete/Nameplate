#!/usr/bin/env bash
set -euo pipefail
CONF=${1:-debug}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/version.env"

# SwiftUI macros need the full Xcode toolchain; plain CommandLineTools fails.
if [[ "$(xcode-select -p)" == *CommandLineTools* && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app
fi

swift build -c "$CONF"
BIN_PATH=$(swift build -c "$CONF" --show-bin-path)

APP="$ROOT/Nameplate.app"
APP_ENTITLEMENTS="$ROOT/Nameplate.entitlements"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BUNDLE_ID="com.steipete.nameplate"
FEED_URL="https://raw.githubusercontent.com/steipete/Nameplate/main/appcast.xml"
AUTO_CHECKS=true
LOWER_CONF=$(printf "%s" "$CONF" | tr '[:upper:]' '[:lower:]')
if [[ "$LOWER_CONF" == "debug" ]]; then
  BUNDLE_ID="com.steipete.nameplate.debug"
  FEED_URL=""
  AUTO_CHECKS=false
fi
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Nameplate</string>
    <key>CFBundleDisplayName</key><string>Nameplate</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>Nameplate</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleIconFile</key><string>Icon</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Peter Steinberger. MIT License.</string>
    <key>NameplateGitCommit</key><string>${GIT_COMMIT}</string>
    <key>SUFeedURL</key><string>${FEED_URL}</string>
    <key>SUPublicEDKey</key><string>PuuzNa/yoisEbFEZOkuwW1Su3Y/RD3Rph8cAk8+VZ4Y=</string>
    <key>SUEnableAutomaticChecks</key><${AUTO_CHECKS}/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>${BUNDLE_ID}</string>
            <key>CFBundleURLSchemes</key>
            <array><string>nameplate</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

cp "$BIN_PATH/Nameplate" "$APP/Contents/MacOS/Nameplate"
chmod +x "$APP/Contents/MacOS/Nameplate"

# Ship the CLI inside the bundle for easy symlinking:
#   ln -s /Applications/Nameplate.app/Contents/Helpers/nameplate /usr/local/bin/nameplate
if [[ -f "$BIN_PATH/NameplateCLI" ]]; then
  mkdir -p "$APP/Contents/Helpers"
  cp "$BIN_PATH/NameplateCLI" "$APP/Contents/Helpers/nameplate"
  chmod +x "$APP/Contents/Helpers/nameplate"
fi

if [[ -f "$ROOT/Icon.icns" ]]; then
  cp "$ROOT/Icon.icns" "$APP/Contents/Resources/Icon.icns"
fi

CODESIGN_ID="${APP_IDENTITY:-Developer ID Application: Peter Steinberger (Y5PE65HELJ)}"
SIGN_FLAGS=(--force --options runtime)
if [[ "$CODESIGN_ID" != "-" ]]; then
  SIGN_FLAGS+=(--timestamp)
fi

# Embed Sparkle.framework
if [[ -d "$BIN_PATH/Sparkle.framework" ]]; then
  mkdir -p "$APP/Contents/Frameworks"
  cp -R "$BIN_PATH/Sparkle.framework" "$APP/Contents/Frameworks/"
  chmod -R a+rX "$APP/Contents/Frameworks/Sparkle.framework"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Nameplate"
  function resign() { codesign "${SIGN_FLAGS[@]}" --sign "$CODESIGN_ID" "$1"; }
  SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
  resign "$SPARKLE/Versions/B/Autoupdate"
  resign "$SPARKLE/Versions/B/Updater.app/Contents/MacOS/Updater"
  resign "$SPARKLE/Versions/B/Updater.app"
  resign "$SPARKLE/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
  resign "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
  resign "$SPARKLE/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"
  resign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
  resign "$SPARKLE/Versions/B/Sparkle"
  resign "$SPARKLE"
fi

chmod -R u+w "$APP"
xattr -cr "$APP"
find "$APP" -name '._*' -delete

codesign "${SIGN_FLAGS[@]}" --entitlements "$APP_ENTITLEMENTS" --sign "$CODESIGN_ID" "$APP/Contents/Helpers/nameplate" 2>/dev/null || true
codesign "${SIGN_FLAGS[@]}" --entitlements "$APP_ENTITLEMENTS" --sign "$CODESIGN_ID" "$APP"

echo "Created $APP"
