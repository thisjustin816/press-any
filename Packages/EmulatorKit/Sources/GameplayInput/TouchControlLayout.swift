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
