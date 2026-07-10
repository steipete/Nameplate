import Foundation

/// The result of an attention request that asked the app to report when the
/// card's lifecycle ends.
public struct AttentionAck: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Equatable, Sendable {
        case clicked
        case autoDismissed
        case superseded
    }

    public var id: String
    public var outcome: Outcome
    public var at: Date

    public init(id: String, outcome: Outcome, at: Date = Date()) {
        self.id = id
        self.outcome = outcome
        self.at = at
    }

    public static let maxAge: TimeInterval = 120

    public static let notificationName = "com.steipete.nameplate.attention.ack"

    public static var handoffURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Nameplate/attention-ack.json")
    }

    public func write(to url: URL = handoffURL) throws {
        let url = Self.handoffURL(matching: self.id, from: url)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// Reads and removes this waiter's acknowledgment file. Stale matching
    /// acknowledgments are consumed.
    public static func consume(
        matching id: String,
        from url: URL = handoffURL,
        now: Date = Date()) -> AttentionAck?
    {
        let url = self.handoffURL(matching: id, from: url)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let ack = try? JSONDecoder().decode(AttentionAck.self, from: data) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        guard ack.id == id else { return nil }
        try? FileManager.default.removeItem(at: url)
        guard abs(now.timeIntervalSince(ack.at)) <= self.maxAge else { return nil }
        return ack
    }

    static func handoffURL(matching id: String, from url: URL = handoffURL) -> URL {
        let basename = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent()
            .appending(path: "\(basename)-\(id).json")
    }
}
