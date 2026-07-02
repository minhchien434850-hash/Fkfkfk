# KENIOS Remote Gateway (Apache Guacamole)

Biến **VPS của anh** thành cổng điều khiển từ xa: nhận **RDP/VNC** rồi phát ra
**web (HTML5)**. App KENIOS mở web này để điều khiển **bất kỳ máy nào** — chỉ cần
nhập **IP + tài khoản + mật khẩu** của máy đó, **không cài gì lên máy đích**.

## Cài trên VPS (1 lệnh)

```bash
cd /root/Fkfkfk/remote-gateway
sudo bash setup.sh
```

Script tự: cài Docker → tạo mật khẩu CSDL ngẫu nhiên → dựng Guacamole → chạy.
Xong sẽ in ra địa chỉ `http://IP_VPS:8080/` và tài khoản đầu tiên
`guacadmin / guacadmin`.

> ⚠️ **Đổi mật khẩu `guacadmin` ngay** sau khi đăng nhập (Settings → Preferences),
> vì cổng mở công khai trên internet.

## Thêm 1 máy để điều khiển (làm trong Guacamole hoặc trong app)

Trong web Guacamole → Settings → Connections → **New Connection**:
- **Protocol**: RDP (hoặc VNC)
- **Hostname**: IP máy cần điều khiển (vd `42.119.44.44`)
- **Port**: cổng RDP (vd `7278`, mặc định RDP là `3389`)
- **Username / Password**: tài khoản máy đó
- RDP nên bật: `Ignore server certificate` = true

Lưu xong bấm vào là thấy màn hình máy + điều khiển chuột/bàn phím.

## Trong app KENIOS

**Khám phá → Remote PC**:
- Nhập **địa chỉ cổng**: `http://IP_VPS:8080`
- Đăng nhập Guacamole (guacadmin/...) — app **nhớ đăng nhập 1 lần**
- Thêm máy: nhập **IP + user + pass** → điều khiển ngay trong app

## Quản lý

```bash
cd /root/Fkfkfk/remote-gateway
docker compose ps          # xem trạng thái
docker compose logs -f     # xem log
docker compose restart     # khởi động lại
docker compose down        # tắt cổng
```

## Yêu cầu để điều khiển được máy đích
- Máy đích phải **bật RDP** (Windows: Settings → Remote Desktop) hoặc chạy VNC.
- VPS phải **kết nối tới được** IP:cổng RDP của máy đích (máy đích có IP công khai,
  hoặc cùng mạng với VPS). Máy game/VPS cloud có IP công khai thì OK.
