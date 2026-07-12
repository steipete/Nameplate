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

    @Test func writingAckPrunesOldAckFiles() throws {
        let url = self.temporaryURL()
        let now = Date()
        let stale = AttentionAck(id: "stale", outcome: .clicked)
        let fresh = AttentionAck(id: "fresh", outcome: .clicked)
        try stale.write(to: url)

        let staleURL = AttentionAck.handoffURL(matching: stale.id, from: url)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-AttentionAck.maxAge - 1)],
            ofItemAtPath: staleURL.path)
        try fresh.write(to: url)

        let freshURL = AttentionAck.handoffURL(matching: fresh.id, from: url)
        #expect(!FileManager.default.fileExists(atPath: staleURL.path))
        #expect(FileManager.default.fileExists(atPath: freshURL.path))
        AttentionAck.remove(matching: fresh.id, from: url)
    }

    @Test func removesMatchingAckFile() throws {
        let url = self.temporaryURL()
        let ack = AttentionAck(id: "timed-out", outcome: .clicked)
        try ack.write(to: url)
        let ackURL = AttentionAck.handoffURL(matching: ack.id, from: url)

        AttentionAck.remove(matching: ack.id, from: url)

        #expect(!FileManager.default.fileExists(atPath: ackURL.path))
    }

    @Test func encodesRequestIDAsOneSafeFilenameComponent() throws {
        let url = self.temporaryURL()
        let ack = AttentionAck(id: "../nested/request", outcome: .expired)
        let ackURL = AttentionAck.handoffURL(matching: ack.id, from: url)

        #expect(ackURL.deletingLastPathComponent() == url.deletingLastPathComponent())
        #expect(!ackURL.lastPathComponent.contains("/"))
        try ack.write(to: url)
        #expect(AttentionAck.consume(matching: ack.id, from: url) == ack)
    }
}
