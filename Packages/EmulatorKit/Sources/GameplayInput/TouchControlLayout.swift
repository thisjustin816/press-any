import Foundation

/// The built-in on-screen controller layouts. Raw values are stored in settings.
public enum TouchControlStyle: String, Codable, Sendable, CaseIterable {
    /// Arranged like a Game Boy: screen on top, D-pad left, A above and right of B, and SELECT
    /// then START centered below.
    case gameBoy
    /// The Playtiles GBC skin's layout, with START and SELECT swapped into Game Boy order.
    case playtiles
}

/// Controls that drive the app rather than the emulated Game Boy.
public enum TouchAction: Hashable, Sendable {
    case menu
    case quickSave
    case quickLoad
    case toggleFastForward
}

public struct TouchControlLayout: Equatable, Sendable {
    public let dpad: TouchRect
    /// Where a touch counts as the D-pad. Directions are still measured from the D-pad's center.
    public let dpadHitArea: TouchRect
    public let a: TouchRect
    public let b: TouchRect
    public let start: TouchRect
    public let select: TouchRect
    /// Where the game picture goes. The picture is aspect-fit inside it.
    public let screen: TouchRect
    public let actions: [TouchAction: TouchRect]
    public let dpadDeadZoneFraction: Double

    public init(
        dpad: TouchRect,
        dpadHitArea: TouchRect? = nil,
        a: TouchRect,
        b: TouchRect,
        start: TouchRect,
        select: TouchRect,
        screen: TouchRect = .init(x: 0, y: 0, width: 0, height: 0),
        actions: [TouchAction: TouchRect] = [:],
        dpadDeadZoneFraction: Double = 0.16
    ) {
        self.dpad = dpad
        self.dpadHitArea = dpadHitArea ?? dpad
        self.a = a
        self.b = b
        self.start = start
        self.select = select
        self.screen = screen
        self.actions = actions
        self.dpadDeadZoneFraction = min(max(dpadDeadZoneFraction, 0), 0.49)
    }

    /// The app action under `point`, if any. Game Boy controls take precedence.
    public func action(at point: TouchPoint) -> TouchAction? {
        guard ![dpadHitArea, a, b, start, select].contains(where: { $0.contains(point) }) else { return nil }
        return actions.first { $0.value.contains(point) }?.key
    }
}

extension TouchControlLayout {
    /// The layout for `style` in a portrait view of the given size, in points. The safe-area
    /// insets keep the screen clear of the status bar and the controls clear of the home indicator.
    public static func make(
        _ style: TouchControlStyle,
        width: Double,
        height: Double,
        safeTop: Double = 0,
        safeBottom: Double = 0
    ) -> TouchControlLayout {
        switch style {
        case .gameBoy:
            gameBoy(width: width, height: height, safeTop: safeTop, safeBottom: safeBottom)
        case .playtiles:
            playtiles(width: width, height: height)
        }
    }

    static func gameBoy(width: Double, height: Double, safeTop: Double, safeBottom: Double) -> TouchControlLayout {
        let scale = max(0.75, min(width / 390.0, 1.35))

        // The picture sits near the top like a Game Boy's screen, below the app's close and menu
        // buttons, filling the width.
        let margin = 16 * scale
        let screenY = safeTop + 56
        let screenWidth = width - margin * 2
        let screen = TouchRect(x: margin, y: screenY, width: screenWidth, height: screenWidth * 144 / 160)

        let regionTop = screen.y + screen.height
        let regionBottom = height - max(safeBottom, 16)
        let dpadSize = 132 * scale
        let dpadCenterY = regionTop + (regionBottom - regionTop) * 0.4
        let dpad = TouchRect(
            x: width * 0.24 - dpadSize / 2,
            y: dpadCenterY - dpadSize / 2,
            width: dpadSize,
            height: dpadSize
        )

        // A sits above and to the right of B, as on the hardware.
        let button = 70 * scale
        let a = TouchRect(
            x: width * 0.81 - button / 2,
            y: dpadCenterY - 22 * scale - button / 2,
            width: button,
            height: button
        )
        let b = TouchRect(
            x: a.x - 84 * scale,
            y: dpadCenterY + 20 * scale - button / 2,
            width: button,
            height: button
        )

        // SELECT then START, centered below, as on the hardware.
        let menuWidth = 64 * scale
        let menuHeight = 24 * scale
        let menuY = max(dpad.y + dpad.height, b.y + b.height) + 24 * scale
        let select = TouchRect(x: width / 2 - 8 * scale - menuWidth, y: menuY, width: menuWidth, height: menuHeight)
        let start = TouchRect(x: width / 2 + 8 * scale, y: menuY, width: menuWidth, height: menuHeight)

        return TouchControlLayout(dpad: dpad, a: a, b: b, start: start, select: select, screen: screen)
    }

    /// Frames from the Playtiles GBC Delta skin (`info.json`, iPhone edge-to-edge portrait),
    /// in its 1080x2340 mapping space, scaled to fit the view and centered across it.
    static func playtiles(width: Double, height: Double) -> TouchControlLayout {
        let scale = min(width / 1080, height / 2340)
        let originX = (width - 1080 * scale) / 2
        func frame(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> TouchRect {
            TouchRect(x: originX + x * scale, y: y * scale, width: w * scale, height: h * scale)
        }

        let dpad = frame(70, 1283, 376, 376)
        // The skin extends the D-pad's touch area by 60 above, 60 below, 26 left and 60 right.
        let dpadHitArea = frame(70 - 26, 1283 - 60, 376 + 26 + 60, 376 + 60 + 60)

        return TouchControlLayout(
            dpad: dpad,
            dpadHitArea: dpadHitArea,
            a: frame(800, 1469, 184, 184),
            b: frame(662, 1269, 184, 184),
            // The skin puts START left of SELECT; these are swapped into Game Boy order.
            start: frame(863, 1900, 108, 108),
            select: frame(702, 1901, 108, 108),
            screen: frame(11, 167, 1058, 951.8717683557),
            actions: [
                .menu: frame(94, 1899, 108, 108),
                .quickSave: frame(67, 1140, 227, 62),
                .quickLoad: frame(766, 1140, 227, 58),
                .toggleFastForward: frame(108, 263, 867, 780),
            ]
        )
    }
}
