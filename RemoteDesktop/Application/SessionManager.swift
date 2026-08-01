import Foundation

/// Drives an active remote session: starts the frame stream, publishes the
/// latest frame + connection telemetry, and provides auto-reconnect via a
/// stall monitor (Wi-Fi ↔ 5G switching / background recovery).
@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var session: RemoteSession?
    @Published private(set) var latestFrame: VideoFrame?
    @Published private(set) var connection = ConnectionInfo()
    @Published private(set) var isActive = false

    private let connectUseCase: ConnectUseCase
    private let startStream: StartStreamUseCase
    private let streamManager: StreamManager

    private var streamTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var lastFrameAt: TimeInterval = 0
    private var framesInWindow = 0

    init(connectUseCase: ConnectUseCase, startStream: StartStreamUseCase, streamManager: StreamManager) {
        self.connectUseCase = connectUseCase
        self.startStream = startStream
        self.streamManager = streamManager
    }

    func connect(to device: Device, quality: StreamQuality) throws {
        let newSession = try connectUseCase(device: device, quality: quality)
        session = newSession
        isActive = true
        lastFrameAt = Date().timeIntervalSince1970
        startFrameConsumption(newSession)
        startMonitor()
    }

    func disconnect() {
        streamTask?.cancel(); streamTask = nil
        monitorTask?.cancel(); monitorTask = nil
        startStream.stop()
        isActive = false
        session = nil
        latestFrame = nil
    }

    private func startFrameConsumption(_ session: RemoteSession) {
        streamTask?.cancel()
        let stream = startStream(session: session)   // created on the main actor
        let processor = streamManager
        streamTask = Task { [weak self] in
            for await frame in stream {
                if Task.isCancelled { break }
                let displayable = processor.process(frame)
                await MainActor.run {
                    guard let self else { return }
                    self.latestFrame = displayable
                    self.lastFrameAt = Date().timeIntervalSince1970
                    self.framesInWindow += 1
                    self.connection.isReconnecting = false
                }
            }
        }
    }

    /// Marks the session as reconnecting if no frame arrives for a while and
    /// samples the frame-rate once per second for the HUD.
    private func startMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { break }
                await self.tickMonitor()
            }
        }
    }

    private func tickMonitor() {
        connection.frameRate = framesInWindow
        framesInWindow = 0
        let idle = Date().timeIntervalSince1970 - lastFrameAt
        connection.isReconnecting = idle > 3
    }
}
