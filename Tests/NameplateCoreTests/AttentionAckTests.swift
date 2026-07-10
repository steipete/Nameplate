import Foundation
import Testing
@testable import NameplateCore

@Suite("AttentionAck")
struct AttentionAckTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "attention-ack-\(UUID().uuidString).json")
    }

    @Test func roundTripsAndConsumesOnce() throws {
        let url = self.temporaryURL()
        let ack = AttentionAck(id: "request-1", outcome: .clicked, at: Date())
        try ack.write(to: url)
        #expect(AttentionAck.consume(matching: ack.id, from: url) == ack)
        #expect(AttentionAck.consume(matching: ack.id, from: url) == nil)
    }

    @Test func onlyConsumesMatchingID() throws {
        let url = self.temporaryURL()
        let ack = AttentionAck(id: "request-1", outcome: .superseded)
        try ack.write(to: url)
        #expect(AttentionAck.consume(matching: "request-2", from: url) == nil)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(AttentionAck.consume(matching: ack.id, from: url) == ack)
    }

    @Test func dropsStaleAcks() throws {
        let url = self.temporaryURL()
        let now = Date()
        let ack = AttentionAck(
            id: "request-1",
            outcome: .autoDismissed,
            at: now.addingTimeInterval(-AttentionAck.maxAge - 1))
        try ack.write(to: url)
        #expect(AttentionAck.consume(matching: ack.id, from: url, now: now) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
