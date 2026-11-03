import Foundation

/// The screen the Monochrome LCD filter draws: a Game Boy's or Game Boy Pocket's screen as BGB
/// measured it, brightened for a phone, with the unlit LCD showing in the gaps between pixels.
///
/// BGB's reality page (https://bgb.bircd.org/reality/) photographed each screen under
/// color-accurate light, corrected the photos with a color checker, then defocused and averaged
/// them. Those colors are as dim and flat as a reflective screen in a room, so the screen here
/// takes them in linear light, multiplies every color by one exposure and raises the contrast of
/// brightness alone, keeping each color's chromaticity:
/// `exposure * c * (Y(c) / Y(lightest)) ^ (contrast - 1)`, with Y the Rec. 709 luminance. The
/// same exposure for both models keeps the Pocket about 1.8 times as bright as the original, as
/// the measurements have it.
///
/// The filter receives the frame in the palette's colors, so it maps them with a tone curve per
/// channel. On the hardware's own palette (Green (DMG) on a Game Boy, Olive (Pocket) on a Pocket)
/// the curve takes each of the palette's shades, and the color it shows while the LCD is off, to
/// the measured screen's, so Accurate shows exactly the measured colors. Any other palette is
/// the player's choice of colors, so it keeps them and gets only the screen's brightness and
/// contrast: one curve for all three channels that puts the palette's lightest shade at the
/// screen's lightest brightness, its darkest at the screen's darkest, and the shades between
/// where the hardware's own palette puts them. Every model but the Pocket draws the original Game
/// Boy's screen: a Game Boy Color, Game Boy Advance, Super Game Boy or Game Boy Player given this
/// filter under Customize shows its game's colors with the original's brightness and contrast,
/// taking white as the lightest shade and black as the darkest.
public struct MonochromeScreen: Equatable, Sendable {
    /// Red, green and blue in linear light.
    public typealias Color = SIMD3<Double>

    /// The two screens BGB measured.
    public enum Model: Sendable {
        case gameBoy
        case pocket

        /// BGB's swatches as sRGB, lightest shade first.
        var measuredShades: [UInt32] {
            switch self {
            case .gameBoy: [0x759833, 0x588f51, 0x3b7560, 0x2e615a]
            case .pocket: [0xadbf92, 0x96a67c, 0x727e64, 0x5a635c]
            }
        }

        /// BGB's swatch of the screen with the LCD off, as sRGB.
        var measuredLCDOff: UInt32 {
            switch self {
            case .gameBoy: 0x948a04
            case .pocket: 0xc2cfa8
            }
        }

        /// How strongly the gaps show the unlit LCD. The Pocket's pixels sit closer together.
        public var gapStrength: Double {
            switch self {
            case .gameBoy: 0.5
            case .pocket: 0.3
            }
        }

        /// The palette SameBoy gives this hardware unless the player picks another.
        var ownPalette: DMGPalette {
            switch self {
            case .gameBoy: .dmgGreen
            case .pocket: .pocket
            }
        }
    }

    /// One knot of the tone curve: each channel's input, and the output it maps to.
    public struct Knot: Equatable, Sendable {
        public let input: Color
        public let output: Color
    }

    /// The width of the gap between two pixels, in pixels: one row or column of six.
    public static let gapWidth = 1.0 / 6.0
    /// The measured colors are multiplied by this in linear light.
    public static let exposure = 1.4
    /// The power that raises the contrast of brightness.
    public static let contrast = 1.4

    /// Five knots whose inputs ascend in every channel. Between two knots a channel's output is
    /// interpolated in linear light; past the first or last, the end segment continues.
    public let curve: [Knot]
    /// What the gaps between pixels show: the unlit LCD.
    public let gapColor: Color
    /// How much of the gap color the gaps show, from 0 to 1.
    public let gapStrength: Double

    /// The screen of `hardware`, resolved, showing `palette`. Automatic counts as the Game Boy.
    public init(hardware: HardwareModel, palette: DMGPalette) {
        let model: Model = hardware == .gameBoyPocket ? .pocket : .gameBoy
        let screen = Self.colors(of: model)
        gapStrength = model.gapStrength
        // Only a Game Boy or Pocket shows the palette; other hardware shows the game's colors.
        let showsPalette = [.automatic, .gameBoy, .gameBoyPocket].contains(hardware)
        if showsPalette, palette == model.ownPalette {
            // The palette's shades darkest first, then its LCD-off color, which is lighter still.
            let source = (palette.previewColors[0].reversed() + [palette.lcdOffColor]).map(Self.linear)
            let target = screen.shades.reversed() + [screen.lcdOff]
            curve = zip(source, target).map { Knot(input: $0, output: $1) }
            gapColor = screen.lcdOff
            return
        }
        var darkest = 0.0, lightest = 1.0, lcdOff = Color(repeating: 1)
        if showsPalette {
            let luminances = palette.previewColors.joined().map { Self.luminance(Self.linear($0)) }
            darkest = luminances.min() ?? 0
            lightest = luminances.max() ?? 1
            lcdOff = Self.linear(palette.lcdOffColor)
        }
        curve = Self.response(of: model, from: darkest, to: lightest)
        gapColor = Self.apply(curve, to: lcdOff)
    }

    /// The measured screen after the exposure and contrast, in linear light: its four shades,
    /// lightest first, and the screen with the LCD off.
    public static func colors(of model: Model) -> (shades: [Color], lcdOff: Color) {
        let measured = model.measuredShades.map(linear)
        let white = luminance(measured[0])
        func adjusted(_ color: Color) -> Color {
            let boosted = color * (exposure * pow(luminance(color) / white, contrast - 1))
            return boosted.clamped(lowerBound: Color(repeating: 0), upperBound: Color(repeating: 1))
        }
        return (measured.map(adjusted), adjusted(linear(model.measuredLCDOff)))
    }

    /// The model's brightness and contrast for colors whose luminance runs from `darkest` to
    /// `lightest`: the same curve on every channel, placing each luminance where the hardware's
    /// own palette places the shade at the same point of its range.
    static func response(of model: Model, from darkest: Double, to lightest: Double) -> [Knot] {
        let own = model.ownPalette.previewColors[0].reversed().map { luminance(linear($0)) }
        let screen = colors(of: model).shades.reversed().map(luminance)
        let span = max(lightest - darkest, 1e-6)
        var knots = zip(own, screen).map { ownLuminance, screenLuminance in
            let input = darkest + (ownLuminance - own[0]) / (own[3] - own[0]) * span
            return Knot(input: Color(repeating: input), output: Color(repeating: screenLuminance))
        }
        // A fifth knot on the line of the last segment, so the curve continues past the lightest.
        let last = knots[3], before = knots[2]
        knots.append(Knot(input: last.input * 2 - before.input, output: last.output * 2 - before.output))
        return knots
    }

    /// `color` through the tone curve, clamped to what a screen can show.
    public func toneMapped(_ color: Color) -> Color { Self.apply(curve, to: color) }

    static func apply(_ curve: [Knot], to color: Color) -> Color {
        var result = Color()
        for channel in 0..<3 {
            let value = color[channel]
            // The last segment that starts at or below the value, or the first.
            let segment = (1..<(curve.count - 1)).last { curve[$0].input[channel] <= value } ?? 0
            let low = curve[segment], high = curve[segment + 1]
            let t = (value - low.input[channel]) / (high.input[channel] - low.input[channel])
            result[channel] = min(max(low.output[channel] + (high.output[channel] - low.output[channel]) * t, 0), 1)
        }
        return result
    }

    /// Rec. 709 luminance of a linear color.
    public static func luminance(_ color: Color) -> Double {
        0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z
    }

    /// An RGB888 color in linear light.
    public static func linear(_ rgb: UInt32) -> Color {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((rgb >> shift) & 0xff) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return Color(channel(16), channel(8), channel(0))
    }

    /// A linear color as RGB888, rounded.
    public static func rgb888(_ color: Color) -> UInt32 {
        func channel(_ value: Double) -> UInt32 {
            let clamped = min(max(value, 0), 1)
            let encoded = clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
            return UInt32((encoded * 255).rounded())
        }
        return channel(color.x) << 16 | channel(color.y) << 8 | channel(color.z)
    }
}
