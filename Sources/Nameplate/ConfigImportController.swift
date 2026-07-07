import AppKit
import NameplateCore
import SwiftUI

/// Reviews settings from a `nameplate://config` link before applying them.
@MainActor
final class ConfigImportController {
    private let settings: AppSettings
    private weak var services: AppServices?
    private var window: NSPanel?

    init(settings: AppSettings, services: AppServices) {
        self.settings = settings
        self.services = services
    }

    func show(_ proposal: ConfigProposal) {
        self.dismiss()

        let identity = self.settings.identity
        let view = ConfigImportView(
            proposal: proposal,
            previewName: proposal.name ?? identity.name,
            previewGlyph: proposal.glyph ?? identity.glyph,
            previewColorHex: proposal.colorHex ?? identity.colorHex,
            onCancel: { [weak self] in self?.dismiss() },
            onApply: { [weak self] in self?.apply(proposal) })
        let hosting = NSHostingView(rootView: view)
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        panel.title = "Nameplate Configuration"
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace]

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let frame = panel.frame
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - frame.width / 2,
                y: visible.midY - frame.height / 2))
        }

        self.window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func apply(_ proposal: ConfigProposal) {
        if let name = proposal.name { self.settings.customName = name }
        if let glyph = proposal.glyph { self.settings.glyph = glyph }
        if let colorHex = proposal.colorHex { self.settings.colorHex = colorHex }
        if let frameThickness = proposal.frameThickness {
            self.settings.frameThickness = frameThickness
        }
        if let frameOpacity = proposal.frameOpacity { self.settings.frameOpacity = frameOpacity }
        if let cornerRadius = proposal.cornerRadius {
            self.settings.frameCornerRadius = cornerRadius
        }
        if let roundTopLeft = proposal.roundTopLeft {
            self.settings.frameRoundTopLeft = roundTopLeft
        }
        if let roundTopRight = proposal.roundTopRight {
            self.settings.frameRoundTopRight = roundTopRight
        }
        if let roundBottomLeft = proposal.roundBottomLeft {
            self.settings.frameRoundBottomLeft = roundBottomLeft
        }
        if let roundBottomRight = proposal.roundBottomRight {
            self.settings.frameRoundBottomRight = roundBottomRight
        }
        if let tagCorner = proposal.tagCorner { self.settings.tagCorner = tagCorner }
        if let watermarkOpacity = proposal.watermarkOpacity {
            self.settings.watermarkOpacity = watermarkOpacity
        }
        if let frameEnabled = proposal.frameEnabled { self.settings.frameEnabled = frameEnabled }
        if let tagEnabled = proposal.tagEnabled { self.settings.tagEnabled = tagEnabled }
        if let watermarkEnabled = proposal.watermarkEnabled {
            self.settings.watermarkEnabled = watermarkEnabled
        }
        if let splashDuration = proposal.splashDuration {
            self.settings.splashDuration = splashDuration
        }

        self.dismiss()
        self.services?.showSplash(force: true)
    }

    private func dismiss() {
        self.window?.close()
        self.window = nil
    }
}

@MainActor
private struct ConfigImportView: View {
    let proposal: ConfigProposal
    let previewName: String
    let previewGlyph: String
    let previewColorHex: String
    let onCancel: @MainActor () -> Void
    let onApply: @MainActor () -> Void

    private var previewColor: Color {
        guard let rgb = ColorHex.components(self.previewColorHex) else { return .accentColor }
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private var previewTextColor: Color {
        ColorHex.prefersDarkText(on: self.previewColorHex) ? .black : .white
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                if !self.previewGlyph.isEmpty {
                    Text(self.previewGlyph)
                }
                Text(self.previewName.isEmpty ? "Nameplate" : self.previewName)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 17, design: .rounded))
            .foregroundStyle(self.previewTextColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(self.previewColor, in: Capsule())

            VStack(spacing: 5) {
                Text("Apply this nameplate?")
                    .font(.title2.bold())
                Text("From a nameplate:// link — review before applying.")
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                ForEach(Array(self.proposal.summaryItems.enumerated()), id: \.offset) { _, item in
                    GridRow {
                        Text(item.label)
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button("Cancel", action: self.onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply", action: self.onApply)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}
