import Foundation

/// `StreamServiceProtocol` implementation.
/// Real path: pulls JPEG preview frames from the relay at a fixed cadence and
/// publishes them as an `AsyncStream`. The `VideoDecoder`/`Renderer` pipeline
/// (VideoToolbox + Metal) plugs in here for a true H.264/H.265 Desktop Agent.
final class StreamService: StreamServiceProtocol {
    private let session: SessionServiceProtocol
    private let interval: TimeInterval
    private var task: Task<Void, Never>?

    init(session: SessionServiceProtocol, interval: TimeInterval = AppConfig.screenPollInterval) {
        self.session = session
        self.interval = interval
    }

    func frames(for deviceId: String) -> AsyncStream<VideoFrame> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    if let frame = try? await session.fetchFrame(deviceId: deviceId) {
                        continuation.yield(frame)
                    }
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                }
                continuation.finish()
            }
            self.task = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop() { task?.cancel(); task = nil }
}
