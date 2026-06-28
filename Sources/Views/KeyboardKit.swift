import SwiftUI
import UIKit

// ============================================================
//  ShareKit — tiện ích chia sẻ dùng chung, tìm đúng màn đang
//  hiển thị để mở khay Share (hoạt động ở mọi màn, cả sheet /
//  fullScreenCover). Nút ẩn bàn phím toàn app nằm ở KeyboardDismiss.swift.
// ============================================================

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

/// Chia sẻ chắc chắn (hoạt động ở mọi màn, cả fullScreenCover/sheet).
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
