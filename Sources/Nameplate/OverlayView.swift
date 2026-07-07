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

/// Full-screen transparent content: frame border, name tag, watermark.
/// Everything is drawn on top of whatever wallpaper and windows are there —
/// Nameplate never touches the actual desktop background.
struct OverlayView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        let identity = self.settings.identity
        ZStack {
            if self.settings.frameEnabled {
                RoundedRectangle(cornerRadius: self.settings.frameCornerRadius, style: .continuous)
                    .strokeBorder(
                        identity.color.opacity(self.settings.frameOpacity),
                        lineWidth: self.settings.frameThickness)
                    .ignoresSafeArea()
            }

            if self.settings.watermarkEnabled {
                WatermarkLabel(identity: identity, opacity: self.settings.watermarkOpacity)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: self.settings.watermarkCorner.alignment)
                    .padding(self.layerPadding)
            }

            if self.settings.tagEnabled {
                NameTagPill(identity: identity, showsGlyph: self.settings.tagShowsGlyph)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: self.settings.tagCorner.alignment)
                    .padding(self.layerPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var layerPadding: CGFloat {
        (self.settings.frameEnabled ? self.settings.frameThickness : 0) + 10
    }
}

struct NameTagPill: View {
    let identity: MacIdentity
    var showsGlyph: Bool = true
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 5 * self.scale) {
            if self.showsGlyph, !self.identity.glyph.isEmpty {
                Text(self.identity.glyph)
                    .font(.system(size: 12 * self.scale))
            }
            Text(self.identity.name)
                .font(.system(size: 12 * self.scale, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(self.identity.textOnColor)
        .padding(.horizontal, 10 * self.scale)
        .padding(.vertical, 4 * self.scale)
        .background(self.identity.color, in: Capsule())
        .shadow(color: .black.opacity(0.35), radius: 3 * self.scale, y: 1 * self.scale)
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
