import UIKit

/// Thin wrapper over UIKit haptics for tactile feedback on clicks/keys.
final class HapticsEngine {
    func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    func rigid() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
