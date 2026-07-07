import AppKit
import SwiftUI

@MainActor
struct AboutPane: View {
    @ObservedObject var settings: AppSettings
    weak var updater: UpdaterProviding?

    var body: some View {
        Form {
            Section {
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
                    Spacer()
                }
                .padding(.vertical, 4)

                Text("Brand every Mac in your fleet so you always know which one you just "
                    + "remoted into. A colored frame, a name tag, a watermark, and a connect "
                    + "splash — all click-through overlays. Your wallpaper stays untouched.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                if let updater = self.updater, updater.isAvailable {
                    Toggle(
                        "Automatically download and install updates",
                        isOn: self.autoUpdateBinding)
                    Button("Check for Updates…") {
                        self.updater?.checkForUpdates(nil)
                    }
                } else {
                    Text(self.updater?.unavailableReason ?? "Updates unavailable in this build.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Updates")
            }

            Section {
                Link("GitHub", destination: URL(string: "https://github.com/steipete/Nameplate")!)
                Link(
                    "Report an issue",
                    destination: URL(string: "https://github.com/steipete/Nameplate/issues")!)
            } footer: {
                Text("© 2026 Peter Steinberger. MIT licensed.")
            }
        }
        .formStyle(.grouped)
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
