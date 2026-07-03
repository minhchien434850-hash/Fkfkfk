# KENIOS PC Agent — điều khiển máy tính từ app/web

Agent nhỏ chạy trên **máy tính cần điều khiển**. Nó tự kết nối **ra** máy chủ KENIOS
bằng chính **tài khoản KENIOS** của bạn, nên:

- **Không cần** ngrok, **không cần** mở cổng, **không cần** nhập IP/VPS ở điện thoại.
- App KENIOS (**Khám phá → Windows App**) và trang Web (**http://103.131.56.11/pc**)
  sẽ **tự thấy** máy này để điều khiển (chuột, bàn phím, media, âm lượng, Desktop, Lock…).

## Cách dùng (trên PC cần điều khiển)

### Windows
1. Cài Python (nhớ tích *Add python.exe to PATH*): https://www.python.org/downloads/
2. Nhấp đúp **start-windows.bat**.
3. Nhập **Tài khoản + Mật khẩu KENIOS** (giống đăng nhập app). Xong.

### macOS / Linux
```bash
pip install requests pyautogui mss pillow
python3 pc_remote.py
```
macOS: cấp quyền **Trợ năng (Accessibility)** + **Ghi màn hình** cho Terminal
(Cài đặt hệ thống → Quyền riêng tư & Bảo mật).

## Điều khiển
- **App:** mở KENIOS → Khám phá → **Windows App** → chọn máy đang online → điều khiển.
- **Web:** mở **http://103.131.56.11/pc** → đăng nhập tài khoản KENIOS → chọn máy.

## Tuỳ chọn (biến môi trường)
| Biến | Ý nghĩa | Mặc định |
| --- | --- | --- |
| `KENIOS_SERVER` | Địa chỉ máy chủ KENIOS | `http://103.131.56.11` |
| `KENIOS_USER` / `KENIOS_PASS` | Đăng nhập sẵn (khỏi gõ) | (hỏi khi chạy) |
| `KENIOS_PC_NAME` | Tên máy hiển thị trong app | tên máy tính |
| `KENIOS_MAXW` | Bề rộng khung gửi (px) — cao hơn = nét hơn | `1280` |
| `KENIOS_QUALITY` | Chất lượng JPEG 1–95 | `60` |
| `KENIOS_FPS` | Số khung/giây mục tiêu | `7` |

Muốn **nét hơn** (mạng khỏe): `KENIOS_MAXW=1600 KENIOS_QUALITY=70 KENIOS_FPS=10 python3 pc_remote.py`.
Muốn **nhẹ mạng**: giảm xuống `KENIOS_MAXW=960 KENIOS_QUALITY=45 KENIOS_FPS=4`.
Cài thêm `pyperclip` để **dán văn bản từ điện thoại vào PC**. Agent **tự đăng nhập lại**
khi token hết hạn nên chạy được lâu dài.

> Bảo mật: agent chỉ nhận lệnh từ **đúng tài khoản KENIOS** đã đăng nhập; máy chủ
> kiểm tra chủ sở hữu trước mỗi lệnh. Không mở cổng ra Internet nên không lộ máy.
