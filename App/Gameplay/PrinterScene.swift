import EmulationCore
import UIKit

/// The Printer background: a Press Any printer with the slip coming out of its slot, the way a
/// print looks on the machine: a black top section with the slot, and a Game Boy gray front. The slip is rendered on a transparent background first, then the
/// printer is drawn around it, so its pixel grid stays as the renderer made it.
enum PrinterScene {
    private static let width: CGFloat = 1200
    /// The slip's paper starts this far into its transparent render.
    private static let paperInset: CGFloat = CGFloat(24 * PrinterSlipRenderer.scale)
    private static let bodyHeight: CGFloat = 520
    private static let slotInset: CGFloat = 150
    private static let slotDepth: CGFloat = 40

    static func render(_ slip: PrinterSlip) -> UIImage? {
        guard let paper = cgImage(PrinterSlipRenderer.render(slip, background: .transparent)) else { return nil }
        let paperSize = CGSize(width: paper.width, height: paper.height)
        let paperOrigin = CGPoint(x: (width - paperSize.width) / 2, y: 40)
        // The paper's bottom edge sits inside the slot, behind the cutter.
        let slotY = paperOrigin.y + paperSize.height - paperInset - 44
        let size = CGSize(width: width, height: slotY + bodyHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            UIColor(white: 0.08, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            drawTop(in: cg, paperOrigin: paperOrigin, slotY: slotY)
            // UIKit draws a CGImage upside down without this flip.
            cg.saveGState()
            cg.translateBy(x: 0, y: paperOrigin.y * 2 + paperSize.height)
            cg.scaleBy(x: 1, y: -1)
            cg.interpolationQuality = .none
            cg.draw(paper, in: CGRect(origin: paperOrigin, size: paperSize))
            cg.restoreGState()
            shadePaperInSlot(in: cg, paperOrigin: paperOrigin, paperWidth: paperSize.width, slotY: slotY)
            drawBody(in: cg, slotY: slotY, size: size)
        }
    }

    /// The black top section, with the slot the paper comes out of along its bottom.
    private static func drawTop(in cg: CGContext, paperOrigin: CGPoint, slotY: CGFloat) {
        let top = CGRect(x: 90, y: max(0, paperOrigin.y + 30), width: width - 180, height: slotY + slotDepth - paperOrigin.y)
        let path = UIBezierPath(roundedRect: top, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 64, height: 64))
        UIColor(white: 0.06, alpha: 1).setFill()
        path.fill()
        UIColor(white: 0.22, alpha: 1).setStroke()
        path.lineWidth = 6
        path.stroke()
        // A soft sheen down each side of the glossy plastic.
        for x in [top.minX + 28, top.maxX - 36] {
            UIColor(white: 1, alpha: 0.07).setFill()
            cg.fill(CGRect(x: x, y: top.minY + 56, width: 8, height: slotY - top.minY - 90))
        }
        let slot = CGRect(x: slotInset, y: slotY, width: width - slotInset * 2, height: slotDepth)
        UIColor(white: 0.01, alpha: 1).setFill()
        UIBezierPath(roundedRect: slot, cornerRadius: 8).fill()
        UIColor(white: 0.25, alpha: 1).setFill()
        cg.fill(CGRect(x: slot.minX + 8, y: slot.minY - 3, width: slot.width - 16, height: 3))
    }

    /// Darkens the paper as it goes down into the slot.
    private static func shadePaperInSlot(in cg: CGContext, paperOrigin: CGPoint, paperWidth: CGFloat, slotY: CGFloat) {
        let colors = [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.55).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        cg.saveGState()
        cg.clip(to: CGRect(x: paperOrigin.x, y: slotY, width: paperWidth, height: slotDepth))
        cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: slotY), end: CGPoint(x: 0, y: slotY + slotDepth), options: [])
        cg.restoreGState()
    }

    /// The Game Boy gray front: the cutter along its top lip, the name and the power light.
    private static func drawBody(in cg: CGContext, slotY: CGFloat, size: CGSize) {
        let lip = slotY + slotDepth
        let body = CGRect(x: 40, y: lip, width: width - 80, height: size.height - lip)
        let colors = [UIColor(red: 0.79, green: 0.79, blue: 0.76, alpha: 1).cgColor,
                      UIColor(red: 0.70, green: 0.70, blue: 0.67, alpha: 1).cgColor] as CFArray
        cg.saveGState()
        UIBezierPath(roundedRect: body, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 18, height: 18)).addClip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
        }
        cg.restoreGState()

        // The cutter's teeth rise from the lip across the slot, in front of the paper.
        UIColor(white: 0.62, alpha: 1).setFill()
        let teeth = UIBezierPath()
        var x = slotInset + 24
        while x + 16 <= width - slotInset - 24 {
            teeth.move(to: CGPoint(x: x, y: lip))
            teeth.addLine(to: CGPoint(x: x + 8, y: lip - 14))
            teeth.addLine(to: CGPoint(x: x + 16, y: lip))
            teeth.close()
            x += 16
        }
        teeth.fill()
        UIColor(white: 0.5, alpha: 1).setFill()
        cg.fill(CGRect(x: slotInset, y: lip, width: width - slotInset * 2, height: 6))

        let ink = UIColor(red: 0.13, green: 0.13, blue: 0.16, alpha: 1)
        let wordmark = AppBrand.Wordmark.artwork(size: 100, appearance: .light).withTintColor(ink, renderingMode: .alwaysOriginal)
        wordmark.draw(at: CGPoint(x: 140, y: lip + 90))
        let printer = NSAttributedString(string: "printer", attributes: [
            .font: UIFont.systemFont(ofSize: 190, weight: .heavy).withTraits(.traitItalic),
            .foregroundColor: ink,
        ])
        printer.draw(at: CGPoint(x: 132, y: lip + 180))

        // The power light.
        let light = CGRect(x: width - 170, y: lip + 300, width: 54, height: 54)
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: 36, color: UIColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.8).cgColor)
        UIColor(red: 0.92, green: 0.07, blue: 0.1, alpha: 1).setFill()
        cg.fillEllipse(in: light)
        cg.restoreGState()
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
