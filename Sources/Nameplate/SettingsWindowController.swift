import AppKit
import SwiftUI

/// Manually managed settings window. The SwiftUI `Settings` scene is
/// unreliable for menu-bar-only apps (it silently fails to open on current
/// macOS builds), so we own the window ourselves — which also gives us
/// activation and reuse for free.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings
    private weak var services: AppServices?

    init(settings: AppSettings, services: AppServices) {
        self.settings = settings
        self.services = services
    }

    func show(tab: SettingsTab? = nil) {
        if self.window == nil {
            self.window = self.makeWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        self.window?.makeKeyAndOrderFront(nil)
        if let tab {
            // Post on the next turn so a freshly created view is subscribed.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .nameplateSelectSettingsTab, object: tab)
            }
        }
    }

    private func makeWindow() -> NSWindow {
        guard let services = self.services else {
            fatalError("SettingsWindowController outlived AppServices")
        }
        let hosting = NSHostingController(
            rootView: SettingsView(settings: self.settings, services: services))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Nameplate Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: SettingsView.windowWidth, height: SettingsView.windowHeight))
        window.center()
        return window
    }
}
