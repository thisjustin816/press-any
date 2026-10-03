import EmulationCore
import MetalKit

@MainActor
final class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var texture: MTLTexture?
    private var textureSize = (width: 0, height: 0)
    private var sourceAspect: Double = 160.0 / 144.0

    init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "gameplayFullscreenVertex"),
              let fragment = library.makeFunction(name: "gameplayTextureFragment") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }

        self.device = device
        self.commandQueue = queue
        self.pipeline = pipeline
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
        ensureTexture(width: frame.width, height: frame.height)
        guard let texture else { return }
        sourceAspect = Double(frame.width) / Double(max(frame.height, 1))

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
        guard let texture,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }

        let viewport = aspectFitViewport(drawableSize: view.drawableSize)
        encoder.setViewport(viewport)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func ensureTexture(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        guard texture == nil || textureSize.width != width || textureSize.height != height else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        texture = device.makeTexture(descriptor: descriptor)
        textureSize = (width, height)
    }

    private func aspectFitViewport(drawableSize: CGSize) -> MTLViewport {
        let width = max(Double(drawableSize.width), 1)
        let height = max(Double(drawableSize.height), 1)
        let destinationAspect = width / height

        if destinationAspect > sourceAspect {
            let fittedWidth = height * sourceAspect
            return MTLViewport(
                originX: (width - fittedWidth) / 2,
                originY: 0,
                width: fittedWidth,
                height: height,
                znear: 0,
                zfar: 1
            )
        }

        let fittedHeight = width / sourceAspect
        return MTLViewport(
            originX: 0,
            originY: (height - fittedHeight) / 2,
            width: width,
            height: fittedHeight,
            znear: 0,
            zfar: 1
        )
    }
}
