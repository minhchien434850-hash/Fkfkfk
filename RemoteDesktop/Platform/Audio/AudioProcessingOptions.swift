import Foundation

/// Audio DSP toggles. The `.voiceChat` AVAudioSession mode used by `AudioEngine`
/// provides hardware echo cancellation, noise suppression and automatic gain
/// control; these flags describe/announce the active processing to the UI.
struct AudioProcessingOptions: Equatable {
    var echoCancellation = true
    var noiseSuppression = true
    var automaticGainControl = true

    static let voiceOptimized = AudioProcessingOptions()
    static let disabled = AudioProcessingOptions(echoCancellation: false,
                                                 noiseSuppression: false,
                                                 automaticGainControl: false)
}
