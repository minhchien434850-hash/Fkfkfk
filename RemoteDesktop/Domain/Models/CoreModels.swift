import Foundation

// MARK: - Core domain entities (pure value types, no framework dependencies)

/// An authenticated user of the RemoteDesktop client.
struct User: Codable, Equatable, Identifiable {
    let id: String
    let username: String
    var displayName: String
}

/// A controllable machine (Desktop Agent) advertised by the relay.
struct Device: Codable, Equatable, Identifiable {
    let id: String        // agent id
    let name: String
    let os: String        // "Windows" | "Darwin" | "Linux"
    var isOnline: Bool
}

/// Quality profile used by the adaptive streaming pipeline.
enum StreamQuality: String, Codable, CaseIterable, Sendable {
    case low, balanced, high, auto
    var displayName: String {
        switch self {
        case .low: return "Low (data saver)"
        case .balanced: return "Balanced"
        case .high: return "High (best quality)"
        case .auto: return "Auto (adaptive)"
        }
    }
}

/// Live connection telemetry shown in the session HUD.
struct ConnectionInfo: Equatable, Sendable {
    var transport: String = "WebSocket/TLS"
    var latencyMs: Int = 0
    var bitrateKbps: Int = 0
    var frameRate: Int = 0
    var isReconnecting: Bool = false
}

/// A remote-control session bound to a single device.
struct RemoteSession: Equatable, Identifiable {
    let id: UUID
    let device: Device
    var quality: StreamQuality
    var startedAt: Date
}

/// A single decoded/preview frame surfaced to the renderer.
struct VideoFrame: Sendable {
    let data: Data            // JPEG (relay) or decoded pixel buffer bytes
    let timestamp: TimeInterval
    let width: Int
    let height: Int
}

/// Authentication state observed by the UI.
enum AuthState: Equatable { case unknown, signedOut, signedIn }
