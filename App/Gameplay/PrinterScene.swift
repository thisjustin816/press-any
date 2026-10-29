import EmulationCore
import UIKit

/// The Printer background: the slip coming out of a printer the way it does on the machine. The
/// layout follows the Game Boy Printer: a smoked lid over the paper roll rising above a tall gray
/// body, a black panel with the slot and its serrated cutter, the name centered under it and a
/// power light, a raised badge, and the Feed button and power switch low on the body.
/// The slip is rendered on a transparent background first, then the printer is drawn around it,
/// so its pixel grid stays as the renderer made it.
enum PrinterScene {
    private static let width: CGFloat = 1300
    /// The slip's paper starts this far into its transparent render.
    private static let paperInset: CGFloat = CGFloat(24 * PrinterSlipRenderer.scale)
    private static let bodyInset: CGFloat = 70
    /// How far the lid stands above the body's top edge.
    private static let lidRise: CGFloat = 150
    /// The body from its top edge to the panel.
    private static let lidHeight: CGFloat = 520
    private static let panelHeight: CGFloat = 470
    private static let panelInset: CGFloat = 70
    /// The body below the panel.
    private static let baseHeight: CGFloat = 900
    /// The wider slab the body stands on, showing below it.
    private static let baseStep: CGFloat = 30
    private static let windowTop: CGFloat = 34
    private static let windowInset: CGFloat = 230
    /// From the slot window's top edge to the cutter.
    private static let slotDepth: CGFloat = 40
    private static let cutterBar: CGFloat = 8
    /// How far the paper's bottom edge runs into the slot: past the cutter's bar by a tooth's depth,
    /// so the notches in that edge stay inside the printer, where the paper is cut off from view.
    private static let paperSink: CGFloat = slotDepth + cutterBar + CGFloat(PrinterSlipRenderer.tearDepth)

    private static let panelBlack = UIColor(red: 0.086, green: 0.094, blue: 0.106, alpha: 1)
    private static let lettering = UIColor(white: 0.93, alpha: 1)
    private static let bodyInk = UIColor(white: 0.45, alpha: 1)

    static func render(_ slip: PrinterSlip) -> UIImage? {
        guard let paper = cgImage(PrinterSlipRenderer.render(slip, background: .transparent)) else { return nil }
        let paperSize = CGSize(width: paper.width, height: paper.height)
        // A short slip comes out under the lid; a long one rises above the printer.
        let bodyTop = max(40 + lidRise, paperSize.height - paperInset - paperSink - lidHeight - windowTop + 40)
        let panelTop = bodyTop + lidHeight
        let slotY = panelTop + windowTop
        let bodyBottom = panelTop + panelHeight + baseHeight
        let paperOrigin = CGPoint(x: (width - paperSize.width) / 2, y: slotY + paperSink + paperInset - paperSize.height)
        let size = CGSize(width: width, height: bodyBottom + baseStep + 40)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            UIColor(white: 0.1, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            drawBody(in: cg, top: bodyTop, bottom: bodyBottom)
            drawLid(in: cg, top: bodyTop - lidRise, bottom: panelTop)
            drawPanel(in: cg, top: panelTop, slotY: slotY)
            // UIKit draws a CGImage upside down without this flip. Below the cutter, the paper is
            // inside the printer.
            cg.saveGState()
            cg.clip(to: CGRect(x: 0, y: 0, width: width, height: slotY + slotDepth + cutterBar))
            cg.translateBy(x: 0, y: paperOrigin.y * 2 + paperSize.height)
            cg.scaleBy(x: 1, y: -1)
            cg.interpolationQuality = .none
            cg.draw(paper, in: CGRect(origin: paperOrigin, size: paperSize))
            cg.restoreGState()
            shadePaperInSlot(in: cg, paperOrigin: paperOrigin, paperWidth: paperSize.width, slotY: slotY)
            drawCutter(in: cg, slotY: slotY, paperLeft: paperOrigin.x + paperInset)
            drawBase(in: cg, top: panelTop + panelHeight)
        }
    }

    /// Fills `rect`, clipped to `path`, with a top-to-bottom gradient.
    private static func fill(_ path: UIBezierPath, in cg: CGContext, from top: UIColor, to bottom: UIColor, over rect: CGRect) {
        let colors = [top.cgColor, bottom.cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        cg.saveGState()
        path.addClip()
        cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
        cg.restoreGState()
    }

    /// The gray body, standing on a slightly wider slab.
    private static func drawBody(in cg: CGContext, top: CGFloat, bottom: CGFloat) {
        UIColor(red: 0.59, green: 0.58, blue: 0.56, alpha: 1).setFill()
        UIBezierPath(roundedRect: CGRect(x: bodyInset - 12, y: bottom - 60, width: width - (bodyInset - 12) * 2, height: 60 + baseStep),
                     cornerRadius: 40).fill()
        let body = CGRect(x: bodyInset, y: top, width: width - bodyInset * 2, height: bottom - top)
        let path = UIBezierPath(roundedRect: body, cornerRadius: 48)
        // The same Game Boy gray as the Classic touch controller.
        let palette = ControllerPalette.classic
        fill(path, in: cg, from: palette.bodyTop, to: palette.bodyBottom, over: body)
        UIColor(white: 0.55, alpha: 1).setStroke()
        path.lineWidth = 4
        path.stroke()
    }

    /// The smoked, see-through lid over the paper roll, with a darker rim along its top. It is as
    /// wide as the panel it sits on.
    private static func drawLid(in cg: CGContext, top: CGFloat, bottom: CGFloat) {
        let lid = CGRect(x: bodyInset + panelInset, y: top, width: width - (bodyInset + panelInset) * 2, height: bottom - top)
        let path = UIBezierPath(roundedRect: lid, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 70, height: 70))
        fill(path, in: cg, from: UIColor(red: 0.27, green: 0.29, blue: 0.31, alpha: 1),
             to: UIColor(red: 0.38, green: 0.40, blue: 0.42, alpha: 1), over: lid)
        // The paper roll shows through: a cylinder lying across, lightest along its middle.
        let roll = CGRect(x: windowInset, y: lid.minY + 80, width: width - windowInset * 2, height: lid.height - 150)
        cg.saveGState()
        UIBezierPath(roundedRect: roll, cornerRadius: 40).addClip()
        let rollColors = [UIColor(white: 0.55, alpha: 0.5).cgColor, UIColor(white: 0.85, alpha: 0.55).cgColor,
                          UIColor(white: 0.5, alpha: 0.5).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: rollColors, locations: [0, 0.45, 1]) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: roll.minY), end: CGPoint(x: 0, y: roll.maxY), options: [])
        }
        cg.restoreGState()
        cg.saveGState()
        path.addClip()
        UIColor(red: 0.12, green: 0.13, blue: 0.14, alpha: 0.9).setFill()
        cg.fill(CGRect(x: lid.minX, y: lid.minY, width: lid.width, height: 54))
        // Light on the clear plastic along one side.
        UIColor(white: 1, alpha: 0.12).setFill()
        cg.fill(CGRect(x: lid.minX + 24, y: lid.minY + 80, width: 10, height: lid.height - 120))
        cg.restoreGState()
        UIColor(white: 0.16, alpha: 1).setStroke()
        path.lineWidth = 4
        path.stroke()
    }

    /// The black panel: the slot window near its top, the name centered under it, and the power
    /// light with BATT. marked under it.
    private static func drawPanel(in cg: CGContext, top: CGFloat, slotY: CGFloat) {
        let panel = CGRect(x: bodyInset + panelInset, y: top, width: width - (bodyInset + panelInset) * 2, height: panelHeight)
        panelBlack.setFill()
        UIBezierPath(roundedRect: panel, cornerRadius: 10).fill()
        let window = CGRect(x: windowInset, y: slotY, width: width - windowInset * 2, height: slotDepth + cutterBar + 40)
        UIColor.black.setFill()
        UIBezierPath(roundedRect: window, cornerRadius: 8).fill()

        // The wordmark over "printer", their left edges lined up and the two centered together.
        let wordmarkHeight: CGFloat = 64
        let name = wordmark(height: wordmarkHeight)
        let printer = NSAttributedString(string: "printer", attributes: [
            .font: UIFont.systemFont(ofSize: 160, weight: .heavy).withTraits(.traitItalic),
            .foregroundColor: lettering,
        ])
        let blockWidth = max(name?.size.width ?? 0, printer.size().width)
        let left = (width - blockWidth) / 2 - 20
        let textTop = window.maxY + 50
        name?.draw(at: CGPoint(x: left + 8, y: textTop))
        printer.draw(at: CGPoint(x: left, y: textTop + wordmarkHeight - 6))

        let light = CGPoint(x: panel.maxX - 70, y: textTop + 60)
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: 24, color: UIColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.8).cgColor)
        UIColor(red: 0.92, green: 0.07, blue: 0.1, alpha: 1).setFill()
        cg.fillEllipse(in: CGRect(x: light.x - 17, y: light.y - 17, width: 34, height: 34))
        cg.restoreGState()
        let markings = UIColor(white: 0.78, alpha: 1)
        markings.setFill()
        cg.fill(CGRect(x: light.x - 1.5, y: light.y + 40, width: 3, height: 90))
        cg.fill(CGRect(x: light.x - 10, y: light.y + 40, width: 12, height: 3))
        label("BATT.", size: 24, color: markings, center: CGPoint(x: light.x - 4, y: light.y + 150))
    }

    /// Darkens the paper as it goes down into the slot.
    private static func shadePaperInSlot(in cg: CGContext, paperOrigin: CGPoint, paperWidth: CGFloat, slotY: CGFloat) {
        let colors = [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.6).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        cg.saveGState()
        cg.clip(to: CGRect(x: paperOrigin.x, y: slotY, width: paperWidth, height: slotDepth))
        cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: slotY), end: CGPoint(x: 0, y: slotY + slotDepth), options: [])
        cg.restoreGState()
    }

    /// The metal cutter in the slot window, its teeth pointing up in front of the paper.
    /// The teeth are the shape the paper's torn edge takes, and line up with it: each tooth's tip
    /// falls under a point of the edge, where this cutter tore it.
    private static func drawCutter(in cg: CGContext, slotY: CGFloat, paperLeft: CGFloat) {
        let edge = slotY + slotDepth
        let pitch = CGFloat(PrinterSlipRenderer.tearPitch)
        let depth = CGFloat(PrinterSlipRenderer.tearDepth)
        UIColor(white: 0.66, alpha: 1).setFill()
        let teeth = UIBezierPath()
        let firstTip = paperLeft - ((paperLeft - windowInset - 16) / pitch).rounded(.down) * pitch
        var x = firstTip - pitch / 2
        while x + pitch <= width - windowInset - 16 + pitch / 2 {
            teeth.move(to: CGPoint(x: x, y: edge))
            teeth.addLine(to: CGPoint(x: x + pitch / 2, y: edge - depth))
            teeth.addLine(to: CGPoint(x: x + pitch, y: edge))
            teeth.close()
            x += pitch
        }
        teeth.fill()
        UIColor(white: 0.58, alpha: 1).setFill()
        cg.fill(CGRect(x: windowInset, y: edge, width: width - windowInset * 2, height: cutterBar))
    }

    /// The body below the panel: the badge, then the Feed button and the power switch low on it.
    private static func drawBase(in cg: CGContext, top: CGFloat) {
        drawEmblem(in: cg, center: CGPoint(x: width / 2, y: top + 130))

        // Feed takes the Game Boy's A and B color, lighter at the top like the touch controls' buttons.
        let feed = CGRect(x: bodyInset + 108, y: top + 570 - 140, width: 280, height: 280)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 8), blur: 14, color: UIColor(white: 0, alpha: 0.35).cgColor)
        cg.fillEllipse(in: feed)
        cg.restoreGState()
        let palette = ControllerPalette.classic
        fill(UIBezierPath(ovalIn: feed), in: cg, from: palette.buttonTop, to: palette.buttonBottom, over: feed)
        // FEED is pressed into the button: darker than it, with light catching the lower edges.
        label("FEED", size: 52, color: UIColor(white: 1, alpha: 0.28), center: CGPoint(x: feed.midX, y: feed.midY + 2))
        label("FEED", size: 52, color: UIColor(red: 0.36, green: 0.06, blue: 0.21, alpha: 1), center: CGPoint(x: feed.midX, y: feed.midY))

        drawPowerSwitch(in: cg, origin: CGPoint(x: width - bodyInset - 108 - 186 - 48 - 90, y: top + 366))
    }

    /// The raised badge under the panel, in the body's own gray, the way the printer carries its
    /// maker's name: straight along the top and bottom with round ends, like a race track.
    private static func drawEmblem(in cg: CGContext, center: CGPoint) {
        let badge = CGRect(x: center.x - 165, y: center.y - 36, width: 330, height: 72)
        let path = UIBezierPath(roundedRect: badge, cornerRadius: badge.height / 2)
        path.lineWidth = 4
        cg.saveGState()
        cg.translateBy(x: 0, y: 2)
        UIColor(white: 1, alpha: 0.45).setStroke()
        path.stroke()
        cg.restoreGState()
        UIColor(white: 0, alpha: 0.22).setStroke()
        path.stroke()
        label("PRESS ANY", size: 36, color: UIColor(white: 1, alpha: 0.45), center: CGPoint(x: center.x, y: center.y + 2))
        label("PRESS ANY", size: 36, color: UIColor(white: 0, alpha: 0.24), center: center)
    }

    /// The power switch: a tall plate in the body's gray that slides along a recessed track ridged
    /// on its right, with POWER and a domed knob on it, and ON and OFF beside it under arrows that
    /// point the way to slide.
    private static func drawPowerSwitch(in cg: CGContext, origin: CGPoint) {
        let plateSize = CGSize(width: 186, height: 444)
        let track = CGRect(x: origin.x, y: origin.y, width: plateSize.width + 60, height: plateSize.height + 12)
        UIColor(white: 0.52, alpha: 1).setFill()
        UIBezierPath(roundedRect: track, cornerRadius: 8).fill()
        UIColor(white: 0.44, alpha: 1).setFill()
        for y in stride(from: track.minY + 14, to: track.maxY - 10, by: 9) {
            cg.fill(CGRect(x: track.maxX - 50, y: y, width: 40, height: 3))
        }
        let plate = CGRect(origin: CGPoint(x: track.minX + 6, y: track.minY + 6), size: plateSize)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 2, height: 3), blur: 4, color: UIColor(white: 0, alpha: 0.3).cgColor)
        UIColor(red: 0.80, green: 0.79, blue: 0.76, alpha: 1).setFill()
        UIBezierPath(roundedRect: plate, cornerRadius: 8).fill()
        cg.restoreGState()
        label("POWER", size: 34, color: bodyInk, center: CGPoint(x: plate.midX, y: plate.minY + 50))
        let knob = CGRect(x: plate.midX - 44, y: plate.minY + plate.height * 0.57 - 44, width: 88, height: 88)
        cg.saveGState()
        cg.addEllipse(in: knob)
        cg.clip()
        let colors = [UIColor(white: 0.93, alpha: 1).cgColor, UIColor(white: 0.70, alpha: 1).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            cg.drawRadialGradient(gradient, startCenter: CGPoint(x: knob.midX - 14, y: knob.midY - 16), startRadius: 2,
                                  endCenter: CGPoint(x: knob.midX, y: knob.midY), endRadius: 46, options: [])
        }
        cg.restoreGState()

        let x = track.maxX + 52
        for (text, y, pointsRight) in [("ON", plate.minY + plate.height * 0.62, true), ("OFF", plate.minY + plate.height * 0.86, false)] {
            bodyInk.setFill()
            cg.fill(CGRect(x: x - 26, y: y - 31.5, width: 52, height: 3))
            let tip = pointsRight ? x + 38 : x - 38, base = pointsRight ? x + 26 : x - 26
            let arrow = UIBezierPath()
            arrow.move(to: CGPoint(x: base, y: y - 38))
            arrow.addLine(to: CGPoint(x: tip, y: y - 30))
            arrow.addLine(to: CGPoint(x: base, y: y - 22))
            arrow.close()
            arrow.fill()
            label(text, size: 30, color: bodyInk, center: CGPoint(x: x, y: y))
        }
    }

    /// The wordmark with the pink A it has in Light Mode, the same magenta as the A and B buttons,
    /// and the other letters in the panel's light lettering.
    private static func wordmark(height: CGFloat) -> UIImage? {
        let art = AppBrand.Wordmark.artwork(size: height, appearance: .light)
        guard let source = art.cgImage else { return nil }
        let width = source.width, rows = source.height
        var pixels = [UInt8](repeating: 0, count: width * rows * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: &pixels, width: width, height: rows, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space, bitmapInfo: info) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: rows))
        var light: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        lettering.getRed(&light.0, green: &light.1, blue: &light.2, alpha: &light.3)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[i + 3])
            // The pink A is much redder than green; the navy letters aren't.
            guard alpha > 0, Int(pixels[i]) - Int(pixels[i + 1]) < alpha / 4 else { continue }
            pixels[i] = UInt8(light.0 * CGFloat(alpha))
            pixels[i + 1] = UInt8(light.1 * CGFloat(alpha))
            pixels[i + 2] = UInt8(light.2 * CGFloat(alpha))
        }
        guard let recolored = context.makeImage() else { return nil }
        return UIImage(cgImage: recolored, scale: art.scale, orientation: .up)
    }

    private static func label(_ text: String, size: CGFloat, color: UIColor, center: CGPoint) {
        let string = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: color,
        ])
        let bounds = string.size()
        string.draw(at: CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
    }

    private static func cgImage(_ image: PrinterSlipRenderer.Image) -> CGImage? {
        guard let provider = CGDataProvider(data: image.bgra8888 as CFData) else { return nil }
        return CGImage(
            width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits)) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
