import Foundation

/// The built-in on-screen controller layouts. Raw values are stored in settings.
public enum TouchControlStyle: String, Codable, Sendable, CaseIterable {
    /// The original Game Boy's front panel: the screen on top, the D-pad left, A above and right
    /// of B, and SELECT and START side by side below them, at the hardware's sizes and angles.
    case gameBoy
    /// The Playtiles GBC skin's layout, with START and SELECT swapped into Game Boy order.
    case playtiles
}

/// How the game picture is scaled into its frame. Raw values are stored in settings.
public enum ScreenScaling: String, Codable, Sendable, CaseIterable {
    /// The largest whole number of device pixels per Game Boy pixel, so every pixel is the same size.
    case integer
    /// As large as the frame allows at the Game Boy's shape, with pixel edges smoothed so the
    /// pixels still look even.
    case fill

    /// Where a `sourceWidth` by `sourceHeight` picture goes in `frame`, centered. Integer scaling
    /// snaps it to whole device pixels at `pixelsPerPoint`; a frame too small for one whole
    /// multiple falls back to fill.
    public func picture(sourceWidth: Double, sourceHeight: Double, in frame: TouchRect, pixelsPerPoint: Double) -> TouchRect {
        let pixels = max(pixelsPerPoint, 1)
        let fit = min(frame.width / sourceWidth, frame.height / sourceHeight)
        var width = sourceWidth * fit, height = sourceHeight * fit
        if self == .integer {
            let multiple = floor(fit * pixels + 1e-9)
            if multiple >= 1 {
                width = sourceWidth * multiple / pixels
                height = sourceHeight * multiple / pixels
            }
        }
        var x = frame.x + (frame.width - width) / 2
        var y = frame.y + (frame.height - height) / 2
        if self == .integer {
            x = (x * pixels).rounded(.down) / pixels
            y = (y * pixels).rounded(.down) / pixels
        }
        return TouchRect(x: x, y: y, width: width, height: height)
    }
}

/// The on-screen controller's colors, the same across layouts. Raw values are stored in settings.
public enum ControllerTheme: String, Codable, Sendable, CaseIterable {
    /// Classic in Light Mode, Dark in Dark Mode.
    case matchSystem
    /// Game Boy colors: a warm gray body, magenta A and B, and navy lettering.
    case classic
    /// The same design on a near-black body.
    case dark
}

/// A drawn control, for looking up its artwork.
public enum TouchControl: Hashable, Sendable {
    case dpad
    case a
    case b
    case start
    case select
}

/// Marks where a physical controller overlay sits on the screen. Drawn only; it takes no touches.
public struct TouchAlignmentGuide: Equatable, Sendable {
    /// A band across the screen.
    public let bar: TouchRect
    /// A tab hanging from the bar, its bottom fully rounded.
    public let tab: TouchRect

    public init(bar: TouchRect, tab: TouchRect) {
        self.bar = bar
        self.tab = tab
    }
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
    /// Where the game picture goes. Screen Scaling decides how the picture fills it.
    public let screen: TouchRect
    /// Where a tap opens the app's menu: the logo, and the game picture when that's turned on.
    public let menuAreas: [TouchRect]
    /// The glass around the game picture, when the layout draws one. Drawn only.
    public let bezel: TouchRect?
    /// How far START and SELECT, and the lettering under them, tilt, in radians. Negative tilts
    /// rise to the right.
    public let selectStartTilt: Double
    /// Where a control is drawn, when that differs from where it responds to touches.
    public let artwork: [TouchControl: TouchRect]
    public let alignmentGuide: TouchAlignmentGuide?
    /// Where the Press Any logo is printed. Drawn only; it takes no touches.
    public let logo: TouchRect?
    public let dpadDeadZoneFraction: Double

    public init(
        dpad: TouchRect,
        dpadHitArea: TouchRect? = nil,
        a: TouchRect,
        b: TouchRect,
        start: TouchRect,
        select: TouchRect,
        screen: TouchRect = .init(x: 0, y: 0, width: 0, height: 0),
        menuAreas: [TouchRect] = [],
        bezel: TouchRect? = nil,
        selectStartTilt: Double = 0,
        artwork: [TouchControl: TouchRect] = [:],
        alignmentGuide: TouchAlignmentGuide? = nil,
        logo: TouchRect? = nil,
        dpadDeadZoneFraction: Double = 0.16
    ) {
        self.dpad = dpad
        self.dpadHitArea = dpadHitArea ?? dpad
        self.a = a
        self.b = b
        self.start = start
        self.select = select
        self.screen = screen
        self.menuAreas = menuAreas
        self.bezel = bezel
        self.selectStartTilt = selectStartTilt
        self.artwork = artwork
        self.alignmentGuide = alignmentGuide
        self.logo = logo
        self.dpadDeadZoneFraction = min(max(dpadDeadZoneFraction, 0), 0.49)
    }

    /// Whether a tap at `point` opens the menu. Game Boy controls take precedence.
    public func opensMenu(at point: TouchPoint) -> Bool {
        guard ![dpadHitArea, a, b, start, select].contains(where: { $0.contains(point) }) else { return false }
        return menuAreas.contains { $0.contains(point) }
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
        }
    }
}

extension TouchControlLayout {
    /// The layout for `style` in a portrait view of the given size, in points. `safeTop` keeps the
    /// screen clear of the status bar and `safeBottom` the logo clear of the home indicator.
    /// `displayScale` lets the Game Boy layout size the picture to whole device pixels under
    /// `scaling`. `pictureOpensMenu` makes a tap on the game picture open the menu as well as one
    /// on the logo.
    public static func make(
        _ style: TouchControlStyle,
        width: Double,
        height: Double,
        safeTop: Double = 0,
        safeBottom: Double = 0,
        displayScale: Double = 3,
        scaling: ScreenScaling = .integer,
        pictureOpensMenu: Bool = false
    ) -> TouchControlLayout {
        switch style {
        case .gameBoy:
            gameBoy(
                width: width,
                height: height,
                safeTop: safeTop,
                safeBottom: safeBottom,
                displayScale: displayScale,
                scaling: scaling,
                pictureOpensMenu: pictureOpensMenu
            )
        case .playtiles:
            playtiles(
                width: width,
                height: height,
                safeBottom: safeBottom,
                displayScale: displayScale,
                scaling: scaling,
                pictureOpensMenu: pictureOpensMenu
            )
        }
    }

    /// The logo's tap area, 44 points tall and grown upward, away from the home indicator, and the
    /// picture when it opens the menu too.
    static func menuAreas(logo: TouchRect, screen: TouchRect, pictureOpensMenu: Bool) -> [TouchRect] {
        let logoArea = TouchRect(x: logo.x - 10, y: logo.y - 16, width: logo.width + 20, height: logo.height + 20)
        return pictureOpensMenu ? [logoArea, screen] : [logoArea]
    }

    /// The logo's box, centered just above the home indicator, or the bottom edge without one.
    static func logo(width: Double, height: Double, safeBottom: Double) -> TouchRect {
        TouchRect(x: width / 2 - 90, y: height - max(safeBottom, 12) - 28, width: 180, height: 24)
    }

    /// The original Game Boy (DMG-01) front panel, in millimeters from its left edge and from the
    /// top of the screen window, measured from a photograph of the hardware and scaled so the
    /// body is its specified 90 mm wide.
    enum GameBoyPanel {
        static let width = 90.0
        static let dpad = (x: 18.2, y: 84.9)
        static let dpadSize = 22.9
        static let a = (x: 79.7, y: 80.4)
        static let b = (x: 64.4, y: 87.4)
        static let buttonSize = 10.8
        static let select = (x: 32.5, y: 107.7)
        static let start = (x: 48.6, y: 107.7)
        static let pillSize = (length: 10.3, width: 3.3)
        /// START and SELECT rise about 18 degrees to the right.
        static let pillTilt = -18.0 * Double.pi / 180
    }

    /// Points per millimeter on an iPhone screen, near enough on every model (153 to 163 points
    /// per inch), so the controls come out at the Game Boy's own size.
    static let pointsPerMillimeter = 6.1

    /// The Game Boy layout. The D-pad, buttons and START and SELECT are drawn at the hardware's
    /// size, with its spacing and angles. Across the width they keep the Game Boy's proportions,
    /// pulled in as needed so nothing leaves the screen, and START and SELECT center under the
    /// logo. The game picture sits at the top, as wide as the edge margins allow, or at a whole
    /// number of device pixels per Game Boy pixel under integer scaling. The controls are centered
    /// between its bezel and the logo, and touch areas reach past them without overlapping.
    static func gameBoy(
        width: Double,
        height: Double,
        safeTop: Double,
        safeBottom: Double,
        displayScale: Double,
        scaling: ScreenScaling,
        pictureOpensMenu: Bool
    ) -> TouchControlLayout {
        let mm = pointsPerMillimeter
        let panel = GameBoyPanel.self
        let edgeMargin = 8.0

        // The picture fits inside the edge margins, which limit only its width: the height given is
        // more than it can use. The bezel takes up to 12 points of what's left on each side.
        let available = TouchRect(x: edgeMargin, y: 0, width: max(width - 2 * edgeMargin, 1), height: width)
        let fitted = scaling.picture(sourceWidth: 160, sourceHeight: 144, in: available, pixelsPerPoint: displayScale)
        let pictureWidth = fitted.width
        let pictureHeight = fitted.height
        let bezelPadding = min(12, (width - pictureWidth) / 2)
        let screen = TouchRect(
            x: (width - pictureWidth) / 2,
            y: max(safeTop, 20) + edgeMargin + bezelPadding,
            width: pictureWidth,
            height: pictureHeight
        )
        let bezel = TouchRect(
            x: screen.x - bezelPadding,
            y: screen.y - bezelPadding,
            width: pictureWidth + 2 * bezelPadding,
            height: pictureHeight + 2 * bezelPadding
        )
        let logo = logo(width: width, height: height, safeBottom: safeBottom)

        let dpadSize = panel.dpadSize * mm
        let buttonSize = panel.buttonSize * mm
        let pill = (length: panel.pillSize.length * mm, width: panel.pillSize.width * mm)

        // Across: the Game Boy's proportions of the width, kept clear of the edges.
        let dpadX = max(width * panel.dpad.x / panel.width, edgeMargin + dpadSize / 2)
        let aX = min(width * panel.a.x / panel.width, width - edgeMargin - buttonSize / 2)
        // A to B at the hardware's spacing and angle, closed up only if B would crowd the D-pad.
        var aToB = (x: (panel.a.x - panel.b.x) * mm, y: (panel.b.y - panel.a.y) * mm)
        let bLimit = dpadX + dpadSize / 2 + 12 + buttonSize / 2
        if aX - aToB.x < bLimit {
            let shrink = max((aX - bLimit) / aToB.x, (buttonSize + 6) / (aToB.x * aToB.x + aToB.y * aToB.y).squareRoot())
            aToB = (aToB.x * shrink, aToB.y * shrink)
        }
        // The hardware puts START and SELECT a little left of center; here they center under the logo.
        let pillsX = width / 2
        let pillSpacing = (panel.start.x - panel.select.x) * mm

        // Down, relative to the D-pad's center: A and B a little higher and lower, START and
        // SELECT well below. The block runs from the D-pad's top to the lettering under the pills.
        let aY = (panel.a.y - panel.dpad.y) * mm
        let lettering = 26.0
        let space = logo.y - (bezel.y + bezel.height)
        var pillsY = (panel.select.y - panel.dpad.y) * mm
        let blockHeight = dpadSize / 2 + pillsY + lettering
        if space < blockHeight { pillsY = max(100, pillsY - (blockHeight - space)) }
        let dpadY = bezel.y + bezel.height + max(0, (space - (dpadSize / 2 + pillsY + lettering)) / 2) + dpadSize / 2

        let dpad = TouchPoint(x: dpadX, y: dpadY)
        let a = TouchPoint(x: aX, y: dpadY + aY)
        let b = TouchPoint(x: aX - aToB.x, y: a.y + aToB.y)
        let select = TouchPoint(x: pillsX - pillSpacing / 2, y: dpadY + pillsY)
        let start = TouchPoint(x: pillsX + pillSpacing / 2, y: dpadY + pillsY)

        // Touch areas stop at the screen's edges.
        func onScreen(_ r: TouchRect) -> TouchRect {
            let minX = max(r.x, 0), maxX = min(r.x + r.width, width)
            return TouchRect(x: minX, y: r.y, width: maxX - minX, height: r.height)
        }
        func centered(_ center: TouchPoint, _ width: Double, _ height: Double) -> TouchRect {
            TouchRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        }
        func square(_ center: TouchPoint, _ size: Double) -> TouchRect { centered(center, size, size) }
        // Buttons take touches 10 points past their edge, the D-pad 12, and START and SELECT a
        // 44-point-tall band, each narrower where it would meet its neighbor.
        let buttonReach = min(buttonSize + 20, (aToB.x * aToB.x + aToB.y * aToB.y).squareRoot() - 2)
        let pillReach = (length: min(pill.length + 24, pillSpacing - 4), width: 44.0)
        let dpadRect = square(dpad, dpadSize)

        return TouchControlLayout(
            dpad: dpadRect,
            dpadHitArea: onScreen(square(dpad, dpadSize + 24)),
            a: onScreen(square(a, buttonReach)),
            b: onScreen(square(b, buttonReach)),
            start: onScreen(centered(start, pillReach.length, pillReach.width)),
            select: onScreen(centered(select, pillReach.length, pillReach.width)),
            screen: screen,
            menuAreas: menuAreas(logo: logo, screen: screen, pictureOpensMenu: pictureOpensMenu),
            bezel: bezel,
            selectStartTilt: panel.pillTilt,
            artwork: [
                .dpad: dpadRect,
                .a: square(a, buttonSize),
                .b: square(b, buttonSize),
                // Unrotated; drawn turned by `selectStartTilt` about the center.
                .select: centered(select, pill.length, pill.width),
                .start: centered(start, pill.length, pill.width),
            ],
            logo: logo
        )
    }

    /// The Playtiles GBC Delta skin (`info.json`, iPhone edge-to-edge portrait) in its 1080x2340
    /// mapping space, scaled to fit the view and centered across it. Touch areas are the skin's
    /// frames joined with its artwork; drawing follows the artwork, measured from the skin's PDF.
    /// The picture is sized by `scaling` inside the skin's screen frame, and the bezel fills the
    /// rest of that frame.
    static func playtiles(
        width: Double,
        height: Double,
        safeBottom: Double,
        displayScale: Double,
        scaling: ScreenScaling,
        pictureOpensMenu: Bool
    ) -> TouchControlLayout {
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
        let screenFrame = frame(11, 167, 1058, 951.8717683557)
        let screen = scaling.picture(sourceWidth: 160, sourceHeight: 144, in: screenFrame, pixelsPerPoint: displayScale)
        let logo = logo(width: width, height: height, safeBottom: safeBottom)

        return TouchControlLayout(
            dpad: frame(70, 1283, 376, 376),
            // The skin extends the D-pad's touch area by 60 above, 60 below, 26 left and 60 right.
            dpadHitArea: frame(70 - 26, 1283 - 60, 376 + 26 + 60, 376 + 60 + 60),
            a: union(frame(800, 1469, 184, 184), aArt),
            b: union(frame(662, 1269, 184, 184), bArt),
            start: union(frame(863, 1900, 108, 108), startArt),
            select: union(frame(702, 1901, 108, 108), selectArt),
            screen: screen,
            // The skin's Menu button and tap-the-game Fast Forward are left out: the logo opens
            // the menu, as on the Game Boy layout.
            menuAreas: menuAreas(logo: logo, screen: screen, pictureOpensMenu: pictureOpensMenu),
            bezel: screenFrame,
            artwork: [
                .dpad: dpadArt,
                .a: aArt,
                .b: bArt,
                .start: startArt,
                .select: selectArt,
            ],
            // The Playtiles controller lines up against the skin's teal bar and the U-shaped tab
            // hanging from its center, measured from the skin's PDF.
            alignmentGuide: TouchAlignmentGuide(
                bar: frame(0, 1129, 1080, 83),
                tab: frame(494, 1129, 92, 182)
            ),
            logo: logo
        )
    }
}
