import Foundation

/// Smooths network jitter by holding frames for a small target delay and
/// releasing them in timestamp order. Keeps playback steady at the cost of a
/// bounded added latency (`targetDelay`).
actor JitterBuffer {
    private var pending: [VideoFrame] = []
    private let targetDelay: TimeInterval

    init(targetDelay: TimeInterval = 0.08) { self.targetDelay = targetDelay }

    func push(_ frame: VideoFrame) {
        pending.append(frame)
        pending.sort { $0.timestamp < $1.timestamp }
    }

    /// Returns frames whose age exceeds the target delay (ready to display).
    func drain(now: TimeInterval = Date().timeIntervalSince1970) -> [VideoFrame] {
        let ready = pending.filter { now - $0.timestamp >= targetDelay }
        pending.removeAll { f in ready.contains { $0.timestamp == f.timestamp } }
        return ready
    }

    func reset() { pending.removeAll() }
}
