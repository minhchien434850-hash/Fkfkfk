import Foundation

/// Analytics abstraction (Dependency Inversion). Swap the console sink for a
/// real backend without touching call sites.
protocol AnalyticsProtocol {
    func track(_ event: String, properties: [String: String])
}

extension AnalyticsProtocol {
    func track(_ event: String) { track(event, properties: [:]) }
}

/// Default sink that routes events to the structured logger.
final class ConsoleAnalytics: AnalyticsProtocol {
    func track(_ event: String, properties: [String: String]) {
        let props = properties.isEmpty ? "" : " " + properties.map { "\($0)=\($1)" }.joined(separator: " ")
        AppLog.shared.info("event=\(event)\(props)", category: "analytics")
    }
}

/// Rolling network statistics for the diagnostics HUD.
struct NetworkStatistics: Equatable {
    var bytesSent: Int64 = 0
    var bytesReceived: Int64 = 0
    var roundTripMs: Int = 0
    var packetLoss: Double = 0
}

@MainActor
final class NetworkStatsTracker: ObservableObject {
    @Published private(set) var stats = NetworkStatistics()

    func record(sent: Int64 = 0, received: Int64 = 0, rttMs: Int? = nil, loss: Double? = nil) {
        stats.bytesSent += sent
        stats.bytesReceived += received
        if let rttMs { stats.roundTripMs = rttMs }
        if let loss { stats.packetLoss = loss }
    }
    func reset() { stats = NetworkStatistics() }
}
