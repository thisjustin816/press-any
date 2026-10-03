import GameplayInput
import UIKit

/// Colors for the on-screen controller. Classic takes the Game Boy colors SameBoy uses; the
/// drawing is Press Any's own.
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
    let usesDarkStatusBar: Bool

    static let classic = ControllerPalette(
        bodyTop: rgb(192, 195, 199),
        bodyBottom: rgb(174, 176, 180),
        bezelTop: rgb(53, 53, 53),
        bezelBottom: rgb(45, 45, 45),
        dpad: rgb(50, 50, 53),
        dpadPressed: rgb(32, 32, 34),
        dpadDimple: rgb(40, 40, 43),
        groove: rgb(162, 164, 169),
        buttonTop: rgb(166, 58, 112),
        buttonBottom: rgb(136, 44, 90),
        buttonPressed: rgb(112, 36, 74),
        pill: rgb(90, 90, 94),
        pillPressed: rgb(66, 66, 70),
        pillText: rgb(222, 224, 228),
        lettering: rgb(0, 70, 141),
        usesDarkStatusBar: true
    )

    static let dark = ControllerPalette(
        bodyTop: rgb(36, 37, 40),
        bodyBottom: rgb(22, 22, 24),
        bezelTop: rgb(12, 12, 13),
        bezelBottom: rgb(8, 8, 9),
        dpad: rgb(70, 70, 75),
        dpadPressed: rgb(96, 96, 102),
        dpadDimple: rgb(58, 58, 62),
        groove: rgb(13, 13, 15),
        buttonTop: rgb(140, 50, 96),
        buttonBottom: rgb(112, 38, 76),
        buttonPressed: rgb(164, 64, 116),
        pill: rgb(78, 78, 83),
        pillPressed: rgb(104, 104, 110),
        pillText: rgb(210, 212, 218),
        lettering: rgb(132, 160, 205),
        usesDarkStatusBar: false
    )

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
