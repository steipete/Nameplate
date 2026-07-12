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

    @Test func queuedPresentationSkipsRequestsThatExpiredWhileWaiting() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var requests = [
            AttentionRequest(
                message: "stale past",
                createdAt: now.addingTimeInterval(-AttentionRequest.maxAge - 1)),
            AttentionRequest(
                message: "stale future",
                createdAt: now.addingTimeInterval(AttentionRequest.maxAge + 1)),
            AttentionRequest(message: "fresh", createdAt: now),
        ]

        let selection = AppServices.takeNextFreshAttentionRequest(from: &requests, now: now)
        let next = try #require(selection.request)

        #expect(next.message == "fresh")
        #expect(selection.expired.map(\.message) == ["stale past", "stale future"])
        #expect(requests.isEmpty)
    }

    @Test func laterDrainStillRejectsRequestsCreatedBeforeDismissal() {
        let cutoff = Date(timeIntervalSince1970: 1_800_000_000)
        let requests = [
            AttentionRequest(message: "before", createdAt: cutoff.addingTimeInterval(-1)),
            AttentionRequest(message: "undated"),
            AttentionRequest(message: "after", createdAt: cutoff.addingTimeInterval(1)),
        ]

        let retained = AppServices.requestsCreatedAfterDismissal(requests, cutoff: cutoff)

        #expect(retained.map(\.message) == ["after"])
    }

    // A forced teardown (the `nameplate dismiss` recovery command, or any
    // fail-safe path that can't keep the card presented) must complete a
    // waiting `--wait` CLI instead of leaving it blocked until timeout.
    @Test func forcedDismissAcknowledgesTheWaitingRequest() {
        let controller = AttentionController(settings: AppSettings())
        let id = "test-forced-dismiss-\(UUID().uuidString)"
        defer { AttentionAck.remove(matching: id) }

        // No duration = sticky: the card would otherwise stay up until clicked.
        controller.show(AttentionRequest(id: id, message: "needs a human"))
        controller.dismissActive()

        let ack = AttentionAck.consume(matching: id)
        #expect(ack?.outcome == .autoDismissed)
    }
}
