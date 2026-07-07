# Changelog

## 0.2.1 - Unreleased

- Windows port in `windows/` (C#/.NET 8 WPF): click-through frame/tag/watermark/splash overlays per monitor, real remote-connect splash via WTS session events, tray dashboard, named-pipe CLI (`nameplate attention|splash`), fleet.json compatibility, and hostname-color parity with macOS. Verified on Windows 11 (21 core tests + on-VM overlay/attention proof).
- Linux port in `linux/` (Rust + GTK4): the same overlay set for X11 (xrdp/VNC fleets; Wayland renders best-effort), unix-socket CLI, logind unlock splash, fleet.json compatibility, and color parity. Verified on Ubuntu 26.04 (8 core tests + on-VM overlay/attention proof).
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
