import NameplateCore
import SwiftUI

extension ScreenCorner {
    var alignment: Alignment {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }
}

extension AppSettings {
    /// The frame shape honoring the per-corner rounding switches.
    func frameShape(scale: CGFloat = 1) -> UnevenRoundedRectangle {
        let radius = self.frameCornerRadius * scale
        return UnevenRoundedRectangle(
            topLeadingRadius: self.frameRoundTopLeft ? radius : 0,
            bottomLeadingRadius: self.frameRoundBottomLeft ? radius : 0,
            bottomTrailingRadius: self.frameRoundBottomRight ? radius : 0,
            topTrailingRadius: self.frameRoundTopRight ? radius : 0,
            style: .continuous)
    }
}

/// Full-screen transparent content: frame border, name tag, watermark.
/// Everything is drawn on top of whatever wallpaper and windows are there —
/// Nameplate never touches the actual desktop background.
struct OverlayView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var infoLineProvider: InfoLineProvider
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let identity = self.settings.identity
        ZStack {
            if self.settings.frameEnabled {
                self.settings.frameShape()
                    .strokeBorder(
                        identity.color.opacity(self.settings.frameOpacity),
                        lineWidth: self.settings.frameThickness)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            if self.settings.watermarkEnabled {
                WatermarkLabel(identity: identity, opacity: self.settings.watermarkOpacity)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: self.settings.watermarkCorner.alignment)
                    .padding(self.layerPadding)
                    .transition(.opacity)
            }

            if self.settings.tagEnabled {
                NameTagPill(
                    identity: identity,
                    showsGlyph: self.settings.tagShowsGlyph,
                    infoLines: self.infoLineProvider.lines)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: self.settings.tagCorner.alignment)
                    .padding(self.layerPadding)
                    .transition(.opacity)
            }
        }
        .animation(self.layerAnimation, value: self.settings.frameEnabled)
        .animation(self.layerAnimation, value: self.settings.tagEnabled)
        .animation(self.layerAnimation, value: self.settings.watermarkEnabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var layerAnimation: Animation? {
        self.reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    private var layerPadding: CGFloat {
        (self.settings.frameEnabled ? self.settings.frameThickness : 0) + 10
    }
}

struct NameTagPill: View {
    let identity: MacIdentity
    var showsGlyph: Bool = true
    var infoLines: [String] = []
    var scale: CGFloat = 1

    var body: some View {
        self.content
            .foregroundStyle(self.identity.textOnColor)
            .padding(.horizontal, 10 * self.scale)
            .padding(.vertical, 4 * self.scale)
            .background {
                if self.infoLines.isEmpty {
                    Capsule()
                        .fill(self.identity.color)
                } else {
                    RoundedRectangle(cornerRadius: 8 * self.scale, style: .continuous)
                        .fill(self.identity.color)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 3 * self.scale, y: 1 * self.scale)
    }

    @ViewBuilder
    private var content: some View {
        if self.infoLines.isEmpty {
            self.nameLine
        } else {
            VStack(alignment: .leading, spacing: 1 * self.scale) {
                self.nameLine
                ForEach(self.infoLines.indices, id: \.self) { index in
                    Text(self.infoLines[index])
                        .font(.system(size: 9 * self.scale, weight: .medium, design: .rounded))
                        .lineLimit(1)
                }
            }
        }
    }

    private var nameLine: some View {
        HStack(spacing: 5 * self.scale) {
            if self.showsGlyph, !self.identity.glyph.isEmpty {
                Text(self.identity.glyph)
                    .font(.system(size: 12 * self.scale))
            }
            Text(self.identity.name)
                .font(.system(size: 12 * self.scale, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
    }
}

struct WatermarkLabel: View {
    let identity: MacIdentity
    let opacity: Double
    var scale: CGFloat = 1

    var body: some View {
        Text(self.identity.name.uppercased())
            .font(.system(size: 64 * self.scale, weight: .black, design: .rounded))
            .kerning(2 * self.scale)
            .lineLimit(1)
            .foregroundStyle(self.identity.color.opacity(self.opacity))
    }
}
