import AppKit
import NameplateCore

// Plain AppKit lifecycle. The SwiftUI scene machinery (MenuBarExtra menus,
// Settings scene, URL-event routing) proved unreliable for menu-bar-only apps
// on current macOS builds; AppKit's NSStatusItem + NSMenu are dependable.
@main
@MainActor
enum NameplateMain {
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = self.delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings?
    private var services: AppServices?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settings = AppSettings()
        let services = AppServices(settings: settings)
        self.settings = settings
        self.services = services
        services.start()

        let firstRunKey = "hasCompletedFirstRun"
        if !UserDefaults.standard.bool(forKey: firstRunKey) {
            UserDefaults.standard.set(true, forKey: firstRunKey)
            services.showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        self.services?.showSettings()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "nameplate" {
            switch url.host() {
            case "splash":
                self.services?.showSplash(force: true)
            case "settings":
                self.services?.showSettings()
            case "config":
                if let proposal = ConfigProposal(url: url) {
                    self.services?.showConfig(proposal)
                } else {
                    self.services?.showSettings()
                }
            default:
                break
            }
        }
    }
}
