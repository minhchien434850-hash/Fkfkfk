import Foundation

/// Batches pointer deltas and flushes them on a fixed cadence for a smooth,
/// jitter-free cursor (the key to responsive control). Discrete commands
/// (click, key, media) are sent immediately.
@MainActor
final class InputManager: ObservableObject {
    @Published var sensitivity: Double = 2.5 { didSet { engine.sensitivity = sensitivity } }

    private let sendInput: SendInputUseCase
    private var engine = TouchEngine()
    private var deviceId: String = ""
    private var accDX: Double = 0
    private var accDY: Double = 0
    private var flushTask: Task<Void, Never>?

    init(sendInput: SendInputUseCase) { self.sendInput = sendInput }

    func begin(deviceId: String) {
        self.deviceId = deviceId
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.flush()
                try? await Task.sleep(nanoseconds: UInt64(AppConfig.inputFlushInterval * 1_000_000_000))
            }
        }
    }

    func end() { flushTask?.cancel(); flushTask = nil; accDX = 0; accDY = 0 }

    /// Accumulate a raw drag delta (in points).
    func pan(dx: Double, dy: Double) { accDX += dx; accDY += dy }

    private func flush() async {
        guard abs(accDX) >= 1 || abs(accDY) >= 1 else { return }
        let cmd = engine.move(dx: accDX, dy: accDY)
        accDX = 0; accDY = 0
        try? await sendInput(cmd, deviceId: deviceId)
    }

    // Discrete commands
    func tap() { dispatch(engine.tap()) }
    func rightClick() { dispatch(engine.longPress()) }
    func doubleClick() { dispatch(engine.doubleTap()) }
    func scroll(_ dy: Int) { dispatch(.scroll(dy: dy)) }
    func key(_ name: String) { dispatch(.key(name)) }
    func text(_ s: String) { dispatch(.text(s)) }
    func media(_ a: MediaAction) { dispatch(.media(a)) }
    func system(_ a: SystemAction) { dispatch(.system(a)) }

    private func dispatch(_ input: RemoteInput) {
        let id = deviceId
        let useCase = sendInput
        Task { try? await useCase(input, deviceId: id) }
    }
}
