# Nameplate for Linux

Nameplate brands Linux machines in a remote-desktop fleet with the same stable identity as the macOS app. It draws a click-through colored frame, name-tag pill, translucent watermark, connect splash, and clickable agent-attention cards over every monitor without modifying the wallpaper.

The X11 path is the primary target for xrdp and VNC fleets. Wayland layer-shell support is optional.

## Install

Homebrew on Linux installs Nameplate and its GTK4/X11 dependencies from source, then keeps it current with `brew upgrade`:

```sh
brew install steipete/tap/nameplate
```

Alternatively, download the `x86_64` or `arm64` Linux tarball from the [latest release](https://github.com/steipete/Nameplate/releases/latest). The tarball requires the system GTK4 and X11 runtime libraries.

## Build

Install Rust, a C compiler, `pkg-config`, GTK4 development headers, and X11 development headers. Package names vary by distribution; on Debian/Ubuntu they are typically:

```sh
sudo apt install build-essential pkg-config libgtk-4-dev libx11-dev
```

Build from this directory:

```sh
cargo build --release
```

The binary is `target/release/nameplate`. Runtime packages need GTK4 (`libgtk-4-1` on Debian/Ubuntu) and X11 libraries.

Core parity tests do not need GTK:

```sh
cargo test -p nameplate-core
```

## Run

Start the overlay daemon in the graphical session:

```sh
nameplate
```

Commands use JSON lines over `$XDG_RUNTIME_DIR/nameplate.sock`. If the socket is absent, the command starts a detached daemon and retries automatically:

```sh
nameplate splash
nameplate attention "Need 1Password approval" \
  --title "Agent needs attention" --duration 12 --color '#E24B30'
```

The daemon listens for monitor changes and rebuilds one GTK window per monitor per enabled layer. A logind `org.freedesktop.login1.Session.Unlock` signal triggers the connect splash. Attention cards dismiss on click or timeout; their animated border windows remain click-through.

## X11 and Wayland

On X11, Nameplate applies `_NET_WM_STATE_ABOVE`, skip-taskbar, and skip-pager window-manager hints, positions each window over its monitor, and gives passive layers an empty GDK input region. The attention window's input region contains only the card.

Wayland compositors do not permit ordinary applications to position always-on-top windows. Build the optional integration when the distribution provides `gtk4-layer-shell` development files:

```sh
cargo build --release --features layer-shell
```

That feature anchors overlay-layer surfaces to each output through `gtk4-layer-shell`. Compositor support for the layer-shell protocol is required. The feature is not part of the default build and does not affect X11.

## Configuration

Fleet identity is read from `~/.config/nameplate/fleet.json`, or `$XDG_CONFIG_HOME/nameplate/fleet.json` when `XDG_CONFIG_HOME` is set. Its schema matches macOS: lowercase short hostnames map to entries whose fields are all optional.

```json
{
  "megaclaw": { "name": "MEGACLAW", "color": "#1D9E75", "glyph": "🦞" },
  "clawmac":  { "name": "clawmac",  "color": "#E24B30", "glyph": "🔥" },
  "studio-1": { "color": "#7F77DD" }
}
```

Local overrides and visual settings live beside it in `settings.json`. Unknown fields are ignored; omitted fields use Linux application defaults.

```json
{
  "name": "lab-linux-1",
  "color": "#378ADD",
  "glyph": "🐧",
  "useFleetFile": true,
  "frameEnabled": true,
  "frameThickness": 4,
  "frameOpacity": 1,
  "frameCornerRadius": 16,
  "frameRoundTopLeft": false,
  "frameRoundTopRight": false,
  "frameRoundBottomLeft": false,
  "frameRoundBottomRight": false,
  "tagEnabled": true,
  "tagCorner": "bottomLeft",
  "tagShowsGlyph": true,
  "watermarkEnabled": false,
  "watermarkCorner": "bottomRight",
  "watermarkOpacity": 0.12,
  "splashEnabled": true,
  "splashDuration": 1.8
}
```

Linux defaults to square frame corners. Set any per-corner value to `true` to opt into rounding.

Changes to either file are applied live, including editor/sync tools that replace files atomically. Fleet values take precedence over local identity values; missing values fall back to local settings and then hostname defaults.

## Identity parity

Unconfigured machines use the exact macOS palette and FNV-1a 64-bit mapping over the lowercased first DNS label. Three- and six-digit hex colors normalize to uppercase six-digit form. Pill foreground switches between black and white using the same WCAG relative-luminance calculation and `> 0.4` threshold as macOS.
