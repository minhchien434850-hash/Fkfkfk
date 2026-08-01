import UIKit

// ============================ Nút "ẩn bàn phím" toàn app ============================
// Gắn 1 thanh nhỏ (nút "Ẩn bàn phím ⌄") phía trên bàn phím cho MỌI ô nhập trong app —
// kể cả popup/sheet. Cài 1 lần lúc khởi động: KeyboardDismissBar.installGlobally().
//
// Cách làm: lắng nghe sự kiện bàn phím sắp hiện / ô bắt đầu nhập → tìm ô đang nhập
// (first responder) → gắn inputAccessoryView (thanh nút) trực tiếp lên ô đó. Cách này
// CHẮC CHẮN hoạt động với cả TextField/TextEditor của SwiftUI (không phụ thuộc swizzling).

/// Thanh công cụ "của KENIOS" — để nhận biết đã gắn rồi (khỏi gắn lại).
final class KeniosKeyboardBar: UIToolbar {}

final class KeyboardDismissHandler {
    static let shared = KeyboardDismissHandler()
    @objc func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for w in ws.windows { w.endEditing(true) }
        }
    }
}

enum KeyboardDismissBar {
    private static var installed = false

    static func installGlobally() {
        guard !installed else { return }
        installed = true
        let names: [Notification.Name] = [
            UIResponder.keyboardWillShowNotification,
            UITextField.textDidBeginEditingNotification,
            UITextView.textDidBeginEditingNotification,
        ]
        for n in names {
            NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { _ in
                attachBar()
            }
        }
    }

    /// Gắn thanh nút vào ô đang nhập (nếu chưa có).
    static func attachBar() {
        guard let responder = findFirstResponder() else { return }
        if let tf = responder as? UITextField {
            if !(tf.inputAccessoryView is KeniosKeyboardBar) {
                tf.inputAccessoryView = makeBar()
                tf.reloadInputViews()
            }
        } else if let tv = responder as? UITextView {
            if !(tv.inputAccessoryView is KeniosKeyboardBar) {
                tv.inputAccessoryView = makeBar()
                tv.reloadInputViews()
            }
        }
    }

    static func makeBar() -> KeniosKeyboardBar {
        let bar = KeniosKeyboardBar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        bar.isTranslucent = true
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let down = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .done, target: KeyboardDismissHandler.shared,
            action: #selector(KeyboardDismissHandler.dismissKeyboard))
        let done = UIBarButtonItem(
            title: "Ẩn bàn phím", style: .done,
            target: KeyboardDismissHandler.shared,
            action: #selector(KeyboardDismissHandler.dismissKeyboard))
        down.tintColor = .systemBlue
        done.tintColor = .systemBlue
        bar.items = [flex, down, done]
        bar.sizeToFit()
        return bar
    }

    /// Tìm ô đang nhập (first responder) trên cửa sổ đang hiển thị.
    static func findFirstResponder() -> UIResponder? {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows {
                if let r = window.kenios_firstResponder() { return r }
            }
        }
        return nil
    }
}

private extension UIView {
    func kenios_firstResponder() -> UIResponder? {
        if isFirstResponder { return self }
        for sub in subviews {
            if let r = sub.kenios_firstResponder() { return r }
        }
        return nil
    }
}
