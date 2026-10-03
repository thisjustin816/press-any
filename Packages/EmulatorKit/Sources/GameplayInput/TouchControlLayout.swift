import Foundation

public struct TouchControlLayout: Equatable, Sendable {
    public let dpad: TouchRect
    public let a: TouchRect
    public let b: TouchRect
    public let start: TouchRect
    public let select: TouchRect
    public let dpadDeadZoneFraction: Double

    public init(
        dpad: TouchRect,
        a: TouchRect,
        b: TouchRect,
        start: TouchRect,
        select: TouchRect,
        dpadDeadZoneFraction: Double = 0.16
    ) {
        self.dpad = dpad
        self.a = a
        self.b = b
        self.start = start
        self.select = select
        self.dpadDeadZoneFraction = min(max(dpadDeadZoneFraction, 0), 0.49)
    }
}

extension TouchControlLayout {
    /// The built-in portrait layout for a view of the given size, in points.
    public static func standard(width: Double, height: Double) -> TouchControlLayout {
        let scale = max(0.75, min(width / 390.0, 1.35))
        let dpadSize = 126.0 * scale
        let button = 66.0 * scale
        let bottom = max(20.0, min(56.0, height * 0.055))
        let controlsY = height - bottom - dpadSize

        let dpad = TouchRect(x: 24 * scale, y: controlsY, width: dpadSize, height: dpadSize)
        let a = TouchRect(x: width - 24 * scale - button, y: controlsY + 8 * scale, width: button, height: button)
        let b = TouchRect(x: width - 42 * scale - button * 2, y: controlsY + 42 * scale, width: button, height: button)

        // SELECT and START stack in the gap between the D-pad and B, level with the bottom of the
        // D-pad. Placed in a row they overlap both, and moving the cluster up to make room for a
        // row covers the bottom of the game picture on small phones.
        let gapStart = dpad.x + dpad.width + 6 * scale
        let gapEnd = b.x - 6 * scale
        let menuWidth = min(gapEnd - gapStart, 60 * scale)
        let menuHeight = 22.0 * scale
        let menuX = (gapStart + gapEnd - menuWidth) / 2
        let startY = dpad.y + dpad.height - menuHeight
        let selectY = startY - menuHeight - 8 * scale

        return TouchControlLayout(
            dpad: dpad,
            a: a,
            b: b,
            start: .init(x: menuX, y: startY, width: menuWidth, height: menuHeight),
            select: .init(x: menuX, y: selectY, width: menuWidth, height: menuHeight)
        )
    }
}
