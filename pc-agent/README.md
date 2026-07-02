# KENIOS PC Remote Agent

Server nhỏ chạy trên **máy tính** để app KENIOS (mục **PC Remote** trong Khám phá)
điều khiển được: chuột, bàn phím, media, xem màn hình — bằng **IP + tài khoản + mật khẩu**.

> ⚠️ Đây KHÔNG phải RDP. Nếu máy anh chỉ cấp thông tin Remote Desktop (IP:port +
> user + pass) như VPS cloud/máy game, hãy dùng app **Microsoft Remote Desktop**.
> Agent này dành cho máy anh **tự cài được Python + mở được cổng** (VPS Ubuntu,
> máy tính cá nhân...).

## 1. Cài trên PC (làm 1 lần)

Cần Python 3.9+.

```bash
pip install -r requirements.txt
```
(hoặc: `pip install fastapi uvicorn pyautogui mss pillow`)

**macOS**: Cài đặt hệ thống → Quyền riêng tư & Bảo mật → cấp quyền
**Trợ năng (Accessibility)** và **Ghi màn hình (Screen Recording)** cho Terminal.

## 2. Chạy Agent (đặt tài khoản + mật khẩu)

```bash
# Windows (PowerShell)
$env:PC_USER="admin"; $env:PASSWORD="matkhau_kho_doan"; python pc_remote.py
# macOS/Linux
PC_USER=admin PASSWORD=matkhau_kho_doan python pc_remote.py
```
Mặc định: cổng `8765`, tài khoản `admin`, mật khẩu `kenios` (NÊN đổi).

## 3. Cho app kết nối được

- **Cùng Wi-Fi với PC**: dùng IP nội bộ của PC (vd `192.168.1.10`). Trên Windows
  nhớ mở cổng `8765` trong Windows Firewall.
- **Khác mạng (qua Internet)**: PC phải có **IP công khai** và mở/forward cổng
  `8765` (VPS cloud thì mở trong firewall của VPS là được). Nếu router nhà không
  mở được cổng, dùng tunnel (ngrok/cloudflared) rồi dán link vào ô IP.

## 4. Kết nối từ app

Mở **KENIOS → Khám phá → PC Remote**:
- **IP máy tính**: IP của PC (nội bộ hoặc public)
- **Cổng**: `8765`
- **Tài khoản / Mật khẩu**: khớp với Agent
- Bấm **Kết nối PC**

Rê tay để di chuột, chạm = click trái, dùng các nút media/bàn phím.

## Bảo mật
- Nếu mở cổng ra Internet, BẮT BUỘC đặt mật khẩu khó đoán.
- Chỉ chạy Agent khi cần; tắt cửa sổ để ngắt hoàn toàn.

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

Mọi request cần header `X-User` + `X-Pass` khớp với Agent.
