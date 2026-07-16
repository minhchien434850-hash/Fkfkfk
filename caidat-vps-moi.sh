#!/usr/bin/env bash
# ============================================================
#  caidat-vps-moi.sh — CÀI TRỌN GÓI KENIOS trên VPS TRỐNG (mới tạo)
#  Cài từ đầu: Python + backend + systemd + nginx + đủ thư viện tính năng.
#
#  CHẠY 1 LỆNH DUY NHẤT (dán vào SSH của VPS mới, THAY mật khẩu admin của anh):
#
#    ADMIN_PASS='matkhau_admin_cua_anh' bash <(curl -s \
#      https://raw.githubusercontent.com/minhchien434850-hash/Fkfkfk/claude/read-branch-file-2lxkte/caidat-vps-moi.sh)
#
#  Sau khi xong, script in ra URL http://<IP-VPS> để vào app / admin.
# ============================================================
set -eo pipefail

BRANCH="claude/read-branch-file-2lxkte"
REPO="https://github.com/minhchien434850-hash/Fkfkfk.git"
WORK="/root/kenios"
PORT="${PORT:-8000}"
ADMIN_USER="${ADMIN_USER:-kenios}"
ADMIN_PASS="${ADMIN_PASS:-}"                       # KHÔNG ghi mật khẩu vào file — truyền qua lệnh
SECRET="${CODEBOX_SECRET:-$(openssl rand -hex 32)}"
ACB_API_TOKEN="${ACB_API_TOKEN:-}"

# Tự sinh mật khẩu admin nếu anh chưa truyền (in ra ở cuối để anh dùng).
GEN_PASS=""
if [ -z "$ADMIN_PASS" ]; then
  ADMIN_PASS="$(openssl rand -base64 9 | tr -d '/+=' )Aa1@"
  GEN_PASS="1"
fi

echo "==> [1/8] Cài gói hệ thống (Python, nginx, ffmpeg, git...)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -qq
apt-get install -y -qq python3 python3-venv python3-pip nginx ffmpeg curl git unzip \
                      build-essential pkg-config libssl-dev >/dev/null

echo "==> [2/8] Tải code KENIOS (branch: $BRANCH)"
rm -rf /root/kenios-src
git clone -q -b "$BRANCH" "$REPO" /root/kenios-src
NEW_COMMIT="$(cd /root/kenios-src && git rev-parse --short HEAD)"
mkdir -p "$WORK"
cp /root/kenios-src/backend/kenios.py "$WORK/kenios.py"
echo "    Commit: $NEW_COMMIT"

echo "==> [3/8] Tạo môi trường Python + cài thư viện"
cd "$WORK"
[ -d venv ] || python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip -q
# Thư viện LÕI (bắt buộc để backend chạy được)
pip install -q "fastapi>=0.110" "uvicorn[standard]>=0.29" "httpx[http2]>=0.27" \
               "cryptography>=42" "python-multipart>=0.0.9" "pydantic>=2"
# Thư viện TÍNH NĂNG (best-effort — thiếu cái nào thì tính năng đó tạm nghỉ, backend vẫn chạy)
pip install -q "TikTokLive>=6.0" "aiosmtpd>=1.4" "yt-dlp" "pypdf" "python-docx" \
               "openpyxl" "PyJWT[crypto]>=2.8" "asyncssh>=2.14" "edge-tts" "gTTS" \
               "qrcode[pil]" "Pillow" 2>/dev/null || true

echo "==> [4/8] Ghi cấu hình .env"
cat > "$WORK/.env" <<EOF
CODEBOX_SECRET=$SECRET
ADMIN_USER=$ADMIN_USER
ADMIN_PASS=$ADMIN_PASS
PORT=$PORT
ACB_API_TOKEN=$ACB_API_TOKEN
EOF
chmod 600 "$WORK/.env"

echo "==> [5/8] Tạo dịch vụ systemd (tự chạy lại khi reboot/lỗi)"
tee /etc/systemd/system/kenios.service >/dev/null <<EOF
[Unit]
Description=KENIOS Backend
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=$WORK
EnvironmentFile=$WORK/.env
ExecStart=$WORK/venv/bin/uvicorn kenios:app --host 0.0.0.0 --port $PORT --workers 1
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable kenios >/dev/null 2>&1 || true
systemctl restart kenios

echo "==> [6/8] Cấu hình nginx (đảo ngược proxy, cho tải file lớn)"
PUBLIC_IP="$(curl -s ifconfig.me 2>/dev/null || echo "_")"
tee /etc/nginx/sites-available/kenios >/dev/null <<EOF
server {
    listen 80;
    server_name $PUBLIC_IP _;
    client_max_body_size 10240M;
    client_body_timeout 3600s;
    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_request_buffering off;
    }
}
EOF
ln -sf /etc/nginx/sites-available/kenios /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
nginx -t >/dev/null 2>&1 && systemctl reload nginx || echo "    ⚠️ nginx -t lỗi — kiểm tra: nginx -t"

echo "==> [7/8] Cài thêm công cụ tính năng (giọng nói, ký IPA, RDP...) — best effort"
# Giọng đọc kể chuyện voice
command -v edge-tts >/dev/null 2>&1 && echo "    ✓ edge-tts (giọng tiếng Việt)."
# zsign (ký IPA cài OTA 1 chạm) — build nếu chưa có
if ! command -v zsign >/dev/null 2>&1; then
  rm -rf /opt/zsign
  git clone -q --depth 1 https://github.com/zhlynn/zsign.git /opt/zsign 2>/dev/null || true
  ( cd /opt/zsign/build/linux 2>/dev/null && make >/dev/null 2>&1 ) || true
  ZBIN="$(find /opt/zsign -type f -name zsign -perm -u+x 2>/dev/null | head -n1)"
  [ -n "$ZBIN" ] && cp -f "$ZBIN" /usr/local/bin/zsign && chmod +x /usr/local/bin/zsign
  command -v zsign >/dev/null 2>&1 && echo "    ✓ zsign (ký IPA)." || echo "    ⚠️ zsign chưa build được (ký IPA sẽ báo tới khi cài)."
fi
# Công cụ RDP (điều khiển máy thuê bằng IP) — nặng, tolerant nếu lỗi
apt-get install -y -qq freerdp2-x11 xvfb xdotool >/dev/null 2>&1 \
  && echo "    ✓ Công cụ RDP." || echo "    (Bỏ qua RDP — cài sau nếu cần.)"

echo "==> [8/8] Kiểm tra sức khoẻ (chờ backend khởi động)"
OK=""
for i in $(seq 1 20); do
  if curl -s "http://127.0.0.1:$PORT/health" | grep -q '"status"'; then OK="1"; break; fi
  sleep 1
done

echo ""
echo "============================================================"
if [ -n "$OK" ]; then
  echo " ✅ XONG! KENIOS đã cài & đang chạy ($NEW_COMMIT)."
else
  echo " ⚠️ Đã cài xong nhưng health chưa trả lời — xem log:"
  echo "     journalctl -u kenios -n 40 --no-pager"
fi
echo " 🌐 URL backend:  http://$PUBLIC_IP"
echo " 👤 Admin:  $ADMIN_USER"
if [ -n "$GEN_PASS" ]; then
  echo " 🔑 Mật khẩu admin (TỰ SINH — lưu lại ngay):  $ADMIN_PASS"
else
  echo " 🔑 Mật khẩu admin:  (mật khẩu anh đã truyền qua ADMIN_PASS)"
fi
echo ""
echo " Bước tiếp theo:"
echo "   • Trỏ tên miền app.kenios.store về IP này ($PUBLIC_IP) rồi cài SSL:"
echo "       apt install -y certbot python3-certbot-nginx && certbot --nginx -d app.kenios.store"
echo "   • Vào app → Quản trị: nhập lại Token bot Telegram, Ngân hàng, API key AI, sản phẩm."
echo "   • Cập nhật code mới sau này:"
echo "       bash <(curl -s https://raw.githubusercontent.com/minhchien434850-hash/Fkfkfk/$BRANCH/capnhat-vps.sh)"
echo "============================================================"
rm -rf /root/kenios-src
