# KENIOS — App bán hàng (iOS 16+)

App iOS bán **key / acc game / ứng dụng** kèm **nạp tiền tự động qua ngân hàng ACB**.
Backend chạy trên VPS của bạn (`backend/kenios.py`). Build ra **IPA chưa ký** tự động bằng
GitHub Actions — **không cần máy Mac**.

## Tính năng chính
- **App bán hàng ("Ứng dụng"):** Danh mục → Thư mục con → Sản phẩm.
  - Sửa tên danh mục / thư mục / sản phẩm; tối đa 5 ảnh hoặc video (dán link) cho mỗi mục.
  - Giá theo thời hạn (giờ / ngày / tuần / tháng…), chỉnh giá VND từng sản phẩm.
  - Loại sản phẩm: **Ứng dụng/Key** hoặc **Acc game** (chung 1 cửa hàng).
  - Kho KEY/ACC: mỗi dòng 1 key, thêm/xoá nhanh; **bán xong tự xoá key khỏi kho** và
    **sao lưu** vào file để admin xem lại.
  - Link **hoặc** file tải (không giới hạn dung lượng) — khách mua xong hiện nút **Tải game**.
  - Giao diện cửa hàng tuỳ biến (logo tên + ảnh, banner ảnh/video qua link) — **chỉ admin** chỉnh,
    khách chỉ thấy giao diện.
- **Thanh toán:** khách chuyển khoản với nội dung là **ID của khách**; hệ thống đọc lịch sử
  giao dịch **ACB (thueapibank.vn)** tự động và giao key/nâng PRO ngay.
- **Nâng cấp PRO:** 1 gói duy nhất, admin tự chỉnh giá VND.
- **Giao diện Sáng / Tối / Tự động** + đa ngôn ngữ (đổi nhanh ngay trên tab Video & Ứng dụng).
- **Quản trị:** thống kê, người dùng, đơn hàng, log lỗi, ngân hàng/ACB, giá PRO.
- Video (reels) đăng & xem trong app; bạn bè / nhắn tin; TTS đọc bình luận TikTok Live.

## Chạy backend trên VPS
Xem file **`CHAY-VPS.sh`** (file gốc, 1 lệnh):
```bash
git clone -b claude/app-issues-repo-creation-px0q60 <LINK_REPO> kenios && cd kenios
chmod +x CHAY-VPS.sh
sudo ADMIN_PASS='matkhau_cua_ban' bash CHAY-VPS.sh
```
Sau khi chạy: mở app → nhập URL VPS hiện ở cuối màn hình → đăng nhập admin
(**kenios / mật khẩu bạn đặt**). Vào **Quản trị → Thông tin ngân hàng** dán
**API token ACB (thueapibank.vn)** để bật nạp tiền tự động.

Cập nhật code mới về VPS:
```bash
cd kenios && git pull && cp backend/kenios.py /root/kenios/kenios.py && systemctl restart kenios
```

## Build IPA bằng GitHub Actions
1. Đẩy repo lên GitHub.
2. Tab **Actions** → workflow build IPA tự chạy (hoặc bấm **Run workflow**).
3. Xong → mở lần chạy → **Artifacts** tải IPA. Cài bằng AltStore / SideStore / Sideloadly.

## Cấu trúc
```
backend/kenios.py            # toàn bộ backend (FastAPI) — chạy trên VPS
CHAY-VPS.sh                  # cài & chạy backend trên VPS (1 lệnh)
project.yml                  # cấu hình XcodeGen
Sources/
  Views/StoreView.swift      # cửa hàng (khách)
  Views/StoreAdminView.swift # quản trị cửa hàng (admin)
  Views/AdminView.swift      # quản trị chung
  Views/...                  # các màn hình khác
```
> `KENIOS.xcodeproj` không commit — XcodeGen sinh ra lúc build (`brew install xcodegen` → `xcodegen generate`).
