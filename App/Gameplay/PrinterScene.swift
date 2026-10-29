import EmulationCore
import UIKit

/// The Printer background: a Press Any printer with the slip coming out of its slot, the way a
/// print looks on the machine. The slip is rendered on a transparent background first, then the
/// printer is drawn around it, so its pixel grid stays as the renderer made it.
enum PrinterScene {
    private static let width: CGFloat = 1200
    /// The slip's paper starts this far into its transparent render.
    private static let paperInset: CGFloat = CGFloat(24 * PrinterSlipRenderer.scale)
    private static let bodyHeight: CGFloat = 540

    static func render(_ slip: PrinterSlip) -> UIImage? {
        guard let paper = cgImage(PrinterSlipRenderer.render(slip, background: .transparent)) else { return nil }
        let paperSize = CGSize(width: paper.width, height: paper.height)
        let paperOrigin = CGPoint(x: (width - paperSize.width) / 2, y: 40)
        // The slot takes the paper's bottom edge and a little of its last margin.
        let slotY = paperOrigin.y + paperSize.height - paperInset - 28
        let size = CGSize(width: width, height: slotY + bodyHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            UIColor(white: 0.08, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            drawCover(in: cg, paperOrigin: paperOrigin, slotY: slotY)
            // UIKit draws a CGImage upside down without this flip.
            cg.saveGState()
            cg.translateBy(x: 0, y: paperOrigin.y * 2 + paperSize.height)
            cg.scaleBy(x: 1, y: -1)
            cg.interpolationQuality = .none
            cg.draw(paper, in: CGRect(origin: paperOrigin, size: paperSize))
            cg.restoreGState()
            drawBody(in: cg, slotY: slotY, size: size)
        }
    }

    /// The smoked cover behind the paper, open at the top.
    private static func drawCover(in cg: CGContext, paperOrigin: CGPoint, slotY: CGFloat) {
        let cover = CGRect(x: 110, y: max(0, paperOrigin.y + 30), width: width - 220, height: slotY - paperOrigin.y)
        let path = UIBezierPath(roundedRect: cover, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 70, height: 70))
        UIColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1).setFill()
        path.fill()
        UIColor(white: 0.32, alpha: 1).setStroke()
        path.lineWidth = 8
        path.stroke()
        // A soft highlight down each side of the clear plastic.
        for x in [cover.minX + 26, cover.maxX - 34] {
            UIColor(white: 1, alpha: 0.06).setFill()
            cg.fill(CGRect(x: x, y: cover.minY + 60, width: 8, height: cover.height - 90))
        }
    }

    private static func drawBody(in cg: CGContext, slotY: CGFloat, size: CGSize) {
        let body = CGRect(x: 50, y: slotY - 44, width: width - 100, height: size.height - slotY + 44)
        let path = UIBezierPath(roundedRect: body, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 40, height: 40))
        cg.saveGState()
        path.addClip()
        let colors = [UIColor(white: 0.19, alpha: 1).cgColor, UIColor(white: 0.12, alpha: 1).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
        }
        cg.restoreGState()

        // The slot, with the serrated tear bar along its top edge.
        let slot = CGRect(x: 150, y: slotY - 10, width: width - 300, height: 54)
        UIColor(white: 0.03, alpha: 1).setFill()
        UIBezierPath(roundedRect: slot, cornerRadius: 10).fill()
        UIColor(white: 0.55, alpha: 1).setFill()
        let teeth = UIBezierPath()
        var x = slot.minX + 30
        while x + 16 <= slot.maxX - 30 {
            teeth.move(to: CGPoint(x: x, y: slot.minY))
            teeth.addLine(to: CGPoint(x: x + 8, y: slot.minY + 12))
            teeth.addLine(to: CGPoint(x: x + 16, y: slot.minY))
            teeth.close()
            x += 16
        }
        teeth.fill()

        let wordmark = AppBrand.Wordmark.artwork(size: 104, appearance: .dark)
        wordmark.draw(at: CGPoint(x: 140, y: slotY + 120))
        let printer = NSAttributedString(string: "printer", attributes: [
            .font: UIFont.systemFont(ofSize: 190, weight: .heavy).withTraits(.traitItalic),
            .foregroundColor: UIColor(white: 0.96, alpha: 1),
        ])
        printer.draw(at: CGPoint(x: 132, y: slotY + 220))

        // The power light.
        let light = CGRect(x: width - 170, y: slotY + 330, width: 54, height: 54)
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: 40, color: UIColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.9).cgColor)
        UIColor(red: 0.95, green: 0.08, blue: 0.1, alpha: 1).setFill()
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
