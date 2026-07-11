import Foundation
import Testing
@testable import Nameplate

@Suite("Install origin")
struct InstallOriginTests {
    @Test func recognizesLegacyCaskroomBundlePaths() {
        #expect(InstallOrigin.isHomebrewCask(
            appBundleURL: URL(fileURLWithPath: "/opt/homebrew/Caskroom/nameplate/0.2.6/Nameplate.app"),
            caskroomRoots: [],
            fileExists: { _ in false }))
        #expect(InstallOrigin.isHomebrewCask(
            appBundleURL: URL(fileURLWithPath: "/usr/local/Homebrew/Caskroom/nameplate/0.2.6/Nameplate.app"),
            caskroomRoots: [],
            fileExists: { _ in false }))
    }

    @Test func recognizesApplicationsBundleWhenReceiptExists() {
        let root = URL(fileURLWithPath: "/test/Caskroom")
        let expectedReceipt = root.appendingPathComponent("nameplate", isDirectory: true).path

        #expect(InstallOrigin.isHomebrewCask(
            appBundleURL: URL(fileURLWithPath: "/Applications/Nameplate.app"),
            caskroomRoots: [root],
            fileExists: { $0 == expectedReceipt }))
    }

    @Test func rejectsApplicationsBundleWithoutReceipt() {
        #expect(!InstallOrigin.isHomebrewCask(
            appBundleURL: URL(fileURLWithPath: "/Applications/Nameplate.app"),
            caskroomRoots: [URL(fileURLWithPath: "/test/Caskroom")],
            fileExists: { _ in false }))
    }
}
