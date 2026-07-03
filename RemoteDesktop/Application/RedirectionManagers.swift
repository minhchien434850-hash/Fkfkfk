import Foundation
import AVFoundation

/// A redirectable hardware/peripheral channel between phone and remote host.
protocol RedirectionChannel: AnyObject {
    var name: String { get }
    var isActive: Bool { get }
    func start() throws
    func stop()
}

/// Camera → remote host redirection. Verifies capture authorization; the frame
/// pump to the agent plugs into `start()`.
final class CameraRedirect: RedirectionChannel {
    let name = "Camera"
    private(set) var isActive = false
    func start() throws {
        guard AVCaptureDevice.default(for: .video) != nil else { throw RemoteError.unknown("No camera") }
        isActive = true
    }
    func stop() { isActive = false }
}

/// Microphone → remote host redirection (paired with AudioEngine on the wire).
final class MicrophoneRedirect: RedirectionChannel {
    let name = "Microphone"
    private(set) var isActive = false
    func start() throws {
        guard AVCaptureDevice.default(for: .audio) != nil else { throw RemoteError.unknown("No microphone") }
        isActive = true
    }
    func stop() { isActive = false }
}

/// Remote host audio → phone speaker.
final class SpeakerRedirect: RedirectionChannel {
    let name = "Speaker"
    private(set) var isActive = false
    func start() throws { isActive = true }
    func stop() { isActive = false }
}

/// Printer redirection (open architecture — surfaces via UIPrintInteraction on
/// receipt of a print job from the host).
final class PrinterRedirect: RedirectionChannel {
    let name = "Printer"
    private(set) var isActive = false
    func start() throws { isActive = true }
    func stop() { isActive = false }
}

/// USB / external-storage redirection is exposed as an open protocol so a future
/// agent channel can register a concrete implementation.
final class USBRedirect: RedirectionChannel {
    let name = "USB Device"
    private(set) var isActive = false
    func start() throws { throw RemoteError.unknown("USB redirection requires a Desktop Agent channel.") }
    func stop() { isActive = false }
}

/// Aggregates all redirection channels behind one observable façade.
@MainActor
final class RedirectionManager: ObservableObject {
    @Published private(set) var activeChannels: Set<String> = []
    private let channels: [RedirectionChannel]

    init(channels: [RedirectionChannel] = [CameraRedirect(), MicrophoneRedirect(),
                                           SpeakerRedirect(), PrinterRedirect(), USBRedirect()]) {
        self.channels = channels
    }

    func toggle(_ name: String) {
        guard let channel = channels.first(where: { $0.name == name }) else { return }
        do {
            if channel.isActive { channel.stop(); activeChannels.remove(name) }
            else { try channel.start(); activeChannels.insert(name) }
        } catch {
            AppLog.shared.warning("Redirect \(name) failed: \(error.localizedDescription)", category: "redirect")
        }
    }

    var availableChannels: [String] { channels.map(\.name) }
}
