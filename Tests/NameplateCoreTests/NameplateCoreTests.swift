import Foundation
import Testing
@testable import NameplateCore

@Suite("ColorHex")
struct ColorHexTests {
    @Test func normalizesSixDigitHex() {
        #expect(ColorHex.normalize("#1d9e75") == "#1D9E75")
        #expect(ColorHex.normalize("1D9E75") == "#1D9E75")
        #expect(ColorHex.normalize("  #1d9e75\n") == "#1D9E75")
    }

    @Test func expandsThreeDigitHex() {
        #expect(ColorHex.normalize("#3fa") == "#33FFAA")
        #expect(ColorHex.normalize("fff") == "#FFFFFF")
    }

    @Test func rejectsInvalidInput() {
        #expect(ColorHex.normalize("") == nil)
        #expect(ColorHex.normalize("#12345") == nil)
        #expect(ColorHex.normalize("nope") == nil)
        #expect(ColorHex.normalize("#GGGGGG") == nil)
        #expect(ColorHex.normalize("ＦＦＦ") == nil)
    }

    @Test func parsesComponents() throws {
        let rgb = try #require(ColorHex.components("#FF8000"))
        #expect(abs(rgb.red - 1.0) < 0.001)
        #expect(abs(rgb.green - 0x80 / 255.0) < 0.001)
        #expect(abs(rgb.blue) < 0.001)
    }

    @Test func picksReadableTextColor() {
        #expect(ColorHex.prefersDarkText(on: "#FFFFFF"))
        #expect(ColorHex.prefersDarkText(on: "#EF9F27"))
        #expect(!ColorHex.prefersDarkText(on: "#000000"))
        #expect(!ColorHex.prefersDarkText(on: "#0C447C"))
    }
}

@Suite("Palette")
struct PaletteTests {
    @Test func defaultColorIsStablePerHost() {
        let first = NameplatePalette.defaultColor(forHost: "megaclaw.local")
        let second = NameplatePalette.defaultColor(forHost: "MEGACLAW.fritz.box")
        #expect(first == second)
    }

    @Test func differentHostsSpreadAcrossPalette() {
        let hosts = ["megaclaw", "clawmac", "studio-1", "macbook-air", "buildbox", "peters-imac"]
        let colors = Set(hosts.map { NameplatePalette.defaultColor(forHost: $0).hex })
        #expect(colors.count >= 3)
    }
}

@Suite("Hostnames")
struct HostnamesTests {
    @Test func shortensToFirstLabel() {
        #expect(Hostnames.short("Megaclaw.local") == "megaclaw")
        #expect(Hostnames.short("studio-1.fritz.box") == "studio-1")
        #expect(Hostnames.short("plain") == "plain")
        #expect(Hostnames.short("") == "")
    }
}

@Suite("MacIdentity")
struct MacIdentityTests {
    @Test func sanitizesColorOnInit() {
        let identity = MacIdentity(name: "test", colorHex: "not-a-color")
        #expect(identity.colorHex == NameplatePalette.fallback.hex)
        let valid = MacIdentity(name: "test", colorHex: "#1d9e75")
        #expect(valid.colorHex == "#1D9E75")
    }
}

@Suite("RemoteViewing")
struct RemoteViewingTests {
    @Test func classifiesJumpDesktopDisplay() {
        // Real values captured from a Jump Desktop virtual display.
        #expect(RemoteViewing.isVirtualDisplay(
            name: "Jump Desktop Display 1", vendorNumber: 0x7035_7379, isBuiltin: false))
        #expect(RemoteViewing.isVirtualDisplay(
            name: "Some Display", vendorNumber: 0x7035_7379, isBuiltin: false))
        #expect(RemoteViewing.isVirtualDisplay(
            name: "Jump Desktop Display 2", vendorNumber: 0, isBuiltin: false))
    }

    @Test func classifiesPhysicalDisplays() {
        #expect(!RemoteViewing.isVirtualDisplay(
            name: "Built-in Retina Display", vendorNumber: 0x610, isBuiltin: true))
        #expect(!RemoteViewing.isVirtualDisplay(
            name: "LG UltraFine", vendorNumber: 0x1E6D, isBuiltin: false))
        // Builtin wins even with a marker-like name.
        #expect(!RemoteViewing.isVirtualDisplay(
            name: "Virtual Display", vendorNumber: 0x610, isBuiltin: true))
    }

    @Test func detectsEstablishedScreenSharing() {
        let active = """
        Active Internet connections (including servers)
        Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)
        tcp4       0      0  192.168.0.10.5900      192.168.0.20.53211     ESTABLISHED
        tcp4       0      0  *.5900                 *.*                    LISTEN
        """
        #expect(RemoteViewing.hasEstablishedScreenSharing(netstatOutput: active))

        let listenOnly = """
        tcp4       0      0  *.5900                 *.*                    LISTEN
        tcp4       0      0  192.168.0.10.59001     1.2.3.4.443            ESTABLISHED
        tcp4       0      0  192.168.0.10.5900      1.2.3.4.53211          TIME_WAIT
        """
        #expect(!RemoteViewing.hasEstablishedScreenSharing(netstatOutput: listenOnly))
    }
}

@Suite("AttentionRequest")
struct AttentionRequestTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "attention-\(UUID().uuidString).json")
    }

    @Test func roundTripsAndConsumesOnce() throws {
        let url = self.temporaryURL()
        let request = AttentionRequest(
            title: "Codex → 1Password",
            message: "Need approval",
            duration: 8,
            color: "#1D9E75",
            createdAt: Date())
        try request.write(to: url)
        #expect(AttentionRequest.consume(from: url) == request)
        #expect(AttentionRequest.consume(from: url) == nil)
    }

    @Test func dropsStaleRequests() throws {
        let url = self.temporaryURL()
        let request = AttentionRequest(message: "old news", createdAt: Date(timeIntervalSinceNow: -600))
        try request.write(to: url)
        #expect(AttentionRequest.consume(from: url) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func dropsFutureDatedRequests() throws {
        let url = self.temporaryURL()
        let now = Date()
        let request = AttentionRequest(message: "not yet", createdAt: now.addingTimeInterval(600))
        try request.write(to: url)
        #expect(AttentionRequest.consume(from: url, now: now) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func keepsUndatedRequests() throws {
        let url = self.temporaryURL()
        try AttentionRequest(message: "no timestamp").write(to: url)
        #expect(AttentionRequest.consume(from: url)?.message == "no timestamp")
    }
}

@Suite("FleetFile")
struct FleetFileTests {
    @Test func parsesAndNormalizesKeys() throws {
        let json = """
        {
          "Megaclaw.local": { "name": "MEGACLAW", "color": "#1D9E75", "glyph": "🦞", "location": "Phoenix" },
          "clawmac": { "color": "#E24B30" }
        }
        """
        let entries = try FleetFile.parse(Data(json.utf8))
        #expect(entries.count == 2)
        #expect(FleetFile.entry(in: entries, forHost: "megaclaw.fritz.box")?.name == "MEGACLAW")
        #expect(FleetFile.entry(in: entries, forHost: "megaclaw.local")?.location == "Phoenix")
        #expect(FleetFile.entry(in: entries, forHost: "CLAWMAC")?.color == "#E24B30")
        #expect(FleetFile.entry(in: entries, forHost: "CLAWMAC")?.name == nil)
        #expect(FleetFile.entry(in: entries, forHost: "CLAWMAC")?.location == nil)
        #expect(FleetFile.entry(in: entries, forHost: "unknown") == nil)
    }

    @Test func rejectsMalformedJSON() {
        #expect(throws: (any Error).self) {
            try FleetFile.parse(Data("[1, 2, 3]".utf8))
        }
    }
}
