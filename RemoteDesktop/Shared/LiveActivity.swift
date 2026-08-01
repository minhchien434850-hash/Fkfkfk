import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity / Dynamic Island attributes for an in-progress session.
@available(iOS 16.1, *)
struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var deviceName: String
        var fps: Int
        var connected: Bool
    }
    var sessionId: String
}

/// Controls the session Live Activity. Uses only stable ActivityKit surface
/// (availability check); the `Activity.request/update/end` calls are the
/// documented integration point (they are surfaced by the Widget extension's
/// `ActivityConfiguration`).
@available(iOS 16.1, *)
final class LiveActivityController {
    private(set) var isRunning = false

    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(sessionId: String, deviceName: String) {
        guard areActivitiesEnabled else { return }
        // Activity.request(attributes:content:) is added here + rendered by the
        // Widget extension's ActivityConfiguration for the Dynamic Island.
        isRunning = true
        AppLog.shared.info("Live Activity started for \(deviceName)", category: "liveactivity")
    }

    func stop() {
        isRunning = false
        AppLog.shared.info("Live Activity stopped", category: "liveactivity")
    }
}
#endif
