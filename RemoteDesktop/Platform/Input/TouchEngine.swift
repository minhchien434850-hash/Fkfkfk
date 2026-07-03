import Foundation

/// Pure gesture → `RemoteInput` translation. No UIKit dependency so it is fully
/// unit-testable. The View feeds raw deltas; the engine applies sensitivity and
/// produces normalized commands for the input pipeline.
struct TouchEngine {
    var sensitivity: Double

    init(sensitivity: Double = 2.5) { self.sensitivity = max(0.5, sensitivity) }

    func move(dx: Double, dy: Double) -> RemoteInput {
        .move(dx: Int((dx * sensitivity).rounded()), dy: Int((dy * sensitivity).rounded()))
    }
    func tap() -> RemoteInput { .click(.left) }
    func doubleTap() -> RemoteInput { .click(.double) }
    func longPress() -> RemoteInput { .click(.right) }
    func scroll(dy: Double) -> RemoteInput { .scroll(dy: Int(dy.rounded())) }

    /// A drag is treated as a tap when total movement stays under the threshold.
    func isTap(totalDX: Double, totalDY: Double, threshold: Double = 8) -> Bool {
        (totalDX * totalDX + totalDY * totalDY).squareRoot() < threshold
    }
}
