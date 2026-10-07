import Foundation

/// Name-tag anchors. Raw values retain the existing `tagCorner` configuration contract.
public enum TagPosition: String, CaseIterable, Codable, Sendable, Identifiable {
    case topLeft, topCenter, topRight
    case leftCenter, rightCenter
    case bottomLeft, bottomCenter, bottomRight

    public var id: String { self.rawValue }

    public var label: String {
        switch self {
        case .topLeft: "Top left"
        case .topCenter: "Top center"
        case .topRight: "Top right"
        case .leftCenter: "Left center"
        case .rightCenter: "Right center"
        case .bottomLeft: "Bottom left"
        case .bottomCenter: "Bottom center"
        case .bottomRight: "Bottom right"
        }
    }

    public var horizontalAnchor: TagAnchor {
        switch self {
        case .topLeft, .leftCenter, .bottomLeft: .start
        case .topCenter, .bottomCenter: .center
        case .topRight, .rightCenter, .bottomRight: .end
        }
    }

    public var verticalAnchor: TagAnchor {
        switch self {
        case .topLeft, .topCenter, .topRight: .start
        case .leftCenter, .rightCenter: .center
        case .bottomLeft, .bottomCenter, .bottomRight: .end
        }
    }

    /// Local top-left origin in display coordinates (positive y points down).
    /// Offsets on edge anchors move inward; centered axes allow signed movement.
    public func origin(
        width: Double, height: Double, tagWidth: Double, tagHeight: Double,
        inset: Double, horizontalOffset: Double, verticalOffset: Double
    ) -> (x: Double, y: Double) {
        (
            self.horizontalAnchor.origin(extent: width, item: tagWidth, inset: inset, offset: horizontalOffset),
            self.verticalAnchor.origin(extent: height, item: tagHeight, inset: inset, offset: verticalOffset))
    }
}

public enum TagAnchor: Sendable {
    case start, center, end

    /// UI limits cover the display; actual placement also accounts for tag size and inset.
    public func offsetRange(extent: Double) -> ClosedRange<Double> {
        let extent = extent.isFinite ? max(1, extent) : 1
        return self == .center ? -extent / 2...extent / 2 : 0...extent
    }

    private func finite(_ value: Double) -> Double { value.isFinite ? value : 0 }

    public func origin(extent: Double, item: Double, inset: Double, offset: Double) -> Double {
        let available = max(0, self.finite(extent) - max(0, self.finite(item)))
        let inset = min(max(0, self.finite(inset)), available / 2)
        let offset = self.finite(offset)
        let proposed: Double
        switch self {
        case .start: proposed = inset + max(0, offset)
        case .center: proposed = available / 2 + offset
        case .end: proposed = available - inset - max(0, offset)
        }
        return min(max(proposed, inset), available - inset)
    }
}
