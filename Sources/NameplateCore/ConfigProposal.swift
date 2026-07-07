import Foundation

/// Settings proposed by a `nameplate://config` link. Every field remains
/// optional so links can update only the values they carry.
public struct ConfigProposal: Equatable, Sendable {
    public var name: String?
    public var glyph: String?
    public var colorHex: String?
    public var frameThickness: Double?
    public var frameOpacity: Double?
    public var cornerRadius: Double?
    public var roundTopLeft: Bool?
    public var roundTopRight: Bool?
    public var roundBottomLeft: Bool?
    public var roundBottomRight: Bool?
    public var tagCorner: ScreenCorner?
    public var watermarkOpacity: Double?
    public var frameEnabled: Bool?
    public var tagEnabled: Bool?
    public var watermarkEnabled: Bool?
    public var splashDuration: Double?

    public init?(url: URL) {
        self.name = nil
        self.glyph = nil
        self.colorHex = nil
        self.frameThickness = nil
        self.frameOpacity = nil
        self.cornerRadius = nil
        self.roundTopLeft = nil
        self.roundTopRight = nil
        self.roundBottomLeft = nil
        self.roundBottomRight = nil
        self.tagCorner = nil
        self.watermarkOpacity = nil
        self.frameEnabled = nil
        self.tagEnabled = nil
        self.watermarkEnabled = nil
        self.splashDuration = nil

        guard url.scheme?.lowercased() == "nameplate", url.host()?.lowercased() == "config",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        var recognizedParameter = false
        for item in components.queryItems ?? [] {
            guard let value = item.value else { continue }
            switch item.name {
            case "name":
                recognizedParameter = true
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                self.name = String(trimmed.prefix(64))
            case "glyph":
                recognizedParameter = true
                self.glyph = String(value.prefix(4))
            case "color":
                recognizedParameter = true
                self.colorHex = ColorHex.normalize(value)
            case "frameThickness":
                recognizedParameter = true
                self.frameThickness = Self.number(value, clampedTo: 1...20)
            case "frameOpacity":
                recognizedParameter = true
                self.frameOpacity = Self.number(value, clampedTo: 0.1...1)
            case "cornerRadius":
                recognizedParameter = true
                self.cornerRadius = Self.number(value, clampedTo: 0...60)
            case "roundTopLeft":
                recognizedParameter = true
                self.roundTopLeft = Self.boolean(value)
            case "roundTopRight":
                recognizedParameter = true
                self.roundTopRight = Self.boolean(value)
            case "roundBottomLeft":
                recognizedParameter = true
                self.roundBottomLeft = Self.boolean(value)
            case "roundBottomRight":
                recognizedParameter = true
                self.roundBottomRight = Self.boolean(value)
            case "tagCorner":
                recognizedParameter = true
                self.tagCorner = ScreenCorner(rawValue: value)
            case "watermarkOpacity":
                recognizedParameter = true
                self.watermarkOpacity = Self.number(value, clampedTo: 0...0.3)
            case "frameEnabled":
                recognizedParameter = true
                self.frameEnabled = Self.boolean(value)
            case "tagEnabled":
                recognizedParameter = true
                self.tagEnabled = Self.boolean(value)
            case "watermarkEnabled":
                recognizedParameter = true
                self.watermarkEnabled = Self.boolean(value)
            case "splashDuration":
                recognizedParameter = true
                self.splashDuration = Self.number(value, clampedTo: 0.5...10)
            default:
                break
            }
        }
        guard recognizedParameter else { return nil }
    }

    public var isEmpty: Bool {
        self.name == nil && self.glyph == nil && self.colorHex == nil
            && self.frameThickness == nil && self.frameOpacity == nil && self.cornerRadius == nil
            && self.roundTopLeft == nil && self.roundTopRight == nil
            && self.roundBottomLeft == nil && self.roundBottomRight == nil
            && self.tagCorner == nil && self.watermarkOpacity == nil
            && self.frameEnabled == nil && self.tagEnabled == nil && self.watermarkEnabled == nil
            && self.splashDuration == nil
    }

    public var summaryItems: [(label: String, value: String)] {
        var items: [(label: String, value: String)] = []
        if let name { items.append(("Name", name)) }
        if let glyph { items.append(("Glyph", glyph)) }
        if let colorHex { items.append(("Color", colorHex)) }
        if let frameThickness {
            items.append(("Frame thickness", Self.numberSummary(frameThickness)))
        }
        if let frameOpacity { items.append(("Frame opacity", Self.numberSummary(frameOpacity))) }
        if let cornerRadius { items.append(("Corner radius", Self.numberSummary(cornerRadius))) }
        if let roundTopLeft { items.append(("Round top left", Self.booleanSummary(roundTopLeft))) }
        if let roundTopRight { items.append(("Round top right", Self.booleanSummary(roundTopRight))) }
        if let roundBottomLeft {
            items.append(("Round bottom left", Self.booleanSummary(roundBottomLeft)))
        }
        if let roundBottomRight {
            items.append(("Round bottom right", Self.booleanSummary(roundBottomRight)))
        }
        if let tagCorner { items.append(("Tag corner", tagCorner.label)) }
        if let watermarkOpacity {
            items.append(("Watermark opacity", Self.numberSummary(watermarkOpacity)))
        }
        if let frameEnabled { items.append(("Frame enabled", Self.booleanSummary(frameEnabled))) }
        if let tagEnabled { items.append(("Tag enabled", Self.booleanSummary(tagEnabled))) }
        if let watermarkEnabled {
            items.append(("Watermark enabled", Self.booleanSummary(watermarkEnabled)))
        }
        if let splashDuration {
            items.append(("Splash duration", Self.numberSummary(splashDuration)))
        }
        return items
    }

    private static func number(_ text: String, clampedTo range: ClosedRange<Double>) -> Double? {
        guard let value = Double(text), value.isFinite else { return nil }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func boolean(_ text: String) -> Bool? {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes": true
        case "0", "false", "no": false
        default: nil
        }
    }

    private static func numberSummary(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func booleanSummary(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }
}
