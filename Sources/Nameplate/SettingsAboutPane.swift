import AppKit
import SwiftUI

@MainActor
struct AboutPane: View {
    @ObservedObject var settings: AppSettings
    weak var updater: UpdaterProviding?

    var body: some View {
        SettingsPaneLayout {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nameplate")
                            .font(.title2.weight(.semibold))
                        Text("Version \(Self.version)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Brand every Mac in your fleet so you always know which one you just "
                    + "remoted into. A colored frame, a name tag, a watermark, and a connect "
                    + "splash — all click-through overlays. Your wallpaper stays untouched.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("GitHub") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/steipete/Nameplate")!)
                    }
                    Button("Report an issue") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/steipete/Nameplate/issues")!)
                    }
                }

                Divider()

                if let updater = self.updater, updater.isAvailable {
                    VStack(alignment: .leading, spacing: 10) {
                        PreferenceToggleRow(
                            title: "Automatically download and install updates",
                            subtitle: nil,
                            binding: self.autoUpdateBinding)
                        Button("Check for Updates…") {
                            self.updater?.checkForUpdates(nil)
                        }
                    }
                } else {
                    Text(self.updater?.unavailableReason ?? "Updates unavailable in this build.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }

                Text("© 2026 Peter Steinberger. MIT licensed.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var autoUpdateBinding: Binding<Bool> {
        Binding(
            get: { self.settings.autoUpdateEnabled },
            set: { newValue in
                self.settings.autoUpdateEnabled = newValue
                self.updater?.automaticallyChecksForUpdates = newValue
                self.updater?.automaticallyDownloadsUpdates = newValue
            })
    }

    private static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (short?, build?): return "\(short) (\(build))"
        case let (short?, nil): return short
        default: return "dev"
        }
    }
}
