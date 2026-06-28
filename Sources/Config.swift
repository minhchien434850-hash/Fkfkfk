import Foundation

enum Config {
    // 👉 ĐIỀN URL VPS CỦA BẠN VÀO ĐÂY (máy chủ đang chạy codebox.py).
    //    Khi có giá trị này, mở app là đăng nhập luôn — KHÔNG cần bước liên kết.
    //    Để TRỐNG ("") nếu muốn bắt người dùng tự nhập máy chủ khi mở app.
    //    Ví dụ: "https://api.kenios.com"  hoặc  "http://123.45.67.89"
    //    Lưu ý: dùng cổng 80 qua nginx (KHÔNG thêm :8000) — cổng 8000 là uvicorn
    //    nội bộ, thường không mở ra ngoài nên app sẽ không kết nối được.
    static let defaultServerURL = "http://103.131.56.11"

    static let defaultServerType = "VPS"
}
