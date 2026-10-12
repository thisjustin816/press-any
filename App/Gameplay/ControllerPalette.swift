import GameplayInput
import UIKit

/// Controller colors use the app's pink, navy and gray, with fixed Light and Dark themes.
struct ControllerPalette {
    let bodyTop: UIColor
    let bodyBottom: UIColor
    let bezelTop: UIColor
    let bezelBottom: UIColor
    let dpad: UIColor
    /// A pressed Playtiles D-pad circle.
    let dpadPressed: UIColor
    /// The shallow dip at the D-pad's center and the arrows pressed into its arms.
    let dpadDimple: UIColor
    /// The shade at the end of a pressed Game Boy D-pad arm, fading out toward the center.
    let dpadTilt: UIColor
    /// The light along a raised control's top edge and the shade along its bottom.
    let edgeLight: UIColor
    let edgeShade: UIColor
    /// The channel A and B sit in on the Game Boy layout.
    let groove: UIColor
    /// The Playtiles alignment guide, raised from the body as a ledge to fit the controller against:
    /// its face, the shadow it casts below, and the light catching its top edge.
    let guide: UIColor
    let guideShadow: UIColor
    let guideHighlight: UIColor
    /// A and B are lighter at the top, like a domed button under light.
    let buttonTop: UIColor
    let buttonBottom: UIColor
    let buttonPressed: UIColor
    let pill: UIColor
    let pillPressed: UIColor
    /// Text on a pill, such as MENU.
    let pillText: UIColor
    /// Lettering printed on the body, such as A, B, SELECT and START.
    let lettering: UIColor
    /// Wordmark artwork follows the controller theme independently of the library.
    let wordmarkAppearance: UIUserInterfaceStyle
    /// Ink around the wordmark button's rim.
    let logo: UIColor
    /// Light along the bottom edges of the pressed wordmark.
    let logoHighlight: UIColor

    static var classic: ControllerPalette {
        ControllerPalette(
            // Fixed appearances keep a chosen controller theme independent of the library.
            bodyTop: AppBrand.Colors.body.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)),
            bodyBottom: rgb(189, 187, 181),
            bezelTop: rgb(128, 126, 132),
            bezelBottom: rgb(112, 110, 116),
            dpad: rgb(48, 48, 50),
            dpadPressed: rgb(30, 30, 32),
            dpadDimple: rgb(38, 38, 40),
            dpadTilt: UIColor.black.withAlphaComponent(0.5),
            edgeLight: UIColor.white.withAlphaComponent(0.3),
            edgeShade: UIColor.black.withAlphaComponent(0.35),
            groove: rgb(170, 168, 165),
            guide: rgb(235, 233, 230),
            guideShadow: rgb(146, 144, 141),
            guideHighlight: rgb(250, 248, 245),
            buttonTop: AppBrand.Colors.button.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)),
            buttonBottom: rgb(145, 27, 84),
            buttonPressed: rgb(123, 23, 71),
            pill: rgb(124, 120, 124),
            pillPressed: rgb(100, 96, 100),
            pillText: rgb(236, 234, 232),
            lettering: AppBrand.Wordmark.lightInk,
            wordmarkAppearance: .light,
            logo: AppBrand.Wordmark.lightInk,
            logoHighlight: rgb(236, 235, 232)
        )
    }

    static var dark: ControllerPalette {
        ControllerPalette(
            bodyTop: AppBrand.Colors.body.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)),
            bodyBottom: rgb(23, 25, 31),
            bezelTop: rgb(56, 56, 60),
            bezelBottom: rgb(48, 48, 52),
            dpad: rgb(70, 70, 75),
            dpadPressed: rgb(96, 96, 102),
            dpadDimple: rgb(58, 58, 62),
            dpadTilt: UIColor.black.withAlphaComponent(0.55),
            edgeLight: UIColor.white.withAlphaComponent(0.16),
            edgeShade: UIColor.black.withAlphaComponent(0.45),
            // Lighter than the body, so the channel behind A and B reads as a tray.
            groove: rgb(46, 46, 50),
            guide: rgb(52, 52, 57),
            guideShadow: rgb(6, 6, 7),
            guideHighlight: rgb(88, 88, 95),
            buttonTop: AppBrand.Colors.button.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)),
            buttonBottom: rgb(145, 27, 84),
            buttonPressed: rgb(123, 23, 71),
            pill: rgb(78, 78, 83),
            pillPressed: rgb(104, 104, 110),
            pillText: rgb(210, 212, 218),
            lettering: AppBrand.Wordmark.darkInk,
            wordmarkAppearance: .dark,
            logo: AppBrand.Wordmark.darkInk,
            logoHighlight: rgb(58, 58, 64)
        )
    }

    static func resolve(_ theme: ControllerTheme, for traits: UITraitCollection) -> ControllerPalette {
        switch theme {
        case .classic: .classic
        case .dark: .dark
        case .matchSystem: traits.userInterfaceStyle == .dark ? .dark : .classic
        }
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }
}
