import AppKit
import Combine
import SwiftUI

/// Click-through, always-on-top panels shared by the overlay and the splash.
enum OverlayPanelFactory {
    @MainActor
    static func makePanel(for screen: NSScreen, level: NSWindow.Level) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = level
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        // Visible on every Space, next to fullscreen apps, and pinned during Mission Control.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}

/// Owns one overlay panel per screen and keeps them alive across display
/// reconfiguration. The SwiftUI content observes AppSettings directly, so the
/// controller only manages panel lifecycle and per-screen visibility.
@MainActor
final class OverlayController {
    private let settings: AppSettings
    private let remoteMonitor: RemoteViewMonitor
    private var panels: [(panel: NSPanel, screen: NSScreen)] = []
    private var cancellable: AnyCancellable?
    // App-lifetime object: observers are registered once and never removed.

    init(settings: AppSettings, remoteMonitor: RemoteViewMonitor) {
        self.settings = settings
        self.remoteMonitor = remoteMonitor
        self.rebuildPanels()

        // objectWillChange fires before the write lands; hop once so we read
        // the post-change values.
        self.cancellable = settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.applyVisibility()
                }
            }

        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuildPanels()
                self?.scheduleFrameSync()
            }
        }
    }

    /// Display reconfiguration often delivers stale NSScreen frames at
    /// notification time (virtual displays resized by a remote client are the
    /// worst offenders), so re-sync panel frames again once the dust settles.
    private func scheduleFrameSync() {
        for delay: TimeInterval in [0.5, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.syncPanelFrames()
            }
        }
    }

    private func syncPanelFrames() {
        let screens = NSScreen.screens
        guard screens.count == self.panels.count else {
            self.rebuildPanels()
            return
        }
        for (index, screen) in screens.enumerated() {
            let panel = self.panels[index].panel
            if panel.frame != screen.frame {
                panel.setFrame(screen.frame, display: true)
            }
            self.panels[index].screen = screen
        }
        self.applyVisibility()
    }

    private var anyLayerEnabled: Bool {
        self.settings.frameEnabled || self.settings.tagEnabled || self.settings.watermarkEnabled
    }

    private func shouldShow(on screen: NSScreen) -> Bool {
        guard self.settings.overlaysEnabled, self.anyLayerEnabled else { return false }
        switch self.settings.visibilityMode {
        case .always:
            return true
        case .remoteOnly:
            return RemoteViewMonitor.isVirtual(screen: screen) || self.remoteMonitor.screenSharingActive
        }
    }

    func rebuildPanels() {
        for (panel, _) in self.panels {
            panel.close()
        }
        self.panels = NSScreen.screens.map { screen in
            // .statusBar floats above app windows and fullscreen content but
            // stays below pop-up menus. Anything higher (.screenSaver) blocks
            // NSMenu from opening at all.
            let panel = OverlayPanelFactory.makePanel(for: screen, level: .statusBar)
            panel.contentView = NSHostingView(rootView: OverlayView(settings: self.settings))
            panel.setFrame(screen.frame, display: true)
            return (panel, screen)
        }
        self.applyVisibility()
    }

    func applyVisibility() {
        for (panel, screen) in self.panels {
            if self.shouldShow(on: screen) {
                if !panel.isVisible {
                    panel.orderFrontRegardless()
                }
            } else {
                panel.orderOut(nil)
            }
        }
    }
}
