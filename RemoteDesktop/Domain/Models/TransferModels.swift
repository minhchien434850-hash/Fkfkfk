import Foundation

// MARK: - Clipboard & File-transfer domain models

/// A clipboard payload synchronized between phone and remote host.
enum ClipboardItem: Equatable, Sendable {
    case text(String)
    case image(Data)
    case file(name: String, data: Data)
}

/// Metadata for a file being transferred.
struct FileInfo: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let sizeBytes: Int64
    var sha256: String?
    init(id: UUID = UUID(), name: String, sizeBytes: Int64, sha256: String? = nil) {
        self.id = id; self.name = name; self.sizeBytes = sizeBytes; self.sha256 = sha256
    }
}

/// Direction of a transfer.
enum TransferDirection: Sendable { case upload, download }

/// Observable progress of a single transfer.
struct TransferProgress: Equatable, Sendable {
    let fileId: UUID
    var direction: TransferDirection = .upload
    var completedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var isPaused: Bool = false
    var fraction: Double { totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0 }
}
