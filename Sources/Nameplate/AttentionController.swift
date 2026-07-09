import AppKit
import NameplateCore
import SwiftUI

/// "The agent needs you": pulsating borders on every screen plus a topmost
/// message card. Stays until the card is clicked; an explicit duration
/// auto-dismisses instead.
@MainActor
final class AttentionController {
    private let settings: AppSettings
    private var borderPanels: [NSPanel] = []
    private var cardPanel: NSPanel?
    private var generation = 0

    init(settings: AppSettings) {
        self.settings = settings
        // Sticky alerts can outlive display reconfigurations; keep the
        // pulsating borders and card on-screen when frames change. Delayed
        // passes because NSScreen data can lag the notification.
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            MainActor.assumeIsolated {
                for delay: TimeInterval in [0, 0.5, 1.5] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.syncFrames()
                    }
                }
            }
        }
    }

    private func syncFrames() {
        guard !self.borderPanels.isEmpty || self.cardPanel != nil else { return }
        let screens = NSScreen.screens
        for (index, panel) in self.borderPanels.enumerated() where index < screens.count {
            if panel.frame != screens[index].frame {
                panel.setFrame(screens[index].frame, display: true)
            }
        }
        if let card = self.cardPanel, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            var size = card.frame.size
            size.width = min(size.width, visible.width - 40)
            size.height = min(size.height, visible.height - 40)
            let y = max(visible.minY + 20, visible.maxY - size.height - 90)
            card.setFrame(
                NSRect(
                    x: max(visible.minX + 20, visible.midX - size.width / 2),
                    y: y,
                    width: size.width,
                    height: size.height),
                display: true)
        }
    }

    func show(_ request: AttentionRequest) {
        self.dismissImmediately()
        self.generation += 1
        let generation = self.generation

        let identity = self.settings.identity
        let colorHex = ColorHex.normalize(request.color ?? "") ?? identity.colorHex
        // No duration = sticky: the agent said something, keep it up until acknowledged.
        let duration: Double? = request.duration.map { max(2, min($0, 120)) }

        let level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        self.borderPanels = NSScreen.screens.map { screen in
            let panel = OverlayPanelFactory.makePanel(for: screen, level: level)
            panel.contentView = NSHostingView(
                rootView: PulsatingBorderView(colorHex: colorHex))
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            return panel
        }

        if let screen = NSScreen.main {
            let panel = OverlayPanelFactory.makePanel(for: screen, level: level)
            // Sized to the card only, so the rest of the screen stays clickable.
            panel.ignoresMouseEvents = false
            let hosting = NSHostingView(
                rootView: AttentionCardView(
                    request: request,
                    colorHex: colorHex,
                    identity: identity,
                    onDismiss: { [weak self] in self?.dismiss(generation: generation) }))
            var size = hosting.fittingSize
            panel.contentView = hosting
            let visible = screen.visibleFrame
            // Clamp to the visible frame so the card is fully on-screen even on
            // small or low-resolution displays.
            size.width = min(size.width, visible.width - 40)
            size.height = min(size.height, visible.height - 40)
            let y = max(visible.minY + 20, visible.maxY - size.height - 90)
            panel.setFrame(
                NSRect(
                    x: max(visible.minX + 20, visible.midX - size.width / 2),
                    y: y,
                    width: size.width,
                    height: size.height),
                display: true)
            panel.orderFrontRegardless()
            self.cardPanel = panel
        }

        if let duration {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                self?.dismiss(generation: generation)
            }
        }
    }

    private func dismiss(generation: Int) {
        guard self.generation == generation else { return }
        let panels = self.borderPanels + [self.cardPanel].compactMap(\.self)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            for panel in panels {
                panel.animator().alphaValue = 0
            }
        } completionHandler: {
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.dismissImmediately()
            }
        }
    }

    private func dismissImmediately() {
        for panel in self.borderPanels {
            panel.close()
        }
        self.borderPanels = []
        self.cardPanel?.close()
        self.cardPanel = nil
    }
}

struct PulsatingBorderView: View {
    let colorHex: String
    @State private var pulsing = false

    private var color: Color {
        guard let rgb = ColorHex.components(self.colorHex) else { return .red }
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(self.color, lineWidth: self.pulsing ? 14 : 6)
            .opacity(self.pulsing ? 1 : 0.45)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    self.pulsing = true
                }
            }
    }
}

struct AttentionCardView: View {
    let request: AttentionRequest
    let colorHex: String
    let identity: MacIdentity
    let onDismiss: @MainActor () -> Void

    private var color: Color {
        guard let rgb = ColorHex.components(self.colorHex) else { return .red }
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(self.color)
                Text(self.request.title ?? "Agent needs attention")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text(self.request.message)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(self.identity.name) · click to dismiss")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 30)
        .frame(maxWidth: 560)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.black.opacity(0.8))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(self.color, lineWidth: 3)
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            self.onDismiss()
        }
        .padding(12)
    }
}
