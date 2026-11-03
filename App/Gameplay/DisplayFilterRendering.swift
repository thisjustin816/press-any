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
/// a line and -3 along it. Mask pitch is in screen pixels for one red, green and blue triad.
struct CRTParameters: Equatable {
    /// Barrel curvature x and y (0 is flat; CRT-Lottes uses 0.031 and 0.042), corner radius in
    /// half-heights, and vignette strength.
    var geometry: SIMD4<Float>
    /// Raster lines per source line, scanline hardness, horizontal hardness and brightness.
    var beam: SIMD4<Float>
    /// Pitch (0 for none), dark and light channel gain, and 1 for a slot mask or 0 for a grille.
    var mask: SIMD4<Float>
    /// Bloom amount (0 for none) and the mip level it is read from.
    var glow: SIMD4<Float>

    var curvature: SIMD2<Float> { SIMD2(geometry.x, geometry.y) }
    var maskPitch: Float { mask.x }
    var linesPerSourceLine: Float { beam.x }

    /// A Super Game Boy on a 1990s consumer set: a spherical tube with visible curvature, one
    /// visible scanline per SNES line, a coarse slot mask and a soft analog picture.
    static let consumerTV = CRTParameters(
        geometry: SIMD4(0.055, 0.075, 0.06, 0.22),
        beam: SIMD4(1, -8, -2.5, 1.55),
        mask: SIMD4(6, 0.6, 1.4, 1),
        glow: SIMD4(0.18, 1.6, 0, 0)
    )

    /// A Game Boy Player on a flat late-model set: a nearly flat face with rounded corners, the
    /// player's line-doubled 480-line picture so the lines nearly close up, and a fine aperture
    /// grille.
    static let lateModelTV = CRTParameters(
        geometry: SIMD4(0.008, 0.010, 0.10, 0.08),
        beam: SIMD4(2, -6, -2.0, 1.25),
        mask: SIMD4(3, 0.75, 1.25, 0),
        glow: SIMD4(0.10, 1.6, 0, 0)
    )

    /// Clean scanlines on a flat picture, without a mask, curvature or glow.
    static let scanlines = CRTParameters(
        geometry: SIMD4(0, 0, 0, 0),
        beam: SIMD4(1, -10, -6, 1.45),
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
