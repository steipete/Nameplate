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
        #expect(ColorHex.normalize("ﬀﬀﬀ") == nil)
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

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "attention-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test func roundTripsAndConsumesOnce() throws {
        let url = self.temporaryURL()
        let request = AttentionRequest(
            id: "request-1",
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
        let consumed = try #require(AttentionRequest.consume(from: url))
        #expect(consumed.message == "no timestamp")
        #expect(consumed.createdAt != nil)
    }

    @Test func queuedWritesDoNotOverwriteEachOther() throws {
        let directory = self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))

        try AttentionRequest(message: "first", createdAt: now)
            .writeQueued(to: directory, now: now, uuid: firstID)
        try AttentionRequest(message: "second", createdAt: now)
            .writeQueued(to: directory, now: now.addingTimeInterval(0.001), uuid: secondID)

        let consumed = AttentionRequest.consumeAll(from: directory, legacyURL: nil, now: now)
        #expect(consumed.map(\.message) == ["first", "second"])

        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test func consumeAllDrainsLegacyRequestBeforeQueuedRequests() throws {
        let root = self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "queue", directoryHint: .isDirectory)
        let legacyURL = root.appending(path: "attention.json")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let queuedID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))

        try AttentionRequest(message: "legacy", createdAt: now).write(to: legacyURL)
        try AttentionRequest(message: "queued", createdAt: now)
            .writeQueued(to: directory, now: now, uuid: queuedID)

        let consumed = AttentionRequest.consumeAll(
            from: directory,
            legacyURL: legacyURL,
            now: now)
        #expect(consumed.map(\.message) == ["legacy", "queued"])
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test func dismissalCutoffRoundTrips() throws {
        let url = self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let cutoff = Date(timeIntervalSince1970: 1_800_000_000)

        try AttentionDismissal(createdAt: cutoff).write(to: url)

        #expect(AttentionDismissal.read(from: url)?.createdAt == cutoff)
    }

    @Test func dismissalPreservesRequestsCreatedAfterItsCutoff() throws {
        let root = self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "queue", directoryHint: .isDirectory)
        let legacyURL = root.appending(path: "attention.json")
        let cutoff = Date(timeIntervalSince1970: 1_800_000_000)
        let beforeID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let afterID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))

        try AttentionRequest(message: "legacy", createdAt: cutoff.addingTimeInterval(-1))
            .write(to: legacyURL)
        try AttentionRequest(message: "before", createdAt: cutoff.addingTimeInterval(-1))
            .writeQueued(to: directory, now: cutoff, uuid: beforeID)
        try AttentionRequest(message: "after", createdAt: cutoff.addingTimeInterval(1))
            .writeQueued(to: directory, now: cutoff.addingTimeInterval(1), uuid: afterID)

        AttentionRequest.discardAll(upTo: cutoff, from: directory, legacyURL: legacyURL)

        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
        let remaining = AttentionRequest.consumeAll(from: directory, legacyURL: nil, now: cutoff)
        #expect(remaining.map(\.message) == ["after"])
    }

    @Test func dismissalPreservesLaterUndatedLegacyHandoff() throws {
        let root = self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyURL = root.appending(path: "attention.json")
        let cutoff = Date(timeIntervalSince1970: 1_800_000_000)
        let writtenAfter = cutoff.addingTimeInterval(1)
        try AttentionRequest(message: "legacy after dismissal").write(to: legacyURL)
        try FileManager.default.setAttributes(
            [.modificationDate: writtenAfter],
            ofItemAtPath: legacyURL.path)

        AttentionRequest.discardAll(
            upTo: cutoff,
            from: root.appending(path: "queue"),
            legacyURL: legacyURL)

        let retained = try #require(AttentionRequest.consume(from: legacyURL, now: writtenAfter))
        #expect(retained.message == "legacy after dismissal")
        #expect(retained.createdAt == writtenAfter)
    }

    @Test func decodesRequestsWithoutID() throws {
        let data = Data(#"{"message":"old writer"}"#.utf8)
        let request = try JSONDecoder().decode(AttentionRequest.self, from: data)
        #expect(request.id == nil)
        #expect(request.message == "old writer")
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
