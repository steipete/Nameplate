import SwiftUI

enum SettingsTab: String, Hashable {
    case identity, layers, splash, general, about
}

@MainActor
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let services: AppServices
    @State private var selectedTab: SettingsTab = .identity

    var body: some View {
        TabView(selection: self.$selectedTab) {
            IdentitySettingsPane(settings: self.settings)
                .tabItem { Label("Identity", systemImage: "person.text.rectangle") }
                .tag(SettingsTab.identity)

            LayersSettingsPane(settings: self.settings)
                .tabItem { Label("Layers", systemImage: "square.3.layers.3d") }
                .tag(SettingsTab.layers)

            SplashSettingsPane(settings: self.settings, services: self.services)
                .tabItem { Label("Splash", systemImage: "sparkles.rectangle.stack") }
                .tag(SettingsTab.splash)

            GeneralSettingsPane(settings: self.settings)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            AboutPane(settings: self.settings, updater: self.services.updater)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: Self.windowWidth, height: Self.windowHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(NotificationCenter.default.publisher(for: .nameplateSelectSettingsTab)) { notification in
            guard let tab = notification.object as? SettingsTab else { return }
            self.selectedTab = tab
        }
    }

    static let windowWidth: CGFloat = 560
    static let windowHeight: CGFloat = 600
}

extension Notification.Name {
    static let nameplateOpenSettings = Notification.Name("nameplateOpenSettings")
    static let nameplateSelectSettingsTab = Notification.Name("nameplateSelectSettingsTab")
}
