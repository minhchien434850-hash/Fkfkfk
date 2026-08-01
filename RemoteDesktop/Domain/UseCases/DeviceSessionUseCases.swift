import Foundation

// MARK: - Device & session use cases

/// Returns the list of devices the user can control.
struct DiscoverDevicesUseCase {
    private let repo: DeviceRepositoryProtocol
    init(repo: DeviceRepositoryProtocol) { self.repo = repo }
    func callAsFunction() async throws -> [Device] { try await repo.discover() }
}

/// Validates that a device is online and creates a `RemoteSession`.
struct ConnectUseCase {
    func callAsFunction(device: Device, quality: StreamQuality) throws -> RemoteSession {
        guard device.isOnline else { throw RemoteError.offline }
        return RemoteSession(id: UUID(), device: device, quality: quality, startedAt: Date())
    }
}

/// Provides the frame stream for a session (streaming service abstraction).
struct StartStreamUseCase {
    private let stream: StreamServiceProtocol
    init(stream: StreamServiceProtocol) { self.stream = stream }
    func callAsFunction(session: RemoteSession) -> AsyncStream<VideoFrame> {
        stream.frames(for: session.device.id)
    }
    func stop() { stream.stop() }
}

/// Sends a normalized input command to the active session's device.
struct SendInputUseCase {
    private let input: InputServiceProtocol
    init(input: InputServiceProtocol) { self.input = input }
    func callAsFunction(_ event: RemoteInput, deviceId: String) async throws {
        try await input.send(event, to: deviceId)
    }
}
