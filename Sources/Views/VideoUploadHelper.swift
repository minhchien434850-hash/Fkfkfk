import Foundation
import AVFoundation

// ======================== Nén video trước khi tải lên ========================
// Vì sao cần: video quay từ máy thường là 4K/HEVC nặng vài trăm MB. Tải nguyên
// bản lên rất lâu ("xử lý lâu") và khi phát lại giật vì máy phải giải mã HEVC +
// tải cả file. Nén về H.264 1080p (moov atom đưa lên đầu) giúp:
//   • Tải lên NHANH  — dung lượng giảm 5–10 lần.
//   • Phát MƯỢT     — H.264 mọi máy giải mã tốt, phát ngay khi vừa tải (stream),
//                      tua nhanh không cần tải hết.
// Có lỗi nén ⇒ trả lại URL gốc để vẫn đăng được (không bao giờ chặn người dùng).
enum VideoUploadHelper {

    /// Nén video ở `src` thành H.264 MP4 tối ưu cho mạng. Trả về URL file tạm đã nén
    /// (hoặc URL gốc nếu không nén được / không cần nén).
    static func compressForUpload(_ src: URL) async -> URL {
        let asset = AVURLAsset(url: src, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        // Nếu file đã nhỏ sẵn (≤ 12MB) thì bỏ qua nén cho nhanh — tải thẳng.
        if let sz = try? FileManager.default.attributesOfItem(atPath: src.path)[.size] as? Int,
           sz > 0, sz <= 12 * 1024 * 1024 {
            return src
        }

        // Ưu tiên 1080p (nét đẹp); không hỗ trợ thì hạ 720p → chất lượng trung bình.
        let compatible = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let preset: String = compatible.contains(AVAssetExportPreset1920x1080)
            ? AVAssetExportPreset1920x1080
            : (compatible.contains(AVAssetExportPreset1280x720)
               ? AVAssetExportPreset1280x720
               : (compatible.contains(AVAssetExportPresetMediumQuality)
                  ? AVAssetExportPresetMediumQuality
                  : AVAssetExportPresetPassthrough))

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            return src
        }
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent("kenios_up_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: dst)
        session.outputURL = dst
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true   // moov atom lên đầu → phát/tua ngay khi đang tải

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { c.resume() }
        }

        if session.status == .completed,
           FileManager.default.fileExists(atPath: dst.path),
           let sz = try? FileManager.default.attributesOfItem(atPath: dst.path)[.size] as? Int,
           sz > 0 {
            return dst
        }
        // Nén thất bại → dùng bản gốc để vẫn đăng được.
        return src
    }
}
