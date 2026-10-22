import Foundation

enum ScrollOverflow {
    static func hasMoreBelow(
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        offsetY: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> Bool {
        guard viewportHeight > 0 else { return false }
        let visibleOffset = max(offsetY, -topInset)
        return contentHeight + bottomInset - visibleOffset - viewportHeight > 1
    }
}
