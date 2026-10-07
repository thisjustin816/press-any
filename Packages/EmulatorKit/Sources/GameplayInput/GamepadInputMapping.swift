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

    public static func input(
        dpad: EmulatorInputState = .init(),
        leftStickX: Float = 0,
        leftStickY: Float = 0,
        rightFaceButton: Bool = false,
        bottomFaceButton: Bool = false,
        menu: Bool = false,
        options: Bool = false,
        leftShoulder: Bool = false
    ) -> EmulatorInputState {
        let stick = directions(x: leftStickX, y: leftStickY)
        return EmulatorInputState(
            up: dpad.up || stick.up, down: dpad.down || stick.down,
            left: dpad.left || stick.left, right: dpad.right || stick.right,
            a: rightFaceButton, b: bottomFaceButton,
            start: menu, select: options || leftShoulder
        )
    }
}
