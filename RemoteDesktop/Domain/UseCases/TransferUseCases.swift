import Foundation

// MARK: - Clipboard / file / audio use cases

struct ClipboardUseCase {
    private let service: ClipboardServiceProtocol
    init(service: ClipboardServiceProtocol) { self.service = service }
    func push(_ item: ClipboardItem, deviceId: String) async throws {
        try await service.push(item, to: deviceId)
    }
    func pull(deviceId: String) async throws -> ClipboardItem? {
        try await service.pull(from: deviceId)
    }
}

struct FileTransferUseCase {
    private let service: FileTransferServiceProtocol
    init(service: FileTransferServiceProtocol) { self.service = service }
    func upload(_ url: URL, deviceId: String) -> AsyncStream<TransferProgress> {
        service.upload(url, to: deviceId)
    }
    func download(_ name: String, deviceId: String) -> AsyncStream<TransferProgress> {
        service.download(name, from: deviceId)
    }
}

struct AudioStreamUseCase {
    private let service: AudioServiceProtocol
    init(service: AudioServiceProtocol) { self.service = service }
    func start(deviceId: String) throws { try service.startTwoWayAudio(deviceId: deviceId) }
    func stop() { service.stop() }
    var isRunning: Bool { service.isRunning }
}
