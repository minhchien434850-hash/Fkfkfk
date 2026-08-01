import Foundation
import MetalKit

/// Metal-backed renderer target (`MTKView`) for low-latency, GPU-accelerated
/// presentation at 60 FPS with triple buffering.
///
/// This scaffold sets up the device, command queue and view. A full pipeline
/// uploads decoded pixel buffers to a texture and draws them each frame; the
/// relay build shows JPEG frames directly in SwiftUI (`Image`), so this class
/// is the plug-in point for the native decode→render path.
final class MetalRenderer: NSObject, RendererProtocol, MTKViewDelegate {
    let view: MTKView
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private var latest: VideoFrame?

    override init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        self.commandQueue = device?.makeCommandQueue()
        self.view = MTKView(frame: .zero, device: device)
        super.init()
        view.framebufferOnly = false
        view.preferredFramesPerSecond = AppConfig.targetFrameRate
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.delegate = self
    }

    func render(_ frame: VideoFrame) { latest = frame }

    // MARK: MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let buffer = commandQueue?.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        // A full renderer would bind the decoded texture + draw a quad here.
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
