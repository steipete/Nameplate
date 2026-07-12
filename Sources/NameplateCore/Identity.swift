import Foundation

/// The resolved visual identity of this Mac: what every layer (frame, tag,
/// splash, menu bar) renders.
public struct MacIdentity: Equatable, Sendable {
    public var name: String
    public var colorHex: String
    public var glyph: String
    public var location: String

    public init(name: String, colorHex: String, glyph: String = "", location: String = "") {
        self.name = name
        self.colorHex = ColorHex.normalize(colorHex) ?? NameplatePalette.fallback.hex
        self.glyph = glyph
        self.location = location
    }
}

/// Preset accent colors. Every Mac gets a stable default color derived from
/// its hostname so an unconfigured fleet is still tellable-apart.
public struct PaletteColor: Equatable, Sendable, Identifiable {
    public let name: String
    public let hex: String

    public var id: String { self.hex }
}

public enum NameplatePalette {
    public static let colors: [PaletteColor] = [
        PaletteColor(name: "Lobster", hex: "#E24B30"),
        PaletteColor(name: "Amber", hex: "#EF9F27"),
        PaletteColor(name: "Lime", hex: "#8BC34A"),
        PaletteColor(name: "Jade", hex: "#1D9E75"),
        PaletteColor(name: "Cyan", hex: "#22B8CF"),
        PaletteColor(name: "Azure", hex: "#378ADD"),
        PaletteColor(name: "Violet", hex: "#7F77DD"),
        PaletteColor(name: "Magenta", hex: "#D4537E"),
    ]

    public static var fallback: PaletteColor { self.colors[3] }

    /// Stable per-host default color (FNV-1a over the short hostname).
    public static func defaultColor(forHost host: String) -> PaletteColor {
        let normalized = Hostnames.short(host)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return self.colors[Int(hash % UInt64(self.colors.count))]
    }
}

public enum ColorHex {
    /// Normalizes "#3fA" / "3fa" / "#33FFAA" to canonical "#33FFAA".
    /// Returns nil for anything that is not a 3- or 6-digit hex color.
    public static func normalize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.utf8.allSatisfy({ byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }) else { return nil }
        text = text.uppercased()
        switch text.count {
        case 3:
            text = text.map { "\($0)\($0)" }.joined()
        case 6:
            break
        default:
            return nil
        }
        return "#" + text
    }

    /// Parses a normalized hex color into 0...1 sRGB components.
    public static func components(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        guard let normalized = normalize(hex) else { return nil }
        let digits = normalized.dropFirst()
        guard let value = UInt32(digits, radix: 16) else { return nil }
        return (
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0)
    }

    /// Relative luminance (WCAG); used to pick readable text on a colored fill.
    public static func luminance(_ hex: String) -> Double {
        guard let rgb = components(hex) else { return 0 }
        func channel(_ component: Double) -> Double {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.red) + 0.7152 * channel(rgb.green) + 0.0722 * channel(rgb.blue)
    }

    public static func prefersDarkText(on hex: String) -> Bool {
        // 0.4 keeps white text on the saturated mid tones (jade, azure) while
        // amber and lime correctly flip to dark text.
        self.luminance(hex) > 0.4
    }
}

public enum Hostnames {
    /// "Megaclaw.local" / "megaclaw.fritz.box" -> "megaclaw".
    public static func short(_ host: String) -> String {
        let lowered = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = lowered.split(separator: ".").first, !first.isEmpty else { return lowered }
        return String(first)
    }

    /// The local hostname via gethostname(2). Deliberately NOT
    /// ProcessInfo.hostName / Host.current(), which resolve via DNS — that
    /// blocks launch and triggers the macOS local-network permission prompt.
    public static func current() -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard gethostname(&buffer, buffer.count - 1) == 0 else { return "mac" }
        let length = buffer.firstIndex(of: 0) ?? buffer.count
        let name = String(decoding: buffer[..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return name.isEmpty ? "mac" : name
    }
}

/// Screen corner used to anchor the name tag and watermark layers.
public enum ScreenCorner: String, CaseIterable, Codable, Sendable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    public var id: String { self.rawValue }

    public var label: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}
