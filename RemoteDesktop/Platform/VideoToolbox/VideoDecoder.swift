import Foundation
import VideoToolbox
import CoreMedia

/// Hardware video decoder abstraction.
///
/// Relay path: preview frames arrive as JPEG (already displayable) so `decode`
/// is a pass-through. Native path: create a `VTDecompressionSession` configured
/// for H.264/H.265 (and AV1 where the device supports it) to decode compressed
/// NAL units into `CVPixelBuffer`s for the Metal renderer.
final class VideoToolboxDecoder: VideoDecoderProtocol {

    /// Returns true when the device advertises hardware AV1 decoding.
    static var supportsAV1: Bool {
        if #available(iOS 16.0, *) {
            return VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        }
        return false
    }

    func decode(_ frame: VideoFrame) throws -> VideoFrame {
        // JPEG preview is display-ready. For a compressed Desktop Agent stream,
        // feed CMSampleBuffers into a VTDecompressionSession here and emit the
        // decoded pixel buffer wrapped in `VideoFrame`.
        return frame
    }
}
