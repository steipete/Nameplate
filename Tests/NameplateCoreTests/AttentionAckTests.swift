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
        let first = AttentionAck(id: "request-1", outcome: .superseded)
        let second = AttentionAck(id: "request-2", outcome: .clicked)
        try first.write(to: url)
        try second.write(to: url)

        let firstURL = AttentionAck.handoffURL(matching: first.id, from: url)
        let secondURL = AttentionAck.handoffURL(matching: second.id, from: url)
        #expect(firstURL != secondURL)
        #expect(FileManager.default.fileExists(atPath: firstURL.path))
        #expect(FileManager.default.fileExists(atPath: secondURL.path))
        #expect(AttentionAck.consume(matching: first.id, from: url) == first)
        #expect(AttentionAck.consume(matching: second.id, from: url) == second)
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
        let ackURL = AttentionAck.handoffURL(matching: ack.id, from: url)
        #expect(!FileManager.default.fileExists(atPath: ackURL.path))
    }
}
