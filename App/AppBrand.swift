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

    /// The name in heavy italic system type, with the first letter of its last word in pink.
    enum Wordmark {
        static let parts: (lead: String, accent: String, tail: String) = split(AppBrand.displayName)

        static var lightInk: UIColor { Colors.ink.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)) }
        static var darkInk: UIColor { Colors.ink.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)) }
        static var lightAccent: UIColor { Colors.accent.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)) }
        static var darkAccent: UIColor { Colors.accent.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)) }
        static var ink: UIColor { Colors.ink }
        static var accent: UIColor { Colors.accent }

        /// Letter spacing as a fraction of the point size.
        static let tracking: CGFloat = 0.028

        /// Weight and slant are set together: adding italic with `withSymbolicTraits` to a black
        /// system font replaces its traits and drops the weight back to regular.
        static func font(size: CGFloat) -> UIFont {
            let traits: [UIFontDescriptor.TraitKey: Any] = [
                .weight: UIFont.Weight.black.rawValue,
                .symbolic: UIFontDescriptor.SymbolicTraits.traitItalic.rawValue,
            ]
            let descriptor = UIFont.systemFont(ofSize: size).fontDescriptor.addingAttributes([.traits: traits])
            return UIFont(descriptor: descriptor, size: size)
        }

        /// For drawing in UIKit, in fixed colors such as a controller theme's.
        static func attributedString(size: CGFloat, ink: UIColor, accent: UIColor) -> NSAttributedString {
            let string = NSMutableAttributedString()
            for (text, color) in [(parts.lead, ink), (parts.accent, accent), (parts.tail, ink)] {
                string.append(NSAttributedString(string: text, attributes: [
                    .font: font(size: size),
                    .kern: size * tracking,
                    .foregroundColor: color,
                ]))
            }
            return string
        }

        static func split(_ name: String) -> (lead: String, accent: String, tail: String) {
            let start = name.lastIndex(of: " ").map { name.index(after: $0) } ?? name.startIndex
            guard start < name.endIndex else { return (name, "", "") }
            let end = name.index(after: start)
            return (String(name[..<start]), String(name[start..<end]), String(name[end...]))
        }
    }
}

/// The wordmark in SwiftUI, following Light and Dark Mode.
struct WordmarkView: View {
    var size: CGFloat = 20

    var body: some View {
        let parts = AppBrand.Wordmark.parts
        let ink = Color(uiColor: AppBrand.Wordmark.ink)
        let accent = Color(uiColor: AppBrand.Wordmark.accent)
        (Text(parts.lead).foregroundStyle(ink)
            + Text(parts.accent).foregroundStyle(accent)
            + Text(parts.tail).foregroundStyle(ink))
            .font(Font(AppBrand.Wordmark.font(size: size)))
            .kerning(size * AppBrand.Wordmark.tracking)
            .lineLimit(1)
            // Larger text sizes widen the toolbar buttons beside the library's title, so the name
            // shrinks to fit the space left rather than losing its last letters.
            .minimumScaleFactor(0.5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppBrand.displayName)
            .accessibilityAddTraits(.isHeader)
    }
}
