import Foundation

/// Classifies displays and network state for the "only when viewed remotely"
/// decoration mode. Pure functions — the app layer feeds in NSScreen /
/// netstat data.
public enum RemoteViewing {
    /// Substrings (lowercased) of display names that mark virtual displays
    /// created by remote-desktop and dummy-display tools.
    public static let virtualNameMarkers: [String] = [
        "jump desktop",
        "virtual display",
        "dummy",
        "deskpad",
        "betterdisplay",
        "luna display",
    ]

    /// Display vendor IDs used by virtual displays. Jump Desktop stamps
    /// 0x70357379; CGVirtualDisplay-based tools commonly use "unkn".
    public static let virtualVendorIDs: Set<UInt32> = [
        0x7035_7379, // Jump Desktop
        0x756E_6B6E, // 'unkn' — CGVirtualDisplay default
    ]

    public static func isVirtualDisplay(name: String, vendorNumber: UInt32, isBuiltin: Bool) -> Bool {
        if isBuiltin { return false }
        if self.virtualVendorIDs.contains(vendorNumber) { return true }
        let lowered = name.lowercased()
        return self.virtualNameMarkers.contains { lowered.contains($0) }
    }

    /// True when netstat output shows an ESTABLISHED connection on a VNC /
    /// Screen Sharing port (5900-5901). Matches Apple Screen Sharing,
    /// classic VNC, and Jump Desktop's VNC-compatible listener.
    public static func hasEstablishedScreenSharing(netstatOutput: String) -> Bool {
        self.establishedConnections(netstatOutput: netstatOutput).contains { connection in
            connection.localPort == 5900 || connection.localPort == 5901
        }
    }

    /// Extends Screen Sharing detection with vendor-specific remote-control
    /// ports, but only while the matching client is running. Generic fallback
    /// ports such as 80/443 are intentionally excluded because they would make
    /// an idle client indistinguishable from unrelated network traffic.
    public static func hasEstablishedRemoteDesktop(
        netstatOutput: String,
        processList: String
    ) -> Bool {
        let connections = self.establishedConnections(netstatOutput: netstatOutput)
        if connections.contains(where: { $0.localPort == 5900 || $0.localPort == 5901 }) {
            return true
        }

        let processes = processList.lowercased()
        if processes.contains("teamviewer"), connections.contains(where: { $0.contains(5938) }) {
            return true
        }
        if processes.contains("anydesk"), connections.contains(where: { $0.contains(6568) }) {
            return true
        }
        return false
    }

    private struct ConnectionPorts {
        let localPort: Int?
        let foreignPort: Int?

        func contains(_ port: Int) -> Bool {
            self.localPort == port || self.foreignPort == port
        }
    }

    private static func establishedConnections(netstatOutput: String) -> [ConnectionPorts] {
        var result: [ConnectionPorts] = []
        for line in netstatOutput.split(separator: "\n") {
            guard line.contains("ESTABLISHED") else { continue }
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            // Local/foreign addresses are columns 3/4 in BSD netstat and use
            // ip.port notation, including for IPv6 addresses.
            guard columns.count >= 5 else { continue }
            result.append(ConnectionPorts(
                localPort: self.port(from: columns[3]),
                foreignPort: self.port(from: columns[4])))
        }
        return result
    }

    private static func port(from endpoint: Substring) -> Int? {
        guard let separator = endpoint.lastIndex(of: ".") else { return nil }
        return Int(endpoint[endpoint.index(after: separator)...])
    }
}
