import AppKit
import notify

/// Long-lived controllers, wired together once at launch. App-lifetime object:
/// observers are registered once and never removed.
@MainActor
final class AppServices {
    private let settings: AppSettings
    private var overlay: OverlayController?
    private var splash: SplashController?
    private var monitor: ConnectionMonitor?
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func showSplash(force: Bool = false) {
        self.splash?.show(force: force)
    }

    func showSettings(tab: SettingsTab? = nil) {
        if self.settingsWindow == nil {
            self.settingsWindow = SettingsWindowController(settings: self.settings, services: self)
        }
        self.settingsWindow?.show(tab: tab)
    }

    func start() {
        guard self.monitor == nil else { return }
        let settings = self.settings
        self.overlay = OverlayController(settings: settings)
        self.splash = SplashController(settings: settings)
        self.statusItem = StatusItemController(settings: settings, services: self)
        let monitor = ConnectionMonitor()
        self.monitor = monitor

        monitor.onTrigger = { [weak self, weak settings] trigger in
            guard let self, let settings else { return }
            let wanted = switch trigger {
            case .wake: settings.splashOnWake
            case .unlock: settings.splashOnUnlock
            case .displayChange: settings.splashOnDisplayChange
            }
            if wanted {
                self.splash?.show()
            }
        }

        _ = NotificationCenter.default.addObserver(
            forName: .nameplateShowSplash,
            object: nil,
            queue: .main)
        { [weak self] _ in
            MainActor.assumeIsolated {
                self?.splash?.show(force: true)
            }
        }

        _ = NotificationCenter.default.addObserver(
            forName: .nameplateOpenSettings,
            object: nil,
            queue: .main)
        { [weak self] _ in
            MainActor.assumeIsolated {
                self?.showSettings()
            }
        }

        // Scripting hooks that work everywhere, no app activation needed:
        //   notifyutil -p com.steipete.nameplate.splash
        self.registerDarwinTrigger(name: "com.steipete.nameplate.splash") { services in
            services.splash?.show(force: true)
        }
        self.registerDarwinTrigger(name: "com.steipete.nameplate.settings") { services in
            services.showSettings()
        }
    }

    private func registerDarwinTrigger(name: String, action: @escaping @MainActor (AppServices) -> Void) {
        var token: Int32 = 0
        notify_register_dispatch(name, &token, DispatchQueue.main) { [weak self] (_: Int32) in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
    }
}
