import EmulatorApplication
import EmulatorDomain
import Importing
import Metal
import UIKit
import XCTest
@testable import PressAny

@MainActor
final class LCDFilterTests: XCTestCase {
    func testLibraryAndQuickPlayResolveSavedFiltersWithTheStandardPresetAsTheDefault() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root, plus: .fixed(ownsPlus: true))
        let file = root.appendingPathComponent("LCD Fixture.gb")
        try Data(repeating: 0, count: 0x8000).write(to: file)
        let analysis = try container.importAnalyzer.analyzeROM(at: file, targetGameID: nil)
        let result = try container.importCommitter.commit(ROMImportPlan(
            analysis: analysis, disposition: .createGame(title: "LCD Fixture"),
            buildDisplayName: "Original", markAsBase: true
        ))
        let context = LaunchContext(gameID: result.build.gameID, buildID: result.build.id, saveProfileID: UUID())
        let standard = GameplayPresetValues.standard(for: .gameBoyPocket).displayFilter
        XCTAssertEqual(container.gameplayValues(for: context).displayFilter, standard)
        XCTAssertEqual(container.gameplayValues(system: .gameBoy).displayFilter, standard)
        let settings = container.repositories.settings
        let key = SettingKey.lcdFilter.rawValue
        try settings.set(DisplayFilter.lcd3x, key: key, scope: .app)
        try settings.set(DisplayFilter.monochromeLCD, key: key, scope: .system(.gameBoy))
        XCTAssertEqual(container.gameplayValues(for: context).displayFilter, .monochromeLCD)
        XCTAssertEqual(container.gameplayValues(system: .gameBoyColor).displayFilter, .lcd3x)
        try settings.set(DisplayFilter.off, key: key, scope: .build(result.build.id))
        let reopened = try AppContainer(rootURL: root, plus: .fixed(ownsPlus: true))
        XCTAssertEqual(reopened.gameplayValues(for: context).displayFilter, .off)
        XCTAssertEqual(reopened.gameplayValues(system: .gameBoy).displayFilter, .monochromeLCD)
        try settings.setValueJSON("\"gameCubeTV\"", key: key, scope: .build(result.build.id))
        XCTAssertEqual(
            container.gameplayValues(for: context).displayFilter, standard,
            "an unknown filter, such as the retired gameCubeTV, plays the default and must not block launch"
        )

        // The defaults follow the hardware the game runs on.
        try settings.removeValue(key: key, scope: .build(result.build.id))
        try settings.removeValue(key: key, scope: .system(.gameBoy))
        try settings.removeValue(key: key, scope: .app)
        try settings.set(HardwareModel.superGameBoy, key: SettingKey.hardwareModel.rawValue, scope: .game(result.build.gameID))
        XCTAssertEqual(container.gameplayValues(for: context).displayFilter, GameplayPresetValues.standard(for: .superGameBoy).displayFilter)
        let quickPlay = container.gameplayDisplay(for: container.gameplaySettingsTarget(system: .gameBoy))
        XCTAssertEqual(quickPlay.lcdFilter, standard, "Quick Play runs on Automatic whatever Model says")
    }

    func testBothSamplingModesPreserveRawPixelsAndRenderTheVersionOneGrids() throws {
        let (device, library) = try metal()
        for fragment in ["gameplayTextureFragment", "gameplaySharpFragment"] {
            let raw = try render(.off, fragment: fragment, device: device, library: library)
            XCTAssertTrue(raw.allSatisfy { $0 == 255 }, "Off must preserve the original white pixel")

            let grid = try render(.lcd1x, fragment: fragment, device: device, library: library)
            XCTAssertLessThan(grid[pixel(0, 12)], grid[pixel(12, 12)], "Pixel Grid must darken cell edges")
            XCTAssertEqual(grid[pixel(12, 12)], 255, "Pixel Grid keeps the v1.0 LCD 1× cell centers")
            for offset in stride(from: 0, to: grid.count, by: 4) {
                XCTAssertEqual(grid[offset], grid[offset + 1], "The pixel grid must not tint colors")
                XCTAssertEqual(grid[offset + 1], grid[offset + 2])
                XCTAssertEqual(grid[offset + 3], 255)
            }

            let subpixels = try render(.lcd3x, fragment: fragment, device: device, library: library)
            let red = pixel(4, 12), green = pixel(12, 12), blue = pixel(20, 12)
            XCTAssertGreaterThan(subpixels[red + 2], subpixels[red + 1], "First band is red")
            XCTAssertGreaterThan(subpixels[green + 1], subpixels[green], "Middle band is green")
            XCTAssertGreaterThan(subpixels[blue], subpixels[blue + 2], "Last band is blue")
            XCTAssertNotEqual(subpixels, grid)

            let backlit = try render(.sp101LCD, fragment: fragment, device: device, library: library, frames: [128])
            let center = pixel(12, 12)
            XCTAssertNotEqual(Array(backlit[center..<(center + 3)]), [128, 128, 128], "the SP101 profile changes gray")
            XCTAssertLessThan(backlit[pixel(0, 12)], backlit[center], "and keeps the grid")
        }
    }

    /// Frame blending mixes the newest frame with the frames before it by the renderer's weights,
    /// in both sampling modes, and Off leaves the newest frame as it is.
    func testFrameBlendingMixesEarlierFramesByTheirWeights() throws {
        let (device, library) = try metal()
        // A white frame after two black ones.
        let frames: [UInt8] = [255, 0, 0]
        for fragment in ["gameplayTextureFragment", "gameplaySharpFragment"] {
            for (blending, expected) in [(FrameBlending.off, 255), (.blend, 128), (.ghosting, 128)] {
                let weights = blending.weights(heldFrames: 3).map { Float($0) }
                let pixels = try render(
                    .off, fragment: fragment, device: device, library: library,
                    frames: frames, weights: SIMD4(weights[0], weights[1], weights[2], 0)
                )
                XCTAssertEqual(Int(pixels[pixel(12, 12)]), expected, accuracy: 1, "\(blending) in \(fragment)")
            }
            let fading = try render(
                .off, fragment: fragment, device: device, library: library,
                frames: [0, 255, 255], weights: SIMD4(0.5, 0.3, 0.2, 0)
            )
            XCTAssertEqual(Int(fading[pixel(12, 12)]), 128, accuracy: 1, "a light that just went out leaves a trail")
        }
    }

    /// Without frame blending no treatment shows an earlier frame, so moving content never combs.
    func testNoTreatmentShowsAnEarlierFrameWithoutFrameBlending() throws {
        let (device, library) = try metal()
        for filter in DisplayFilter.allCases {
            let still = try render(
                filter, fragment: "gameplayTextureFragment", device: device, library: library,
                frames: [200, 200, 200], sourceWidth: 16, sourceHeight: 16, outputWidth: 96, outputHeight: 96
            )
            let moving = try render(
                filter, fragment: "gameplayTextureFragment", device: device, library: library,
                frames: [200, 0, 0], sourceWidth: 16, sourceHeight: 16, outputWidth: 96, outputHeight: 96
            )
            XCTAssertEqual(still, moving, "\(filter)")
        }
    }

    /// The curvature orderings, measured on the picture at a phone's size (7 screen pixels per
    /// Game Boy pixel): Super Game Boy treatments curve more than Game Boy Player ones in Accurate
    /// and in Nostalgic, each Nostalgic less than its hardware's Accurate, every one of the four
    /// visibly, and flat Scanlines not at all.
    func testCRTCurvatureOrderingsHoldOnTheRenderedPicture() throws {
        let (device, library) = try metal()
        let width = 1120, height = 1008
        // The raster's top and left edges, to a fraction of a pixel, from the light the outer
        // rows and columns carry once the beam is even and the mask, glow and vignette are off;
        // the geometry is the filter's own.
        func edgeBow(_ filter: DisplayFilter) throws -> (top: Double, side: Double) {
            let parameters = try XCTUnwrap(filter.crtParameters).geometryOnly
            let pixels = try render(
                filter, fragment: "gameplayTextureFragment", device: device, library: library,
                frames: [255], sourceWidth: 160, sourceHeight: 144, outputWidth: width, outputHeight: height, crt: parameters
            )
            func topEdge(_ x: Int) -> Double {
                100 - (0..<100).reduce(0.0) { $0 + Double(brightness(pixels, at: pixel(x, $1, width: width))) / 765 }
            }
            func sideEdge(_ y: Int) -> Double {
                100 - (0..<100).reduce(0.0) { $0 + Double(brightness(pixels, at: pixel($1, y, width: width))) / 765 }
            }
            // An eighth of the way in from a side or the top, clear of the rounded corners.
            return (topEdge(width / 8) - topEdge(width / 2), sideEdge(height / 8) - sideEdge(height / 2))
        }
        // The same orderings with the filter as it ships, from a bright line drawn near the top
        // of the picture: its vertical center of light in each column follows the warp whatever
        // the scanlines, mask and glow do to its brightness.
        func lineBow(_ filter: DisplayFilter) throws -> Double {
            var source = [UInt8](repeating: 0, count: 160 * 144 * 4)
            for x in 0..<160 {
                for channel in 0..<4 { source[(8 * 160 + x) * 4 + channel] = 255 }
            }
            let pixels = try render(
                filter, fragment: "gameplayTextureFragment", device: device, library: library,
                sourceWidth: 160, sourceHeight: 144, outputWidth: width, outputHeight: height, sourcePixels: source
            )
            func center(_ x: Int) -> Double {
                var weight = 0.0, moment = 0.0
                for y in 0..<200 {
                    let light = Double(brightness(pixels, at: pixel(x, y, width: width)))
                    weight += light
                    moment += light * Double(y)
                }
                return moment / weight
            }
            return center(width / 8) - center(width / 2)
        }

        let accurateSGB = try edgeBow(.crt240p), accurateGBP = try edgeBow(.crt480p)
        let nostalgicSGB = try edgeBow(.curvedScanlines), nostalgicGBP = try edgeBow(.slightlyCurvedScanlines)
        let flat = try edgeBow(.scanlines)
        let curved = [
            ("CRT 240p", accurateSGB), ("CRT 480p", accurateGBP),
            ("Curved Scanlines", nostalgicSGB), ("Slightly Curved Scanlines", nostalgicGBP),
        ]
        for (name, bow) in curved {
            XCTAssertGreaterThanOrEqual(bow.top, 3, "\(name) bows visibly at phone size")
            XCTAssertGreaterThanOrEqual(bow.side, 1.5, "\(name) curves across as well as down")
        }
        XCTAssertGreaterThan(accurateSGB.top, accurateGBP.top + 2, "the Super Game Boy's set curves more than the Game Boy Player's")
        XCTAssertGreaterThan(nostalgicSGB.top, nostalgicGBP.top + 2, "and so does its remembered set")
        XCTAssertGreaterThan(accurateSGB.top, nostalgicSGB.top + 1.5, "Nostalgic curves less than Accurate on a Super Game Boy")
        XCTAssertGreaterThan(accurateGBP.top, nostalgicGBP.top + 1, "and on a Game Boy Player")
        XCTAssertEqual(flat.top, 0, accuracy: 0.05, "flat Scanlines have no bow")
        XCTAssertEqual(flat.side, 0, accuracy: 0.05)

        let filters: [DisplayFilter] = [.crt240p, .crt480p, .curvedScanlines, .slightlyCurvedScanlines, .scanlines]
        let bows = Dictionary(uniqueKeysWithValues: try filters.map { ($0, try lineBow($0)) })
        func bow(_ filter: DisplayFilter) throws -> Double { try XCTUnwrap(bows[filter]) }
        XCTAssertGreaterThan(try bow(.crt240p), try bow(.crt480p) + 1)
        XCTAssertGreaterThan(try bow(.curvedScanlines), try bow(.slightlyCurvedScanlines) + 1)
        XCTAssertGreaterThan(try bow(.crt240p), try bow(.curvedScanlines) + 1)
        XCTAssertGreaterThan(try bow(.crt480p), try bow(.slightlyCurvedScanlines) + 0.5)
        XCTAssertGreaterThan(try bow(.slightlyCurvedScanlines), 1.5, "the gentlest treatment still moves a line near the top by over a pixel")
        XCTAssertEqual(try bow(.scanlines), 0, accuracy: 0.05)

        XCTAssertEqual(CRTParameters.consumerTV.linesPerSourceLine, 1)
        XCTAssertEqual(CRTParameters.flatSquareTV.linesPerSourceLine, 2)
        XCTAssertEqual(CRTParameters.flatScanlines.geometry, .zero, "flat Scanlines have no warp and no rounded corners")
        for parameters in [CRTParameters.curvedScanlines, .slightlyCurvedScanlines] {
            XCTAssertGreaterThan(parameters.cornerRadius, 0, "Nostalgic's scanlines have small rounded corners")
            XCTAssertEqual(parameters.triadsPerSourcePixel, 0, "and no mask")
            XCTAssertEqual(parameters.glowAmount, 0, "and no glow")
        }
    }

    func testCRTRastersAndMasksDifferInDensity() throws {
        let (device, library) = try metal()
        // Mid-gray stays below clipping, so the mask and beam show in full. Twelve screen pixels
        // per source pixel resolve the finer mask.
        func picture(_ filter: DisplayFilter, size: Int = 384, crt: CRTParameters? = nil) throws -> [UInt8] {
            try render(
                filter, fragment: "gameplayTextureFragment", device: device, library: library,
                frames: [96], sourceWidth: 32, sourceHeight: 32, outputWidth: size, outputHeight: size, crt: crt
            )
        }
        // Scanlines: brightness along a column through the middle, over four source lines, with
        // the mask left out so a slot mask's breaks don't count as lines.
        func ripple(_ filter: DisplayFilter) throws -> (depth: Int, peaks: Int) {
            var beamOnly = try XCTUnwrap(filter.crtParameters)
            beamOnly.mask = .zero
            let pixels = try picture(filter, crt: beamOnly)
            let column = (168..<216).map { brightness(pixels, at: pixel(192, $0, width: 384)) }
            let peaks = (1..<(column.count - 1)).filter { column[$0] > column[$0 - 1] && column[$0] >= column[$0 + 1] }
            return ((column.max() ?? 0) - (column.min() ?? 0), peaks.count)
        }
        let consumerRipple = try ripple(.crt240p), lateRipple = try ripple(.crt480p)
        XCTAssertGreaterThan(consumerRipple.depth, 40, "CRT 240p shows dark gaps between lines")
        XCTAssertGreaterThan(lateRipple.depth, 8, "CRT 480p still shows its finer lines")
        XCTAssertLessThan(lateRipple.depth, consumerRipple.depth)
        XCTAssertGreaterThan(lateRipple.peaks, consumerRipple.peaks, "CRT 480p draws more lines over the same source lines")
        for filter in [DisplayFilter.scanlines, .curvedScanlines, .slightlyCurvedScanlines] {
            XCTAssertGreaterThan(try ripple(filter).depth, 40, "\(filter) draws crisp scanlines")
        }

        // The mask: the spacing between the starts of red-dominant runs along a row a quarter of
        // the way down a source line, clear of a slot mask's breaks.
        func maskPitch(_ pixels: [UInt8], size: Int) -> Double {
            let row = 16 * (size / 32) + size / 128
            let reds = (0..<size).map { x -> Bool in
                let index = pixel(x, row, width: size)
                return Int(pixels[index + 2]) > Int(pixels[index + 1]) + 4
            }
            let starts = (1..<reds.count).filter { reds[$0] && !reds[$0 - 1] }
            guard starts.count > 2, let first = starts.first, let last = starts.last else { return 0 }
            return Double(last - first) / Double(starts.count - 1)
        }
        XCTAssertGreaterThan(
            CRTParameters.flatSquareTV.triadsPerSourcePixel, CRTParameters.consumerTV.triadsPerSourcePixel,
            "CRT 480p's grille is finer than CRT 240p's slot mask"
        )
        XCTAssertTrue(CRTParameters.consumerTV.isSlotMask)
        XCTAssertFalse(CRTParameters.flatSquareTV.isSlotMask)
        // The mask follows source pixels, so its pitch scales with them and every pixel carries
        // the same stripes.
        let televisions: [(DisplayFilter, CRTParameters)] = [(.crt240p, .consumerTV), (.crt480p, .flatSquareTV)]
        for size in [384, 288] {
            let pixelsPerSource = Double(size / 32)
            for (filter, parameters) in televisions {
                XCTAssertEqual(
                    maskPitch(try picture(filter, size: size), size: size),
                    pixelsPerSource / Double(parameters.triadsPerSourcePixel), accuracy: 0.3, "\(filter) at \(size)"
                )
            }
            for filter in [DisplayFilter.scanlines, .curvedScanlines, .slightlyCurvedScanlines] {
                XCTAssertEqual(maskPitch(try picture(filter, size: size), size: size), 0, "\(filter) has no mask")
            }
        }
    }

    /// Pixel art stays readable: a one-pixel dark outline stays dark and an edge between source
    /// pixels takes well under a source pixel. The scanline filters are the crispest.
    func testCRTKeepsOutlinesDarkAndEdgesSharp() throws {
        let (device, library) = try metal()
        let scale = 12
        func row(_ filter: DisplayFilter, source: [UInt8], crt: CRTParameters? = nil) throws -> [Int] {
            let pixels = try render(
                filter, fragment: "gameplayTextureFragment", device: device, library: library,
                sourceWidth: 32, sourceHeight: 32, outputWidth: 32 * scale, outputHeight: 32 * scale,
                sourcePixels: source, crt: crt
            )
            // A line center: CRT 480p draws two lines per source line.
            let lines = Int(try XCTUnwrap(filter.crtParameters).linesPerSourceLine)
            let y = 15 * scale + scale / (2 * lines)
            return (0..<(32 * scale)).map { brightness(pixels, at: pixel($0, y, width: 32 * scale)) }
        }
        func picture(_ gray: (Int) -> UInt8) -> [UInt8] {
            (0..<(32 * 32)).flatMap { index -> [UInt8] in
                let value = gray(index % 32)
                return [value, value, value, 255]
            }
        }
        // A black column on white, as an outline is, and white on the left with black on the right.
        let outline = picture { $0 == 16 ? 0 : 255 }
        let edge = picture { $0 < 16 ? 255 : 0 }
        var widths: [DisplayFilter: Int] = [:]
        let scanlineFilters: [DisplayFilter] = [.scanlines, .curvedScanlines, .slightlyCurvedScanlines]
        for filter in [DisplayFilter.crt240p, .crt480p] + scanlineFilters {
            let line = try row(filter, source: outline)
            let darkest = try XCTUnwrap(line[(16 * scale)..<(17 * scale)].min())
            let white = try XCTUnwrap(line[(8 * scale)..<(12 * scale)].max())
            XCTAssertGreaterThan(white, 600, "\(filter) keeps white bright")
            XCTAssertLessThan(darkest, scanlineFilters.contains(filter) ? 120 : 300, "\(filter) keeps a one-pixel outline dark")

            // The beam alone, without mask or glow, from 10% to 90% of the way across the edge.
            var beam = try XCTUnwrap(filter.crtParameters)
            beam.mask = .zero
            beam.glow = .zero
            let ramp = try row(filter, source: edge, crt: beam)[(13 * scale)..<(19 * scale)]
            let low = try XCTUnwrap(ramp.min()), high = try XCTUnwrap(ramp.max())
            let width = ramp.filter { $0 > low + (high - low) / 10 && $0 < low + (high - low) * 9 / 10 }.count
            XCTAssertLessThanOrEqual(width, scale * 2 / 3, "\(filter) edges take under two thirds of a source pixel")
            widths[filter] = width
        }
        for filter in scanlineFilters {
            XCTAssertLessThanOrEqual(try XCTUnwrap(widths[filter]), try XCTUnwrap(widths[.crt480p]))
            XCTAssertLessThanOrEqual(try XCTUnwrap(widths[filter]), try XCTUnwrap(widths[.crt240p]))
        }
    }

    /// The curved treatments round their corners off to black; flat Scanlines keep the picture's
    /// square corners.
    func testCRTCornersAreBlackAndRoundedExceptOnFlatScanlines() throws {
        let (device, library) = try metal()
        for filter in [DisplayFilter.crt240p, .crt480p, .curvedScanlines, .slightlyCurvedScanlines, .scanlines] {
            let pixels = try render(
                filter, fragment: "gameplayTextureFragment", device: device, library: library,
                frames: [255], sourceWidth: 160, sourceHeight: 144, outputWidth: 320, outputHeight: 288
            )
            let corners = [(0, 0), (319, 0), (0, 287), (319, 287), (2, 2)].map { brightness(pixels, at: pixel($0, $1, width: 320)) }
            if filter == .scanlines {
                XCTAssertGreaterThan(try XCTUnwrap(corners.last), 600, "flat Scanlines light the corner")
            } else {
                XCTAssertEqual(corners, [0, 0, 0, 0, 0], "\(filter) corners are black")
            }
            XCTAssertGreaterThan(brightness(pixels, at: pixel(160, 144, width: 320)), 300)
            XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 })
        }
    }

    /// Glow spills a little light just past a bright area and stays near it, so it doesn't veil
    /// the picture; reduced work drops it.
    func testCRTGlowsNearBrightLightAndReducedWorkDropsTheGlow() throws {
        let (device, library) = try metal()
        // White on the left half of a 16-pixel source, black on the right.
        var pixels = [UInt8]()
        for _ in 0..<16 {
            for x in 0..<16 {
                let value: UInt8 = x < 8 ? 255 : 0
                pixels += [value, value, value, 255]
            }
        }
        let televisions: [(DisplayFilter, CRTParameters)] = [(.crt240p, .consumerTV), (.crt480p, .flatSquareTV)]
        for (filter, parameters) in televisions {
            XCTAssertGreaterThan(parameters.glowAmount, 0, "\(filter) glows")
            func crt(_ parameters: CRTParameters) throws -> [UInt8] {
                try render(
                    filter, fragment: "gameplayTextureFragment", device: device, library: library,
                    sourceWidth: 16, sourceHeight: 16, outputWidth: 320, outputHeight: 320, sourcePixels: pixels, crt: parameters
                )
            }
            let glowing = try crt(parameters)
            let reduced = try crt(parameters.withoutGlow)
            // A source pixel and a half into the black, where the beam has no light left, at a
            // line center; and six and a half pixels in.
            let beside = pixel(190, 170, width: 320), far = pixel(290, 170, width: 320)
            XCTAssertGreaterThan(brightness(glowing, at: beside), brightness(reduced, at: beside) + 3, "\(filter) glows beside the light")
            XCTAssertLessThan(brightness(glowing, at: beside), 120, "\(filter) glow is faint")
            XCTAssertEqual(brightness(reduced, at: beside), 0, "\(filter) without glow the dark stays dark")
            XCTAssertEqual(brightness(glowing, at: far), 0, "\(filter) glow stays near the light")
        }
    }

    func testPhysicalTreatmentsDrawTheSameInBothScalingPaths() throws {
        let (device, library) = try metal()
        for filter in DisplayFilter.allCases where filter.shaderMode > 3 {
            for (width, height) in [(480, 432), (523, 471)] {
                let integer = try render(
                    filter, fragment: "gameplayTextureFragment", device: device, library: library,
                    sourceWidth: 160, sourceHeight: 144, outputWidth: width, outputHeight: height
                )
                let fill = try render(
                    filter, fragment: "gameplaySharpFragment", device: device, library: library,
                    sourceWidth: 160, sourceHeight: 144, outputWidth: width, outputHeight: height
                )
                XCTAssertEqual(integer, fill, "\(filter) reconstructs the same physical display in either path")
                XCTAssertTrue(stride(from: 3, to: fill.count, by: 4).allSatisfy { fill[$0] == 255 })
            }
        }
    }

    /// Every filter, drawn from one synthetic picture, attached for review. Each must show
    /// something, and no two may look the same.
    func testDisplayReferenceCaptures() throws {
        let (device, library) = try metal()
        let width = 160, height = 144, outWidth = 640, outHeight = 576
        var fixture = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                // A gradient, an 8-pixel checker and a one-pixel grid every 16 pixels, like text.
                let checker = ((x / 8 + y / 8) % 2) == 0
                let line = x % 16 == 0 || y % 16 == 0
                let blue: UInt8 = line ? 0 : (checker ? 255 : 32)
                fixture += [blue, UInt8(y * 255 / (height - 1)), UInt8(x * 255 / (width - 1)), 255]
            }
        }
        var captures: [DisplayFilter: [UInt8]] = [:]
        for filter in DisplayFilter.allCases {
            let pixels = try render(
                filter, fragment: "gameplayTextureFragment", device: device, library: library,
                sourceWidth: width, sourceHeight: height, outputWidth: outWidth, outputHeight: outHeight,
                sourcePixels: fixture
            )
            let mean = stride(from: 0, to: pixels.count, by: 4).reduce(0) { $0 + brightness(pixels, at: $1) } / (outWidth * outHeight)
            XCTAssertGreaterThan(mean, 150, "\(filter) keeps the picture readable")
            for (other, seen) in captures {
                XCTAssertNotEqual(seen, pixels, "\(filter) looks different from \(other)")
            }
            captures[filter] = pixels
            let attachment = XCTAttachment(image: try XCTUnwrap(image(from: pixels, width: outWidth, height: outHeight)))
            attachment.name = "device-display-\(filter.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// CRT 240p as it ships beside a crisper variant on the same picture, for the owner to choose
    /// its sharpness: the shipped horizontal hardness -5 with glow 0.05, and -6 with glow 0.04.
    func testCRT240pSharpnessComparisonCapture() throws {
        let (device, library) = try metal()
        let width = 160, height = 144, scale = 7
        var fixture = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                // Pixel art at the scale of game text: 8-pixel tiles with one-pixel outlines,
                // 2-pixel strokes and a checker, on a gradient, with a grid of single dark pixels.
                let tx = x % 8, ty = y % 8
                let outline = tx == 0 || ty == 0
                let stroke = (tx == 3 || tx == 4) && ty > 1 && ty < 7
                let checker = (x / 8 + y / 8) % 2 == 0
                let dot = x % 4 == 2 && y % 4 == 2 && !checker
                let dark = outline || stroke || dot
                let value: UInt8 = dark ? 16 : (checker ? 240 : 200)
                fixture += [value, UInt8(min(255, Int(value) * (y + 100) / 244)), UInt8(min(255, Int(value) * (x + 80) / 240)), 255]
            }
        }
        var crisper = CRTParameters.consumerTV
        crisper.beam.z = -6
        crisper.glow.x = 0.04
        let variants: [(String, CRTParameters)] = [("shipped: hardness -5, glow 0.05", .consumerTV), ("crisper: hardness -6, glow 0.04", crisper)]
        let outWidth = width * scale, outHeight = height * scale
        var combined = [UInt8](repeating: 0, count: outWidth * 2 * outHeight * 4)
        for (index, (_, parameters)) in variants.enumerated() {
            let pixels = try render(
                .crt240p, fragment: "gameplayTextureFragment", device: device, library: library,
                sourceWidth: width, sourceHeight: height, outputWidth: outWidth, outputHeight: outHeight,
                sourcePixels: fixture, crt: parameters
            )
            for y in 0..<outHeight {
                let source = y * outWidth * 4, destination = (y * outWidth * 2 + index * outWidth) * 4
                combined.replaceSubrange(destination..<(destination + outWidth * 4), with: pixels[source..<(source + outWidth * 4)])
            }
        }
        let attachment = XCTAttachment(image: try XCTUnwrap(image(from: combined, width: outWidth * 2, height: outHeight)))
        attachment.name = "device-display-crt240p-sharpness-comparison (left \(variants[0].0); right \(variants[1].0))"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Accurate on a Game Boy or Pocket, with the hardware's own palette, shows BGB's measured
    /// screen after the chosen exposure and contrast: each pixel's average is its shade, in both
    /// scaling paths, and the gaps between pixels show the lighter, yellower unlit LCD.
    func testMonochromeLCDShowsTheMeasuredScreenWithLightGaps() throws {
        let (device, library) = try metal()
        let screens: [(HardwareModel, [UInt32])] = [
            (.gameBoy, [0x89b13d, 0x64a25c, 0x3e7a64, 0x2d5e58]),
            (.gameBoyPocket, [0xc9deaa, 0xa5b789, 0x717c63, 0x515953]),
        ]
        let scale = 12, width = 8, height = 2
        for (hardware, targets) in screens {
            let palette = DMGPalette.defaultValue(for: hardware)
            // Two columns of each shade, lightest first, in the palette's colors.
            let source = (0..<(width * height)).flatMap { index in bgra(palette.previewColors[0][(index % width) / 2]) }
            for fragment in ["gameplayTextureFragment", "gameplaySharpFragment"] {
                let pixels = try render(
                    .monochromeLCD, fragment: fragment, device: device, library: library,
                    sourceWidth: width, sourceHeight: height, outputWidth: width * scale, outputHeight: height * scale,
                    sourcePixels: source, monochrome: MonochromeScreen(hardware: hardware, palette: palette)
                )
                for (shade, target) in targets.enumerated() {
                    // One whole pixel, edge to edge, averaged in linear light.
                    var sum = MonochromeScreen.Color()
                    for y in 0..<scale {
                        for x in (shade * 2 * scale)..<((shade * 2 + 1) * scale) {
                            sum += color(pixels, at: pixel(x, y, width: width * scale))
                        }
                    }
                    let measured = MonochromeScreen.rgb888(sum / Double(scale * scale))
                    print("\(hardware) shade \(shade) in \(fragment): measured #\(hex(measured)), target #\(hex(target))")
                    for shift: UInt32 in [16, 8, 0] {
                        XCTAssertEqual(
                            Int((measured >> shift) & 0xff), Int((target >> shift) & 0xff), accuracy: 2,
                            "\(hardware) shade \(shade) in \(fragment): #\(hex(measured)), not #\(hex(target))"
                        )
                    }
                }
                // The gap between the two darkest pixels, and the middle of the second.
                let gap = color(pixels, at: pixel(7 * scale, scale / 2, width: width * scale))
                let dark = color(pixels, at: pixel(7 * scale + scale / 2, scale / 2, width: width * scale))
                XCTAssertGreaterThan(MonochromeScreen.luminance(gap), MonochromeScreen.luminance(dark) * 1.1, "\(hardware) gaps are lighter than a dark pixel")
                XCTAssertGreaterThan(gap.x - gap.z, dark.x - dark.z, "\(hardware) gaps are yellower than a dark pixel")
            }
        }
    }

    /// Accurate on a Game Boy and on a Pocket at a phone's scale, from one picture in each
    /// hardware's own palette, attached for review.
    func testMonochromeLCDReferenceCaptures() throws {
        let (device, library) = try metal()
        let width = 160, height = 144, scale = 7
        for hardware in [HardwareModel.gameBoy, .gameBoyPocket] {
            let palette = DMGPalette.defaultValue(for: hardware)
            var source = [UInt8]()
            for y in 0..<height {
                for x in 0..<width {
                    // Bands of the four shades, with outlined tiles and one-pixel strokes like text.
                    let band = min(x / 40, 3)
                    let tile = (x % 16 == 0 || y % 16 == 0) || ((x % 16 == 7) && y % 16 > 3 && y % 16 < 13)
                    let shade = tile ? (band < 2 ? 3 : 0) : band
                    source += bgra(palette.previewColors[0][shade])
                }
            }
            let pixels = try render(
                .monochromeLCD, fragment: "gameplayTextureFragment", device: device, library: library,
                sourceWidth: width, sourceHeight: height, outputWidth: width * scale, outputHeight: height * scale,
                sourcePixels: source, monochrome: MonochromeScreen(hardware: hardware, palette: palette)
            )
            let attachment = XCTAttachment(image: try XCTUnwrap(image(from: pixels, width: width * scale, height: height * scale)))
            attachment.name = "device-display-monochromeLCD-accurate-\(hardware.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func bgra(_ rgb: UInt32) -> [UInt8] {
        [UInt8(rgb & 0xff), UInt8((rgb >> 8) & 0xff), UInt8((rgb >> 16) & 0xff), 255]
    }

    private func hex(_ rgb: UInt32) -> String { String(format: "%06x", rgb) }

    /// A rendered pixel in linear light.
    private func color(_ pixels: [UInt8], at index: Int) -> MonochromeScreen.Color {
        let rgb = UInt32(pixels[index + 2]) << 16 | UInt32(pixels[index + 1]) << 8 | UInt32(pixels[index])
        return MonochromeScreen.linear(rgb)
    }

    private func image(from pixels: [UInt8], width: Int, height: Int) -> UIImage? {
        pixels.withUnsafeBytes { bytes -> UIImage? in
            guard let context = CGContext(
                data: UnsafeMutableRawPointer(mutating: bytes.baseAddress), width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ), let cgImage = context.makeImage() else { return nil }
            return UIImage(cgImage: cgImage)
        }
    }

    private func metal() throws -> (any MTLDevice, any MTLLibrary) {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "Display rendering requires Metal")
        return (device, try device.makeDefaultLibrary(bundle: Bundle(for: GameplayViewController.self)))
    }

    private func pixel(_ x: Int, _ y: Int, width: Int = 24) -> Int { (y * width + x) * 4 }

    private func brightness(_ pixels: [UInt8], at index: Int) -> Int {
        Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2])
    }

    /// Renders solid gray `frames`, newest first, or `sourcePixels` in each, scaled by `fragment`,
    /// with the textures and parameters MetalRenderer gives the filter.
    private func render(
        _ filter: DisplayFilter, fragment: String, device: any MTLDevice, library: any MTLLibrary,
        frames: [UInt8] = [255], weights: SIMD4<Float> = SIMD4(1, 0, 0, 0),
        sourceWidth: Int = 1, sourceHeight: Int = 1,
        outputWidth: Int = 24, outputHeight: Int = 24,
        sourcePixels: [UInt8]? = nil, crt: CRTParameters? = nil,
        monochrome: MonochromeScreen = MonochromeScreen(hardware: .gameBoy, palette: .dmgGreen)
    ) throws -> [UInt8] {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try XCTUnwrap(library.makeFunction(name: "gameplayFullscreenVertex"))
        descriptor.fragmentFunction = try XCTUnwrap(library.makeFunction(name: fragment))
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let sourceDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: sourceWidth, height: sourceHeight, mipmapped: true
        )
        sourceDescriptor.storageMode = .shared
        sourceDescriptor.usage = [.shaderRead, .pixelFormatView]
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let sources = try frames.map { gray in
            let source = try XCTUnwrap(device.makeTexture(descriptor: sourceDescriptor))
            var color = [UInt8]()
            color.reserveCapacity(sourceWidth * sourceHeight * 4)
            for _ in 0..<(sourceWidth * sourceHeight) {
                color.append(contentsOf: [gray, gray, gray, 255])
            }
            if let sourcePixels { color = sourcePixels }
            color.withUnsafeBytes {
                source.replace(
                    region: MTLRegionMake2D(0, 0, sourceWidth, sourceHeight), mipmapLevel: 0,
                    withBytes: $0.baseAddress!, bytesPerRow: sourceWidth * 4
                )
            }
            return source
        }
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: outputWidth, height: outputHeight, mipmapped: false
        )
        targetDescriptor.storageMode = .shared
        targetDescriptor.usage = .renderTarget
        let target = try XCTUnwrap(device.makeTexture(descriptor: targetDescriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        sources.forEach { blit.generateMipmaps(for: $0) }
        blit.endEncoding()
        let bound = try sources.map { source in
            filter.samplesLinearLight ? try XCTUnwrap(source.makeTextureView(pixelFormat: .bgra8Unorm_srgb)) : source
        }
        let encoder = try XCTUnwrap(commands.makeRenderCommandEncoder(descriptor: pass))
        encoder.setRenderPipelineState(pipeline)
        for slot in 0..<3 {
            encoder.setFragmentTexture(bound[slot < bound.count ? slot : 0], index: slot)
        }
        var mode = filter.shaderMode
        encoder.setFragmentBytes(&mode, length: MemoryLayout<UInt32>.size, index: 0)
        var blendWeights = weights
        encoder.setFragmentBytes(&blendWeights, length: MemoryLayout<SIMD4<Float>>.size, index: 1)
        var parameters = crt ?? filter.crtParameters ?? .none
        encoder.setFragmentBytes(&parameters, length: MemoryLayout<CRTParameters>.stride, index: 2)
        var screen = MonochromeLCDParameters(monochrome)
        encoder.setFragmentBytes(&screen, length: MemoryLayout<MonochromeLCDParameters>.stride, index: 3)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, commands.error?.localizedDescription ?? "GPU render failed")
        var pixels = [UInt8](repeating: 0, count: outputWidth * outputHeight * 4)
        pixels.withUnsafeMutableBytes {
            target.getBytes($0.baseAddress!, bytesPerRow: outputWidth * 4, from: MTLRegionMake2D(0, 0, outputWidth, outputHeight), mipmapLevel: 0)
        }
        return pixels
    }
}
