import Foundation

/// Owns the decode → render stage of the pipeline. The relay build shows JPEG
/// frames directly, but every frame still passes through the decoder so the
/// native VideoToolbox/Metal path is a drop-in replacement.
/// `@unchecked Sendable`: instances are only touched from a single stream task.
final class StreamManager: @unchecked Sendable {
    private let decoder: VideoDecoderProtocol
    private let renderer: RendererProtocol

    init(decoder: VideoDecoderProtocol, renderer: RendererProtocol) {
        self.decoder = decoder
        self.renderer = renderer
    }

    /// Process one inbound frame; returns the display-ready frame.
    @discardableResult
    func process(_ frame: VideoFrame) -> VideoFrame {
        let displayable = (try? decoder.decode(frame)) ?? frame
        renderer.render(displayable)
        return displayable
    }
}
