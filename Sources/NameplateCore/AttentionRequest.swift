import Foundation

/// A request from the CLI (or any script) to grab the human's attention:
/// a topmost message card plus pulsating screen borders. Written as JSON to
/// the handoff file, announced via the Darwin notification
/// `com.steipete.nameplate.attention`.
public struct AttentionRequest: Codable, Equatable, Sendable {
    public var title: String?
    public var message: String
    /// Seconds the alert stays up without interaction. Defaults to 10.
    public var duration: Double?
    /// Optional hex border color; defaults to the Mac's identity color.
    public var color: String?
    /// Written by the sender; requests older than `maxAge` are ignored so a
    /// login-time launch does not replay an hours-old alert.
    public var createdAt: Date?

    public init(
        title: String? = nil,
        message: String,
        duration: Double? = nil,
        color: String? = nil,
        createdAt: Date? = nil)
    {
        self.title = title
        self.message = message
        self.duration = duration
        self.color = color
        self.createdAt = createdAt
    }

    public static let maxAge: TimeInterval = 120

    public static let notificationName = "com.steipete.nameplate.attention"

    public static var handoffURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Nameplate/attention.json")
    }

    public func write(to url: URL = handoffURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// Reads and removes the pending request (one-shot handoff). Stale
    /// requests are consumed but not returned.
    public static func consume(from url: URL = handoffURL, now: Date = Date()) -> AttentionRequest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        guard let request = try? JSONDecoder().decode(AttentionRequest.self, from: data) else { return nil }
        if let createdAt = request.createdAt, abs(now.timeIntervalSince(createdAt)) > self.maxAge {
            return nil
        }
        return request
    }
}
