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
        case .scanlines, .curvedScanlines, .slightlyCurvedScanlines, .crt240p, .crt480p: 7
        }
    }

    var samplesLinearLight: Bool { shaderMode >= 3 }

    /// The television a CRT treatment draws, or nil for the others.
    var crtParameters: CRTParameters? {
        switch self {
        case .crt240p: .consumerTV
        case .crt480p: .flatSquareTV
        case .scanlines: .flatScanlines
        case .curvedScanlines: .curvedScanlines
        case .slightlyCurvedScanlines: .slightlyCurvedScanlines
        default: nil
        }
    }
}

/// One television for the CRT shader, matching `CRTParameters` in DisplayShaders.h. Beam hardness
/// is the exponent of a base-2 Gaussian, so more negative is narrower; CRT-Lottes uses -8 across
/// a line and -3 along it. At -3 a pixel's center still takes about a tenth of its neighbor and
/// an edge ramps across the whole pixel, which reads as blur at a phone's 7 screen pixels per
/// Game Boy pixel, so the treatments here are harder along the line.
///
/// The barrel warp stands for a convex glass face seen up close: a straight raster edge recedes
/// toward the corners by the face's sagitta, so from a viewing distance d the corners pull in by
/// sagitta / d, which is the warp's corner droop. For a spherical face of radius R, a half-width
/// w and a half-height h that gives warp (h² / 2Rd, w² / 2Rd); a cylindrical face curved only
/// across gives (0, w² / 2Rd). `docs/display-presets.md` has the tubes, sources and distances.
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
    var cornerRadius: Float { geometry.z }
    var triadsPerSourcePixel: Float { mask.x }
    var isSlotMask: Bool { mask.x > 0 && mask.w > 0 }
    var linesPerSourceLine: Float { beam.x }
    var glowAmount: Float { glow.x }

    /// The warp of a 4:3 spherical tube whose face radius is `radiusInDiagonals` screen diagonals,
    /// seen from `viewingDistanceInHeights` screen heights: the geometry above with w = 2/3 H,
    /// h = H/2 and R in those units (a 4:3 diagonal is 5/3 H).
    static func sphericalWarp(radiusInDiagonals: Float, viewingDistanceInHeights: Float) -> SIMD2<Float> {
        let radius = radiusInDiagonals * 5 / 3
        let denominator = 2 * radius * viewingDistanceInHeights
        return SIMD2((0.5 * 0.5) / denominator, (2.0 / 3.0 * 2.0 / 3.0) / denominator)
    }

    /// The close look the treatments take at their sets: two screen heights, about 60 cm from a
    /// 20-inch set, where the bulge of the glass is plain. From a couch (ITU-R's 7 heights) the
    /// same tubes would bow under a third as much and the curve would be lost at phone size.
    static let viewingDistanceInHeights: Float = 2

    /// A Super Game Boy on a 1990s consumer set: a standard-radius (1R) spherical shadow-mask
    /// tube, whose face radius is 1.63 screen diagonals, one visible scanline per SNES line and a
    /// slot mask of two triads per pixel. The analog picture stays a little soft along the line,
    /// with a faint glow, while outlines stay dark.
    static let consumerTV = CRTParameters(
        curvature: sphericalWarp(radiusInDiagonals: 1.63, viewingDistanceInHeights: viewingDistanceInHeights),
        cornerRadius: 0.06, vignette: 0.22,
        beam: SIMD4(1, -8, -5, 1.3),
        mask: SIMD4(2, 0.8, 1.35, 0.15),
        glow: SIMD4(0.05, 2, 0, 0)
    )

    /// A Game Boy Player on a 2000s set: the flattest spherical contour still sold curved, a
    /// flat-square (2R) tube of twice the standard radius, with rounded corners, the player's
    /// line-doubled 480-line picture so the lines nearly close up, a sharper component picture
    /// and a finer aperture grille.
    static let flatSquareTV = CRTParameters(
        curvature: sphericalWarp(radiusInDiagonals: 3.26, viewingDistanceInHeights: viewingDistanceInHeights),
        cornerRadius: 0.10, vignette: 0.08,
        beam: SIMD4(2, -7, -6, 1.2),
        mask: SIMD4(2.5, 0.85, 1.25, 0),
        glow: SIMD4(0.03, 2, 0, 0)
    )

    /// The crispest beam of the treatments, for the scanline filters: sharp lines with dark gaps
    /// and pixel edges as crisp as the Pixel Grid's, without a mask, glow or vignette.
    private static let crispBeam = SIMD4<Float>(1, -10, -8, 1.45)

    /// Scanlines on a flat picture: no warp and no rounded corners.
    static let flatScanlines = CRTParameters(
        geometry: .zero, beam: crispBeam, mask: SIMD4(0, 1, 1, 0), glow: .zero
    )

    /// The Super Game Boy's television as players remember it: the crisp scanlines on a curved
    /// screen with small rounded corners, three quarters of CRT 240p's warp.
    static let curvedScanlines = CRTParameters(
        curvature: consumerTV.curvature * 0.75, cornerRadius: 0.05, vignette: 0,
        beam: crispBeam, mask: SIMD4(0, 1, 1, 0), glow: .zero
    )

    /// The Game Boy Player's television as players remember it: the crisp scanlines on a slightly
    /// curved screen, two thirds of CRT 480p's warp, still a visible curve at phone size.
    static let slightlyCurvedScanlines = CRTParameters(
        curvature: flatSquareTV.curvature * (2.0 / 3.0), cornerRadius: 0.05, vignette: 0,
        beam: crispBeam, mask: SIMD4(0, 1, 1, 0), glow: .zero
    )

    /// What a filter that isn't a CRT is given, so the shader's buffer is always bound.
    static let none = CRTParameters(geometry: .zero, beam: SIMD4(1, 0, 0, 1), mask: .zero, glow: .zero)

    init(geometry: SIMD4<Float>, beam: SIMD4<Float>, mask: SIMD4<Float>, glow: SIMD4<Float>) {
        self.geometry = geometry
        self.beam = beam
        self.mask = mask
        self.glow = glow
    }

    init(curvature: SIMD2<Float>, cornerRadius: Float, vignette: Float, beam: SIMD4<Float>, mask: SIMD4<Float>, glow: SIMD4<Float>) {
        self.init(geometry: SIMD4(curvature.x, curvature.y, cornerRadius, vignette), beam: beam, mask: mask, glow: glow)
    }

    /// Without bloom, which also saves building the frames' mipmaps.
    var withoutGlow: CRTParameters {
        var copy = self
        copy.glow = .zero
        return copy
    }

    /// The same geometry with a flat, even beam and no mask, glow or vignette, so a white frame
    /// renders as a uniform white raster whose edges can be measured to a fraction of a pixel.
    /// An even beam sums two whole lines, so the brightness halves to keep white at white.
    var geometryOnly: CRTParameters {
        CRTParameters(
            geometry: SIMD4(geometry.x, geometry.y, geometry.z, 0),
            beam: SIMD4(1, 0, 0, 0.5), mask: .zero, glow: .zero
        )
    }
}
