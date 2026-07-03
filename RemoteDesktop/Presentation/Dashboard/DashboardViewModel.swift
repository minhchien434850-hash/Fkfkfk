import Foundation
import Combine

/// View model for the device dashboard. Forwards `DeviceManager` changes so the
/// View binds only to the view model (MVVM).
@MainActor
final class DashboardViewModel: ObservableObject {
    private let devices: DeviceManager
    private var cancellable: AnyCancellable?

    init(devices: DeviceManager) {
        self.devices = devices
        cancellable = devices.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var deviceList: [Device] { devices.devices }
    var isLoading: Bool { devices.isLoading }
    var errorMessage: String? { devices.errorMessage }

    func load() async { await devices.refresh() }
    func remove(_ device: Device) async { await devices.remove(device) }
}
