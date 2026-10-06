import EmulationCore
import Foundation

/// Resolves an arbitrary set of screen touches into Game Boy input.
///
/// Touches are intentionally identified by an opaque integer supplied by the platform layer. A touch may
/// slide between directions or between A/B without lifting; every update recomputes the combined state from
/// all active touches, so multitouch combinations remain deterministic.
public final class TouchInputResolver {
    public private(set) var input = EmulatorInputState()
    public let layout: TouchControlLayout

    private var activeTouches: [Int: TouchPoint] = [:]

    public init(layout: TouchControlLayout) {
        self.layout = layout
    }

    public func touchBegan(id: Int, point: TouchPoint) {
        activeTouches[id] = point
        recompute()
    }

    public func touchMoved(id: Int, point: TouchPoint) {
        guard activeTouches[id] != nil else { return }
        activeTouches[id] = point
        recompute()
    }

    public func touchEnded(id: Int) {
        activeTouches.removeValue(forKey: id)
        recompute()
    }

    public func cancelAllTouches() {
        activeTouches.removeAll(keepingCapacity: true)
        recompute()
    }

    private func recompute() {
        var next = EmulatorInputState()
        for point in activeTouches.values {
            if layout.dpadHitArea.contains(point) {
                applyDPad(point, to: &next)
                continue
            }
            if layout.a.contains(point) { next.a = true }
            if layout.b.contains(point) { next.b = true }
            if layout.start.contains(point) { next.start = true }
            if layout.select.contains(point) { next.select = true }
        }
        input = next
    }

    private func applyDPad(_ point: TouchPoint, to input: inout EmulatorInputState) {
        let center = layout.dpad.center
        let halfWidth = max(layout.dpad.width / 2, 1)
        let halfHeight = max(layout.dpad.height / 2, 1)
        let normalizedX = (point.x - center.x) / halfWidth
        let normalizedY = (point.y - center.y) / halfHeight
        let deadZone = layout.dpadDeadZoneFraction
        let horizontalThreshold = max(deadZone, abs(normalizedY) * layout.dpadDiagonalRatio)
        let verticalThreshold = max(deadZone, abs(normalizedX) * layout.dpadDiagonalRatio)

        if normalizedX < -horizontalThreshold { input.left = true }
        if normalizedX > horizontalThreshold { input.right = true }
        if normalizedY < -verticalThreshold { input.up = true }
        if normalizedY > verticalThreshold { input.down = true }
    }
}
