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
    //    👉 Tên miền HTTPS mới (có SSL). Nếu domain/SSL chưa sẵn sàng, app TỰ né sang
    //    IP VPS dự phòng (APIClient.fallbackBase) nên không bao giờ mất kết nối.
    static let defaultServerURL = "https://kenios.io.vn"

    static let defaultServerType = "VPS"
}
