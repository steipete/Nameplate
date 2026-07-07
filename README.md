# Nameplate

**Brand every Mac in your fleet so you always know which one you just remoted into.**

If you drive a herd of Macs over [Jump Desktop](https://jumpdesktop.com/), Screen Sharing, or any other remote desktop, the screens all look the same. Nameplate gives each Mac an unmistakable identity — like an aircraft livery — rendered as click-through overlays that float above everything:

- **Frame** — a colored border around every display, with rounded corners that follow the screen's curve. Always visible, costs zero pixels of workspace, survives fullscreen apps.
- **Name tag** — a small pill with the Mac's name (and an optional emoji glyph) pinned to a corner.
- **Watermark** — a big translucent name across the screen, readable from across the room.
- **Connect splash** — the Mac's name flashes center-screen when a remote session likely just started, then fades out.
- **Menu bar plate** — a colored mini-nameplate (plus the name) in the menu bar. Its menu doubles as a glanceable dashboard: uptime, IP address (click to copy), CPU load, RAM, and free disk, plus layer toggles.

Your wallpaper stays untouched — everything is a transparent overlay, so you can keep any background you like.

Each Mac gets a stable default color derived from its hostname, so even an unconfigured fleet is instantly tellable-apart.

<p align="center"><img src="docs/settings.png" width="460" alt="Nameplate settings with live preview"></p>

## Install

Build from source (requires Xcode 26 / Swift 6.2+):

```sh
git clone https://github.com/steipete/Nameplate.git
cd Nameplate
./Scripts/package_app.sh release
open Nameplate.app
```

`package_app.sh` signs with a Developer ID identity; pass your own via `APP_IDENTITY="Developer ID Application: You (TEAMID)"`, or use ad-hoc signing for a quick local build: `APP_IDENTITY="-" ./Scripts/package_app.sh release`.

## Configure

Click the nameplate in the menu bar → **Settings…** (opens automatically on first launch):

- **Identity** — name, color (8 presets or custom), optional glyph. Empty name = computer name.
- **Layers** — frame thickness/corners/opacity, tag corner, watermark corner/opacity.
- **Splash** — duration and triggers (display wake, screen unlock, display reconfiguration).
- **General** — start at login, menu bar appearance.

### Fleet file

Manage the whole fleet from one dotfile. Nameplate reads `~/.config/nameplate/fleet.json`, keyed by short hostname:

```json
{
  "megaclaw": { "name": "MEGACLAW", "color": "#1D9E75", "glyph": "🦞" },
  "clawmac":  { "name": "clawmac",  "color": "#E24B30", "glyph": "🔥" },
  "studio-1": { "color": "#7F77DD" }
}
```

All fields are optional; anything missing falls back to local settings. Sync the file via your dotfiles and every Mac picks up its own entry. Changes are applied live.

### Scripting

Trigger the splash from your own connect automation (works from SSH sessions too, no app activation needed):

```sh
notifyutil -p com.steipete.nameplate.splash
```

`notifyutil -p com.steipete.nameplate.settings` opens Settings. The `nameplate://splash` and `nameplate://settings` URLs are registered as well, but URL delivery to menu-bar-only SwiftUI apps is unreliable on current macOS betas — the Darwin notification is the dependable path.

## Why the splash triggers are heuristics

macOS has no public "a remote session just connected" event. Nameplate reacts to the events that accompany a connect in practice: displays waking, the session unlocking, and display reconfiguration (on headless Macs, the remote-desktop host plugging in its virtual display fires this). Each trigger can be toggled individually.

## Development

```sh
swift build          # needs full Xcode (SwiftUI macros), not just CommandLineTools
swift test
./Scripts/package_app.sh          # debug .app bundle
```

## License

MIT — see [LICENSE](LICENSE). © 2026 Peter Steinberger.
