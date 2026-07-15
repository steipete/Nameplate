# Nameplate for Windows

Windows port of Nameplate: stable per-machine identity for remote-desktop fleets. It renders click-through colored frames, name-tag pills, and watermarks on every monitor; shows an animated connect splash on remote-connect/session-unlock; and displays click-through agent attention alerts.

## Build

Requires the .NET 8 SDK and Windows 10 or later. From `windows/`:

```powershell
dotnet restore Nameplate.sln
dotnet test Nameplate.Core.Tests
dotnet publish Nameplate.App -c Release -r win-x64 --self-contained -p:PublishSingleFile=true
```

The single-file executable is written below `Nameplate.App/bin/Release/net8.0-windows/win-x64/publish/nameplate.exe`.

## Install

Copy `nameplate.exe` to a stable folder such as `%LOCALAPPDATA%\Nameplate`, run it once, then place a shortcut in `shell:startup` if it should launch at sign-in. The process lives in the notification area; double-click its colored plate or choose **Show splash** to replay the identity card.

Use the same executable as the CLI. If the tray app is not running, a command starts it, waits for `\\.\pipe\nameplate`, forwards one JSON line, and exits:

```powershell
nameplate splash
nameplate attention "Need approval before release" --title "Agent attention" --duration 12 --color "#D4537E"
```

Only one tray instance runs per user session.

## Configuration

Fleet identity file (same schema and precedence as macOS):

`%USERPROFILE%\.config\nameplate\fleet.json`

```json
{
  "megaclaw": { "name": "MEGACLAW", "color": "#1D9E75", "glyph": "🦞" },
  "clawmac": { "name": "clawmac", "color": "#E24B30", "glyph": "🔥" },
  "studio-1": { "color": "#7F77DD" }
}
```

Keys are lowercase short hostnames. Fleet fields override local fields; omitted fields fall back to local settings and then hostname-derived defaults. Malformed fleet files are ignored. Changes apply live.

Local overrides:

`%APPDATA%\Nameplate\settings.json`

```json
{
  "name": "BUILD PC",
  "color": "#378ADD",
  "glyph": "🛠️",
  "layers": {
    "frameEnabled": true,
    "tagEnabled": true,
    "watermarkEnabled": false,
    "frameThickness": 8,
    "frameOpacity": 0.9,
    "frameCornerRadius": 18,
    "roundTopLeft": false,
    "roundTopRight": false,
    "roundBottomLeft": false,
    "roundBottomRight": false,
    "tagCorner": "TopRight",
    "watermarkCorner": "BottomRight",
    "watermarkOpacity": 0.14
  },
  "splash": {
    "duration": 2.5,
    "onRemoteConnect": true,
    "onSessionUnlock": true
  }
}
```

Windows defaults to square frame corners. Set any per-corner value to `true` to opt into rounding.

The tray menu toggles frame, tag, and watermark and persists those choices here. **Open config folder** opens the local override directory.

## Product parity

- Host identity uses the lowercased first DNS label.
- Default accent uses the same FNV-1a 64-bit hash and eight-color palette as macOS.
- Pill text uses the same WCAG relative-luminance calculation and `0.4` dark-text threshold.
- Every display receives independent frame, tag, watermark, splash, and attention windows. The splash traces the colored perimeter, brings the identity plate into focus, and respects Windows' client-animation setting.
- All overlay layers use Win32 layered/transparent/no-activate/tool-window styles. A passive low-level mouse observer dismisses attention on any button press and always forwards the original event, so the intended control still receives it.

The Windows app uses WPF plus the built-in WinForms `NotifyIcon`; application and Core projects have no third-party NuGet dependencies. xUnit is used only by `Nameplate.Core.Tests`.
