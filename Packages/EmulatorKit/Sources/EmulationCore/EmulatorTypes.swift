import Foundation

public struct EmulatorInputState: Equatable, Sendable {
    public var up: Bool
    public var down: Bool
    public var left: Bool
    public var right: Bool
    public var a: Bool
    public var b: Bool
    public var start: Bool
    public var select: Bool

    public init(
        up: Bool = false,
        down: Bool = false,
        left: Bool = false,
        right: Bool = false,
        a: Bool = false,
        b: Bool = false,
        start: Bool = false,
        select: Bool = false
    ) {
        self.up = up
        self.down = down
        self.left = left
        self.right = right
        self.a = a
        self.b = b
        self.start = start
        self.select = select
    }
}

public enum EmulationSpeed: Equatable, Sendable {
    case normal
    case multiplier(Double)
    case unlimited
}

public struct EmulatorVideoFrame: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let bgra8888: Data
    public let emulatedNanoseconds: UInt64

    public init(width: Int, height: Int, bgra8888: Data, emulatedNanoseconds: UInt64) {
        self.width = width
        self.height = height
        self.bgra8888 = bgra8888
        self.emulatedNanoseconds = emulatedNanoseconds
    }
}

public struct StereoSample: Equatable, Sendable {
    public let left: Int16
    public let right: Int16

    public init(left: Int16, right: Int16) {
        self.left = left
        self.right = right
    }
}
