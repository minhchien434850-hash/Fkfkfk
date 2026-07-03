import Foundation

/// Global, immutable application configuration.
/// Central place for environment values (server URL, timeouts, feature flags).
enum AppConfig {

    /// Base URL of the KENIOS relay/signaling server that the app talks to.
    /// The RemoteDesktop client reuses this relay for auth, device discovery,
    /// session commands and screen frames (see `Infrastructure/Networking`).
    static let serverBaseURL = URL(string: "http://103.131.56.11")!

    /// Networking timeouts (seconds).
    static let requestTimeout: TimeInterval = 20
    static let resourceTimeout: TimeInterval = 60

    /// Streaming defaults.
    static let targetFrameRate: Int = 60
    static let screenPollInterval: TimeInterval = 0.5      // relay JPEG preview cadence
    static let inputFlushInterval: TimeInterval = 0.045    // batch pointer deltas (smooth cursor)

    /// Adaptive bitrate bounds (kbps).
    static let minBitrateKbps: Int = 800
    static let maxBitrateKbps: Int = 12_000

    /// Keychain service identifier for secure storage.
    static let keychainService = "com.kenios.remotedesktop.secure"
}
