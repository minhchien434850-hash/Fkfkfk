import Foundation

// ======================== Model cập nhật OTA (bản đã ký) ========================
struct AppOTAUpdate: Decodable {
    let available: Bool
    let installUrl: String?
    let bundleId: String?
    let version: String?
    let build: Int?
    let title: String?
}

// ======================== Model cuộc gọi ========================
struct CallStartResult: Decodable { let callId: String }
struct IncomingCall: Decodable {
    let callId: String?
    let from: Int?
    let fromName: String?
    let video: Bool?
}
struct CallStateResult: Decodable { let state: String; let video: Bool? }
struct CallFrame: Decodable { let jpg: String; let ts: Double? }
struct CallAudioChunk: Decodable { let seq: Int; let pcm: String }
struct CallAudioResult: Decodable { let chunks: [CallAudioChunk] }

// ======================== API cuộc gọi (relay qua máy chủ) ========================
extension APIClient {
    func callStart(to: Int, video: Bool) async throws -> CallStartResult {
        try decode(try await send("/calls/start", method: "POST", json: ["to": to, "video": video]))
    }
    /// Trả về cuộc gọi đến đang đổ chuông (nil nếu không có).
    func callIncoming() async throws -> IncomingCall? {
        let c: IncomingCall = try decode(try await send("/calls/incoming"))
        guard let id = c.callId, !id.isEmpty else { return nil }
        return c
    }
    func callAnswer(_ cid: String, accept: Bool) async throws {
        _ = try await send("/calls/\(cid)/answer?accept=\(accept)", method: "POST")
    }
    func callEnd(_ cid: String) async throws {
        _ = try await send("/calls/\(cid)/end", method: "POST")
    }
    func callState(_ cid: String) async throws -> CallStateResult {
        try decode(try await send("/calls/\(cid)/state"))
    }
    func callPutFrame(_ cid: String, jpgBase64: String) async throws {
        _ = try await send("/calls/\(cid)/frame", method: "POST", json: ["jpg": jpgBase64])
    }
    func callGetFrame(_ cid: String) async throws -> CallFrame {
        try decode(try await send("/calls/\(cid)/frame"))
    }
    func callPutAudio(_ cid: String, pcmBase64: String) async throws {
        _ = try await send("/calls/\(cid)/audio", method: "POST", json: ["pcm": pcmBase64])
    }
    func callGetAudio(_ cid: String, after: Int) async throws -> CallAudioResult {
        try decode(try await send("/calls/\(cid)/audio?after=\(after)"))
    }
}
