import Foundation
import GameController

/// Maps a connected MFi/Xbox/PlayStation controller to `RemoteInput` — left
/// stick moves the cursor, A/B are left/right click.
@MainActor
final class GameControllerService: ObservableObject {
    @Published private(set) var connectedName: String?
    private let onInput: (RemoteInput) -> Void

    init(onInput: @escaping (RemoteInput) -> Void) {
        self.onInput = onInput
        observe()
    }

    private func observe() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let self, let controller = note.object as? GCController,
                  let pad = controller.extendedGamepad else { return }
            self.connectedName = controller.vendorName
            pad.valueChangedHandler = { [weak self] gamepad, _ in
                guard let self else { return }
                let x = Double(gamepad.leftThumbstick.xAxis.value)
                let y = Double(gamepad.leftThumbstick.yAxis.value)
                if abs(x) > 0.12 || abs(y) > 0.12 {
                    self.onInput(.move(dx: Int(x * 14), dy: Int(-y * 14)))
                }
                if gamepad.buttonA.isPressed { self.onInput(.click(.left)) }
                if gamepad.buttonB.isPressed { self.onInput(.click(.right)) }
            }
        }
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            self?.connectedName = nil
        }
    }
}
