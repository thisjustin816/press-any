import EmulationCore
import EmulatorDomain
import GameplayInput
import MetalKit

@MainActor
final class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    /// Nearest sampling, for integer scaling.
    private let nearestPipeline: MTLRenderPipelineState
    /// Edge-smoothed sampling, for fill.
    private let sharpPipeline: MTLRenderPipelineState
    /// The newest frames, oldest overwritten first, so frame blending can mix earlier ones in.
    private var textures: [MTLTexture] = []
    private var newest = 0
    /// How many of `textures` hold a frame of the current size.
    private var heldFrames = 0
    private var textureSize = (width: 0, height: 0)
    private var sourceSize = (width: 160.0, height: 144.0)
    /// Where the controller layout puts the game picture, in the view's points. Nil fills the view.
    var screenRect: CGRect?
    var scaling: ScreenScaling = .integer
    var lcdFilter: LCDFilter = .off
    var frameBlending: FrameBlending = .off

    init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "gameplayFullscreenVertex") else {
            return nil
        }
        func pipeline(_ fragmentName: String) -> MTLRenderPipelineState? {
            guard let fragment = library.makeFunction(name: fragmentName) else { return nil }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        guard let nearest = pipeline("gameplayTextureFragment"), let sharp = pipeline("gameplaySharpFragment") else {
            return nil
        }

        self.device = device
        self.commandQueue = queue
        self.nearestPipeline = nearest
        self.sharpPipeline = sharp
        super.init()

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.delegate = self
    }

    func submit(_ frame: EmulatorVideoFrame, to view: MTKView) {
        ensureTextures(width: frame.width, height: frame.height)
        guard !textures.isEmpty else { return }
        newest = (newest + 1) % textures.count
        heldFrames = min(heldFrames + 1, textures.count)
        let texture = textures[newest]
        sourceSize = (Double(frame.width), Double(max(frame.height, 1)))

        frame.bgra8888.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, frame.width, frame.height),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: frame.width * 4
            )
        }
        view.setNeedsDisplay()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard !textures.isEmpty,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }

        let pixelsPerPoint = view.bounds.width > 0 ? view.drawableSize.width / view.bounds.width : 1
        let target = screenRect.map {
            CGRect(
                x: $0.minX * pixelsPerPoint,
                y: $0.minY * pixelsPerPoint,
                width: $0.width * pixelsPerPoint,
                height: $0.height * pixelsPerPoint
            )
        } ?? CGRect(origin: .zero, size: view.drawableSize)
        // The target is already in device pixels.
        let picture = scaling.picture(
            sourceWidth: sourceSize.width,
            sourceHeight: sourceSize.height,
            in: TouchRect(x: target.minX, y: target.minY, width: target.width, height: target.height),
            pixelsPerPoint: 1
        )
        encoder.setViewport(MTLViewport(
            originX: picture.x,
            originY: picture.y,
            width: picture.width,
            height: picture.height,
            znear: 0,
            zfar: 1
        ))
        encoder.setRenderPipelineState(scaling == .integer ? nearestPipeline : sharpPipeline)
        // The newest frame first. An unused slot repeats the newest, with no weight.
        let weights = frameBlending.weights(heldFrames: heldFrames)
        for age in 0..<textures.count {
            let texture = weights[age] > 0 ? textures[(newest - age + textures.count) % textures.count] : textures[newest]
            encoder.setFragmentTexture(texture, index: age)
        }
        var filter = lcdFilter.shaderMode
        encoder.setFragmentBytes(&filter, length: MemoryLayout<UInt32>.size, index: 0)
        var blendWeights = SIMD4<Float>(Float(weights[0]), Float(weights[1]), Float(weights[2]), 0)
        encoder.setFragmentBytes(&blendWeights, length: MemoryLayout<SIMD4<Float>>.size, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// A new size, as when a Game Boy Color game switches the picture, starts the history over.
    private func ensureTextures(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        guard textures.isEmpty || textureSize.width != width || textureSize.height != height else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        let made = (0..<3).compactMap { _ in device.makeTexture(descriptor: descriptor) }
        textures = made.count == 3 ? made : []
        newest = 0
        heldFrames = 0
        textureSize = (width, height)
    }
}

extension LCDFilter {
    var shaderMode: UInt32 {
        switch self {
        case .off: 0
        case .lcd1x: 1
        case .lcd3x: 3
        }
    }
}
