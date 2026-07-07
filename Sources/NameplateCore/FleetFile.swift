import Foundation

/// Optional fleet-wide identity config, one JSON file synced via dotfiles:
///
///     {
///       "megaclaw": { "name": "MEGACLAW", "color": "#1D9E75", "glyph": "🦞" },
///       "clawmac":  { "name": "clawmac",  "color": "#E24B30" }
///     }
///
/// Keys are short hostnames (lowercase, first DNS label). All fields optional;
/// anything missing falls back to local settings.
public struct FleetEntry: Codable, Equatable, Sendable {
    public var name: String?
    public var color: String?
    public var glyph: String?
    public var location: String?

    public init(
        name: String? = nil,
        color: String? = nil,
        glyph: String? = nil,
        location: String? = nil)
    {
        self.name = name
        self.color = color
        self.glyph = glyph
        self.location = location
    }
}

public enum FleetFile {
    public static var defaultPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/nameplate/fleet.json")
    }

    public static func parse(_ data: Data) throws -> [String: FleetEntry] {
        let decoded = try JSONDecoder().decode([String: FleetEntry].self, from: data)
        var normalized: [String: FleetEntry] = [:]
        for (key, value) in decoded {
            normalized[Hostnames.short(key)] = value
        }
        return normalized
    }

    public static func entry(in entries: [String: FleetEntry], forHost host: String) -> FleetEntry? {
        entries[Hostnames.short(host)]
    }

    public static func load(from url: URL = defaultPath, forHost host: String) -> FleetEntry? {
        guard let data = try? Data(contentsOf: url),
              let entries = try? parse(data) else { return nil }
        return self.entry(in: entries, forHost: host)
    }
}
