import AppKit
import Security

/// Sparkle gating: updates only make sense for Developer ID-signed bundled
/// builds that were not installed via Homebrew.
@MainActor
protocol UpdaterProviding: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var isAvailable: Bool { get }
    var unavailableReason: String? { get }
    func checkForUpdates(_ sender: Any?)
}

/// No-op updater for dev/unsigned/brew builds to suppress Sparkle dialogs.
final class DisabledUpdaterController: UpdaterProviding {
    var automaticallyChecksForUpdates: Bool = false
    var automaticallyDownloadsUpdates: Bool = false
    let isAvailable: Bool = false
    let unavailableReason: String?

    init(unavailableReason: String? = nil) {
        self.unavailableReason = unavailableReason
    }

    func checkForUpdates(_: Any?) {}
}

#if canImport(Sparkle)
import Sparkle

@MainActor
final class SparkleUpdaterController: NSObject, UpdaterProviding {
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil)
    let unavailableReason: String? = nil

    init(savedAutoUpdate: Bool) {
        super.init()
        let updater = self.controller.updater
        updater.automaticallyChecksForUpdates = savedAutoUpdate
        updater.automaticallyDownloadsUpdates = savedAutoUpdate
        self.controller.startUpdater()
    }

    var automaticallyChecksForUpdates: Bool {
        get { self.controller.updater.automaticallyChecksForUpdates }
        set { self.controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { self.controller.updater.automaticallyDownloadsUpdates }
        set { self.controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    var isAvailable: Bool { true }

    func checkForUpdates(_ sender: Any?) {
        self.controller.checkForUpdates(sender)
    }
}
#endif

private func isDeveloperIDSigned(bundleURL: URL) -> Bool {
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
          let code = staticCode else { return false }

    var infoCF: CFDictionary?
    guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF) == errSecSuccess,
          let info = infoCF as? [String: Any],
          let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
          let leaf = certs.first else { return false }

    if let summary = SecCertificateCopySubjectSummary(leaf) as String? {
        return summary.hasPrefix("Developer ID Application:")
    }
    return false
}

@MainActor
func makeUpdaterController(settings: AppSettings) -> UpdaterProviding {
    #if canImport(Sparkle)
    let bundleURL = Bundle.main.bundleURL
    guard bundleURL.pathExtension == "app" else {
        return DisabledUpdaterController(unavailableReason: "Updates unavailable in this build.")
    }
    if InstallOrigin.isHomebrewCask(appBundleURL: bundleURL) {
        return DisabledUpdaterController(
            unavailableReason: "Updates managed by Homebrew. Run: brew upgrade --cask nameplate")
    }
    guard isDeveloperIDSigned(bundleURL: bundleURL) else {
        return DisabledUpdaterController(unavailableReason: "Updates unavailable in this build.")
    }
    return SparkleUpdaterController(savedAutoUpdate: settings.autoUpdateEnabled)
    #else
    return DisabledUpdaterController(unavailableReason: "Updates unavailable in this build.")
    #endif
}
