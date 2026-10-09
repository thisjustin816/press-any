import EmulatorDomain
import SwiftUI
import UIKit

enum DMGPaletteGroup: String, CaseIterable {
    case console = "Console Palettes"
    case button = "Button Palettes"
    case game = "Game Palettes"

    func contains(_ palette: DMGPalette) -> Bool {
        let group: Self = switch palette {
        case .dmgGreen, .pocket, .light: .console
        case .cgbOlive: .game
        default: .button
        }
        return group == self
    }
}

enum DMGPalettePreview {
    static func image(for palette: DMGPalette) -> Image {
        Image(uiImage: thumbnail(for: palette))
            .renderingMode(.original)
    }

    static func thumbnail(for palette: DMGPalette) -> UIImage {
        let colors = palette.previewColors
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 24), format: format)
        return renderer.image { context in
            for (row, shades) in colors.enumerated() {
                for (column, rgb) in shades.enumerated() {
                    let color = UIColor(
                        red: CGFloat((rgb >> 16) & 255) / 255,
                        green: CGFloat((rgb >> 8) & 255) / 255,
                        blue: CGFloat(rgb & 255) / 255,
                        alpha: 1
                    )
                    context.cgContext.setFillColor(color.cgColor)
                    context.cgContext.fill(CGRect(x: column * 8, y: row * 8, width: 8, height: 8))
                }
            }
        }.withRenderingMode(.alwaysOriginal)
    }
}
