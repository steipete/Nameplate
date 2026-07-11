import Foundation

enum InstallOrigin {
    private static let caskName = "nameplate"
    private static let defaultApplicationURL = URL(fileURLWithPath: "/Applications/Nameplate.app")
    private static let defaultCaskroomRoots = [
        URL(fileURLWithPath: "/opt/homebrew/Caskroom"),
        URL(fileURLWithPath: "/usr/local/Caskroom"),
    ]

    static func isHomebrewCask(
        appBundleURL: URL,
        caskroomRoots: [URL] = Self.defaultCaskroomRoots,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Bool {
        let path = appBundleURL.path
        if path.contains("/Caskroom/") || path.contains("/Homebrew/Caskroom/") {
            return true
        }
        guard appBundleURL.standardizedFileURL == Self.defaultApplicationURL else {
            return false
        }
        return caskroomRoots.contains { root in
            fileExists(root.appendingPathComponent(Self.caskName, isDirectory: true).path)
        }
    }
}
