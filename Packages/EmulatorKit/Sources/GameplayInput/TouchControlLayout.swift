import Foundation

/// The built-in on-screen controller layouts. Raw values are stored in settings.
public enum TouchControlStyle: String, Codable, Sendable, CaseIterable {
    /// SameBoy's portrait layout: the screen on top, the D-pad left, A above and right of B, and
    /// SELECT and START below them, as on a Game Boy.
    case gameBoy
    /// The Playtiles GBC skin's layout, with START and SELECT swapped into Game Boy order.
    case playtiles
}

/// Controls that drive the app rather than the emulated Game Boy.
public enum TouchAction: Hashable, Sendable {
    case menu
    case toggleFastForward
}

/// A drawn control, for looking up its artwork.
public enum TouchControl: Hashable, Sendable {
    case dpad
    case a
    case b
    case start
    case select
    case action(TouchAction)
}

public struct TouchControlLayout: Equatable, Sendable {
    /// Directions are measured from the D-pad's center.
    public let dpad: TouchRect
    /// Where a touch counts as the D-pad.
    public let dpadHitArea: TouchRect
    public let a: TouchRect
    public let b: TouchRect
    public let start: TouchRect
    public let select: TouchRect
    /// Where the game picture goes. The picture is aspect-fit inside it.
    public let screen: TouchRect
    public let actions: [TouchAction: TouchRect]
    /// Where a control is drawn, when that differs from where it responds to touches.
    public let artwork: [TouchControl: TouchRect]
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
        artwork: [TouchControl: TouchRect] = [:],
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
        self.artwork = artwork
        self.dpadDeadZoneFraction = min(max(dpadDeadZoneFraction, 0), 0.49)
    }

    /// The app action under `point`, if any. Game Boy controls take precedence.
    public func action(at point: TouchPoint) -> TouchAction? {
        guard ![dpadHitArea, a, b, start, select].contains(where: { $0.contains(point) }) else { return nil }
        return actions.first { $0.value.contains(point) }?.key
    }

    /// Where `control` is drawn.
    public func drawnRect(_ control: TouchControl) -> TouchRect? {
        if let art = artwork[control] { return art }
        switch control {
        case .dpad: return dpad
        case .a: return a
        case .b: return b
        case .start: return start
        case .select: return select
        case .action(let action): return actions[action]
        }
    }
}

extension TouchControlLayout {
    /// The layout for `style` in a portrait view of the given size, in points. `safeTop` keeps
    /// the screen clear of the status bar; `displayScale` lets the Game Boy layout size the
    /// picture to whole device pixels, as SameBoy does.
    public static func make(
        _ style: TouchControlStyle,
        width: Double,
        height: Double,
        safeTop: Double = 0,
        safeBottom: Double = 0,
        displayScale: Double = 3
    ) -> TouchControlLayout {
        switch style {
        case .gameBoy:
            gameBoy(width: width, height: height, safeTop: safeTop, displayScale: displayScale)
        case .playtiles:
            playtiles(width: width, height: height)
        }
    }

    /// SameBoy 1.0.3's `GBVerticalLayout`, in points rather than pixels. Positions are the
    /// controls' centers; sizes are SameBoy's touch radii (36 for buttons, 75 for the D-pad).
    static func gameBoy(width: Double, height: Double, safeTop: Double, displayScale: Double) -> TouchControlLayout {
        let scale = max(displayScale, 1)
        let screenWidth = max(floor(width * scale / 160), 1) * 160 / scale
        let screenHeight = screenWidth / 160 * 144
        let border = min(screenWidth / 40, 16)
        let statusBar = safeTop > 0 ? safeTop : 20
        let screen = TouchRect(
            x: (width - screenWidth) / 2,
            y: statusBar + min(border * 2, 20),
            width: screenWidth,
            height: screenHeight
        )
        let controlAreaStart = screen.y + screenHeight + min(border * 2, 20)

        let select = TouchPoint(
            x: min(width / 4, 120),
            y: min(height - 80, (height - controlAreaStart) * 0.75 + controlAreaStart)
        )
        let start = TouchPoint(x: width - select.x, y: select.y)

        let buttonRadius = 36.0
        let maxDistance = width / 2 - buttonRadius * 2 - border * 2
        let delta = maxDistance >= 90
            ? (width: 90.0, height: 45.0)
            : (width: maxDistance, height: floor((100 * 100 - maxDistance * maxDistance).squareRoot()))

        let dpad = TouchPoint(x: select.x, y: select.y - 140)
        let buttonsCenter = TouchPoint(x: width - dpad.x, y: dpad.y)
        let a = TouchPoint(x: buttonsCenter.x + delta.width / 2, y: buttonsCenter.y - delta.height / 2)
        let b = TouchPoint(x: buttonsCenter.x - delta.width / 2, y: buttonsCenter.y + delta.height / 2)

        func square(_ center: TouchPoint, radius: Double) -> TouchRect {
            TouchRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        }
        // SameBoy opens its menu from its logo. Here Menu is a small pill between SELECT and
        // START, which nothing else uses.
        let menu = TouchRect(x: width / 2 - 26, y: select.y - 12, width: 52, height: 24)

        return TouchControlLayout(
            dpad: square(dpad, radius: 75),
            a: square(a, radius: buttonRadius),
            b: square(b, radius: buttonRadius),
            start: square(start, radius: buttonRadius),
            select: square(select, radius: buttonRadius),
            screen: screen,
            actions: [.menu: menu],
            artwork: [
                // SameBoy's images: a 147x151 cross and 75x79 buttons.
                .dpad: square(dpad, radius: 74),
                .a: square(a, radius: 37),
                .b: square(b, radius: 37),
            ]
        )
    }

    /// The Playtiles GBC Delta skin (`info.json`, iPhone edge-to-edge portrait) in its 1080x2340
    /// mapping space, scaled to fit the view and centered across it. Touch areas are the skin's
    /// frames joined with its artwork; drawing follows the artwork, measured from the skin's PDF.
    static func playtiles(width: Double, height: Double) -> TouchControlLayout {
        let scale = min(width / 1080, height / 2340)
        let originX = (width - 1080 * scale) / 2
        func frame(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> TouchRect {
            TouchRect(x: originX + x * scale, y: y * scale, width: w * scale, height: h * scale)
        }
        func union(_ lhs: TouchRect, _ rhs: TouchRect) -> TouchRect {
            let minX = min(lhs.x, rhs.x), minY = min(lhs.y, rhs.y)
            let maxX = max(lhs.x + lhs.width, rhs.x + rhs.width), maxY = max(lhs.y + lhs.height, rhs.y + rhs.height)
            return TouchRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        // A is the larger button in the artwork: 190 across to B's 157.
        let aArt = frame(796, 1461, 190, 191)
        let bArt = frame(688, 1297, 157, 158)
        let dpadArt = frame(83, 1297, 347, 354)
        // The skin draws START at the left pill and SELECT at the right; they are swapped into
        // Game Boy order, frames and artwork together.
        let selectArt = frame(691, 1924, 134, 53)
        let startArt = frame(847, 1924, 135, 53)
        let menuArt = frame(81, 1924, 134, 53)

        return TouchControlLayout(
            dpad: frame(70, 1283, 376, 376),
            // The skin extends the D-pad's touch area by 60 above, 60 below, 26 left and 60 right.
            dpadHitArea: frame(70 - 26, 1283 - 60, 376 + 26 + 60, 376 + 60 + 60),
            a: union(frame(800, 1469, 184, 184), aArt),
            b: union(frame(662, 1269, 184, 184), bArt),
            start: union(frame(863, 1900, 108, 108), startArt),
            select: union(frame(702, 1901, 108, 108), selectArt),
            screen: frame(11, 167, 1058, 951.8717683557),
            actions: [
                .menu: union(frame(94, 1899, 108, 108), menuArt),
                .toggleFastForward: frame(108, 263, 867, 780),
            ],
            artwork: [
                .dpad: dpadArt,
                .a: aArt,
                .b: bArt,
                .start: startArt,
                .select: selectArt,
                .action(.menu): menuArt,
            ]
        )
    }
}
