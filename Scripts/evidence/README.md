# Native placement evidence

These tools capture the actual native tag implementation with a synthetic identity.
Each records all eight anchors, signed center offsets, and extreme-offset clamping.
Screenshots and `runtime.json` contain the display dimensions, scale, offsets, and
source revision. Pixel checks fail when the photographed pill is missing or misplaced.

- macOS: run `Scripts/evidence/mac.sh /absolute/output/directory` on a Mac with Screen
  Recording permission. It builds a temporary isolated app bundle linked to the
  production overlay controller and SwiftUI views, captures every connected physical
  screen with ScreenCaptureKit, and restores the desktop afterward. Display name,
  vendor, and the production virtual-display classification are recorded; Screen
  Sharing can expose virtual screens instead of the connected physical monitors.
  Use `NAMEPLATE_EVIDENCE_MIN_PHYSICAL_DISPLAYS=2 Scripts/evidence/mac.sh /absolute/output`
  for dual-monitor hardware evidence: it fails before capture if fewer than two
  physical displays are visible to the session. The composite
  includes only the synthetic backdrop and production overlay panels. Settings use
  a separate bundle identifier. Re-run after connecting or rearranging monitors;
  report the actual screen origins and scales rather than claiming simulated displays.
- Windows: run `dotnet run --project windows/Nameplate.Evidence -- C:/evidence` on a
  Windows desktop. The harness links the production `TagWindow`, verifies its native
  HWND and photographed pixels, and captures the desktop over a synthetic backdrop.
  CI uploads `nameplate-windows-runtime`. CI currently supplies one virtual display;
  its screenshots do not establish physical multi-monitor or mixed-DPI behavior.
- Linux: run `dbus-run-session -- python3 Scripts/evidence/linux.py /absolute/output`
  after installing the dependencies listed in `linux.py`. It runs the production GTK
  daemon in an isolated Xvfb/Openbox/X11 session, changes the actual JSON config, and
  checks photographed pixels. CI uploads `nameplate-linux-runtime`. Its one virtual
  display does not establish physical multi-monitor or Wayland behavior.

Runtime screenshots supplement the shared placement vectors and native tests. They
do not substitute for physical display-connect/disconnect, monitor rearrangement,
mixed-scale, notch, or click-through interaction checks.
