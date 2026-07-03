import Foundation

/// Loads and maintains the list of controllable devices.
@MainActor
final class DeviceManager: ObservableObject {
    @Published private(set) var devices: [Device] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let discover: DiscoverDevicesUseCase
    private let repository: DeviceRepositoryProtocol

    init(discover: DiscoverDevicesUseCase, repository: DeviceRepositoryProtocol) {
        self.discover = discover
        self.repository = repository
    }

    func refresh() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do { devices = try await discover() }
        catch { errorMessage = (error as? RemoteError)?.errorDescription ?? error.localizedDescription }
    }

    func remove(_ device: Device) async {
        try? await repository.remove(deviceId: device.id)
        await refresh()
    }
}
