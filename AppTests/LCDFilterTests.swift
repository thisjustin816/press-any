import EmulatorApplication
import EmulatorDomain
import Importing
import Metal
import XCTest
@testable import PressAny

@MainActor
final class LCDFilterTests: XCTestCase {
    func testLibraryAndQuickPlayResolveSavedFiltersWithOffAsTheDefault() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
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
        try settings.set(LCDFilter.lcd3x, key: key, scope: .app)
        try settings.set(LCDFilter.lcd1x, key: key, scope: .system(.gameBoy))
        XCTAssertEqual(container.lcdFilter(for: context), .lcd1x)
        XCTAssertEqual(container.lcdFilter(system: .gameBoy), .lcd1x)
        XCTAssertEqual(container.lcdFilter(system: .gameBoyColor), .lcd3x)
        try settings.set(LCDFilter.off, key: key, scope: .build(result.build.id))
        let reopened = try AppContainer(rootURL: root)
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
            XCTAssertLessThan(grid[pixel(0, 12)], grid[pixel(12, 12)], "LCD 1× must darken cell edges")
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

    private func pixel(_ x: Int, _ y: Int) -> Int { (y * 24 + x) * 4 }

    private func render(
        _ filter: LCDFilter, fragment: String, device: any MTLDevice, library: any MTLLibrary
    ) throws -> [UInt8] {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try XCTUnwrap(library.makeFunction(name: "gameplayFullscreenVertex"))
        descriptor.fragmentFunction = try XCTUnwrap(library.makeFunction(name: fragment))
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let sourceDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false
        )
        sourceDescriptor.storageMode = .shared
        sourceDescriptor.usage = .shaderRead
        let source = try XCTUnwrap(device.makeTexture(descriptor: sourceDescriptor))
        let white: [UInt8] = [255, 255, 255, 255]
        white.withUnsafeBytes {
            source.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 4)
        }
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 24, height: 24, mipmapped: false
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
        encoder.setFragmentTexture(source, index: 0)
        var mode = filter.shaderMode
        encoder.setFragmentBytes(&mode, length: MemoryLayout<UInt32>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, commands.error?.localizedDescription ?? "GPU render failed")
        var pixels = [UInt8](repeating: 0, count: 24 * 24 * 4)
        pixels.withUnsafeMutableBytes {
            target.getBytes($0.baseAddress!, bytesPerRow: 24 * 4, from: MTLRegionMake2D(0, 0, 24, 24), mipmapLevel: 0)
        }
        return pixels
    }
}
