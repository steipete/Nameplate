import NameplateCore
import SwiftUI

/// Measures the whole pill before anchoring it; shared by the overlay and settings preview.
struct NameTagLayout: Layout {
    let position: TagPosition
    let inset: CGFloat
    let horizontalOffset: Double
    let verticalOffset: Double
    var topSafeAreaInset: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let tag = subviews.first else { return }
        // Top-center tags must sit below a display notch. Corner tags keep their existing inset.
        let topInset = self.position == .topCenter ? min(max(0, self.topSafeAreaInset), bounds.height) : 0
        let usableHeight = bounds.height - topInset
        let tagProposal = ProposedViewSize(
            width: max(0, bounds.width - 2 * self.inset),
            height: max(0, usableHeight - 2 * self.inset))
        let measured = tag.sizeThatFits(tagProposal)
        let size = CGSize(width: min(measured.width, bounds.width), height: min(measured.height, usableHeight))
        let origin = self.position.origin(
            width: bounds.width, height: usableHeight,
            tagWidth: size.width, tagHeight: size.height, inset: self.inset,
            horizontalOffset: self.horizontalOffset, verticalOffset: self.verticalOffset)
        tag.place(
            at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + topInset + origin.y),
            anchor: .topLeading,
            proposal: ProposedViewSize(size))
    }
}
