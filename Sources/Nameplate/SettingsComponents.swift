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
