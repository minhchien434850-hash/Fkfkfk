import Foundation
import AVFoundation

/// Two-way audio via `AVAudioEngine`.
///
/// Uses the `.voiceChat` mode which enables the system's echo cancellation and
/// noise suppression. This scaffold configures the session and starts the
/// engine (mic → mixer loopback); the network tap that ships mic frames to the
/// host and plays received frames plugs into `installTap`/`scheduleBuffer`.
final class AudioEngine: AudioServiceProtocol {
    private let engine = AVAudioEngine()
    private(set) var isRunning = false

    func startTwoWayAudio(deviceId: String) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        // Local monitoring path (scaffold). Replace with a network tap that
        // packetizes mic audio upstream and schedules downstream buffers.
        engine.connect(input, to: engine.mainMixerNode, format: format)
        try engine.start()
        isRunning = true
    }

    func stop() {
        engine.stop()
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
