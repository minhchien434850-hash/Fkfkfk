import Foundation

/// A bounded, thread-safe frame queue (triple buffering).
/// Backed by an `actor` so producers (network) and consumers (renderer) never
/// race. When full it drops the oldest frame to keep latency low.
actor FrameQueue {
    private var frames: [VideoFrame] = []
    private let capacity: Int

    init(capacity: Int = 3) { self.capacity = max(1, capacity) }

    func enqueue(_ frame: VideoFrame) {
        frames.append(frame)
        if frames.count > capacity { frames.removeFirst(frames.count - capacity) }
    }

    func dequeue() -> VideoFrame? {
        frames.isEmpty ? nil : frames.removeFirst()
    }

    var count: Int { frames.count }
    func clear() { frames.removeAll() }
}
