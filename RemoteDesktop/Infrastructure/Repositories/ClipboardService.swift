import Foundation

/// Clipboard sync. Text is pushed to the remote host as keyboard `text` input
/// (works with the current relay). Image/file clipboard and read-back require a
/// Desktop Agent clipboard channel and are surfaced as clear errors.
final class ClipboardService: ClipboardServiceProtocol {
    private let input: InputServiceProtocol
    init(input: InputServiceProtocol) { self.input = input }

    func push(_ item: ClipboardItem, to deviceId: String) async throws {
        switch item {
        case .text(let string):
            try await input.send(.text(string), to: deviceId)
        case .image, .file:
            throw RemoteError.unknown("Image/file clipboard requires a Desktop Agent channel.")
        }
    }

    func pull(from deviceId: String) async throws -> ClipboardItem? {
        // Relay preview has no clipboard read-back; returns nil until the agent
        // exposes a clipboard endpoint.
        return nil
    }
}
