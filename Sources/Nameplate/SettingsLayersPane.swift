import NameplateCore
import SwiftUI

@MainActor
struct LayersSettingsPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsPaneLayout {
            SettingsSection(
                "Frame",
                subtitle: "A colored border around every display. Always visible, costs zero pixels of workspace.")
            {
                VStack(alignment: .leading, spacing: 12) {
                    PreferenceToggleRow(
                        title: "Show frame",
                        subtitle: nil,
                        binding: self.$settings.frameEnabled)
                    LabeledSlider(
                        title: "Thickness",
                        value: self.$settings.frameThickness,
                        range: 2...12,
                        format: { "\(Int($0)) pt" })
                        .disabled(!self.settings.frameEnabled)
                    LabeledSlider(
                        title: "Corners",
                        value: self.$settings.frameCornerRadius,
                        range: 0...40,
                        format: { "\(Int($0)) pt" })
                        .disabled(!self.settings.frameEnabled)
                    LabeledSlider(
                        title: "Opacity",
                        value: self.$settings.frameOpacity,
                        range: 0.2...1,
                        step: 0.05,
                        format: { "\(Int($0 * 100))%" })
                        .disabled(!self.settings.frameEnabled)
                }
            }

            SettingsSection(
                "Name tag",
                subtitle: "A small pill with this Mac's name, floating above everything in a corner.")
            {
                VStack(alignment: .leading, spacing: 12) {
                    PreferenceToggleRow(
                        title: "Show name tag",
                        subtitle: nil,
                        binding: self.$settings.tagEnabled)
                    CornerPicker(title: "Corner", corner: self.$settings.tagCorner)
                        .disabled(!self.settings.tagEnabled)
                    PreferenceToggleRow(
                        title: "Include glyph",
                        subtitle: nil,
                        binding: self.$settings.tagShowsGlyph)
                        .disabled(!self.settings.tagEnabled)
                }
            }

            SettingsSection(
                "Watermark",
                subtitle: "A large translucent name across the screen — visible even from across the room.")
            {
                VStack(alignment: .leading, spacing: 12) {
                    PreferenceToggleRow(
                        title: "Show watermark",
                        subtitle: nil,
                        binding: self.$settings.watermarkEnabled)
                    CornerPicker(title: "Corner", corner: self.$settings.watermarkCorner)
                        .disabled(!self.settings.watermarkEnabled)
                    LabeledSlider(
                        title: "Opacity",
                        value: self.$settings.watermarkOpacity,
                        range: 0.04...0.5,
                        step: 0.02,
                        format: { "\(Int($0 * 100))%" })
                        .disabled(!self.settings.watermarkEnabled)
                }
            }
        }
    }
}

@MainActor
struct CornerPicker: View {
    let title: String
    @Binding var corner: ScreenCorner

    var body: some View {
        HStack(spacing: 12) {
            Text(self.title)
                .frame(width: 88, alignment: .leading)
            Picker(self.title, selection: self.$corner) {
                ForEach(ScreenCorner.allCases) { corner in
                    Text(corner.label).tag(corner)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }
}
