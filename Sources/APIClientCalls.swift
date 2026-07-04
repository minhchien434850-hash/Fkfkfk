import Foundation

// ======================== Model thông báo qua email ========================
struct EmailNotifyStatus: Decodable {
    let enabled: Bool
    let hasRelay: Bool?
    let smtpHost: String?
    let smtpPort: Int?
    let smtpUser: String?
    let mailFrom: String?
    let smtpPassSet: Bool?
    let testResult: String?
    let testOk: Bool?
}

// ======================== Model bot Telegram hỗ trợ ========================
struct TelegramBotStatus: Decodable {
    let enabled: Bool
    let hasToken: Bool?
    let adminChat: String?
    let welcome: String?
    let about: String?
    let username: String?
    let tokenOk: Bool?
    // Quản lý nhóm
    let modEnabled: Bool?
    let delLinks: Bool?
    let delStickers: Bool?
    let delPhotos: Bool?
    let warnLimit: Int?
    let warnAction: String?
    let welcomeOn: Bool?
    let welcomeGroup: String?
    let welcomeBtnText: String?
    let welcomeBtnUrl: String?
    let goodbyeOn: Bool?
    let goodbye: String?
}

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
    func callHistory() async throws -> [CallHistoryItem] {
        try decode(try await send("/calls/history"))
    }
}

// ======================== Model lịch sử cuộc gọi ========================
struct CallHistoryItem: Decodable, Identifiable {
    let id: Int
    let incoming: Bool
    let peerId: Int
    let peer: String
    let video: Bool
    let status: String       // answered / missed / declined
    let missed: Bool         // incoming + (missed/declined) = cuộc gọi nhỡ
    let startedAt: Int
    let duration: Int
}
