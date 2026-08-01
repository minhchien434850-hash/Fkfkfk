import Foundation

/// Adaptive Bitrate (ABR) controller.
/// Adjusts the target encoder bitrate from measured latency and packet loss so
/// the stream stays smooth on changing networks (Wi-Fi ↔ 5G).
struct AdaptiveBitrate {
    private(set) var currentKbps: Int
    let minKbps: Int
    let maxKbps: Int

    init(startKbps: Int = 4_000,
         minKbps: Int = AppConfig.minBitrateKbps,
         maxKbps: Int = AppConfig.maxBitrateKbps) {
        self.minKbps = minKbps
        self.maxKbps = maxKbps
        self.currentKbps = Swift.min(Swift.max(startKbps, minKbps), maxKbps)
    }

    /// Feed a measurement window; returns the new target bitrate.
    @discardableResult
    mutating func update(latencyMs: Int, lossFraction: Double) -> Int {
        if lossFraction > 0.05 || latencyMs > 180 {
            currentKbps = max(minKbps, Int(Double(currentKbps) * 0.7))   // back off fast
        } else if lossFraction < 0.01 && latencyMs < 80 {
            currentKbps = min(maxKbps, Int(Double(currentKbps) * 1.1))   // ramp up gently
        }
        return currentKbps
    }
}
