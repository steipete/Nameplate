import AppKit
import NameplateCore
import SwiftUI
import ScreenCaptureKit

/// Linked to the production OverlayController/OverlayView; run in an isolated evidence bundle.
@main
@MainActor
enum MacPlacementEvidence {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("Native evidence failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        guard CGPreflightScreenCaptureAccess() else {
            throw NSError(domain: "Evidence", code: 1, userInfo: [NSLocalizedDescriptionKey: "Screen Recording permission is required for live screenshots."])
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let screens = NSScreen.screens
        let physicalCount = screens.filter { !RemoteViewMonitor.isVirtual(screen: $0) }.count
        let minimumPhysical = Int(ProcessInfo.processInfo.environment["NAMEPLATE_EVIDENCE_MIN_PHYSICAL_DISPLAYS"] ?? "0") ?? 0
        guard physicalCount >= minimumPhysical else {
            throw NSError(domain: "Evidence", code: 8, userInfo: [NSLocalizedDescriptionKey:
                "Expected at least \(minimumPhysical) physical displays; this session exposes \(physicalCount) physical and \(screens.count - physicalCount) virtual displays."])
        }
        UserDefaults.standard.setVolatileDomain([
            "customName": "Evidence machine", "colorHex": "#1D9E75", "glyph": "★",
            "useFleetFile": false, "frameEnabled": false, "watermarkEnabled": false,
            "tagEnabled": true, "overlaysEnabled": true, "visibilityModeRaw": "always",
            "tagInfoFields": "", "launchAtLogin": false, "autoUpdateEnabled": false,
        ], forName: UserDefaults.argumentDomain)
        let settings = AppSettings()
        let provider = InfoLineProvider()
        let remote = RemoteViewMonitor()
        let controller = OverlayController(settings: settings, remoteMonitor: remote, infoLineProvider: provider)
        let running = ["com.steipete.nameplate", "com.steipete.nameplate.debug"].flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }.filter { !$0.isHidden }
        running.forEach { _ = $0.hide() }
        defer { running.forEach { _ = $0.unhide() } }
        var backdrops: [NSWindow] = []
        var labels: [NSTextField] = []
        for (index, screen) in screens.enumerated() {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.backgroundColor = NSColor(srgbRed: 0.06, green: 0.08, blue: 0.10, alpha: 1)
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            let label = NSTextField(labelWithString: "")
            label.textColor = .white
            label.font = .systemFont(ofSize: 24, weight: .medium)
            label.alignment = .center
            label.frame = NSRect(x: 40, y: screen.frame.height / 2 - 90, width: screen.frame.width - 80, height: 180)
            window.contentView?.addSubview(label)
            window.orderFrontRegardless()
            backdrops.append(window)
            labels.append(label)
            print("Display \(index + 1): \(screen.frame), scale \(screen.backingScaleFactor)×, virtual \(RemoteViewMonitor.isVirtual(screen: screen))")
        }
        defer { backdrops.forEach { $0.close() } }
        var cases = TagPosition.allCases.map { ($0, 0.0, 0.0) }
        cases += [(.rightCenter, 0, -100), (.rightCenter, 0, 100), (.topCenter, -100, 0), (.bottomRight, 100000, 100000)]
        var rows: [[String: Any]] = []
        for (position, x, y) in cases {
            settings.tagCorner = position
            settings.tagHorizontalOffset = x
            settings.tagVerticalOffset = y
            for (index, screen) in screens.enumerated() {
                let kind = RemoteViewMonitor.isVirtual(screen: screen) ? "virtual" : "physical"
                labels[index].stringValue = "Nameplate runtime evidence\nmacOS \(kind) display \(index + 1) · \(screen.backingScaleFactor)×\n\(position.label) · offsets \(x), \(y)"
            }
            controller.applyVisibility(animated: false)
            self.pump()
            let panels = app.windows.compactMap { $0 as? NSPanel }.filter { $0.contentView is NSHostingView<OverlayView> && $0.isVisible }
            guard panels.count == screens.count, panels.allSatisfy(\.ignoresMouseEvents) else {
                throw NSError(domain: "Evidence", code: 2, userInfo: [NSLocalizedDescriptionKey: "Production overlays were not visible on every screen."])
            }
            for (index, screen) in screens.enumerated() {
                let file = "\(position.rawValue)-\(Int(x))-\(Int(y))-display-\(index + 1).png"
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    throw NSError(domain: "Evidence", code: 3)
                }
                let ids = Set((panels.map(\.windowNumber) + [backdrops[index].windowNumber]).map { CGWindowID($0) })
                let windows = content.windows.filter { ids.contains($0.windowID) }
                let filter = SCContentFilter(display: display, including: windows)
                let config = SCStreamConfiguration()
                config.width = Int(screen.frame.width * screen.backingScaleFactor)
                config.height = Int(screen.frame.height * screen.backingScaleFactor)
                config.showsCursor = false
                config.colorSpaceName = CGColorSpace.sRGB
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let bounds = try verifyTagPixels(image, position: position, x: x, y: y, scale: screen.backingScaleFactor,
                    topSafeAreaInset: screen.safeAreaInsets.top)
                let bitmap = NSBitmapImageRep(cgImage: image)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "Evidence", code: 4) }
                try png.write(to: output.appendingPathComponent(file))
                rows.append([
                    "position": position.rawValue, "horizontalOffset": x, "verticalOffset": y,
                    "display": index + 1, "widthPoints": screen.frame.width, "heightPoints": screen.frame.height,
                    "originX": screen.frame.minX, "originY": screen.frame.minY,
                    "displayID": displayID, "displayName": screen.localizedName,
                    "displayVendor": CGDisplayVendorNumber(displayID), "isVirtual": RemoteViewMonitor.isVirtual(screen: screen),
                    "scale": screen.backingScaleFactor, "topSafeAreaInset": screen.safeAreaInsets.top, "screenshot": file,
                    "productionPanelsVisible": panels.count, "clickThrough": true, "panelLevel": panels[0].level.rawValue,
                    "capture": "ScreenCaptureKit live display composite restricted to evidence backdrop and production panels",
                    "capturedPixelBounds": bounds,
                ])
            }
        }
        // Tear down before returning so the user's desktop is immediately restored.
        app.windows.compactMap { $0 as? NSPanel }.forEach { $0.close() }
        let data = try JSONSerialization.data(withJSONObject: [
            "environment": "macOS displays classified by the production RemoteViewMonitor; production NSPanel controller and SwiftUI overlay; isolated synthetic identity",
            "physicalDisplayCount": physicalCount, "virtualDisplayCount": screens.count - physicalCount,
            "revision": ProcessInfo.processInfo.environment["NAMEPLATE_EVIDENCE_SHA"] ?? "unknown",
            "cases": rows,
        ], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("runtime.json"))
        print("Captured \(rows.count) live production overlay screenshots.")
    }

    private static func pump() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }

    /// Verify the photographed green pill rather than merely asserting that a panel exists.
    private static func verifyTagPixels(_ image: CGImage, position: TagPosition, x: Double, y: Double, scale: Double,
        topSafeAreaInset: Double) throws -> [String: Int] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        var left = width, top = height, right = -1, bottom = -1, count = 0
        try bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                throw NSError(domain: "Evidence", code: 5)
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = buffer.bindMemory(to: UInt8.self)
            for py in 0..<height {
                for px in 0..<width {
                    let i = (py * width + px) * 4
                    // Display color management changes exact RGB values; the green pill
                    // is the only green object in this restricted live composite.
                    let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                    if g > 80 && g > r + 30 && g > b + 20 {
                        left = min(left, px); right = max(right, px)
                        top = min(top, py); bottom = max(bottom, py); count += 1
                    }
                }
            }
        }
        guard count > 100 else { throw NSError(domain: "Evidence", code: 6, userInfo: [NSLocalizedDescriptionKey: "No visible green production tag: \(position.rawValue)"]) }
        let topInset = position == .topCenter ? topSafeAreaInset * scale : 0
        let expected = position.origin(width: Double(width), height: Double(height) - topInset,
            tagWidth: Double(right - left + 1), tagHeight: Double(bottom - top + 1), inset: 10 * scale,
            horizontalOffset: x * scale, verticalOffset: y * scale)
        guard abs(Double(left) - expected.x) <= 3, abs(Double(top) - topInset - expected.y) <= 3 else {
            throw NSError(domain: "Evidence", code: 7, userInfo: [NSLocalizedDescriptionKey: "Incorrect photographed tag position: \(left),\(top) vs \(expected)"])
        }
        return ["left": left, "top": top, "right": right, "bottom": bottom, "greenPixels": count]
    }
}
