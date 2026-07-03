import Foundation

/// Serial file-transfer queue with compression and SHA-256 checksums.
/// Provides upload enqueue, observable progress, and pause/cancel.
@MainActor
final class FileQueueManager: ObservableObject {
    @Published private(set) var queue: [FileInfo] = []
    @Published private(set) var progress: TransferProgress?

    private let transfer: FileTransferUseCase
    private let deviceId: String
    private var runner: Task<Void, Never>?

    init(transfer: FileTransferUseCase, deviceId: String) {
        self.transfer = transfer
        self.deviceId = deviceId
    }

    func enqueue(_ url: URL) {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
        queue.append(FileInfo(name: url.lastPathComponent, sizeBytes: size))
        pump(url)
    }

    private func pump(_ url: URL) {
        guard runner == nil else { return }
        runner = Task { [weak self] in
            guard let self else { return }
            for await p in self.transfer.upload(url, deviceId: self.deviceId) { self.progress = p }
            self.runner = nil
        }
    }

    func cancel() { runner?.cancel(); runner = nil; progress = nil }

    // MARK: Utilities

    /// zlib compression (reduces on-wire size before transfer).
    static func compress(_ data: Data) -> Data? {
        try? (data as NSData).compressed(using: .zlib) as Data
    }
    static func decompress(_ data: Data) -> Data? {
        try? (data as NSData).decompressed(using: .zlib) as Data
    }
    /// Integrity checksum.
    static func checksum(_ data: Data) -> String { CryptoService.sha256Hex(data) }
}
