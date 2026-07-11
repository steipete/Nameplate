# Changelog

## 0.2.6 - Unreleased

- Fixed (macOS): imported config links now preserve watermark opacity values through the full Settings range instead of silently clamping them to 30%. Thanks @abhinavgautam01!
- Fixed (macOS): `nameplate attention --color` now rejects invalid values and normalizes valid hex colors before handing requests to the app. Thanks @abhinavgautam01!
- Fixed (macOS): Settings window placement now persists across app restarts. Thanks @abhinavgautam01!
- Fixed (macOS): rapid attention requests now queue and display in order instead of overwriting each other, while legacy handoffs still migrate. Thanks @abhinavgautam01!
- Fixed (macOS): attention cards now stay visibly bounded and click-through until presentation succeeds, recover safely across display and Space changes, and can be cleared with `nameplate dismiss` without quitting the app.
- Fixed (macOS): Sparkle now stays disabled for Homebrew-managed installs even when the app lives directly in `/Applications`. Thanks @abhinavgautam01!

## 0.2.5 - 2026-07-09

- Changed (Windows/Linux): new and unconfigured installs now default to square frame corners; macOS keeps its rounded bottom-corner default.
- Fixed: the DMG installer window no longer clips the bottom of the drag-to-install background (window height now accounts for the title bar).

## 0.2.4 - 2026-07-09

- Fixed (Windows): DPI-correct overlay sizing so frame corners aren't clipped on scaled displays.
- Fixed: overlay frames now track display size changes reliably — screen frames are re-synced after display reconfiguration settles (remote-session window resizes reported stale sizes before). Sticky attention borders and the card re-anchor too.

## 0.2.3 - 2026-07-08

- Attention alerts now stay on screen until clicked by default (all platforms); pass `--duration <seconds>` for the old auto-dismiss behavior.
- The attention card clamps to the visible screen area so it stays fully readable on small displays.

## 0.2.2 - 2026-07-08

- Fixed: fleet-file watcher no longer triggers status/overlay redraws every 15 s when `fleet.json` is absent. Thanks @abhinavgautam01!
- Fixed: `nameplate://` deep links now match case-insensitively (`Nameplate://Config` works). Thanks @abhinavgautam01!
- Fixed: future-dated attention requests (clock drift, spoofed handoff) are rejected by the freshness filter. Thanks @abhinavgautam01!
- Status menu falls back to a routable IPv6 address when no IPv4 is available (IPv6-only/NAT64 networks). Thanks @abhinavgautam01!
- Website: "Summon me" demo fires a real attention alert (card + pulsating frame) on the page; one subtle frame-pulse hint per session when the agents section scrolls into view — never uninvited.

## 0.2.1 - 2026-07-07

- Windows port in `windows/` (C#/.NET 8 WPF): click-through frame/tag/watermark/splash overlays per monitor, real remote-connect splash via WTS session events, tray dashboard, named-pipe CLI (`nameplate attention|splash`), fleet.json compatibility, and hostname-color parity with macOS. Verified on Windows 11 (21 core tests + on-VM overlay/attention proof).
- Linux port in `linux/` (Rust + GTK4): the same overlay set for X11 (xrdp/VNC fleets; Wayland renders best-effort), unix-socket CLI, logind unlock splash, fleet.json compatibility, and color parity. Verified on Ubuntu 26.04 (8 core tests + on-VM overlay/attention proof).
- Releases now ship per-platform artifacts: `Nameplate-Windows-{x64,arm64}.zip` and `Nameplate-Linux-{x86_64,arm64}.tar.gz` alongside the Mac zip/DMG, with stable `releases/latest` download URLs.
- Website: cross-platform — the live settings window auto-adopts your OS's chrome (macOS / Windows 11 / GNOME) with a manual OS toggle, and the download button targets your platform.
- Releases now ship a notarized DMG with a branded drag-to-install background, plus stable `Nameplate.dmg` / `Nameplate.zip` download URLs via `releases/latest`; website and README link the DMG.
- Per-Mac location: optional `location` field (fleet file or Settings) shown in the status menu, connect splash, and identity.

## 0.2.0 - 2026-07-07

- `nameplate://config` URL: opens a floating confirmation panel summarizing the proposed identity/layer settings with Cancel/Apply — the website's live settings window sends its state here via "Apply on this Mac".
- Homebrew cask: `brew install --cask steipete/tap/nameplate` (installs the app and links the `nameplate` CLI).
- Website: the settings screenshot is now a live interactive remake of the Settings window — tabs work, and Identity/Layers/Splash/General controls restyle the nameplate the page itself wears; "Apply on this Mac" hands the config to the app, and the site ships a social card.

## 0.1.1 - 2026-07-07

- Project website in `docs/`, served at [nameplate.sh](https://nameplate.sh) via GitHub Pages.
- Fixed: the rounded-corner toggle tiles in Settings → Layers only accepted clicks on their border; the whole tile is now clickable.

## 0.1.0 - 2026-07-07

- Initial release: frame, name tag, watermark, and connect-splash overlays with per-host default colors.
- Status menu doubles as a dashboard: uptime, IP address (click to copy), CPU load, RAM, free disk, and layer toggles.
- Frame corner rounding is configurable per corner (radius slider + corner toggles); default rounds only the bottom corners.
- Agent skill for attention alerts ships in `skills/nameplate-attention/`.
- Decoration visibility mode: show frame/tag/watermark/splash always, or only when viewed remotely (virtual display detected or Screen Sharing/VNC connected); attention alerts are exempt.
- Native grouped settings (System Settings style): Identity, Layers, Splash, General, and About panes with a live preview.
- Fleet file support (`~/.config/nameplate/fleet.json`) to brand every Mac from one synced dotfile.
- Bundled `nameplate` CLI: `attention` (topmost message card + pulsating borders for agents that need the human), `splash`, and `settings`.
- Sparkle auto-updates for Developer ID release builds (disabled for dev and Homebrew installs).
- Designed app icon: dark glass screen with a glowing jade frame and nameplate pill.
- Start at login, menu bar name toggle, hideable menu bar icon, and `nameplate://splash` URL scheme.
