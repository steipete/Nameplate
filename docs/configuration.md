# Configuration

Nameplate resolves a local identity, then applies any matching fleet entry. Missing values fall back to the local settings and finally to the hostname-derived defaults.

## macOS settings

Click the nameplate in the menu bar and choose **Settings…**. The window opens automatically on first launch.

- **Identity** sets the name, color, optional glyph, and location.
- **Layers** controls the frame, name tag, watermark, frame/watermark corners, name-tag position and offsets, and optional information lines.
- **Splash** controls the duration and the display-wake, screen-unlock, and display-reconfiguration triggers.
- **General** controls login startup, menu bar appearance, and whether decorations are always visible or only visible during detected remote viewing.

The remote-only mode recognizes virtual displays and active Screen Sharing/VNC, TeamViewer, or AnyDesk sessions. Attention alerts remain visible in either mode.

## Fleet file

All platforms read `~/.config/nameplate/fleet.json`. Linux honors `$XDG_CONFIG_HOME/nameplate/fleet.json` when `XDG_CONFIG_HOME` is set. Keys are lowercase short hostnames; `name`, `color`, and `glyph` work across macOS, Windows, and Linux.

```json
{
  "megaclaw": { "name": "MEGACLAW", "color": "#1D9E75", "glyph": "🦞" },
  "clawmac": { "name": "clawmac", "color": "#E24B30", "glyph": "🔥" },
  "studio-1": { "color": "#7F77DD" }
}
```

macOS also accepts a `location` field and shows it in the status menu and connect splash. Windows and Linux ignore unknown fields. Changes to the fleet file apply live.

For local Windows and Linux visual settings, including their JSON shape, see the [Windows](../windows/README.md#configuration) and [Linux](../linux/README.md#configuration) guides.

## Name-tag placement

Choose one of eight positions: Top left, Top center, Top right, Left center, Right center, Bottom left, Bottom center, or Bottom right. On macOS, Top center sits below a display notch when present. Zero offsets retain the normal inset from the display edge; centered positions align the center of the complete name tag with the center of the edge.

Offsets on an edge-anchored axis move inward. On a centered axis, negative horizontal offsets move left and positive offsets move right; negative vertical offsets move up and positive offsets move down. For example, **Right center**, horizontal `0`, vertical `-100` places the tag on the right edge, 100 units above the midpoint. Negative offsets on edge-anchored axes are treated as zero.

macOS Settings and the website demo provide sliders, numeric entry, and **Reset offsets**. Slider limits follow display dimensions rather than the previous 400-unit ceiling. macOS uses the largest connected display for each slider axis; actual placement is bounded independently on every display. Stored offsets are retained across display resizing and position changes, and may be bounded differently on a smaller screen. The tag remains inside the display with its normal edge inset; names too wide for the display are constrained to fit.

Windows and Linux use their existing local JSON configuration. The key remains `tagCorner` for compatibility, with values `topLeft`, `topCenter`, `topRight`, `leftCenter`, `rightCenter`, `bottomLeft`, `bottomCenter`, and `bottomRight`. Windows also accepts its existing PascalCase spelling. For example (inside `layers` on Windows, at the top level on Linux):

```json
{
  "tagCorner": "rightCenter",
  "tagHorizontalOffset": 0,
  "tagVerticalOffset": -100
}
```

Offsets use points on macOS, device-independent pixels on Windows, and pixels on Linux/the website. Existing corner choices, valid offsets, and the bottom-left default are preserved. These new position values require an updated app; watermark corners remain unchanged. The website's **Apply on this Mac** link includes the selected position and signed offsets.

## Connect triggers

Windows receives remote-connect and session-unlock notifications from the operating system. Linux listens for logind session unlock and rebuilds overlays when monitors change.

macOS does not expose a public “remote session connected” event. Nameplate treats display wake, screen unlock, and display reconfiguration as connection signals because remote-desktop hosts produce those events when they attach or resize a virtual display. Each trigger can be disabled independently.

## Updates

Developer ID release builds on macOS update through Sparkle. Homebrew-managed builds update through Homebrew; development builds leave Sparkle disabled.
