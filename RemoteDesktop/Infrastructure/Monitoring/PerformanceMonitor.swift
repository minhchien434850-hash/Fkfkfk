import Foundation
import QuartzCore

/// Live FPS + memory monitor for the diagnostics screen and adaptive quality.
@MainActor
final class PerformanceMonitor: ObservableObject {
    @Published private(set) var fps: Int = 0
    @Published private(set) var memoryMB: Int = 0

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount = 0

    func start() {
        stop()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() { displayLink?.invalidate(); displayLink = nil; lastTimestamp = 0; frameCount = 0 }

    @objc private func tick(_ link: CADisplayLink) {
        if lastTimestamp == 0 { lastTimestamp = link.timestamp; return }
        frameCount += 1
        let delta = link.timestamp - lastTimestamp
        if delta >= 1 {
            fps = Int((Double(frameCount) / delta).rounded())
            frameCount = 0
            lastTimestamp = link.timestamp
            memoryMB = Self.usedMemoryMB()
        }
    }

    /// Resident memory of this process in megabytes (mach task info).
    static func usedMemoryMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.resident_size) / (1024 * 1024)
    }
}
