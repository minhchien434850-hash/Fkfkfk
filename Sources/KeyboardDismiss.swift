import UIKit
import ObjectiveC

// ============================ Nút "ẩn bàn phím" toàn app ============================
// Gắn 1 thanh nhỏ phía trên bàn phím (có nút ⌨️⌄) cho MỌI ô nhập (UITextField + UITextView)
// trong toàn bộ app — kể cả các màn hình popup/sheet. Bấm nút → ẩn bàn phím.
// Cài 1 lần lúc khởi động: KeyboardDismissBar.installGlobally()
enum KeyboardDismissBar {
    static func installGlobally() {
        UITextField.kenios_swizzleAccessory()
        UITextView.kenios_swizzleAccessory()
    }

    /// Tạo thanh công cụ với nút ẩn bàn phím nằm bên phải.
    static func makeBar() -> UIToolbar {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let down = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .done, target: nil,
            action: #selector(UIResponder.resignFirstResponder))   // ẩn bàn phím (first responder tự thoát)
        bar.items = [flex, down]
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
