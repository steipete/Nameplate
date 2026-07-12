import Foundation

public enum InfoLineField: String, CaseIterable, Codable, Sendable, Identifiable {
    case ipAddress
    case uptime
    case osVersion
    case location

    public var id: String { self.rawValue }

    public var label: String {
        switch self {
        case .ipAddress: "IP address"
        case .uptime: "Uptime"
        case .osVersion: "macOS version"
        case .location: "Location"
        }
    }
}

/// Pure formatting for the compact secondary lines shown in the name tag.
public enum InfoLineFormatter {
    public static func ipAddress(_ address: String?, interface: String?) -> String? {
        guard let address = self.trimmed(address) else { return nil }
        guard let interface = self.trimmed(interface) else { return address }
        return "\(address) · \(interface)"
    }

    public static func uptime(seconds: Int?) -> String? {
        guard let seconds, seconds >= 0 else { return nil }
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    public static func osVersion(major: Int, minor: Int, patch: Int) -> String {
        let patchSuffix = patch > 0 ? ".\(patch)" : ""
        return "macOS \(major).\(minor)\(patchSuffix)"
    }

    public static func location(_ location: String?) -> String? {
        self.trimmed(location)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
