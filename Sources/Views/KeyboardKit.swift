import SwiftUI
import UIKit

// ============================================================
//  KeyboardKit — tiện ích dùng chung cho TẤT CẢ màn hình có bàn phím
//  • Nút "ẩn bàn phím" nổi, tự hiện trên mọi bàn phím (kể cả sheet).
//  • Hàm chia sẻ chắc chắn (tìm đúng màn đang hiển thị để mở khay Share).
// ============================================================

// MARK: - Ẩn bàn phím ở mọi nơi
extension UIApplication {
    /// Thu bàn phím trên mọi cửa sổ đang mở.
    func keniosEndEditing() {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .forEach { $0.endEditing(true) }
    }

    /// Cửa sổ chính đang hiển thị.
    var keniosKeyWindow: UIWindow? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
            ?? scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow })
            ?? scenes.flatMap { $0.windows }.first
    }

    /// Màn hình (view controller) trên cùng — để present khay chia sẻ đúng chỗ.
    func keniosTopViewController(_ base: UIViewController? = nil) -> UIViewController? {
        let base = base ?? keniosKeyWindow?.rootViewController
        if let nav = base as? UINavigationController {
            return keniosTopViewController(nav.visibleViewController ?? nav)
        }
        if let tab = base as? UITabBarController {
            return keniosTopViewController(tab.selectedViewController ?? tab)
        }
        if let presented = base?.presentedViewController {
            return keniosTopViewController(presented)
        }
        return base
    }
}

// MARK: - Chia sẻ chắc chắn (hoạt động ở mọi màn, cả fullScreenCover/sheet)
@MainActor
func keniosPresentShare(_ items: [Any]) {
    guard !items.isEmpty,
          let top = UIApplication.shared.keniosTopViewController() else { return }
    let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
    // iPad: cần nguồn neo cho popover, nếu không sẽ crash.
    if let pop = vc.popoverPresentationController {
        pop.sourceView = top.view
        pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 40,
                                width: 0, height: 0)
        pop.permittedArrowDirections = []
    }
    top.present(vc, animated: true)
}

// MARK: - Nút "ẩn bàn phím" nổi, dùng chung cho toàn app
@MainActor
final class KeyboardDismissBar: NSObject {
    static let shared = KeyboardDismissBar()
    private weak var button: UIButton?
    private var started = false

    /// Gọi 1 lần khi app khởi động.
    func start() {
        guard !started else { return }
        started = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(keyboardChanged(_:)),
                       name: UIResponder.keyboardWillShowNotification, object: nil)
        nc.addObserver(self, selector: #selector(keyboardChanged(_:)),
                       name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        nc.addObserver(self, selector: #selector(keyboardHidden(_:)),
                       name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    private func ensureButton(in window: UIWindow) -> UIButton {
        if let b = button, b.window === window { return b }
        button?.removeFromSuperview()

        let b = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        b.setImage(UIImage(systemName: "keyboard.chevron.compact.down", withConfiguration: cfg), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor(red: 0.0, green: 0.58, blue: 0.96, alpha: 0.95)
        b.layer.cornerRadius = 19
        b.layer.shadowColor = UIColor.black.cgColor
        b.layer.shadowOpacity = 0.25
        b.layer.shadowRadius = 4
        b.layer.shadowOffset = CGSize(width: 0, height: 2)
        b.frame = CGRect(x: 0, y: 0, width: 38, height: 38)
        b.addTarget(self, action: #selector(tapDismiss), for: .touchUpInside)
        window.addSubview(b)
        button = b
        return b
    }

    @objc private func tapDismiss() {
        UIApplication.shared.keniosEndEditing()
    }

    @objc private func keyboardChanged(_ note: Notification) {
        guard let win = UIApplication.shared.keniosKeyWindow,
              let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }
        let kbTopInWindow = win.frame.height - end.height
        // Bàn phím đang ẩn / ngoài màn hình.
        if end.height <= 0 || kbTopInWindow >= win.frame.height - 1 {
            button?.isHidden = true
            return
        }
        let b = ensureButton(in: win)
        let size: CGFloat = 38
        b.isHidden = false
        b.frame = CGRect(x: win.bounds.width - size - 10,
                         y: kbTopInWindow - size - 6,
                         width: size, height: size)
        win.bringSubviewToFront(b)
    }

    @objc private func keyboardHidden(_ note: Notification) {
        button?.isHidden = true
    }
}
