import Foundation
import Combine
import UIKit

/// View model for an active remote session. Bridges `SessionManager` (frames /
/// telemetry) and `InputManager` (control) to the SwiftUI session screen.
@MainActor
final class SessionViewModel: ObservableObject {
    let device: Device
    let input: InputManager
    private let session: SessionManager
    private var cancellables = Set<AnyCancellable>()

    init(device: Device, session: SessionManager, input: InputManager) {
        self.device = device
        self.session = session
        self.input = input
        session.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        input.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var frameImage: UIImage? { session.latestFrame.flatMap { UIImage(data: $0.data) } }
    var connection: ConnectionInfo { session.connection }
    var isReconnecting: Bool { session.connection.isReconnecting }

    var sensitivity: Double {
        get { input.sensitivity }
        set { input.sensitivity = newValue }
    }

    func start() {
        try? session.connect(to: device, quality: .auto)
        input.begin(deviceId: device.id)
    }
    func stop() {
        input.end()
        session.disconnect()
    }
}
