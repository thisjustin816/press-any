import Foundation
import SwiftUI
import UIKit

/// The user-facing product name. Its one source is the app target's
/// `INFOPLIST_KEY_CFBundleDisplayName` build setting in project.yml.
enum AppBrand {
    static let displayName: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? ""

    enum Colors {
        static var accent: UIColor { UIColor(named: "AccentColor") ?? .systemPink }
        static var ink: UIColor { UIColor(named: "BrandInk") ?? .label }
        static var body: UIColor { UIColor(named: "BrandBody") ?? .systemGray6 }
        // Filled controls keep white labels readable in both appearances.
        static var button: UIColor { UIColor(named: "BrandButton") ?? .systemPink }
        static var secondaryButton: UIColor {
            ink.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        }
    }

    /// Fixed Corporatus wordmark artwork, with the first letter of its last word in pink.
    enum Wordmark {
        static var lightInk: UIColor { Colors.ink.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)) }
        static var darkInk: UIColor { Colors.ink.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)) }
        static var accent: UIColor { Colors.accent }

        static var aspectRatio: CGFloat {
            let image = UIImage(named: "Wordmark")
            return (image?.size.width ?? 1) / max(image?.size.height ?? 1, 1)
        }

        static func artwork(size: CGFloat, appearance: UIUserInterfaceStyle, recessed: Bool = false) -> UIImage {
            let traits = UITraitCollection(userInterfaceStyle: appearance)
            guard let image = UIImage(named: recessed ? "WordmarkRecess" : "Wordmark", in: .main, compatibleWith: traits)
            else { return UIImage() }
            let canvas = CGSize(width: size * aspectRatio, height: size)
            return UIGraphicsImageRenderer(size: canvas).image { _ in
                image.draw(in: CGRect(origin: .zero, size: canvas))
            }
        }
    }
}

/// The wordmark in SwiftUI, following Light and Dark Mode.
struct WordmarkView: View {
    var size: CGFloat = 20

    var body: some View {
        Image("Wordmark")
            .renderingMode(.original)
            .resizable()
            .aspectRatio(AppBrand.Wordmark.aspectRatio, contentMode: .fit)
            .frame(maxWidth: size * AppBrand.Wordmark.aspectRatio, maxHeight: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppBrand.displayName)
            .accessibilityAddTraits(.isHeader)
    }
}
