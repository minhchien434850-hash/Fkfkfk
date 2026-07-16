import Foundation

enum Config {
    // 👉 ĐIỀN URL VPS CỦA BẠN VÀO ĐÂY (máy chủ đang chạy codebox.py).
    //    Khi có giá trị này, mở app là đăng nhập luôn — KHÔNG cần bước liên kết.
    //    Để TRỐNG ("") nếu muốn bắt người dùng tự nhập máy chủ khi mở app.
    //    Ví dụ: "https://api.kenios.com"  hoặc  "http://123.45.67.89"
    //    Lưu ý: dùng cổng 80/443 qua nginx (KHÔNG thêm :8000) — cổng 8000 là uvicorn
    //    nội bộ, thường không mở ra ngoài nên app sẽ không kết nối được.
    //    Dùng domain HTTPS (app.kenios.store) → khách hàng mở app là chạy ngay,
    //    KHÔNG cần đăng nhập/nhập máy chủ, lại bảo mật (khỏi vướng ATS của iOS).
    //    👉 KHÔNG dùng tên miền nữa — trỏ thẳng vào IP VPS mới (qua nginx cổng 80).
    static let defaultServerURL = "http://160.25.168.234"

    static let defaultServerType = "VPS"
}
