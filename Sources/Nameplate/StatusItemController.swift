import AppKit
import Combine
import NameplateCore

/// Classic NSStatusItem + NSMenu. Reliable everywhere, and gives us live
/// info rows (uptime, IP, stats) refreshed each time the menu opens.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let settings: AppSettings
    private unowned let services: AppServices
    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?

    private let headerItem = NSMenuItem()
    private let uptimeItem = NSMenuItem()
    private let ipItem = NSMenuItem()
    private let statsItem = NSMenuItem()
    private let diskItem = NSMenuItem()
    private let locationItem = NSMenuItem()
    private let overlaysItem = NSMenuItem()
    private let frameItem = NSMenuItem()
    private let tagItem = NSMenuItem()
    private let watermarkItem = NSMenuItem()
    private let dismissAttentionItem = NSMenuItem()

    private var copyableIP: String?

    init(settings: AppSettings, services: AppServices) {
        self.settings = settings
        self.services = services
        super.init()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = self.buildMenu()
        self.statusItem = statusItem
        self.applyAppearance()

        // objectWillChange fires before the write lands; hop once to read
        // post-change values.
        self.cancellable = settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.applyAppearance()
                }
            }
    }

    private func applyAppearance() {
        guard let statusItem = self.statusItem, let button = statusItem.button else { return }
        let identity = self.settings.identity
        button.image = StatusItemIcon.image(for: identity)
        button.imagePosition = .imageLeading
        button.title = self.settings.showNameInMenuBar ? " \(identity.name)" : ""
        statusItem.isVisible = !self.settings.hideMenuBarIcon
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        self.headerItem.isEnabled = false
        menu.addItem(self.headerItem)
        self.locationItem.isEnabled = false
        menu.addItem(self.locationItem)
        menu.addItem(.separator())

        for item in [self.uptimeItem, self.statsItem, self.diskItem] {
            item.isEnabled = false
            menu.addItem(item)
        }
        self.ipItem.isEnabled = true
        self.ipItem.target = self
        self.ipItem.action = #selector(self.copyIPAddress)
        self.ipItem.toolTip = "Copy IP address"
        menu.addItem(self.ipItem)
        menu.addItem(.separator())

        self.configureToggle(self.overlaysItem, title: "Show overlays", action: #selector(self.toggleOverlays))
        menu.addItem(self.overlaysItem)
        self.configureToggle(self.frameItem, title: "Frame", action: #selector(self.toggleFrame))
        menu.addItem(self.frameItem)
        self.configureToggle(self.tagItem, title: "Name tag", action: #selector(self.toggleTag))
        menu.addItem(self.tagItem)
        self.configureToggle(self.watermarkItem, title: "Watermark", action: #selector(self.toggleWatermark))
        menu.addItem(self.watermarkItem)

        let splashItem = NSMenuItem(title: "Show splash", action: #selector(self.showSplash), keyEquivalent: "")
        splashItem.target = self
        menu.addItem(splashItem)

        self.dismissAttentionItem.title = "Dismiss attention"
        self.dismissAttentionItem.target = self
        self.dismissAttentionItem.action = #selector(self.dismissAttention)
        menu.addItem(self.dismissAttentionItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(self.openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "About Nameplate", action: #selector(self.openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit Nameplate", action: #selector(self.quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func configureToggle(_ item: NSMenuItem, title: String, action: Selector) {
        item.title = title
        item.target = self
        item.action = action
        item.isEnabled = true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let identity = self.settings.identity
        let glyph = identity.glyph.isEmpty ? "" : "\(identity.glyph) "
        self.headerItem.title = "\(glyph)\(identity.name)"
        self.locationItem.title = identity.location
        self.locationItem.isHidden = identity.location.isEmpty
        if !identity.location.isEmpty {
            self.locationItem.image = NSImage(
                systemSymbolName: "mappin.and.ellipse",
                accessibilityDescription: "Location")
        }

        self.uptimeItem.title = "Uptime \(SystemInfo.uptime() ?? "–")"
        if let ip = SystemInfo.primaryIPAddress() {
            self.copyableIP = ip.address
            self.ipItem.title = "IP \(ip.address) (\(ip.interface))"
            self.ipItem.isEnabled = true
        } else {
            self.copyableIP = nil
            self.ipItem.title = "IP –"
            self.ipItem.isEnabled = false
        }
        self.statsItem.title = SystemInfo.statsLine()
        self.statsItem.isHidden = self.statsItem.title.isEmpty
        if let disk = SystemInfo.diskLine() {
            self.diskItem.title = disk
            self.diskItem.isHidden = false
        } else {
            self.diskItem.isHidden = true
        }

        self.overlaysItem.state = self.settings.overlaysEnabled ? .on : .off
        self.frameItem.state = self.settings.frameEnabled ? .on : .off
        self.tagItem.state = self.settings.tagEnabled ? .on : .off
        self.watermarkItem.state = self.settings.watermarkEnabled ? .on : .off
        self.dismissAttentionItem.isEnabled = self.services.hasActiveAttention
    }

    @objc private func copyIPAddress() {
        guard let ip = self.copyableIP else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
    }

    @objc private func toggleOverlays() { self.settings.overlaysEnabled.toggle() }
    @objc private func toggleFrame() { self.settings.frameEnabled.toggle() }
    @objc private func toggleTag() { self.settings.tagEnabled.toggle() }
    @objc private func toggleWatermark() { self.settings.watermarkEnabled.toggle() }

    @objc private func showSplash() {
        self.services.showSplash(force: true)
    }

    @objc private func dismissAttention() {
        self.services.dismissAttention(upTo: Date())
    }

    @objc private func openSettings() {
        self.services.showSettings()
    }

    @objc private func openAbout() {
        self.services.showSettings(tab: .about)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
