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
        let standard = GameplayPresetValues.standard(for: .gameBoy).displayFilter
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

    func testBothCRTsCurveThePictureAndTheSuperGameBoyMoreThanTheGameBoyPlayer() throws {
        XCTAssertGreaterThan(CRTParameters.lateModelTV.curvature.x, 0)
        XCTAssertGreaterThan(CRTParameters.lateModelTV.curvature.y, 0)
        XCTAssertLessThan(CRTParameters.lateModelTV.curvature.x, CRTParameters.consumerTV.curvature.x)
        XCTAssertLessThan(CRTParameters.lateModelTV.curvature.y, CRTParameters.consumerTV.curvature.y)
        XCTAssertLessThan(CRTParameters.lateModelTV.maskPitch, CRTParameters.consumerTV.maskPitch)
        XCTAssertGreaterThan(CRTParameters.lateModelTV.maskPitch, 0)
        XCTAssertEqual(CRTParameters.consumerTV.linesPerSourceLine, 1)
        XCTAssertEqual(CRTParameters.lateModelTV.linesPerSourceLine, 2)
        XCTAssertEqual(CRTParameters.scanlines.curvature, .zero)
        XCTAssertEqual(CRTParameters.scanlines.maskPitch, 0)

        // Measured on the picture: how far the raster's top edge bows down at a quarter of the
        // width, away from the rounded corners, compared with its middle.
        let (device, library) = try metal()
        func bow(_ filter: DisplayFilter) throws -> Int {
            let pixels = try render(
                filter, fragment: "gameplayTextureFragment", device: device, library: library,
                frames: [255], sourceWidth: 160, sourceHeight: 144, outputWidth: 320, outputHeight: 288
            )
            func firstLitRow(_ x: Int) -> Int {
                (0..<288).first { brightness(pixels, at: pixel(x, $0, width: 320)) > 60 } ?? 288
            }
            return firstLitRow(40) - firstLitRow(160)
        }
        let consumer = try bow(.crt240p)
        let lateModel = try bow(.crt480p)
        XCTAssertGreaterThanOrEqual(consumer, 7, "CRT 240p is clearly curved")
        XCTAssertGreaterThanOrEqual(lateModel, 2, "CRT 480p is gently curved")
        XCTAssertLessThan(lateModel, consumer, "CRT 480p is flatter than CRT 240p")
        XCTAssertEqual(try bow(.scanlines), 0, "Scanlines are flat")
    }

    func testCRTRastersAndMasksDifferInDensity() throws {
        let (device, library) = try metal()
        // Mid-gray stays below clipping, so the mask and beam show in full.
        func picture(_ filter: DisplayFilter) throws -> [UInt8] {
            try render(
                filter, fragment: "gameplayTextureFragment", device: device, library: library,
                frames: [96], sourceWidth: 32, sourceHeight: 32, outputWidth: 192, outputHeight: 192
            )
        }
        // Scanlines: brightness along a column through the middle, over four source lines.
        func ripple(_ pixels: [UInt8]) -> (depth: Int, peaks: Int) {
            let column = (84..<108).map { brightness(pixels, at: pixel(96, $0, width: 192)) }
            let peaks = (1..<(column.count - 1)).filter { column[$0] > column[$0 - 1] && column[$0] >= column[$0 + 1] }
            return ((column.max() ?? 0) - (column.min() ?? 0), peaks.count)
        }
        // The mask: the spacing between the starts of red-dominant runs along a middle row.
        func maskPitch(_ pixels: [UInt8]) -> Double {
            let reds = (0..<192).map { x -> Bool in
                let index = pixel(x, 96, width: 192)
                return Int(pixels[index + 2]) > Int(pixels[index + 1]) + 4
            }
            let starts = (1..<reds.count).filter { reds[$0] && !reds[$0 - 1] }
            guard starts.count > 2, let first = starts.first, let last = starts.last else { return 0 }
            return Double(last - first) / Double(starts.count - 1)
        }
        let consumer = try picture(.crt240p), lateModel = try picture(.crt480p), lines = try picture(.scanlines)
        let consumerRipple = ripple(consumer), lateRipple = ripple(lateModel), linesRipple = ripple(lines)
        XCTAssertGreaterThan(consumerRipple.depth, 40, "CRT 240p shows dark gaps between lines")
        XCTAssertGreaterThan(lateRipple.depth, 8, "CRT 480p still shows its finer lines")
        XCTAssertLessThan(lateRipple.depth, consumerRipple.depth)
        XCTAssertGreaterThan(lateRipple.peaks, consumerRipple.peaks, "CRT 480p draws more lines over the same source lines")
        XCTAssertGreaterThan(linesRipple.depth, 40)

        let consumerPitch = maskPitch(consumer), latePitch = maskPitch(lateModel)
        XCTAssertEqual(consumerPitch, Double(CRTParameters.consumerTV.maskPitch), accuracy: 0.5)
        XCTAssertEqual(latePitch, Double(CRTParameters.lateModelTV.maskPitch), accuracy: 0.5)
        XCTAssertEqual(maskPitch(lines), 0, "Scanlines have no mask")
    }

    func testCRTCornersAreBlackAndRounded() throws {
        let (device, library) = try metal()
        for filter in [DisplayFilter.crt240p, .crt480p] {
            let pixels = try render(
                filter, fragment: "gameplayTextureFragment", device: device, library: library,
                frames: [255], sourceWidth: 160, sourceHeight: 144, outputWidth: 320, outputHeight: 288
            )
            for (x, y) in [(0, 0), (319, 0), (0, 287), (319, 287), (2, 2)] {
                XCTAssertEqual(brightness(pixels, at: pixel(x, y, width: 320)), 0, "\(filter) corner \(x),\(y)")
            }
            XCTAssertGreaterThan(brightness(pixels, at: pixel(160, 144, width: 320)), 300)
            XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 })
        }
    }

    func testCRTGlowsBeyondABrightPixelAndReducedWorkDropsTheGlow() throws {
        let (device, library) = try metal()
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        for offset in stride(from: 3, to: pixels.count, by: 4) { pixels[offset] = 255 }
        let center = (4 * 8 + 4) * 4
        pixels.replaceSubrange(center..<(center + 4), with: [255, 255, 255, 255])
        func crt(_ parameters: CRTParameters) throws -> [UInt8] {
            try render(
                .crt240p, fragment: "gameplayTextureFragment", device: device, library: library,
                sourceWidth: 8, sourceHeight: 8, outputWidth: 160, outputHeight: 160, sourcePixels: pixels, crt: parameters
            )
        }
        let glowing = try crt(.consumerTV)
        let reduced = try crt(CRTParameters.consumerTV.withoutGlow)
        // A source pixel and a half right of the bright one, where the beam has no light left.
        let beside = pixel(120, 90, width: 160)
        XCTAssertGreaterThan(brightness(glowing, at: beside), brightness(reduced, at: beside) + 3, "glow reaches beside the pixel")
        XCTAssertEqual(brightness(reduced, at: beside), 0, "without glow the dark stays dark")
        XCTAssertEqual(Array(glowing[0..<3]), [0, 0, 0])
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
            let image = pixels.withUnsafeBytes { bytes -> UIImage? in
                guard let context = CGContext(
                    data: UnsafeMutableRawPointer(mutating: bytes.baseAddress), width: outWidth, height: outHeight,
                    bitsPerComponent: 8, bytesPerRow: outWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                ), let cgImage = context.makeImage() else { return nil }
                return UIImage(cgImage: cgImage)
            }
            let attachment = XCTAttachment(image: try XCTUnwrap(image))
            attachment.name = "device-display-\(filter.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
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
        sourcePixels: [UInt8]? = nil, crt: CRTParameters? = nil
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
