import AppKit
import Combine
import NameplateCore
import notify

/// Long-lived controllers, wired together once at launch. App-lifetime object:
/// observers are registered once and never removed.
@MainActor
final class AppServices {
    private let settings: AppSettings
    private var overlay: OverlayController?
    private var splash: SplashController?
    private var attention: AttentionController?
    private var configImport: ConfigImportController?
    private var monitor: ConnectionMonitor?
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private(set) var updater: UpdaterProviding?
    private let remoteMonitor = RemoteViewMonitor()
    private var settingsCancellable: AnyCancellable?
    private var pendingAttentionRequests: [AttentionRequest] = []
    private var attentionShowing = false
    private var activeAttentionRequest: AttentionRequest?
    private var latestAttentionDismissalCutoff: Date?

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

    func showConfig(_ proposal: ConfigProposal) {
        if self.configImport == nil {
            self.configImport = ConfigImportController(settings: self.settings, services: self)
        }
        self.configImport?.show(proposal)
    }

    var hasActiveAttention: Bool {
        self.attentionShowing || !self.pendingAttentionRequests.isEmpty
            || (self.attention?.isActive ?? false)
    }

    func dismissAttention(upTo cutoff: Date) {
        let effectiveCutoff = max(self.latestAttentionDismissalCutoff ?? cutoff, cutoff)
        self.latestAttentionDismissalCutoff = effectiveCutoff
        self.pendingAttentionRequests.removeAll { !$0.wasCreated(after: effectiveCutoff) }
        AttentionRequest.discardAll(upTo: effectiveCutoff)
        guard !(self.activeAttentionRequest?.wasCreated(after: effectiveCutoff) ?? false) else { return }
        self.attentionShowing = false
        self.activeAttentionRequest = nil
        self.attention?.dismissActive()
    }

    /// Same per-screen rule the overlay uses: in remote-only mode a screen is
    /// decorated when it is virtual or someone is screen-shared in.
    /// Attention alerts ignore this.
    private func decorationAllowed(on screen: NSScreen) -> Bool {
        switch self.settings.visibilityMode {
        case .always:
            true
        case .remoteOnly:
            RemoteViewMonitor.isVirtual(screen: screen) || self.remoteMonitor.screenSharingActive
        }
    }

    func start() {
        guard self.monitor == nil else { return }
        let settings = self.settings
        self.overlay = OverlayController(settings: settings, remoteMonitor: self.remoteMonitor)
        self.splash = SplashController(settings: settings)
        self.attention = AttentionController(settings: settings)
        self.statusItem = StatusItemController(settings: settings, services: self)
        self.updater = makeUpdaterController(settings: settings)
        let monitor = ConnectionMonitor()
        self.monitor = monitor

        self.remoteMonitor.onChange = { [weak self] in
            self?.overlay?.applyVisibility()
        }
        self.remoteMonitor.setPollingEnabled(settings.visibilityMode == .remoteOnly)
        self.settingsCancellable = settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.remoteMonitor.setPollingEnabled(self.settings.visibilityMode == .remoteOnly)
                }
            }

        self.splash?.screenFilter = { [weak self] screen in
            self?.decorationAllowed(on: screen) ?? true
        }

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
        self.registerDarwinTrigger(name: AttentionRequest.notificationName) { services in
            services.drainAttentionRequests()
        }
        self.registerDarwinTrigger(name: "com.steipete.nameplate.attention.dismiss") { services in
            services.dismissAttention(upTo: Date())
        }
        self.registerDarwinTrigger(name: AttentionDismissal.notificationName) { services in
            let cutoff = AttentionDismissal.read()?.createdAt ?? Date()
            services.dismissAttention(upTo: cutoff)
        }

        // Darwin notifications are not queued: a CLI-triggered cold launch can
        // post before our observer exists. Pick up anything already on disk.
        self.latestAttentionDismissalCutoff = AttentionDismissal.read()?.createdAt
        self.drainAttentionRequests()
    }

    private func drainAttentionRequests() {
        let requests = Self.requestsCreatedAfterDismissal(
            AttentionRequest.consumeAll(),
            cutoff: self.latestAttentionDismissalCutoff)
        self.pendingAttentionRequests.append(contentsOf: requests)
        self.showNextAttentionRequest()
    }

    static func requestsCreatedAfterDismissal(
        _ requests: [AttentionRequest],
        cutoff: Date?) -> [AttentionRequest]
    {
        guard let cutoff else { return requests }
        return requests.filter { $0.wasCreated(after: cutoff) }
    }

    private func showNextAttentionRequest() {
        guard !self.attentionShowing,
              let request = Self.takeNextFreshAttentionRequest(from: &self.pendingAttentionRequests)
        else { return }
        self.attentionShowing = true
        self.activeAttentionRequest = request
        self.attention?.show(request) { [weak self] in
            guard let self else { return }
            self.attentionShowing = false
            self.activeAttentionRequest = nil
            self.showNextAttentionRequest()
        }
    }

    static func takeNextFreshAttentionRequest(
        from requests: inout [AttentionRequest],
        now: Date = Date()) -> AttentionRequest?
    {
        while !requests.isEmpty {
            let request = requests.removeFirst()
            if request.isFresh(at: now) {
                return request
            }
        }
        return nil
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
