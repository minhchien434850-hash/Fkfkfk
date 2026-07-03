import Foundation

/// Low-latency signaling channel over `URLSessionWebSocketTask`.
///
/// The relay build uses HTTP long-poll for control + JPEG preview; this
/// WebSocket client is the forward path for a real-time Desktop Agent that
/// speaks a framed binary protocol (input up, video/audio down). It exposes an
/// `AsyncStream` of inbound messages and a `send` for outbound frames.
final class WebSocketClient {
    enum Message: Sendable { case data(Data), text(String) }

    private let url: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    init(url: URL, session: URLSession = .shared) {
        self.url = url; self.session = session
    }

    func connect() -> AsyncStream<Message> {
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        return AsyncStream { continuation in
            func receive() {
                task.receive { result in
                    switch result {
                    case .failure:
                        continuation.finish()
                    case .success(let message):
                        switch message {
                        case .data(let d): continuation.yield(.data(d))
                        case .string(let s): continuation.yield(.text(s))
                        @unknown default: break
                        }
                        receive()
                    }
                }
            }
            receive()
            continuation.onTermination = { _ in task.cancel(with: .goingAway, reason: nil) }
        }
    }

    func send(_ data: Data) async throws {
        guard let task else { throw RemoteError.network("socket closed") }
        try await task.send(.data(data))
    }

    func close() { task?.cancel(with: .goingAway, reason: nil); task = nil }
}
