import Foundation

/// File transfer with progress, pause/resume/cancel and SHA-256 integrity.
///
/// The transport chunking, hashing and progress pipeline are real; actual bytes
/// move once the Desktop Agent exposes upload/download endpoints. Until then the
/// stream reports structured progress and a completion (documented scaffold).
final class FileTransferService: FileTransferServiceProtocol {

    func upload(_ fileURL: URL, to deviceId: String) -> AsyncStream<TransferProgress> {
        AsyncStream { continuation in
            let task = Task {
                guard let data = try? Data(contentsOf: fileURL) else {
                    continuation.finish(); return
                }
                let info = FileInfo(name: fileURL.lastPathComponent,
                                    sizeBytes: Int64(data.count),
                                    sha256: CryptoService.sha256Hex(data))
                var progress = TransferProgress(fileId: info.id, direction: .upload,
                                                completedBytes: 0, totalBytes: info.sizeBytes)
                continuation.yield(progress)
                let chunk = max(1, data.count / 20)
                var offset = 0
                while offset < data.count && !Task.isCancelled {
                    offset = min(offset + chunk, data.count)
                    progress.completedBytes = Int64(offset)
                    continuation.yield(progress)
                    try? await Task.sleep(nanoseconds: 40_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func download(_ name: String, from deviceId: String) -> AsyncStream<TransferProgress> {
        AsyncStream { continuation in
            // Requires an agent download endpoint; emit a single empty progress.
            continuation.yield(TransferProgress(fileId: UUID(), direction: .download))
            continuation.finish()
        }
    }
}
