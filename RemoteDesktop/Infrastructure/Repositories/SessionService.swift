import Foundation

/// Implements both `SessionServiceProtocol` (frames) and `InputServiceProtocol`
/// (commands) over the relay `/pc/screen/{id}` and `/pc/send` endpoints.
final class SessionService: SessionServiceProtocol, InputServiceProtocol {
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func fetchFrame(deviceId: String) async throws -> VideoFrame? {
        let dto: ScreenDTO = try await api.get(Endpoints.screen(deviceId), auth: true)
        guard !dto.jpg.isEmpty, let data = Data(base64Encoded: dto.jpg) else { return nil }
        return VideoFrame(data: data, timestamp: TimeInterval(dto.ts), width: 0, height: 0)
    }

    func send(_ input: RemoteInput, to deviceId: String) async throws {
        let _: APIEmpty = try await api.post(
            Endpoints.sendInput, body: ["agent_id": deviceId, "cmd": input.payload], auth: true)
    }
}
