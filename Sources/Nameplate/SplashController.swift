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
            panel.contentView = NSHostingView(rootView: SplashView(
                identity: identity,
                duration: holdDuration))
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            return panel
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
    let duration: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frameProgress: CGFloat = 0
    @State private var frameOpacity = 1.0
    @State private var contentOpacity = 0.0
    @State private var contentScale: CGFloat = 0.88
    @State private var glowScale: CGFloat = 0.78
    @State private var glowOpacity = 0.0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .trim(from: 0, to: self.frameProgress)
                .stroke(
                    self.identity.color,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                .padding(7)
                .shadow(color: self.identity.color.opacity(0.9), radius: 18)
                .opacity(self.frameOpacity)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(self.identity.color.opacity(0.16), lineWidth: 2)
                .padding(7)
                .scaleEffect(self.glowScale)
                .opacity(self.glowOpacity)

            self.plate
                .scaleEffect(self.contentScale)
                .opacity(self.contentOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            self.play()
        }
        .allowsHitTesting(false)
    }

    private var plate: some View {
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
                .shadow(color: self.identity.color.opacity(0.3), radius: 36)
        }
    }

    private func play() {
        if self.reduceMotion {
            self.frameProgress = 1
            self.glowScale = 1
            self.glowOpacity = 1
            self.contentOpacity = 1
            self.contentScale = 1
        } else {
            withAnimation(.easeInOut(duration: 0.62)) {
                self.frameProgress = 1
            }
            withAnimation(.easeOut(duration: 0.55).delay(0.08)) {
                self.glowScale = 1.03
                self.glowOpacity = 1
            }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.72).delay(0.2)) {
                self.contentOpacity = 1
                self.contentScale = 1
            }
        }

        let exitDuration = self.reduceMotion ? 0.2 : 0.38
        let exitDelay = self.reduceMotion
            ? max(0, self.duration - exitDuration)
            : max(0.75, self.duration - 0.42)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(exitDelay))
            withAnimation(.easeIn(duration: exitDuration)) {
                self.contentOpacity = 0
                self.frameOpacity = 0
                self.glowOpacity = 0
                if !self.reduceMotion {
                    self.contentScale = 1.045
                    self.glowScale = 1.08
                }
            }
        }
    }
}

extension Notification.Name {
    static let nameplateShowSplash = Notification.Name("nameplateShowSplash")
}
