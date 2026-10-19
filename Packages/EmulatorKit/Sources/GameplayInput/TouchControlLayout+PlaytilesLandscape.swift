import Foundation

extension TouchControlLayout {
    /// Two copies of the measured Playtiles control band, turned clockwise so each D-pad is above
    /// its face buttons. The software-only portrait START and SELECT pills are outside this band.
    static func playtilesLandscape(
        width: Double, height: Double,
        safeTop: Double, safeBottom: Double, safeLeft: Double, safeRight: Double,
        displayScale: Double, scaling: ScreenScaling, pictureOpensMenu: Bool
    ) -> TouchControlLayout {
        let portrait = playtiles(width: height, height: width, safeBottom: 0,
                                 displayScale: displayScale, scaling: scaling, pictureOpensMenu: false)
        let scale = min(height / 1080, width / 2340)
        // Include the extended D-pad hit area, down to the skin's y=1719 line.
        let bandBottom = 1719 * scale
        let bandWidth = (1719 - 1129) * scale
        let physicalTileWidth = 40 * pointsPerMillimeter
        let padArtwork = portrait.drawnRect(.dpad)!
        let firstControlX = bandBottom - max(portrait.a.y + portrait.a.height,
                                             max(portrait.b.y + portrait.b.height, padArtwork.y + padArtwork.height))
        let lastControlX = bandBottom - min(portrait.a.y, min(portrait.b.y, padArtwork.y - 10 * scale))
        // Blank tile margins can occupy the cutout inset; buttons keep an eight-point margin.
        let left = max(8, safeLeft + 8 - firstControlX)
        let right = min(width - 8 - bandWidth, width - safeRight - 8 - lastControlX)

        func rotated(_ rect: TouchRect, at x: Double) -> TouchRect {
            TouchRect(x: x + bandBottom - rect.y - rect.height, y: rect.x,
                      width: rect.height, height: rect.width)
        }
        func art(_ control: TouchControl, at x: Double) -> TouchRect {
            rotated(portrait.drawnRect(control)!, at: x)
        }
        let dpadHit = rotated(portrait.dpadHitArea, at: left)
        let dpadHitLeft = max(safeLeft, dpadHit.x)
        func guide(at x: Double) -> TouchAlignmentGuide {
            let source = portrait.alignmentGuide!
            let center = rotated(source.bar, at: x).center
            let bar = TouchRect(x: center.x - source.bar.width / 2, y: center.y - source.bar.height / 2,
                                width: source.bar.width, height: source.bar.height)
            let tab = TouchRect(x: center.x + source.tab.x - source.bar.center.x,
                                y: bar.y + source.tab.y - source.bar.y,
                                width: source.tab.width, height: source.tab.height)
            return TouchAlignmentGuide(bar: bar, tab: tab, rotation: .pi / 2, showsBar: false)
        }

        let rightPad = art(.dpad, at: right)
        let diameter = rightPad.height * 121 / 347
        func circle(x: Double, y: Double) -> TouchRect {
            TouchRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter)
        }
        let up = circle(x: rightPad.center.x, y: rightPad.y + diameter / 2)
        let down = circle(x: rightPad.center.x, y: rightPad.y + rightPad.height - diameter / 2)
        let leftButton = circle(x: rightPad.x + diameter / 2, y: rightPad.center.y)
        let rightButton = circle(x: rightPad.x + rightPad.width - diameter / 2, y: rightPad.center.y)
        func reach(_ rect: TouchRect) -> TouchRect {
            TouchRect(x: rect.x - 10 * scale, y: rect.y - 10 * scale,
                      width: rect.width + 20 * scale, height: rect.height + 20 * scale)
        }

        let pictureLeft = left + bandWidth + 8
        // Clockwise rotation puts the tile's alignment edge on its right. Its 40 mm body extends left.
        let rightTileStart = min(right, right + bandWidth - physicalTileWidth)
        let pictureRight = rightTileStart - 8
        let pictureWidth = max(1, pictureRight - pictureLeft)
        let bottom = height - safeBottom
        let logoWidth = min(180, max(1, pictureWidth - 20))
        let logo = TouchRect(x: pictureLeft + (pictureWidth - logoWidth) / 2, y: bottom - 28,
                             width: logoWidth, height: 24)
        let menuTop = menuAreas(logo: logo, screen: portrait.screen, pictureOpensMenu: false)[0].y
        let frame = TouchRect(x: pictureLeft, y: safeTop + 8, width: pictureWidth,
                              height: max(1, menuTop - 8 - safeTop - 8))
        let screen = scaling.picture(sourceWidth: 160, sourceHeight: 144, in: frame, pixelsPerPoint: displayScale)

        return TouchControlLayout(
            dpad: rotated(portrait.dpad, at: left),
            dpadHitArea: TouchRect(x: dpadHitLeft, y: dpadHit.y,
                                   width: dpadHit.x + dpadHit.width - dpadHitLeft, height: dpadHit.height),
            a: reach(rightButton), b: reach(down),
            start: rotated(portrait.a, at: left), select: rotated(portrait.b, at: left),
            screen: screen,
            menuAreas: menuAreas(logo: logo, screen: screen, pictureOpensMenu: pictureOpensMenu),
            artwork: [.dpad: art(.dpad, at: left), .a: rightButton, .b: down,
                      .start: art(.a, at: left), .select: art(.b, at: left)],
            alignmentGuide: guide(at: left),
            additionalAlignmentGuides: [guide(at: right)],
            additionalButtons: [
                TouchButtonTarget(control: .a, area: reach(up), artwork: up),
                TouchButtonTarget(control: .b, area: reach(leftButton), artwork: leftButton),
                TouchButtonTarget(control: .start, area: rotated(portrait.a, at: right), artwork: art(.a, at: right)),
                TouchButtonTarget(control: .select, area: rotated(portrait.b, at: right), artwork: art(.b, at: right)),
            ],
            logo: logo
        )
    }
}
