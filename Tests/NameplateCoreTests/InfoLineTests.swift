import Testing
@testable import NameplateCore

@Suite("InfoLineFormatter")
struct InfoLineFormatterTests {
    @Test func formatsIPAddressAndInterface() {
        #expect(InfoLineFormatter.ipAddress("192.168.0.10", interface: "en0") == "192.168.0.10 · en0")
        #expect(InfoLineFormatter.ipAddress("2001:db8::1", interface: nil) == "2001:db8::1")
    }

    @Test func omitsMissingIPAddress() {
        #expect(InfoLineFormatter.ipAddress(nil, interface: "en0") == nil)
        #expect(InfoLineFormatter.ipAddress("  ", interface: "en0") == nil)
    }

    @Test func formatsCompactUptime() {
        #expect(InfoLineFormatter.uptime(seconds: 3 * 86400 + 4 * 3600 + 59 * 60) == "3d 4h")
        #expect(InfoLineFormatter.uptime(seconds: 4 * 3600 + 5 * 60) == "4h 5m")
        #expect(InfoLineFormatter.uptime(seconds: 59) == "0m")
        #expect(InfoLineFormatter.uptime(seconds: -1) == nil)
        #expect(InfoLineFormatter.uptime(seconds: nil) == nil)
    }

    @Test func formatsOSVersion() {
        #expect(InfoLineFormatter.osVersion(major: 26, minor: 0, patch: 0) == "macOS 26.0")
        #expect(InfoLineFormatter.osVersion(major: 15, minor: 6, patch: 1) == "macOS 15.6.1")
    }

    @Test func trimsAndOmitsLocation() {
        #expect(InfoLineFormatter.location("  Phoenix \n") == "Phoenix")
        #expect(InfoLineFormatter.location("") == nil)
        #expect(InfoLineFormatter.location(nil) == nil)
    }

    @Test func fieldsHaveStableDisplayOrder() {
        #expect(InfoLineField.allCases == [.ipAddress, .uptime, .osVersion, .location])
    }
}
