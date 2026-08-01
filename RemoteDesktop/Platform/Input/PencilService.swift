import UIKit

/// Apple Pencil support: precise pointer + double-tap gesture mapped to a
/// right-click. Attach the interaction to the trackpad's host view.
final class PencilService: NSObject, UIPencilInteractionDelegate {
    var onDoubleTap: (() -> Void)?

    func attach(to view: UIView) {
        let interaction = UIPencilInteraction()
        interaction.delegate = self
        view.addInteraction(interaction)
    }

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        onDoubleTap?()
    }
}
