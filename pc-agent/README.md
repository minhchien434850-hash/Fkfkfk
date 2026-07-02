# KENIOS PC Remote Agent

Server nhỏ chạy trên **máy tính** để app KENIOS (mục **PC Remote** trong Khám phá)
điều khiển được: chuột, bàn phím, media, xem màn hình.

## 1. Cài trên PC (làm 1 lần)

Cần Python 3.9+.

```bash
pip install -r requirements.txt
```
(hoặc: `pip install fastapi uvicorn pyautogui mss pillow`)

**macOS**: vào Cài đặt hệ thống → Quyền riêng tư & Bảo mật → cấp quyền
**Trợ năng (Accessibility)** và **Ghi màn hình (Screen Recording)** cho Terminal,
nếu không chuột/ảnh màn hình sẽ không hoạt động.

## 2. Chạy Agent

```bash
python pc_remote.py
```
Mặc định: cổng `8765`, token `kenios`. Nên đổi token cho an toàn:
```bash
# Windows (PowerShell)
$env:TOKEN="matkhau_kho_doan"; python pc_remote.py
# macOS/Linux
TOKEN=matkhau_kho_doan python pc_remote.py
```

## 3. Mở ra ngoài bằng ngrok (cửa sổ khác)

```bash
ngrok http 8765
```
Copy link `https://xxxx.ngrok-free.dev` mà ngrok in ra.

## 4. Kết nối từ app

Mở **KENIOS → Khám phá → PC Remote**:
- **Địa chỉ Agent**: dán link ngrok ở trên
- **Token**: nhập đúng token đã đặt
- Bấm **Kết nối PC**

Xong! Rê tay để di chuột, chạm = click trái, dùng các nút media/bàn phím.

## Bảo mật
- Link ngrok là **công khai** → BẮT BUỘC đặt token khó đoán.
- Chỉ chạy Agent khi cần dùng; tắt cửa sổ để ngắt hoàn toàn.

## API (tham khảo)
| Method | Path | Body | Chức năng |
|---|---|---|---|
| GET | /ping | — | Kiểm tra kết nối |
| GET | /screen | — | Ảnh JPEG màn hình |
| POST | /move | {dx,dy} | Di chuột |
| POST | /click | {button} | left/right/double |
| POST | /scroll | {amount} | Cuộn |
| POST | /type | {text} | Gõ chữ |
| POST | /key | {name} | enter/backspace/space... |
| POST | /media | {action} | playpause/next/prev/mute/volup/voldown |
| POST | /system | {action} | desktop/lock |

Mọi request cần header `X-Token: <token>`.
