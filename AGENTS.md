# Nameplate — agent notes

- SwiftPM menu bar app, zero dependencies. Building needs full Xcode (SwiftUI macros); if `xcode-select -p` is CommandLineTools, set `DEVELOPER_DIR=/Applications/Xcode.app`.
- Build/test: `swift build`, `swift test`. Bundle: `./Scripts/package_app.sh [debug|release]` (signs Developer ID; `APP_IDENTITY="-"` for ad-hoc).
- Icon: `./Scripts/build_icon.sh` regenerates `Icon.icns` from `Icon-master.png` (falls back to `Scripts/render_icon.swift`).
- Sparkle: public key in `Scripts/package_app.sh`; private key in the maintainer's keychain/1Password (see release-private notes). `Scripts/make_appcast.sh` regenerates `appcast.xml` from `./release/*.zip`.
- CLI lives at `Nameplate.app/Contents/Helpers/nameplate`; attention requests hand off via `~/Library/Application Support/Nameplate/attention.json` + Darwin notification.
- Plain AppKit lifecycle (no SwiftUI scenes): NSStatusItem + NSMenu, manual settings NSWindow. SwiftUI scene machinery (MenuBarExtra menus, Settings scene, URL events) is unreliable for menu-bar-only apps on current macOS.
- Overlay windows are click-through NSPanels at `.statusBar` level (higher levels block NSMenu); splash sits one level above. Controllers in `Sources/Nameplate` are app-lifetime singletons — observers are intentionally never removed.
- `NameplateCore` stays AppKit-free (identity, colors, fleet file) and is the only tested target.
- Version bumps: `version.env`. Changelog: one bullet per entry, one line.
