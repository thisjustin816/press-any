import GameplayInput
import UIKit

/// Colors for the on-screen controller. Classic's are sampled from a photograph of an original
/// Game Boy; Dark is Press Any's own.
struct ControllerPalette {
    let bodyTop: UIColor
    let bodyBottom: UIColor
    let bezelTop: UIColor
    let bezelBottom: UIColor
    let dpad: UIColor
    let dpadPressed: UIColor
    /// The shallow dip at the D-pad's center.
    let dpadDimple: UIColor
    /// Recesses in the body: the channel A and B sit in and the Playtiles alignment guide.
    let groove: UIColor
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
    /// The app's wordmark (`AppBrand.Wordmark`) in this theme's colors.
    let logo: UIColor
    let logoAccent: UIColor

    static var classic: ControllerPalette {
        ControllerPalette(
            // The warm gray case, its gray screen lens, and the maroon-magenta A and B.
            bodyTop: rgb(199, 198, 195),
            bodyBottom: rgb(183, 181, 178),
            bezelTop: rgb(128, 126, 132),
            bezelBottom: rgb(112, 110, 116),
            dpad: rgb(48, 48, 50),
            dpadPressed: rgb(30, 30, 32),
            dpadDimple: rgb(38, 38, 40),
            groove: rgb(170, 168, 165),
            buttonTop: rgb(150, 44, 100),
            buttonBottom: rgb(124, 32, 80),
            buttonPressed: rgb(100, 24, 64),
            pill: rgb(124, 120, 124),
            pillPressed: rgb(100, 96, 100),
            pillText: rgb(236, 234, 232),
            lettering: rgb(52, 52, 136),
            logo: AppBrand.Wordmark.lightInk,
            logoAccent: AppBrand.Wordmark.lightAccent
        )
    }

    static var dark: ControllerPalette {
        ControllerPalette(
            bodyTop: rgb(36, 37, 40),
            bodyBottom: rgb(22, 22, 24),
            bezelTop: rgb(12, 12, 13),
            bezelBottom: rgb(8, 8, 9),
            dpad: rgb(70, 70, 75),
            dpadPressed: rgb(96, 96, 102),
            dpadDimple: rgb(58, 58, 62),
            // Lighter than the body, so the channel behind A and B reads as a tray.
            groove: rgb(46, 46, 50),
            buttonTop: rgb(166, 58, 112),
            buttonBottom: rgb(136, 44, 90),
            buttonPressed: rgb(112, 36, 74),
            pill: rgb(78, 78, 83),
            pillPressed: rgb(104, 104, 110),
            pillText: rgb(210, 212, 218),
            lettering: rgb(132, 160, 205),
            logo: AppBrand.Wordmark.darkInk,
            logoAccent: AppBrand.Wordmark.darkAccent
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
