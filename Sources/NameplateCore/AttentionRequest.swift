import Foundation

/// A request from the CLI (or any script) to grab the human's attention:
/// a topmost message card plus pulsating screen borders. Written as a queued
/// JSON handoff, announced via the Darwin notification
/// `com.steipete.nameplate.attention`.
public struct AttentionRequest: Codable, Equatable, Sendable {
    public var title: String?
    public var message: String
    /// Seconds the alert stays up without interaction. Nil stays until dismissed.
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

    public static var handoffDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Nameplate/AttentionRequests")
    }

    public static var legacyHandoffURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Nameplate/attention.json")
    }

    public static func handoffURL(
        in directory: URL = handoffDirectory,
        now: Date = Date(),
        uuid: UUID = UUID()) -> URL
    {
        let microseconds = Int64((now.timeIntervalSince1970 * 1_000_000).rounded())
        return directory.appending(path: "attention-\(microseconds)-\(uuid.uuidString).json")
    }

    public func write() throws {
        try self.writeQueued()
    }

    public func writeQueued(
        to directory: URL = handoffDirectory,
        now: Date = Date(),
        uuid: UUID = UUID()) throws
    {
        try self.write(to: Self.handoffURL(in: directory, now: now, uuid: uuid))
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    public func isFresh(at now: Date = Date()) -> Bool {
        guard let createdAt else { return true }
        return abs(now.timeIntervalSince(createdAt)) <= Self.maxAge
    }

    public func wasCreated(after cutoff: Date) -> Bool {
        self.createdAt.map { $0 > cutoff } ?? false
    }

    /// Reads and removes the pending request (one-shot handoff). Stale
    /// requests are consumed but not returned.
    public static func consume(from url: URL = legacyHandoffURL, now: Date = Date()) -> AttentionRequest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        guard let request = try? JSONDecoder().decode(AttentionRequest.self, from: data) else { return nil }
        guard request.isFresh(at: now) else { return nil }
        return request
    }

    public static func consumeAll(
        from directory: URL = handoffDirectory,
        legacyURL: URL? = legacyHandoffURL,
        now: Date = Date()) -> [AttentionRequest]
    {
        var requests: [AttentionRequest] = []
        if let legacyURL, let request = self.consume(from: legacyURL, now: now) {
            requests.append(request)
        }

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil)) ?? []
        let queued = urls
            .filter {
                $0.pathExtension == "json"
                    && $0.lastPathComponent.hasPrefix("attention-")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for url in queued {
            if let request = self.consume(from: url, now: now) {
                requests.append(request)
            }
        }
        return requests
    }

    public static func discardAll(
        upTo cutoff: Date,
        from directory: URL = AttentionRequest.handoffDirectory,
        legacyURL: URL? = AttentionRequest.legacyHandoffURL)
    {
        if let legacyURL {
            self.discard(from: legacyURL, upTo: cutoff)
        }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.pathExtension == "json"
            && url.lastPathComponent.hasPrefix("attention-")
        {
            self.discard(from: url, upTo: cutoff)
        }
    }

    private static func discard(from url: URL, upTo cutoff: Date) {
        guard let data = try? Data(contentsOf: url) else { return }
        if let request = try? JSONDecoder().decode(AttentionRequest.self, from: data),
           request.wasCreated(after: cutoff)
        {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }
}

public struct AttentionDismissal: Codable, Sendable {
    public var createdAt: Date

    public static let notificationName = "com.steipete.nameplate.attention.dismiss.cutoff"

    public init(createdAt: Date) {
        self.createdAt = createdAt
    }

    public static var handoffURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Nameplate/attention-dismissal.json")
    }

    public func write(to url: URL = Self.handoffURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    public static func read(from url: URL = Self.handoffURL) -> AttentionDismissal? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AttentionDismissal.self, from: data)
    }
}
