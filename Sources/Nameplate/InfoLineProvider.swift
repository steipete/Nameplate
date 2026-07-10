import Combine
import Foundation
import NameplateCore

/// Samples the values shown below the name. Polling exists only while at
/// least one info field is enabled.
@MainActor
final class InfoLineProvider: ObservableObject {
    @Published private(set) var lines: [String] = []

    private var fields: Set<InfoLineField> = []
    private var location = ""
    private var timer: Timer?

    func configure(fields: Set<InfoLineField>, location: String) {
        let changed = fields != self.fields || location != self.location
        self.fields = fields
        self.location = location

        guard !fields.isEmpty else {
            self.stopPolling()
            return
        }
        let startsPolling = self.timer == nil
        if self.timer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sample()
                }
            }
            timer.tolerance = 10
            self.timer = timer
        }
        if changed || startsPolling {
            self.sample()
        }
    }

    private func stopPolling() {
        self.timer?.invalidate()
        self.timer = nil
        if !self.lines.isEmpty {
            self.lines = []
        }
    }

    private func sample() {
        let ip = self.fields.contains(.ipAddress) ? SystemInfo.primaryIPAddress() : nil
        let uptime = self.fields.contains(.uptime) ? SystemInfo.uptimeSeconds() : nil
        let version = ProcessInfo.processInfo.operatingSystemVersion

        self.lines = InfoLineField.allCases.compactMap { field in
            guard self.fields.contains(field) else { return nil }
            switch field {
            case .ipAddress:
                return InfoLineFormatter.ipAddress(ip?.address, interface: ip?.interface)
            case .uptime:
                return InfoLineFormatter.uptime(seconds: uptime)
            case .osVersion:
                return InfoLineFormatter.osVersion(
                    major: version.majorVersion,
                    minor: version.minorVersion,
                    patch: version.patchVersion)
            case .location:
                return InfoLineFormatter.location(self.location)
            }
        }
    }
}
