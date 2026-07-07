import AppKit
import SwiftUI

@MainActor
struct GeneralSettingsPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                CaptionedToggle(
                    title: "Start at login",
                    caption: "Launch Nameplate automatically when you sign in.",
                    isOn: self.$settings.launchAtLogin)
            } header: {
                Text("Startup")
            } footer: {
                Text("A branding app only works if it is actually running.")
            }

            Section {
                CaptionedToggle(
                    title: "Show name next to icon",
                    caption: "Display this Mac's name in the menu bar, not just the colored plate.",
                    isOn: self.$settings.showNameInMenuBar)
                CaptionedToggle(
                    title: "Hide menu bar icon",
                    caption: "Keep the overlays without the menu bar item. Open Nameplate again "
                        + "(e.g. from Finder or Spotlight) to get back to Settings.",
                    isOn: self.$settings.hideMenuBarIcon)
            } header: {
                Text("Menu bar")
            }

            Section {
                CaptionedToggle(
                    title: "Show overlays",
                    caption: "Turns the frame, name tag, and watermark off at once.",
                    isOn: self.$settings.overlaysEnabled)
            } header: {
                Text("Overlays")
            }

            Section {
                LabeledContent("Remove all overlays and quit") {
                    Button("Quit Nameplate") {
                        NSApp.terminate(nil)
                    }
                }
            } header: {
                Text("App")
            }
        }
        .formStyle(.grouped)
    }
}
