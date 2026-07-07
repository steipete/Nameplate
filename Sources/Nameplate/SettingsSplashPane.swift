import SwiftUI

@MainActor
struct SplashSettingsPane: View {
    @ObservedObject var settings: AppSettings
    let services: AppServices

    static let splashCommand = "notifyutil -p com.steipete.nameplate.splash"

    var body: some View {
        Form {
            Section {
                Toggle("Enable splash", isOn: self.$settings.splashEnabled)
                SliderRow(
                    title: "Duration",
                    value: self.$settings.splashDuration,
                    range: 0.8...4,
                    format: { String(format: "%.1f s", $0) })
                    .disabled(!self.settings.splashEnabled)
                LabeledContent("Preview") {
                    Button("Show splash") {
                        self.services.showSplash(force: true)
                    }
                }
            } header: {
                Text("Connect splash")
            } footer: {
                Text("Flashes this Mac's name across the screen when a remote session likely just "
                    + "started, then fades out.")
            }

            Section {
                Group {
                    Toggle("When displays wake", isOn: self.$settings.splashOnWake)
                    Toggle("When the screen unlocks", isOn: self.$settings.splashOnUnlock)
                    Toggle("When displays change", isOn: self.$settings.splashOnDisplayChange)
                }
                .disabled(!self.settings.splashEnabled)
            } header: {
                Text("Triggers")
            } footer: {
                Text("macOS has no public \"remote session started\" event, so Nameplate reacts to its "
                    + "reliable companions. On a headless Mac, the remote host plugging in its virtual "
                    + "display fires the display trigger.")
            }

            Section {
                LabeledContent {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.splashCommand, forType: .string)
                    }
                    .controlSize(.small)
                } label: {
                    Text(verbatim: Self.splashCommand)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            } header: {
                Text("Scripting")
            } footer: {
                Text("Trigger the splash from anywhere — hook it into your own connect automation. "
                    + "The bundled CLI (Contents/Helpers/nameplate) can also raise attention alerts.")
            }
        }
        .formStyle(.grouped)
    }
}
