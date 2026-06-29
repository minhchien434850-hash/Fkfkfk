import UIKit
import ObjectiveC

// ============================ Nút "ẩn bàn phím" toàn app ============================
// Gắn 1 thanh nhỏ phía trên bàn phím (có nút "Xong ⌄") cho MỌI ô nhập (UITextField + UITextView)
// trong toàn bộ app — kể cả popup/sheet. Bấm nút → ẩn bàn phím.
// Cài 1 lần lúc khởi động: KeyboardDismissBar.installGlobally()

// Bộ xử lý dùng chung (singleton, sống suốt vòng đời app) để nút bấm luôn có target hợp lệ.
final class KeyboardDismissHandler {
    static let shared = KeyboardDismissHandler()
    @objc func dismissKeyboard() {
        // Gửi resignFirstResponder TỚI first responder hiện tại (cách chắc chắn nhất) +
        // ép cửa sổ ngừng nhập liệu để chắc chắn bàn phím ẩn.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for w in ws.windows { w.endEditing(true) }
        }
    }
}

enum KeyboardDismissBar {
    static func installGlobally() {
        UITextField.kenios_swizzleAccessory()
        UITextView.kenios_swizzleAccessory()
    }

    /// Thanh công cụ với nút ẩn bàn phím nằm bên phải.
    static func makeBar() -> UIToolbar {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        bar.isTranslucent = true
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let down = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .done,
            target: KeyboardDismissHandler.shared,
            action: #selector(KeyboardDismissHandler.dismissKeyboard))
        let doneText = UIBarButtonItem(
            title: "Xong",
            style: .done,
            target: KeyboardDismissHandler.shared,
            action: #selector(KeyboardDismissHandler.dismissKeyboard))
        down.tintColor = .systemBlue
        doneText.tintColor = .systemBlue
        bar.items = [flex, down, doneText]
        bar.sizeToFit()
        return bar
    }
}

private var kKeniosAccessoryKey: UInt8 = 0

extension UITextField {
    static func kenios_swizzleAccessory() {
        guard let original = class_getInstanceMethod(self, #selector(getter: inputAccessoryView)),
              let replacement = class_getInstanceMethod(self, #selector(getter: kenios_accessory))
        else { return }
        method_exchangeImplementations(original, replacement)
    }

    // Sau khi hoán đổi: gọi self.inputAccessoryView sẽ chạy thân hàm này;
    // còn gọi self.kenios_accessory lại trả về giá trị GỐC (accessory riêng nếu có).
    @objc var kenios_accessory: UIView? {
        if let custom = self.kenios_accessory { return custom }   // ô đã có thanh riêng → giữ nguyên
        if let bar = objc_getAssociatedObject(self, &kKeniosAccessoryKey) as? UIToolbar { return bar }
        let bar = KeyboardDismissBar.makeBar()
        objc_setAssociatedObject(self, &kKeniosAccessoryKey, bar, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return bar
    }
}

extension UITextView {
    static func kenios_swizzleAccessory() {
        guard let original = class_getInstanceMethod(self, #selector(getter: inputAccessoryView)),
              let replacement = class_getInstanceMethod(self, #selector(getter: kenios_accessory))
        else { return }
        method_exchangeImplementations(original, replacement)
    }

    @objc var kenios_accessory: UIView? {
        if let custom = self.kenios_accessory { return custom }
        if let bar = objc_getAssociatedObject(self, &kKeniosAccessoryKey) as? UIToolbar { return bar }
        let bar = KeyboardDismissBar.makeBar()
        objc_setAssociatedObject(self, &kKeniosAccessoryKey, bar, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return bar
    }
}
