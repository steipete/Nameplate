# Changelog

## 0.1.0 - Unreleased

- Initial release: frame, name tag, watermark, and connect-splash overlays with per-host default colors.
- Status menu doubles as a dashboard: uptime, IP address (click to copy), CPU load, RAM, free disk, and layer toggles.
- Frame corners are rounded (configurable) so the border follows the display's curve instead of looking clipped.
- Native grouped settings (System Settings style): Identity, Layers, Splash, General, and About panes with a live preview.
- Fleet file support (`~/.config/nameplate/fleet.json`) to brand every Mac from one synced dotfile.
- Bundled `nameplate` CLI: `attention` (topmost message card + pulsating borders for agents that need the human), `splash`, and `settings`.
- Sparkle auto-updates for Developer ID release builds (disabled for dev and Homebrew installs).
- Designed app icon: dark glass screen with a glowing jade frame and nameplate pill.
- Start at login, menu bar name toggle, hideable menu bar icon, and `nameplate://splash` URL scheme.
