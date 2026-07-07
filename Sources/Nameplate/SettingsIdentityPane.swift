import NameplateCore
import SwiftUI

@MainActor
struct IdentitySettingsPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                IdentityPreviewCard(settings: self.settings)
                    .padding(.vertical, 4)
            }

            if self.settings.identityIsFleetManaged {
                Section {
                    Label {
                        Text("This Mac's identity is managed by the fleet file. Edit "
                            + "~/.config/nameplate/fleet.json or turn off \"Follow fleet file\" below.")
                            .font(.callout)
                    } icon: {
                        Image(systemName: "externaldrive.badge.checkmark")
                            .foregroundStyle(.blue)
                    }
                }
            }

            Section {
                TextField(
                    "Name",
                    text: self.$settings.customName,
                    prompt: Text(self.settings.defaultName))
                    .disabled(self.settings.identityIsFleetManaged)
                TextField(
                    "Glyph",
                    text: self.$settings.glyph,
                    prompt: Text("Optional, e.g. 🦞"))
                    .disabled(self.settings.identityIsFleetManaged)
                LabeledContent("Color") {
                    ColorSwatchRow(settings: self.settings)
                        .disabled(self.settings.identityIsFleetManaged)
                }
            } header: {
                Text("Identity")
            } footer: {
                Text("How this Mac announces itself. Leave the name empty to use the computer name.")
            }

            Section {
                CaptionedToggle(
                    title: "Follow fleet file",
                    caption: "When the file has an entry for this Mac, it overrides the identity above.",
                    isOn: self.$settings.useFleetFile)
                LabeledContent {
                    HStack(spacing: 8) {
                        if !self.settings.fleetFileExists {
                            Button("Create template") { self.createFleetTemplate() }
                        } else {
                            Button("Reveal") {
                                NSWorkspace.shared.activateFileViewerSelecting([FleetFile.defaultPath])
                            }
                        }
                        Button("Reload") { self.settings.reloadFleetEntry() }
                    }
                    .controlSize(.small)
                } label: {
                    Label {
                        Text(self.fleetStatusText)
                    } icon: {
                        Image(systemName: self.fleetStatusSymbol)
                            .foregroundStyle(self.fleetStatusColor)
                    }
                }
            } header: {
                Text("Fleet file")
            } footer: {
                Text("Optional JSON at ~/.config/nameplate/fleet.json, keyed by short hostname. "
                    + "Sync it via dotfiles to brand every Mac from one place.")
            }
        }
        .formStyle(.grouped)
    }

    private var fleetStatusSymbol: String {
        if !self.settings.fleetFileExists { return "doc.badge.plus" }
        return self.settings.fleetEntry != nil ? "checkmark.circle.fill" : "questionmark.circle"
    }

    private var fleetStatusColor: Color {
        if !self.settings.fleetFileExists { return .secondary }
        return self.settings.fleetEntry != nil ? .green : .orange
    }

    private var fleetStatusText: String {
        let host = Hostnames.short(self.settings.hostName)
        if !self.settings.fleetFileExists {
            return "No fleet file found"
        }
        return self.settings.fleetEntry != nil
            ? "Entry found for \"\(host)\""
            : "No entry for \"\(host)\""
    }

    private func createFleetTemplate() {
        let host = Hostnames.short(self.settings.hostName)
        let identity = self.settings.identity
        let entry = FleetEntry(
            name: identity.name,
            color: identity.colorHex,
            glyph: identity.glyph.isEmpty ? nil : identity.glyph)
        let url = FleetFile.defaultPath
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode([host: entry])
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            self.settings.reloadFleetEntry()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSLog("Nameplate: writing fleet template failed: \(error)")
        }
    }
}

/// Miniature screen that mirrors the live overlay configuration.
@MainActor
struct IdentityPreviewCard: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        let identity = self.settings.identity
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.16), Color(white: 0.09)],
                startPoint: .top,
                endPoint: .bottom)

            VStack(spacing: 0) {
                HStack {
                    Circle().frame(width: 4, height: 4)
                    Circle().frame(width: 4, height: 4)
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.25))
                .padding(.horizontal, 10)
                .frame(height: 14)
                .background(.white.opacity(0.08))
                Spacer()
            }

            if self.settings.watermarkEnabled {
                WatermarkLabel(identity: identity, opacity: self.settings.watermarkOpacity, scale: 0.3)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: self.settings.watermarkCorner.alignment)
                    .padding(12)
            }

            if self.settings.tagEnabled {
                NameTagPill(identity: identity, showsGlyph: self.settings.tagShowsGlyph, scale: 0.9)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: self.settings.tagCorner.alignment)
                    .padding(10)
            }

            if self.settings.frameEnabled {
                RoundedRectangle(
                    cornerRadius: max(10, self.settings.frameCornerRadius * 0.6),
                    style: .continuous)
                    .strokeBorder(
                        identity.color.opacity(self.settings.frameOpacity),
                        lineWidth: max(2, self.settings.frameThickness * 0.75))
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
    }
}

@MainActor
struct ColorSwatchRow: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 8) {
            ForEach(NameplatePalette.colors) { palette in
                let selected = self.settings.identity.colorHex == palette.hex
                Button {
                    self.settings.colorHex = palette.hex
                } label: {
                    Circle()
                        .fill(Color(
                            .sRGB,
                            red: ColorHex.components(palette.hex)?.red ?? 0,
                            green: ColorHex.components(palette.hex)?.green ?? 0,
                            blue: ColorHex.components(palette.hex)?.blue ?? 0))
                        .frame(width: 18, height: 18)
                        .overlay {
                            if selected {
                                Circle().strokeBorder(.primary, lineWidth: 2).padding(-3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(palette.name)
            }

            ColorPicker("Custom", selection: self.customColorBinding, supportsOpacity: false)
                .labelsHidden()
                .help("Custom color")

            Button("Auto") {
                self.settings.colorHex = ""
            }
            .controlSize(.small)
            .help("Stable per-host default color derived from the hostname.")
        }
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { self.settings.identity.color },
            set: { newColor in
                guard let srgb = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                let hex = String(
                    format: "#%02X%02X%02X",
                    Int(round(srgb.redComponent * 255)),
                    Int(round(srgb.greenComponent * 255)),
                    Int(round(srgb.blueComponent * 255)))
                self.settings.colorHex = hex
            })
    }
}
