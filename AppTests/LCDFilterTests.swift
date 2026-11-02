import EmulatorApplication
import EmulatorDomain
import Importing
import Metal
import UIKit
import XCTest
@testable import PressAny

@MainActor
final class LCDFilterTests: XCTestCase {
    func testLibraryAndQuickPlayResolveSavedFiltersWithOffAsTheDefault() throws {
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
        XCTAssertEqual(container.lcdFilter(for: context), .off)
        XCTAssertEqual(container.lcdFilter(system: .gameBoy), .off)
        let settings = container.repositories.settings
        let key = SettingKey.lcdFilter.rawValue
        try settings.set(DisplayFilter.lcd3x, key: key, scope: .app)
        try settings.set(DisplayFilter.lcd1x, key: key, scope: .system(.gameBoy))
        XCTAssertEqual(container.lcdFilter(for: context), .lcd1x)
        XCTAssertEqual(container.lcdFilter(system: .gameBoy), .lcd1x)
        XCTAssertEqual(container.lcdFilter(system: .gameBoyColor), .lcd3x)
        try settings.set(DisplayFilter.off, key: key, scope: .build(result.build.id))
        let reopened = try AppContainer(rootURL: root, plus: .fixed(ownsPlus: true))
        XCTAssertEqual(reopened.lcdFilter(for: context), .off)
        XCTAssertEqual(reopened.lcdFilter(system: .gameBoy), .lcd1x)
        try settings.setValueJSON("\"unknown-filter\"", key: key, scope: .build(result.build.id))
        XCTAssertEqual(container.lcdFilter(for: context), .off, "An unreadable filter must not block launch")
    }

    func testBothSamplingModesPreserveRawPixelsAndRenderDistinctLCDMasks() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "LCD rendering requires Metal")
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: GameplayViewController.self))
        for fragment in ["gameplayTextureFragment", "gameplaySharpFragment"] {
            let raw = try render(.off, fragment: fragment, device: device, library: library)
            XCTAssertTrue(raw.allSatisfy { $0 == 255 }, "Off must preserve the original white pixel")

            let grid = try render(.lcd1x, fragment: fragment, device: device, library: library)
            XCTAssertLessThan(grid[pixel(0, 12)], grid[pixel(12, 12)], "Monochrome LCD must darken cell edges")
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
        }
    }

    func testCRTFiltersShowVisibleStructureInBothSamplingModes() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "CRT rendering requires Metal")
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: GameplayViewController.self))
        for fragment in ["gameplayTextureFragment", "gameplaySharpFragment"] {
            let off = try render(
                .off, fragment: fragment, device: device, library: library,
                sourceWidth: 8, sourceHeight: 8
            )
            let crt240 = try render(
                .crt240p, fragment: fragment, device: device, library: library,
                sourceWidth: 8, sourceHeight: 8
            )
            let crt480 = try render(
                .gameCubeTV, fragment: fragment, device: device, library: library,
                sourceWidth: 8, sourceHeight: 8
            )

            XCTAssertNotEqual(crt240, off, "CRT 240p must visibly differ from Off")
            XCTAssertNotEqual(crt480, off, "CRT 480i must visibly differ from Off")
            XCTAssertNotEqual(crt240, crt480, "240p and 480i CRT tuning must remain distinct")

            let center240 = columnBrightness(crt240, x: 12, yRange: 5..<19)
            let center480 = columnBrightness(crt480, x: 12, yRange: 5..<19)
            XCTAssertGreaterThan(
                (center240.max() ?? 0) - (center240.min() ?? 0), 20,
                "CRT 240p must have visible scanline/beam variation"
            )
            XCTAssertGreaterThan(
                (center480.max() ?? 0) - (center480.min() ?? 0), 12,
                "CRT 480i must retain visible denser scanline/beam variation"
            )

            let center = brightestPixel(crt240, xRange: 8..<16, yRange: 8..<16)
            XCTAssertLessThan(
                brightness(crt240, at: pixel(1, 1)), center,
                "curved CRT glass must darken/feather the raster near its corners"
            )
            let maskIndex = pixel(12, 12)
            let maskChannels = [crt240[maskIndex], crt240[maskIndex + 1], crt240[maskIndex + 2]]
            XCTAssertGreaterThan(
                Int(maskChannels.max() ?? 0) - Int(maskChannels.min() ?? 0), 8,
                "CRT output must include a visible RGB phosphor mask"
            )
        }
    }

    /// Frame blending mixes the newest frame with the frames before it by the renderer's weights,
    /// in both sampling modes, and Off leaves the newest frame as it is.
    func testFrameBlendingMixesEarlierFramesByTheirWeights() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "Frame blending requires Metal")
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: GameplayViewController.self))
        // A white frame after two black ones.
        let frames: [UInt8] = [255, 0, 0]
        for fragment in ["gameplayTextureFragment", "gameplaySharpFragment"] {
            for (blending, expected) in [(FrameBlending.off, 255), (.blend, 128), (.ghosting, 128)] {
                let weights = blending.weights(heldFrames: 3).map { Float($0) }
                let pixels = try render(
                    .off, fragment: fragment, device: device, library: library,
                    frames: frames, weights: SIMD4(weights[0], weights[1], weights[2], 0)
                )
                let center = pixels[pixel(12, 12)]
                XCTAssertEqual(Int(center), expected, accuracy: 1, "\(blending) in \(fragment)")
            }
            let fading = try render(
                .off, fragment: fragment, device: device, library: library,
                frames: [0, 255, 255], weights: SIMD4(0.5, 0.3, 0.2, 0)
            )
            XCTAssertEqual(Int(fading[pixel(12, 12)]), 128, accuracy: 1, "a light that just went out leaves a trail")
        }
    }

    func testDeviceTreatmentsUseContinuousCoordinatesInBothScalingPaths() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: GameplayViewController.self))
        for filter in DisplayFilter.selectable(for: .automatic) where filter != .off {
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

    func testInterlacedCRTUsesThePreviousFieldForMovingContent() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: GameplayViewController.self))
        let even = try render(
            .gameCubeTV, fragment: "gameplayTextureFragment", device: device, library: library,
            frames: [255, 0], sourceWidth: 16, sourceHeight: 16,
            outputWidth: 160, outputHeight: 160, fieldParity: 0
        )
        let odd = try render(
            .gameCubeTV, fragment: "gameplayTextureFragment", device: device, library: library,
            frames: [255, 0], sourceWidth: 16, sourceHeight: 16,
            outputWidth: 160, outputHeight: 160, fieldParity: 1
        )
        XCTAssertNotEqual(even, odd, "moving content must alternate which raster lines retain the previous field")
        let progressiveEven = try render(.crt240p, fragment: "gameplayTextureFragment", device: device, library: library, fieldParity: 0)
        let progressiveOdd = try render(.crt240p, fragment: "gameplayTextureFragment", device: device, library: library, fieldParity: 1)
        XCTAssertEqual(progressiveEven, progressiveOdd, "240p does not alternate fields")
    }

    func testCRTGlowsBeyondAnIsolatedBrightPixelWithoutLightingTheWholeScreen() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: GameplayViewController.self))
        var pixels = [UInt8](repeating: 0, count: 9 * 9 * 4)
        for offset in stride(from: 3, to: pixels.count, by: 4) { pixels[offset] = 255 }
        let center = (4 * 9 + 4) * 4
        pixels.replaceSubrange(center..<(center + 4), with: [255, 255, 255, 255])
        let crt = try render(
            .crt240p, fragment: "gameplayTextureFragment", device: device, library: library,
            sourceWidth: 9, sourceHeight: 9, outputWidth: 180, outputHeight: 180, sourcePixels: pixels
        )
        let glow = (90 * 180 + 113) * 4
        XCTAssertGreaterThan(Int(crt[glow]) + Int(crt[glow + 1]) + Int(crt[glow + 2]), 0)
        XCTAssertEqual(Array(crt[0..<3]), [0, 0, 0])
    }

    func testCuratedDeviceReferenceCaptures() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: GameplayViewController.self))
        let width = 160, height = 144, outWidth = 640, outHeight = 576
        var fixture = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                let checker = ((x / 8 + y / 8) % 2) == 0
                fixture += [UInt8(x * 255 / (width - 1)), UInt8(y * 255 / (height - 1)), checker ? 255 : 32, 255]
            }
        }
        for filter in DisplayFilter.selectable(for: .automatic) {
            let pixels = try render(
                filter, fragment: "gameplayTextureFragment", device: device, library: library,
                sourceWidth: width, sourceHeight: height, outputWidth: outWidth, outputHeight: outHeight,
                sourcePixels: fixture
            )
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

    private func pixel(_ x: Int, _ y: Int) -> Int { (y * 24 + x) * 4 }

    private func brightness(_ pixels: [UInt8], at index: Int) -> Int {
        Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2])
    }

    private func columnBrightness(_ pixels: [UInt8], x: Int, yRange: Range<Int>) -> [Int] {
        yRange.map { brightness(pixels, at: pixel(x, $0)) }
    }

    private func brightestPixel(_ pixels: [UInt8], xRange: Range<Int>, yRange: Range<Int>) -> Int {
        yRange.flatMap { y in xRange.map { x in brightness(pixels, at: pixel(x, y)) } }.max() ?? 0
    }

    /// Renders solid gray `frames`, newest first, scaled to 24×24 by `fragment`.
    private func render(
        _ filter: DisplayFilter, fragment: String, device: any MTLDevice, library: any MTLLibrary,
        frames: [UInt8] = [255], weights: SIMD4<Float> = SIMD4(1, 0, 0, 0),
        sourceWidth: Int = 1, sourceHeight: Int = 1,
        outputWidth: Int = 24, outputHeight: Int = 24,
        sourcePixels: [UInt8]? = nil, fieldParity: UInt32 = 0
    ) throws -> [UInt8] {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try XCTUnwrap(library.makeFunction(name: "gameplayFullscreenVertex"))
        descriptor.fragmentFunction = try XCTUnwrap(library.makeFunction(name: fragment))
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let sourceDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: sourceWidth, height: sourceHeight, mipmapped: false
        )
        sourceDescriptor.storageMode = .shared
        sourceDescriptor.usage = .shaderRead
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
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(commands.makeRenderCommandEncoder(descriptor: pass))
        encoder.setRenderPipelineState(pipeline)
        for slot in 0..<3 {
            encoder.setFragmentTexture(sources[slot < sources.count ? slot : 0], index: slot)
        }
        var mode = filter.shaderMode
        encoder.setFragmentBytes(&mode, length: MemoryLayout<UInt32>.size, index: 0)
        var blendWeights = weights
        encoder.setFragmentBytes(&blendWeights, length: MemoryLayout<SIMD4<Float>>.size, index: 1)
        var parity = fieldParity
        encoder.setFragmentBytes(&parity, length: MemoryLayout<UInt32>.size, index: 2)
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
