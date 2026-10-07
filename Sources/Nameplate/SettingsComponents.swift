import NameplateCore
import SwiftUI

/// A grouped-form slider row: leading label, continuous slider, trailing
/// monospaced value.
@MainActor
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String = { String(format: "%.0f", $0) }

    var body: some View {
        HStack(spacing: 12) {
            Text(self.title)
            Slider(value: self.$value, in: self.range)
                .labelsHidden()
            Text(self.format(self.value))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }
}

/// Offset entry keeps a slider for quick adjustment and a field for exact placement.
@MainActor
struct TagOffsetRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    // Changing anchor or display size must not silently overwrite the saved offset.
    private var sliderValue: Binding<Double> {
        Binding(
            get: { min(max(self.value.isFinite ? self.value : 0, self.range.lowerBound), self.range.upperBound) },
            set: { self.value = min(max($0.isFinite ? $0 : 0, self.range.lowerBound), self.range.upperBound) })
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(self.title)
            Slider(value: self.sliderValue, in: self.range, step: 1)
                .accessibilityLabel(self.title)
            TextField(self.title, value: self.sliderValue, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 76)
            Text("pt").foregroundStyle(.secondary)
        }
    }
}

/// Four mini corner-diagram buttons: each shows a square rounded only at its
/// corner; filled accent when that screen corner is rounded.
@MainActor
struct CornerRoundingControl: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 8) {
            CornerToggleButton(corner: .topLeft, isOn: self.$settings.frameRoundTopLeft)
            CornerToggleButton(corner: .topRight, isOn: self.$settings.frameRoundTopRight)
            CornerToggleButton(corner: .bottomLeft, isOn: self.$settings.frameRoundBottomLeft)
            CornerToggleButton(corner: .bottomRight, isOn: self.$settings.frameRoundBottomRight)
        }
    }
}

@MainActor
private struct CornerToggleButton: View {
    let corner: ScreenCorner
    @Binding var isOn: Bool

    var body: some View {
        Button {
            self.isOn.toggle()
        } label: {
            self.shape
                .strokeBorder(
                    self.isOn ? Color.accentColor : Color.secondary.opacity(0.45),
                    lineWidth: 2)
                .background {
                    if self.isOn {
                        self.shape.fill(Color.accentColor.opacity(0.2))
                    }
                }
                .frame(width: 22, height: 22)
                // Stroke-only shapes hit-test just the drawn border; make the whole tile clickable.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(self.corner.label) rounded")
        .accessibilityLabel("\(self.corner.label) rounded")
        .accessibilityValue(self.isOn ? "on" : "off")
    }

    private var shape: UnevenRoundedRectangle {
        let radius: CGFloat = 9
        return UnevenRoundedRectangle(
            topLeadingRadius: self.corner == .topLeft ? radius : 2,
            bottomLeadingRadius: self.corner == .bottomLeft ? radius : 2,
            bottomTrailingRadius: self.corner == .bottomRight ? radius : 2,
            topTrailingRadius: self.corner == .topRight ? radius : 2,
            style: .continuous)
    }
}

/// Toggle with a caption underneath, System Settings style.
@MainActor
struct CaptionedToggle: View {
    let title: String
    var caption: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: self.$isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(self.title)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
