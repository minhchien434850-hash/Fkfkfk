# 📘 Hướng dẫn VPS — KENIOS

Tất cả lệnh cần cho VPS gom về đây cho dễ chạy. IP VPS: **103.131.56.11**

---

## ⭐ A. CẬP NHẬT BACKEND (làm mỗi khi có bản mới) — 1 LỆNH

Dán đúng 1 dòng này, chạy bất cứ lúc nào:

```bash
bash <(curl -s https://raw.githubusercontent.com/minhchien434850-hash/Fkfkfk/claude/read-branch-file-2lxkte/capnhat-vps.sh)
```

→ Tự tải code mới, chép `kenios.py`, khởi động lại, kiểm tra. Xong báo `✅ XONG!`.

> Nếu muốn làm tay (không dùng script trên):
> ```bash
> cd /root && git clone -b claude/read-branch-file-2lxkte https://github.com/minhchien434850-hash/Fkfkfk.git kenios-new && cp kenios-new/backend/kenios.py /root/kenios/kenios.py && rm -rf kenios-new && systemctl restart kenios
> ```

---

## 📧 B. CẤU HÌNH GỬI EMAIL OTP (Brevo) — làm 1 LẦN

Dán khối này (thay `<LOGIN_BREVO>` và `<SMTP_KEY>` bằng giá trị của bạn lấy ở
Brevo → SMTP & API → SMTP):

```bash
cat >> /root/kenios/.env << 'EOF'
SMTP_RELAY_HOST=smtp-relay.brevo.com
SMTP_RELAY_PORT=587
SMTP_RELAY_USER=<LOGIN_BREVO>
SMTP_RELAY_PASS=<SMTP_KEY>
MAIL_FROM=chientran0913@gmail.com
EOF
systemctl restart kenios
```

> ⚠️ Chỉ chạy khối này **1 lần** (chạy nhiều lần sẽ thêm trùng dòng).
> `MAIL_FROM` phải là email đã đăng ký/đã xác minh trong Brevo.

---

## 🔴 LIVE. BẬT MÁY CHỦ LIVE (để "Phát trực tiếp bằng camera" có hình) — làm 1 LẦN

Muốn nút **Phát trực tiếp bằng camera** trong app hiện hình cho người xem, VPS phải
có máy chủ nhận luồng RTMP + phát HLS. Làm 2 bước:

**1) Cài máy chủ RTMP + HLS (1 lệnh):**
```bash
bash <(curl -s https://raw.githubusercontent.com/minhchien434850-hash/Fkfkfk/claude/read-branch-file-2lxkte/live-server/install-rtmp.sh)
```
→ Cài nginx + module RTMP + ffmpeg, mở cổng **1935** (nhận luồng) và **8080** (phát HLS).

**2) Báo cho backend biết IP máy chủ live (1 lệnh, chạy 1 lần):**
```bash
echo LIVE_SERVER=103.131.56.11 >> /root/kenios/.env && systemctl restart kenios
```
> `LIVE_SERVER` giúp app tạo đúng link `rtmp://103.131.56.11:1935/live` và
> `http://103.131.56.11:8080/hls/...`. Nếu sau này đổi IP/đổi domain thì sửa lại dòng này.

Sau đó vào app: **Khám phá → Live Now → Phát trực tiếp bằng camera** → bấm **Bắt đầu phát**.
Người xem mở phòng live sẽ thấy hình (trễ ~5–15 giây là bình thường với HLS).

---

## 🧩 C. (TÙY CHỌN) Cài C/C++ để chạy code C++

```bash
sudo apt update && sudo apt install -y g++ gcc
```

---

## 🔒 D. (TÙY CHỌN) Bật HTTPS cho domain kenios.store

Sau khi đã trỏ bản ghi **A**: `kenios.store → 103.131.56.11` (làm bên iNET):

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d kenios.store -d www.kenios.store
```

---

## 🛠️ E. LỆNH HỮU ÍCH

```bash
systemctl restart kenios            # khởi động lại
journalctl -u kenios -n 30 --no-pager   # xem log gần nhất
journalctl -u kenios -f             # xem log realtime
curl http://127.0.0.1/health        # kiểm tra sống
```

---

## 📦 F. NHỮNG GÌ ĐÃ LÀM (tóm tắt)

**Backend (cập nhật bằng mục A):**
- Giao key kèm tin nhắn (sản phẩm + nền tảng iOS/Android + hạn dùng + ngày hết hạn).
- Chống cộng tiền trùng khi xác nhận chuyển khoản ngân hàng (vân tay giao dịch).
- Email OTP có thương hiệu: logo KENIOS + tích xanh ✓ + mã 6 số, hết hạn 5 phút.
- Hỗ trợ `MAIL_FROM` (đặt email người gửi) — cấu hình ở mục B.

**App iOS (cài file IPA mới từ GitHub → Releases, lấy bản số cao nhất):**
- Icon app mới (chữ K gradient xanh–tím–hồng).
- Logo KENIOS ở: màn đăng nhập, Cài đặt, Quản trị.
- Hero banner: chữ + nút "Mua ngay" đè lên ảnh + logo + slogan.
- Hết giật, hết chóp nháy cửa hàng; sửa URL server về cổng 80.
- Tách code thành nhiều file cho dễ sửa.

> Tải IPA mới: https://github.com/minhchien434850-hash/Fkfkfk/releases (lấy bản trên cùng).
