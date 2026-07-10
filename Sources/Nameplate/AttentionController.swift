import AppKit
import NameplateCore
import SwiftUI
import notify

/// "The agent needs you": pulsating borders on every screen plus a topmost
/// message card. Stays until the card is clicked; an explicit duration
/// auto-dismisses instead.
@MainActor
final class AttentionController {
    static let cardMaximumWidth: CGFloat = 584
    static let cardMaximumHeight: CGFloat = 360

    private let settings: AppSettings
    private var borderPanels: [NSPanel] = []
    private var cardPanel: NSPanel?
    private var generation = 0
    private var isDismissing = false
    private var onDismiss: (@MainActor () -> Void)?
    private var activeRequestID: String?

    var isActive: Bool {
        !self.borderPanels.isEmpty || self.cardPanel != nil
    }

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
                self?.cardPanel?.ignoresMouseEvents = true
                let passes: [(delay: TimeInterval, restoreInteraction: Bool)] = [
                    (0, false),
                    (0.5, false),
                    (1.5, true),
                ]
                for pass in passes {
                    DispatchQueue.main.asyncAfter(deadline: .now() + pass.delay) { [weak self] in
                        self?.syncFrames(restoreInteraction: pass.restoreInteraction)
                    }
                }
            }
        }

        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cardPanel?.ignoresMouseEvents = true
                DispatchQueue.main.async { [weak self] in
                    self?.syncFrames(restoreInteraction: true)
                }
            }
        }
    }

    private func syncFrames(restoreInteraction: Bool) {
        guard !self.borderPanels.isEmpty || self.cardPanel != nil else { return }
        let screens = NSScreen.screens
        for (index, panel) in self.borderPanels.enumerated() where index < screens.count {
            if panel.frame != screens[index].frame {
                panel.setFrame(screens[index].frame, display: true)
            }
        }
        if let card = self.cardPanel, let screen = NSScreen.main ?? NSScreen.screens.first {
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
            card.orderFrontRegardless()
            if restoreInteraction {
                self.enableCardInteractionIfPresented(card)
            }
        } else if self.cardPanel != nil, restoreInteraction {
            // A stale topmost input window is worse than a dropped card.
            self.finishImmediately()
        }
    }

    func show(_ request: AttentionRequest, onDismiss: (@MainActor () -> Void)? = nil) {
        if self.activeRequestID != nil {
            self.acknowledge(.superseded)
        }
        self.resetPresentation()
        self.onDismiss = nil
        self.generation += 1
        let generation = self.generation
        self.onDismiss = onDismiss
        self.activeRequestID = request.id

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

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let panel = OverlayPanelFactory.makeAttentionCardPanel(for: screen, level: level)
            let hosting = NSHostingController(
                rootView: AttentionCardView(
                    request: request,
                    colorHex: colorHex,
                    identity: identity,
                    onDismiss: { [weak self] in
                        self?.dismiss(generation: generation, outcome: .clicked)
                    }))
            let visible = screen.visibleFrame
            let available = NSSize(
                width: min(Self.cardMaximumWidth, max(0, visible.width - 40)),
                height: min(Self.cardMaximumHeight, max(0, visible.height / 2)))
            let size = hosting.sizeThatFits(in: available)
            guard Self.isValidCardSize(size, fitting: available) else {
                self.finishImmediately()
                return
            }
            hosting.sizingOptions = []
            panel.contentViewController = hosting
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
            // Ordering and SwiftUI's first render finish on the next main-loop
            // turn. Until then the panel remains click-through.
            DispatchQueue.main.async { [weak self, weak panel] in
                guard let self, let panel, self.generation == generation else { return }
                self.enableCardInteractionIfPresented(panel)
            }
        } else {
            self.finishImmediately()
            return
        }

        if let duration {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                self?.dismiss(generation: generation, outcome: .autoDismissed)
            }
        }
    }

    private func dismiss(generation: Int, outcome: AttentionAck.Outcome) {
        guard self.generation == generation else { return }
        self.acknowledge(outcome)
        self.isDismissing = true
        let panels = self.borderPanels + [self.cardPanel].compactMap(\.self)
        // Never leave a fading or interrupted card intercepting input.
        self.cardPanel?.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            for panel in panels {
                panel.animator().alphaValue = 0
            }
        } completionHandler: {
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.finishImmediately()
            }
        }
    }

    func dismissActive() {
        guard self.isActive || self.onDismiss != nil else { return }
        self.generation += 1
        self.isDismissing = true
        self.cardPanel?.ignoresMouseEvents = true
        self.finishImmediately()
    }

    static func isValidCardSize(_ size: NSSize, fitting available: NSSize) -> Bool {
        size.width.isFinite && size.height.isFinite
            && size.width > 0 && size.height > 0
            && size.width <= available.width && size.height <= available.height
    }

    private func enableCardInteractionIfPresented(_ panel: NSPanel) {
        guard panel === self.cardPanel,
              !self.isDismissing,
              panel.isVisible,
              panel.isOnActiveSpace,
              panel.alphaValue > 0,
              panel.contentView != nil,
              NSScreen.screens.contains(where: { $0.visibleFrame.contains(panel.frame) })
        else {
            self.finishImmediately()
            return
        }
        panel.ignoresMouseEvents = false
    }

    private func acknowledge(_ outcome: AttentionAck.Outcome) {
        guard let id = self.activeRequestID else { return }
        self.activeRequestID = nil
        do {
            try AttentionAck(id: id, outcome: outcome).write()
            notify_post(AttentionAck.notificationName)
        } catch {
            NSLog("Nameplate: writing attention acknowledgment failed: \(error)")
        }
    }

    private func finishImmediately() {
        let onDismiss = self.onDismiss
        self.onDismiss = nil
        self.resetPresentation()
        onDismiss?()
    }

    private func resetPresentation() {
        for panel in self.borderPanels {
            panel.close()
        }
        self.borderPanels = []
        self.cardPanel?.close()
        self.cardPanel = nil
        self.activeRequestID = nil
        self.isDismissing = false
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
                .lineLimit(8)
                .truncationMode(.tail)
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
