import AppKit
import NameplateCore
import SwiftUI

/// Big "you just landed on THIS Mac" banner: fades in on every screen,
/// holds for a moment, fades out.
@MainActor
final class SplashController {
    private let settings: AppSettings
    private var panels: [NSPanel] = []
    private var lastShownAt: ContinuousClock.Instant?
    private var generation = 0

    /// Per-screen gate for automatic splashes (decoration visibility mode).
    /// Forced splashes (explicit user/CLI action) ignore it.
    var screenFilter: (@MainActor (NSScreen) -> Bool)?

    /// Collapses trigger storms (wake + unlock + display change often fire together).
    private static let debounceInterval: Duration = .seconds(8)

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show(force: Bool = false) {
        if !force {
            guard self.settings.splashEnabled else { return }
            let now = ContinuousClock.now
            if let last = self.lastShownAt, now - last < Self.debounceInterval {
                return
            }
        }
        let screens = force
            ? NSScreen.screens
            : NSScreen.screens.filter { self.screenFilter?($0) ?? true }
        guard !screens.isEmpty else { return }
        self.lastShownAt = ContinuousClock.now

        self.dismissImmediately()
        self.generation += 1
        let generation = self.generation

        let identity = self.settings.identity
        let holdDuration = self.settings.splashDuration

        self.panels = screens.map { screen in
            let panel = OverlayPanelFactory.makePanel(
                for: screen,
                level: NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1))
            panel.contentView = NSHostingView(rootView: SplashView(identity: identity))
            panel.setFrame(screen.frame, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            return panel
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            for panel in self.panels {
                panel.animator().alphaValue = 1
            }
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(holdDuration))
            guard let self, self.generation == generation else { return }
            self.fadeOut(generation: generation)
        }
    }

    private func fadeOut(generation: Int) {
        let panels = self.panels
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
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
        for panel in self.panels {
            panel.close()
        }
        self.panels = []
    }
}

struct SplashView: View {
    let identity: MacIdentity
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            if !self.identity.glyph.isEmpty {
                Text(self.identity.glyph)
                    .font(.system(size: 76))
            }
            Text(self.identity.name)
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text(Hostnames.current())
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
            if !self.identity.location.isEmpty {
                Label(self.identity.location, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 64)
        .padding(.vertical, 44)
        .frame(maxWidth: 720)
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.black.opacity(0.74))
                .overlay {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(self.identity.color, lineWidth: 4)
                }
        }
        .scaleEffect(self.appeared ? 1 : 0.94)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.appeared = true
            }
        }
        .allowsHitTesting(false)
    }
}

extension Notification.Name {
    static let nameplateShowSplash = Notification.Name("nameplateShowSplash")
}
