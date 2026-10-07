import AppKit
import NameplateCore
import SwiftUI

@MainActor
struct LayersSettingsPane: View {
    @ObservedObject var settings: AppSettings

    @State private var displaySize = Self.largestDisplaySize

    private static var largestDisplaySize: CGSize {
        CGSize(
            width: NSScreen.screens.map(\.frame.width).max() ?? 1920,
            height: NSScreen.screens.map(\.frame.height).max() ?? 1080)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show frame", isOn: self.$settings.frameEnabled)
                Group {
                    SliderRow(
                        title: "Thickness",
                        value: self.$settings.frameThickness,
                        range: 2...12,
                        format: { "\(Int($0)) pt" })
                    SliderRow(
                        title: "Corner radius",
                        value: self.$settings.frameCornerRadius,
                        range: 0...40,
                        format: { "\(Int($0)) pt" })
                    LabeledContent("Rounded corners") {
                        CornerRoundingControl(settings: self.settings)
                    }
                    SliderRow(
                        title: "Opacity",
                        value: self.$settings.frameOpacity,
                        range: 0.2...1,
                        format: { "\(Int($0 * 100))%" })
                }
                .disabled(!self.settings.frameEnabled)
            } header: {
                Text("Frame")
            } footer: {
                Text("A colored border around every display. Always visible, costs zero pixels of workspace.")
            }

            Section {
                Toggle("Show name tag", isOn: self.$settings.tagEnabled)
                Group {
                    Picker("Position", selection: self.$settings.tagCorner) {
                        ForEach(TagPosition.allCases) { position in
                            Text(position.label).tag(position)
                        }
                    }
                    TagOffsetRow(
                        title: "Horizontal offset",
                        value: self.$settings.tagHorizontalOffset,
                        range: self.settings.tagCorner.horizontalAnchor.offsetRange(extent: self.displaySize.width))
                    TagOffsetRow(
                        title: "Vertical offset",
                        value: self.$settings.tagVerticalOffset,
                        range: self.settings.tagCorner.verticalAnchor.offsetRange(extent: self.displaySize.height))
                    Button("Reset offsets") {
                        self.settings.tagHorizontalOffset = 0
                        self.settings.tagVerticalOffset = 0
                    }
                    Toggle("Include glyph", isOn: self.$settings.tagShowsGlyph)
                    LabeledContent("Info lines") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(InfoLineField.allCases) { field in
                                Toggle(field.label, isOn: self.infoFieldBinding(field))
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .disabled(!self.settings.tagEnabled)
            } header: {
                Text("Name tag")
            } footer: {
                Text("Offsets move inward from an edge. On centered axes, negative moves left/up and positive moves right/down. Selected details may appear in screenshots and recordings.")
            }

            Section {
                Toggle("Show watermark", isOn: self.$settings.watermarkEnabled)
                Group {
                    Picker("Corner", selection: self.$settings.watermarkCorner) {
                        ForEach(ScreenCorner.allCases) { corner in
                            Text(corner.label).tag(corner)
                        }
                    }
                    SliderRow(
                        title: "Opacity",
                        value: self.$settings.watermarkOpacity,
                        range: 0.04...0.5,
                        format: { "\(Int($0 * 100))%" })
                }
                .disabled(!self.settings.watermarkEnabled)
            } header: {
                Text("Watermark")
            } footer: {
                Text("A large translucent name across the screen — visible even from across the room.")
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            self.displaySize = Self.largestDisplaySize
        }
    }

    private func infoFieldBinding(_ field: InfoLineField) -> Binding<Bool> {
        Binding(
            get: { self.settings.tagInfoFields.contains(field) },
            set: { enabled in
                var fields = self.settings.tagInfoFields
                if enabled {
                    fields.insert(field)
                } else {
                    fields.remove(field)
                }
                self.settings.tagInfoFields = fields
            })
    }
}
