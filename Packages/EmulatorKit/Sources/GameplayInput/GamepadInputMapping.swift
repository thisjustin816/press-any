import EmulationCore
import Foundation

public enum GamepadInputMapping {
    /// Normalized stick axes, with positive Y pointing up.
    public static func directions(x: Float, y: Float) -> EmulatorInputState {
        guard hypot(x, y) > 0.25 else { return .init() }
        let sector = Int((atan2(Double(y), Double(x)) / (.pi / 4)).rounded())
        return switch (sector + 8) % 8 {
        case 0: .init(right: true)
        case 1: .init(up: true, right: true)
        case 2: .init(up: true)
        case 3: .init(up: true, left: true)
        case 4: .init(left: true)
        case 5: .init(down: true, left: true)
        case 6: .init(down: true)
        default: .init(down: true, right: true)
        }
    }

    /// The buttons arrive after any remapping in iOS Settings > General > Game Controller, the only
    /// button mapping there is. A and B follow the controller's letters, and X and Y are START and
    /// SELECT for controllers whose Menu and Options buttons are hard to reach. A PlayStation
    /// controller has no lettered buttons, so A is Circle and B is Cross, where a Game Boy has
    /// them, and Triangle is START. The shoulders stay free for Rewind and Fast Forward.
    public static func input(
        dpad: EmulatorInputState = .init(),
        leftStickX: Float = 0,
        leftStickY: Float = 0,
        buttonA: Bool = false,
        buttonB: Bool = false,
        buttonX: Bool = false,
        buttonY: Bool = false,
        menu: Bool = false,
        options: Bool = false,
        isPlayStation: Bool = false
    ) -> EmulatorInputState {
        let stick = directions(x: leftStickX, y: leftStickY)
        return EmulatorInputState(
            up: dpad.up || stick.up, down: dpad.down || stick.down,
            left: dpad.left || stick.left, right: dpad.right || stick.right,
            a: isPlayStation ? buttonB : buttonA,
            b: isPlayStation ? buttonA : buttonB,
            start: menu || (isPlayStation ? buttonY : buttonX),
            select: options || (isPlayStation ? buttonX : buttonY)
        )
    }
}
