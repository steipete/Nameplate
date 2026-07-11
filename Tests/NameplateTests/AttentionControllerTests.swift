import AppKit
import NameplateCore
import SwiftUI
import Testing
@testable import Nameplate

@MainActor
@Suite("Attention card presentation")
struct AttentionControllerTests {
    @Test func constrainedMeasurementDoesNotCreateFullHeightInputPanel() {
        let controller = NSHostingController(
            rootView: AttentionCardView(
                request: AttentionRequest(
                    title: "Codex to Nameplate",
                    message: "Issue 22 regression"),
                colorHex: "#1D9E75",
                identity: MacIdentity(name: "miniclaw", colorHex: "#1D9E75"),
                onDismiss: {}))
        let available = NSSize(width: AttentionController.cardMaximumWidth, height: 680)

        let size = controller.sizeThatFits(in: available)

        #expect(AttentionController.isValidCardSize(size, fitting: available))
        #expect(size.height < 250)
    }

    @Test func rejectsInvalidOrOversizedCardMeasurements() {
        let available = NSSize(width: 584, height: 680)
        #expect(!AttentionController.isValidCardSize(.zero, fitting: available))
        #expect(!AttentionController.isValidCardSize(
            NSSize(width: 584, height: 681),
            fitting: available))
        #expect(!AttentionController.isValidCardSize(
            NSSize(width: CGFloat.infinity, height: 100),
            fitting: available))
    }

    @Test func longMessagesStayWithinTheCardHeightLimit() {
        let controller = NSHostingController(
            rootView: AttentionCardView(
                request: AttentionRequest(
                    title: "Long attention request",
                    message: String(repeating: "This message must not create a full-screen input panel. ", count: 100)),
                colorHex: "#1D9E75",
                identity: MacIdentity(name: "miniclaw", colorHex: "#1D9E75"),
                onDismiss: {}))
        let available = NSSize(
            width: AttentionController.cardMaximumWidth,
            height: AttentionController.cardMaximumHeight)

        let size = controller.sizeThatFits(in: available)

        #expect(AttentionController.isValidCardSize(size, fitting: available))
        #expect(size.height <= AttentionController.cardMaximumHeight)
    }

    @Test func interactivePanelStartsClickThroughAndAvoidsStationaryBehavior() throws {
        let screen = try #require(NSScreen.main ?? NSScreen.screens.first)
        let panel = OverlayPanelFactory.makeAttentionCardPanel(for: screen, level: .floating)
        defer { panel.close() }

        #expect(panel.ignoresMouseEvents)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(!panel.collectionBehavior.contains(.stationary))
    }

    @Test func explicitDismissCompletesPresentedRequestExactlyOnce() {
        let controller = AttentionController(settings: AppSettings())
        var completionCount = 0
        controller.show(AttentionRequest(title: "Queue proof", message: "First")) {
            completionCount += 1
        }

        #expect(controller.isActive)
        controller.dismissActive()
        #expect(!controller.isActive)
        #expect(completionCount == 1)

        controller.dismissActive()
        #expect(completionCount == 1)
    }
}
