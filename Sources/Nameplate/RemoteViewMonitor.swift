import AppKit
import NameplateCore

/// Feeds the "only when viewed remotely" decoration mode: per-screen virtual
/// display classification plus a low-frequency poll for active Screen
/// Sharing / remote-desktop connections. Polling only runs while the mode needs it.
@MainActor
final class RemoteViewMonitor {
    var onChange: (() -> Void)?
    private(set) var screenSharingActive = false
    private var timer: Timer?
    private var pollGeneration = 0

    static func isVirtual(screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return false }
        let displayID = CGDirectDisplayID(number.uint32Value)
        return RemoteViewing.isVirtualDisplay(
            name: screen.localizedName,
            vendorNumber: CGDisplayVendorNumber(displayID),
            isBuiltin: CGDisplayIsBuiltin(displayID) != 0)
    }

    static func anyVirtualScreen() -> Bool {
        NSScreen.screens.contains { self.isVirtual(screen: $0) }
    }

    func setPollingEnabled(_ enabled: Bool) {
        if enabled {
            guard self.timer == nil else { return }
            let timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.poll()
                }
            }
            timer.tolerance = 1
            self.timer = timer
            self.poll()
        } else {
            self.timer?.invalidate()
            self.timer = nil
            if self.screenSharingActive {
                self.screenSharingActive = false
                self.onChange?()
            }
        }
    }

    private func poll() {
        self.pollGeneration += 1
        let generation = self.pollGeneration
        Task.detached(priority: .utility) {
            let active = Self.checkScreenSharing()
            await MainActor.run { [weak self] in
                guard let self, self.pollGeneration == generation, self.timer != nil else { return }
                if active != self.screenSharingActive {
                    self.screenSharingActive = active
                    self.onChange?()
                }
            }
        }
    }

    /// screensharingd only runs while Apple Screen Sharing is in use
    /// (launchd socket activation); netstat catches generic VNC clients plus
    /// vendor-specific TeamViewer/AnyDesk connections while their client runs.
    nonisolated private static func checkScreenSharing() -> Bool {
        if self.runTool("/usr/bin/pgrep", ["-x", "screensharingd"]) != nil {
            return true
        }
        guard let netstat = self.runTool("/usr/sbin/netstat", ["-an", "-p", "tcp"]) else {
            return false
        }
        let remoteProcesses = self.runTool(
            "/usr/bin/pgrep", ["-ifl", "teamviewer|anydesk"]) ?? ""
        return RemoteViewing.hasEstablishedRemoteDesktop(
            netstatOutput: netstat,
            processList: remoteProcesses)
    }

    /// Returns stdout on exit 0, nil otherwise.
    nonisolated private static func runTool(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
