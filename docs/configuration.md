# Configuration

Nameplate resolves a local identity, then applies any matching fleet entry. Missing values fall back to the local settings and finally to the hostname-derived defaults.

## macOS settings

Click the nameplate in the menu bar and choose **Settings…**. The window opens automatically on first launch.

- **Identity** sets the name, color, optional glyph, and location.
- **Layers** controls the frame, name tag, watermark, their corners, and optional information lines.
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

## Connect triggers

Windows receives remote-connect and session-unlock notifications from the operating system. Linux listens for logind session unlock and rebuilds overlays when monitors change.

macOS does not expose a public “remote session connected” event. Nameplate treats display wake, screen unlock, and display reconfiguration as connection signals because remote-desktop hosts produce those events when they attach or resize a virtual display. Each trigger can be disabled independently.

## Updates

Developer ID release builds on macOS update through Sparkle. Homebrew-managed builds update through Homebrew; development builds leave Sparkle disabled.
