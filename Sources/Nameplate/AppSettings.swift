import Combine
import NameplateCore
import ServiceManagement
import SwiftUI
import SystemConfiguration

enum DecorationVisibility: String, CaseIterable, Identifiable {
    case always
    case remoteOnly

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .always: "Always"
        case .remoteOnly: "Only when viewed remotely"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    // Identity — empty string means "derive from hostname".
    @AppStorage("customName") var customName: String = ""
    @AppStorage("colorHex") var colorHex: String = ""
    @AppStorage("glyph") var glyph: String = ""
    @AppStorage("customLocation") var customLocation: String = ""

    // Master switch, mirrored as the top toggle in the menu.
    @AppStorage("overlaysEnabled") var overlaysEnabled: Bool = true

    // "Always" or only when this Mac is being viewed remotely (virtual
    // display present or Screen Sharing/VNC connected). Gates all decoration;
    // attention alerts always show.
    @AppStorage("visibilityModeRaw") private var visibilityModeRaw: String = DecorationVisibility.always.rawValue

    var visibilityMode: DecorationVisibility {
        get { DecorationVisibility(rawValue: self.visibilityModeRaw) ?? .always }
        set { self.visibilityModeRaw = newValue.rawValue }
    }

    // Frame layer.
    @AppStorage("frameEnabled") var frameEnabled: Bool = true
    @AppStorage("frameThickness") var frameThickness: Double = 4
    @AppStorage("frameOpacity") var frameOpacity: Double = 1.0
    // Modern Mac displays have rounded corners; a square frame looks clipped.
    // Per-corner control: default rounds only the bottom, where nothing else
    // competes with the border (menu bar owns the top).
    @AppStorage("frameCornerRadius") var frameCornerRadius: Double = 16
    @AppStorage("frameRoundTopLeft") var frameRoundTopLeft: Bool = false
    @AppStorage("frameRoundTopRight") var frameRoundTopRight: Bool = false
    @AppStorage("frameRoundBottomLeft") var frameRoundBottomLeft: Bool = true
    @AppStorage("frameRoundBottomRight") var frameRoundBottomRight: Bool = true

    // Name tag layer.
    @AppStorage("tagEnabled") var tagEnabled: Bool = true
    @AppStorage("tagCornerRaw") private var tagCornerRaw: String = ScreenCorner.bottomLeft.rawValue
    @AppStorage("tagShowsGlyph") var tagShowsGlyph: Bool = true

    // Watermark layer.
    @AppStorage("watermarkEnabled") var watermarkEnabled: Bool = false
    @AppStorage("watermarkCornerRaw") private var watermarkCornerRaw: String = ScreenCorner.bottomRight.rawValue
    @AppStorage("watermarkOpacity") var watermarkOpacity: Double = 0.12

    // Connect splash.
    @AppStorage("splashEnabled") var splashEnabled: Bool = true
    @AppStorage("splashOnWake") var splashOnWake: Bool = true
    @AppStorage("splashOnUnlock") var splashOnUnlock: Bool = true
    @AppStorage("splashOnDisplayChange") var splashOnDisplayChange: Bool = true
    @AppStorage("splashDuration") var splashDuration: Double = 1.8

    // App behavior.
    @AppStorage("autoUpdateEnabled") var autoUpdateEnabled: Bool = true
    @AppStorage("showNameInMenuBar") var showNameInMenuBar: Bool = true
    @AppStorage("hideMenuBarIcon") var hideMenuBarIcon: Bool = false
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false {
        didSet { LaunchAtLoginManager.setEnabled(self.launchAtLogin) }
    }

    // Fleet file (~/.config/nameplate/fleet.json), synced via dotfiles.
    @AppStorage("useFleetFile") var useFleetFile: Bool = true

    @Published private(set) var fleetEntry: FleetEntry?
    @Published private(set) var fleetFileExists: Bool = false

    private var fleetWatcher: FleetFileWatcher?

    init() {
        LaunchAtLoginManager.syncRegistration(desired: self.launchAtLogin)
        self.reloadFleetEntry()
        self.fleetWatcher = FleetFileWatcher(url: FleetFile.defaultPath) { [weak self] in
            self?.reloadFleetEntry()
        }
    }

    var tagCorner: ScreenCorner {
        get { ScreenCorner(rawValue: self.tagCornerRaw) ?? .bottomLeft }
        set { self.tagCornerRaw = newValue.rawValue }
    }

    var watermarkCorner: ScreenCorner {
        get { ScreenCorner(rawValue: self.watermarkCornerRaw) ?? .bottomRight }
        set { self.watermarkCornerRaw = newValue.rawValue }
    }

    var hostName: String {
        Hostnames.current()
    }

    var defaultName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? Hostnames.short(self.hostName)
    }

    /// Fleet file (when enabled and matching) > local settings > hostname defaults.
    var identity: MacIdentity {
        let fleet = self.useFleetFile ? self.fleetEntry : nil
        let trimmedName = self.customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = fleet?.name ?? (trimmedName.isEmpty ? self.defaultName : trimmedName)
        let hexSource = fleet?.color ?? self.colorHex
        let hex = ColorHex.normalize(hexSource)
            ?? NameplatePalette.defaultColor(forHost: self.hostName).hex
        let glyph = fleet?.glyph ?? self.glyph.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = fleet?.location ?? self.customLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        return MacIdentity(name: name, colorHex: hex, glyph: glyph, location: location)
    }

    var identityIsFleetManaged: Bool {
        self.useFleetFile && self.fleetEntry != nil
    }

    func reloadFleetEntry() {
        let url = FleetFile.defaultPath
        self.fleetFileExists = FileManager.default.fileExists(atPath: url.path)
        self.fleetEntry = FleetFile.load(from: url, forHost: self.hostName)
    }
}

extension MacIdentity {
    var color: Color {
        guard let rgb = ColorHex.components(self.colorHex) else { return .accentColor }
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    var nsColor: NSColor {
        guard let rgb = ColorHex.components(self.colorHex) else { return .controlAccentColor }
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    /// Readable text color on top of the identity color.
    var textOnColor: Color {
        ColorHex.prefersDarkText(on: self.colorHex) ? .black : .white
    }
}

enum LaunchAtLoginManager {
    @MainActor
    static func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            NSLog("Nameplate: launch-at-login change failed: \(error)")
        }
    }

    /// Re-align actual registration with the saved preference at startup
    /// (the user can flip it behind our back in System Settings).
    @MainActor
    static func syncRegistration(desired: Bool) {
        let service = SMAppService.mainApp
        let registered = service.status == .enabled
        guard registered != desired else { return }
        self.setEnabled(desired)
    }
}

/// Watches the fleet file (and keeps watching across replace-writes, which is
/// how editors and `mv`-based syncs update it).
@MainActor
final class FleetFileWatcher {
    private let url: URL
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var rearmTimer: Timer?

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
        self.arm()
    }

    deinit {
        self.source?.cancel()
    }

    @discardableResult
    private func arm() -> Bool {
        self.source?.cancel()
        self.source = nil

        let descriptor = open(self.url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // File absent — retry occasionally so dropping the file in later "just works".
            self.scheduleRearm(after: 15)
            return false
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onChange()
                let events = self.source?.data ?? []
                if events.contains(.delete) || events.contains(.rename) {
                    self.scheduleRearm(after: 0.5)
                }
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
        return true
    }

    private func scheduleRearm(after delay: TimeInterval) {
        self.rearmTimer?.invalidate()
        self.rearmTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.arm() {
                    self.onChange()
                }
            }
        }
    }
}
