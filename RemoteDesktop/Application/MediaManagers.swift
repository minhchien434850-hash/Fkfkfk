import Foundation

/// Clipboard synchronization coordinator.
@MainActor
final class ClipboardManager: ObservableObject {
    @Published var errorMessage: String?
    private let useCase: ClipboardUseCase
    init(useCase: ClipboardUseCase) { self.useCase = useCase }

    func syncText(_ text: String, deviceId: String) async {
        do { try await useCase.push(.text(text), deviceId: deviceId) }
        catch { errorMessage = (error as? RemoteError)?.errorDescription }
    }
}

/// File-transfer coordinator with observable progress.
@MainActor
final class FileTransferManager: ObservableObject {
    @Published private(set) var progress: TransferProgress?
    private let useCase: FileTransferUseCase
    private var task: Task<Void, Never>?
    init(useCase: FileTransferUseCase) { self.useCase = useCase }

    func upload(_ url: URL, deviceId: String) {
        task?.cancel()
        task = Task {
            for await p in useCase.upload(url, deviceId: deviceId) { self.progress = p }
        }
    }
    func cancel() { task?.cancel(); progress = nil }
}

/// Two-way audio coordinator.
@MainActor
final class AudioManager: ObservableObject {
    @Published private(set) var isOn = false
    @Published var errorMessage: String?
    private let useCase: AudioStreamUseCase
    init(useCase: AudioStreamUseCase) { self.useCase = useCase }

    func toggle(deviceId: String) {
        if isOn { useCase.stop(); isOn = false; return }
        do { try useCase.start(deviceId: deviceId); isOn = useCase.isRunning }
        catch { errorMessage = (error as? RemoteError)?.errorDescription ?? error.localizedDescription }
    }
}
