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

    /// The wordmark: the name in heavy italic system type, with the first letter of its last word
    /// ("A" in "Press Any") in the magenta of a Game Boy A button. docs/NAMING.md describes it.
    enum Wordmark {
        /// The name around and including its accented letter.
        static let parts: (lead: String, accent: String, tail: String) = split(AppBrand.displayName)

        /// Charcoal on light backgrounds, the D-pad's color on the Classic controller.
        static var lightInk: UIColor { UIColor(red: 50 / 255, green: 50 / 255, blue: 53 / 255, alpha: 1) }
        /// Gray on dark backgrounds.
        static var darkInk: UIColor { UIColor(red: 128 / 255, green: 128 / 255, blue: 134 / 255, alpha: 1) }
        static var lightAccent: UIColor { UIColor(red: 150 / 255, green: 44 / 255, blue: 100 / 255, alpha: 1) }
        static var darkAccent: UIColor { UIColor(red: 164 / 255, green: 62 / 255, blue: 116 / 255, alpha: 1) }
        static var ink: UIColor { UIColor { $0.userInterfaceStyle == .dark ? darkInk : lightInk } }
        static var accent: UIColor { UIColor { $0.userInterfaceStyle == .dark ? darkAccent : lightAccent } }

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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppBrand.displayName)
            .accessibilityAddTraits(.isHeader)
    }
}
