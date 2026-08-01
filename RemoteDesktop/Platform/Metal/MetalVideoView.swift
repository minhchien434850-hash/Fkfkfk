import SwiftUI
import MetalKit

/// SwiftUI bridge that hosts the `MetalRenderer`'s `MTKView` for the native
/// decode→render path (60 FPS, GPU-accelerated).
struct MetalVideoView: UIViewRepresentable {
    let renderer: MetalRenderer
    func makeUIView(context: Context) -> MTKView { renderer.view }
    func updateUIView(_ uiView: MTKView, context: Context) {}
}
