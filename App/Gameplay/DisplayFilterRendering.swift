import EmulatorDomain
import simd

extension DisplayFilter {
    /// The `displayMode` the gameplay fragment shaders read. Modes 3 and up get sRGB views of the
    /// frames, so they sample linear light; modes above 3 are in DisplayShaders.h.
    var shaderMode: UInt32 {
        switch self {
        case .off: 0
        case .lcd1x: 1
        case .lcd3x: 2
        case .sp101LCD: 3
        case .monochromeLCD: 4
        case .authenticGBC: 5
        case .gbaLCD: 6
        case .scanlines, .crt240p, .crt480p: 7
        }
    }

    var samplesLinearLight: Bool { shaderMode >= 3 }

    /// The television a CRT treatment draws, or nil for the others.
    var crtParameters: CRTParameters? {
        switch self {
        case .crt240p: .consumerTV
        case .crt480p: .lateModelTV
        case .scanlines: .scanlines
        default: nil
        }
    }
}

/// One television for the CRT shader, matching `CRTParameters` in DisplayShaders.h. Beam hardness
/// is the exponent of a base-2 Gaussian, so more negative is narrower; CRT-Lottes uses -8 across
/// a line and -3 along it. At -3 a pixel's center still takes about a tenth of its neighbor and
/// an edge ramps across the whole pixel, which reads as blur at a phone's 7 screen pixels per
/// Game Boy pixel, so the treatments here are harder along the line.
struct CRTParameters: Equatable {
    /// Barrel curvature x and y (0 is flat; CRT-Lottes uses 0.031 and 0.042), corner radius in
    /// half-heights, and vignette strength.
    var geometry: SIMD4<Float>
    /// Raster lines per source line, scanline hardness, horizontal hardness and brightness.
    var beam: SIMD4<Float>
    /// Phosphor triads per source pixel (0 for none), dark and light channel gain, and for a slot
    /// mask the height of the break between slots as a fraction of a source line (0 for a grille).
    /// The mask follows source pixels, so every pixel carries the same stripes at any scale.
    var mask: SIMD4<Float>
    /// Bloom amount (0 for none) and the mip level it is read from.
    var glow: SIMD4<Float>

    var curvature: SIMD2<Float> { SIMD2(geometry.x, geometry.y) }
    var triadsPerSourcePixel: Float { mask.x }
    var isSlotMask: Bool { mask.x > 0 && mask.w > 0 }
    var linesPerSourceLine: Float { beam.x }
    var glowAmount: Float { glow.x }

    /// A Super Game Boy on a 1990s consumer set: a spherical tube with visible curvature, one
    /// visible scanline per SNES line and a slot mask of two triads per pixel. The analog picture
    /// stays a little soft along the line, with a faint glow, while outlines stay dark.
    static let consumerTV = CRTParameters(
        geometry: SIMD4(0.055, 0.075, 0.06, 0.22),
        beam: SIMD4(1, -8, -5, 1.3),
        mask: SIMD4(2, 0.8, 1.35, 0.15),
        glow: SIMD4(0.05, 2, 0, 0)
    )

    /// A Game Boy Player on a flat late-model set: a nearly flat face with rounded corners, the
    /// player's line-doubled 480-line picture so the lines nearly close up, a sharper component
    /// picture and a finer aperture grille.
    static let lateModelTV = CRTParameters(
        geometry: SIMD4(0.008, 0.010, 0.10, 0.08),
        beam: SIMD4(2, -7, -6, 1.2),
        mask: SIMD4(2.5, 0.85, 1.25, 0),
        glow: SIMD4(0.03, 2, 0, 0)
    )

    /// The television as players remember it: a gently curved screen with rounded corners and
    /// crisp scanlines, without a mask, glow or vignette. Lighter than either CRT treatment.
    static let scanlines = CRTParameters(
        geometry: SIMD4(0.024, 0.032, 0.05, 0),
        beam: SIMD4(1, -10, -8, 1.45),
        mask: SIMD4(0, 1, 1, 0),
        glow: SIMD4(0, 0, 0, 0)
    )

    /// What a filter that isn't a CRT is given, so the shader's buffer is always bound.
    static let none = CRTParameters(geometry: .zero, beam: SIMD4(1, 0, 0, 1), mask: .zero, glow: .zero)

    /// Without bloom, which also saves building the frames' mipmaps.
    var withoutGlow: CRTParameters {
        var copy = self
        copy.glow = .zero
        return copy
    }
}
