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
        // START and SELECT get their own row under the D-pad and A/B, so no touch can land in two
        // controls at once.
        let menuHeight = 24.0 * scale
        let menuY = height - bottom - menuHeight
        let controlsY = menuY - 12 * scale - dpadSize

        return TouchControlLayout(
            dpad: .init(x: 24 * scale, y: controlsY, width: dpadSize, height: dpadSize),
            a: .init(x: width - 24 * scale - button, y: controlsY + 8 * scale, width: button, height: button),
            b: .init(x: width - 42 * scale - button * 2, y: controlsY + 42 * scale, width: button, height: button),
            start: .init(x: width / 2 + 8 * scale, y: menuY, width: 70 * scale, height: menuHeight),
            select: .init(x: width / 2 - 78 * scale, y: menuY, width: 70 * scale, height: menuHeight)
        )
    }
}
