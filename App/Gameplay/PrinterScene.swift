import EmulationCore
import UIKit

/// The Printer background: the slip coming out of a printer the way it does on the machine. The
/// layout and colors follow the Game Boy Printer: a smoked lid over the paper roll, a black panel
/// with the slot, its serrated cutter and the name, and a light gray body with a purple Feed button.
/// The slip is rendered on a transparent background first, then the printer is drawn around it,
/// so its pixel grid stays as the renderer made it.
enum PrinterScene {
    private static let width: CGFloat = 1200
    /// The slip's paper starts this far into its transparent render.
    private static let paperInset: CGFloat = CGFloat(24 * PrinterSlipRenderer.scale)
    private static let lidHeight: CGFloat = 360
    private static let panelHeight: CGFloat = 400
    private static let baseHeight: CGFloat = 330
    private static let slotInset: CGFloat = 150
    private static let slotDepth: CGFloat = 40

    private static let bodyGray = UIColor(red: 0.81, green: 0.79, blue: 0.77, alpha: 1)
    private static let bodyShade = UIColor(red: 0.72, green: 0.70, blue: 0.68, alpha: 1)
    private static let panelBlack = UIColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)
    private static let lettering = UIColor(white: 0.93, alpha: 1)

    static func render(_ slip: PrinterSlip) -> UIImage? {
        guard let paper = cgImage(PrinterSlipRenderer.render(slip, background: .transparent)) else { return nil }
        let paperSize = CGSize(width: paper.width, height: paper.height)
        // A short slip still clears the lid; a long one rises above the printer.
        let bodyTop = max(40, paperSize.height - paperInset - 44 - lidHeight + 40)
        let slotY = bodyTop + lidHeight
        let paperOrigin = CGPoint(x: (width - paperSize.width) / 2, y: slotY + 44 + paperInset - paperSize.height)
        let size = CGSize(width: width, height: slotY + panelHeight + baseHeight + 40)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            UIColor(white: 0.1, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            drawShell(in: cg, top: bodyTop, size: size)
            drawLid(in: cg, top: bodyTop, slotY: slotY)
            drawPanel(in: cg, slotY: slotY)
            // UIKit draws a CGImage upside down without this flip.
            cg.saveGState()
            cg.translateBy(x: 0, y: paperOrigin.y * 2 + paperSize.height)
            cg.scaleBy(x: 1, y: -1)
            cg.interpolationQuality = .none
            cg.draw(paper, in: CGRect(origin: paperOrigin, size: paperSize))
            cg.restoreGState()
            shadePaperInSlot(in: cg, paperOrigin: paperOrigin, paperWidth: paperSize.width, slotY: slotY)
            drawCutter(in: cg, slotY: slotY)
            drawBase(in: cg, top: slotY + panelHeight)
        }
    }

    /// The gray shell the lid and panel sit in.
    private static func drawShell(in cg: CGContext, top: CGFloat, size: CGSize) {
        let shell = CGRect(x: 50, y: top, width: width - 100, height: size.height - top - 20)
        let path = UIBezierPath(roundedRect: shell, cornerRadius: 56)
        cg.saveGState()
        path.addClip()
        let colors = [bodyGray.cgColor, bodyShade.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: shell.minY), end: CGPoint(x: 0, y: shell.maxY), options: [])
        }
        cg.restoreGState()
        UIColor(white: 0.55, alpha: 1).setStroke()
        path.lineWidth = 4
        path.stroke()
    }

    /// The smoked, see-through lid over the paper roll.
    private static func drawLid(in cg: CGContext, top: CGFloat, slotY: CGFloat) {
        let lid = CGRect(x: 110, y: top + 24, width: width - 220, height: slotY - top - 24)
        let path = UIBezierPath(roundedRect: lid, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 44, height: 44))
        UIColor(red: 0.36, green: 0.38, blue: 0.40, alpha: 1).setFill()
        path.fill()
        // The roll inside shows through.
        UIColor(white: 0.62, alpha: 0.35).setFill()
        cg.fill(CGRect(x: lid.minX + 120, y: lid.minY + 60, width: lid.width - 240, height: lid.height - 110))
        UIColor(white: 1, alpha: 0.12).setFill()
        cg.fill(CGRect(x: lid.minX + 24, y: lid.minY + 40, width: 10, height: lid.height - 70))
        UIColor(white: 0.25, alpha: 1).setStroke()
        path.lineWidth = 4
        path.stroke()
    }

    /// The black panel: the slot along its top, the name and the power light.
    private static func drawPanel(in cg: CGContext, slotY: CGFloat) {
        let panel = CGRect(x: 90, y: slotY - 12, width: width - 180, height: panelHeight + 12)
        panelBlack.setFill()
        UIBezierPath(roundedRect: panel, cornerRadius: 14).fill()
        let slot = CGRect(x: slotInset, y: slotY, width: width - slotInset * 2, height: slotDepth)
        UIColor(white: 0.0, alpha: 1).setFill()
        UIBezierPath(roundedRect: slot, cornerRadius: 6).fill()

        let top = slotY + slotDepth + 70
        let wordmark = AppBrand.Wordmark.artwork(size: 92, appearance: .light).withTintColor(lettering, renderingMode: .alwaysOriginal)
        wordmark.draw(at: CGPoint(x: 150, y: top))
        let printer = NSAttributedString(string: "printer", attributes: [
            .font: UIFont.systemFont(ofSize: 176, weight: .heavy).withTraits(.traitItalic),
            .foregroundColor: lettering,
        ])
        printer.draw(at: CGPoint(x: 142, y: top + 84))

        let light = CGRect(x: width - 200, y: top + 150, width: 48, height: 48)
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: 32, color: UIColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.8).cgColor)
        UIColor(red: 0.92, green: 0.07, blue: 0.1, alpha: 1).setFill()
        cg.fillEllipse(in: light)
        cg.restoreGState()
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

    /// The metal cutter along the slot's front edge, its teeth pointing up in front of the paper.
    private static func drawCutter(in cg: CGContext, slotY: CGFloat) {
        let edge = slotY + slotDepth
        UIColor(white: 0.66, alpha: 1).setFill()
        let teeth = UIBezierPath()
        var x = slotInset + 16
        while x + 16 <= width - slotInset - 16 {
            teeth.move(to: CGPoint(x: x, y: edge))
            teeth.addLine(to: CGPoint(x: x + 8, y: edge - 16))
            teeth.addLine(to: CGPoint(x: x + 16, y: edge))
            teeth.close()
            x += 16
        }
        teeth.fill()
        UIColor(white: 0.58, alpha: 1).setFill()
        cg.fill(CGRect(x: slotInset, y: edge, width: width - slotInset * 2, height: 8))
    }

    /// The gray base below the panel, with the Feed button and the power switch.
    private static func drawBase(in cg: CGContext, top: CGFloat) {
        let feed = CGRect(x: 150, y: top + 90, width: 150, height: 150)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 6), blur: 10, color: UIColor(white: 0, alpha: 0.35).cgColor)
        UIColor(red: 0.45, green: 0.18, blue: 0.36, alpha: 1).setFill()
        cg.fillEllipse(in: feed)
        cg.restoreGState()
        label("FEED", size: 34, color: UIColor(white: 0.95, alpha: 0.9), center: CGPoint(x: feed.midX, y: feed.midY))

        let switchWell = CGRect(x: width - 330, y: top + 120, width: 160, height: 110)
        UIColor(red: 0.68, green: 0.66, blue: 0.64, alpha: 1).setFill()
        UIBezierPath(roundedRect: switchWell, cornerRadius: 10).fill()
        UIColor(red: 0.86, green: 0.84, blue: 0.82, alpha: 1).setFill()
        cg.fillEllipse(in: CGRect(x: switchWell.midX - 32, y: switchWell.midY - 22, width: 64, height: 64))
        label("POWER", size: 28, color: UIColor(white: 0.25, alpha: 1), center: CGPoint(x: switchWell.midX, y: switchWell.minY - 24))
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
