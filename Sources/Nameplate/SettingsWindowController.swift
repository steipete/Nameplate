import AppKit
import SwiftUI

/// Native settings window: NSTabViewController with toolbar-style tabs (the
/// System Settings look — icons in the title bar, window resizes per pane).
/// The SwiftUI `Settings` scene is unreliable for menu-bar-only apps on
/// current macOS builds, so we own the window ourselves.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var tabController: NSTabViewController?
    private let settings: AppSettings
    private weak var services: AppServices?

    private static let paneWidth: CGFloat = 560
    private static let frameAutosaveName = "NameplateSettingsWindow"

    init(settings: AppSettings, services: AppServices) {
        self.settings = settings
        self.services = services
    }

    func show(tab: SettingsTab? = nil) {
        if self.window == nil {
            self.makeWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        self.window?.makeKeyAndOrderFront(nil)
        if let tab, let index = SettingsTab.allCases.firstIndex(of: tab) {
            self.tabController?.selectedTabViewItemIndex = index
        }
    }

    private func makeWindow() {
        guard let services = self.services else {
            fatalError("SettingsWindowController outlived AppServices")
        }
        let settings = self.settings

        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar

        func addPane(_ tab: SettingsTab, symbol: String, height: CGFloat, view: some View) {
            let hosting = NSHostingController(rootView: view)
            hosting.title = tab.label
            hosting.preferredContentSize = NSSize(width: Self.paneWidth, height: height)
            let item = NSTabViewItem(viewController: hosting)
            item.label = tab.label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tab.label)
            tabs.addTabViewItem(item)
        }

        addPane(
            .identity, symbol: "person.text.rectangle", height: 620,
            view: IdentitySettingsPane(settings: settings))
        addPane(
            .layers, symbol: "square.3.layers.3d", height: 680,
            view: LayersSettingsPane(settings: settings))
        addPane(
            .splash, symbol: "sparkles.rectangle.stack", height: 560,
            view: SplashSettingsPane(settings: settings, services: services))
        addPane(
            .general, symbol: "gearshape", height: 470,
            view: GeneralSettingsPane(settings: settings))
        addPane(
            .about, symbol: "info.circle", height: 480,
            view: AboutPane(settings: settings, updater: services.updater))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        let restoredFrame = window.setFrameUsingName(Self.frameAutosaveName)
        window.setFrameAutosaveName(Self.frameAutosaveName)
        if !restoredFrame {
            window.center()
        }
        self.tabController = tabs
        self.window = window
    }
}
