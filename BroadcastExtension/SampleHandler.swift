import ReplayKit
import UIKit
import CoreImage
import CoreMedia

// ============================================================================
//  KENIOS — Broadcast Upload Extension: chia sẻ TOÀN BỘ màn hình máy (mọi app)
//  trong lúc gọi video. Đọc cuộc gọi đang diễn ra từ App Group (app chính ghi),
//  rồi đẩy khung hình màn hình lên máy chủ qua cùng kênh relay của cuộc gọi.
// ============================================================================
class SampleHandler: RPBroadcastSampleHandler {
    private let ctx = CIContext(options: [.useSoftwareRenderer: false])
    private var lastUpload = Date.distantPast
    private let interval: TimeInterval = 0.22    // ~4–5 khung/giây (nhẹ RAM cho extension)
    private var callId = ""
    private var token = ""
    private var base = ""

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let ud = UserDefaults(suiteName: "group.com.kenios.codebox")
        callId = ud?.string(forKey: "call_id") ?? ""
        token = ud?.string(forKey: "token") ?? ""
        base = ud?.string(forKey: "base") ?? ""
        if callId.isEmpty || base.isEmpty {
            finishBroadcastWithError(NSError(
                domain: "KENIOS", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Chưa có cuộc gọi video. Hãy gọi video trước rồi mới chia sẻ màn hình."]))
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, !callId.isEmpty else { return }
        let now = Date()
        guard now.timeIntervalSince(lastUpload) >= interval else { return }
        lastUpload = now
        autoreleasepool {
            guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            var ci = CIImage(cvPixelBuffer: pb)
            let w = ci.extent.width
            let scale = min(1.0, 480.0 / max(1.0, w))
            if scale < 1.0 { ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
            guard let cg = ctx.createCGImage(ci, from: ci.extent),
                  let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.35) else { return }
            upload(data)
        }
    }

    private func upload(_ jpeg: Data) {
        guard let url = URL(string: base + "/calls/\(callId)/frame") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["jpg": jpeg.base64EncodedString()])
        URLSession.shared.dataTask(with: req).resume()
    }
}
