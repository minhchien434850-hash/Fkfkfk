#!/usr/bin/env bash
# ============================================================
#  CHAY-VPS.sh — File GỐC chạy KENIOS Backend trên VPS
#  (đã gồm: App bán hàng, nạp tiền tự động ACB, bán key/acc game)
#
#  CÁCH CHẠY (chỉ 3 bước):
#    1) Tải code về VPS:
#         git clone -b claude/app-issues-repo-creation-px0q60 <LINK_REPO> kenios
#         cd kenios
#    2) Cấp quyền & chạy:
#         chmod +x CHAY-VPS.sh
#         sudo ADMIN_PASS='matkhau_cua_ban' bash CHAY-VPS.sh
#    3) Mở app → nhập URL hiện ở cuối màn hình → đăng nhập admin.
#
#  Sau khi chạy xong, vào app: Quản trị → Thông tin ngân hàng →
#  dán "API token ACB (thueapibank.vn)" rồi Lưu để bật nạp tiền tự động.
# ============================================================
set -eo pipefail

ADMIN_USER="${ADMIN_USER:-kenios}"
ADMIN_PASS="${ADMIN_PASS:-admin1999@}"
PORT="${PORT:-8000}"
WORK_DIR="${WORK_DIR:-/root/kenios}"
SECRET="${CODEBOX_SECRET:-$(openssl rand -hex 32)}"

# Cho phép bật nạp tiền tự động ngay khi cài (tuỳ chọn): ACB_API_TOKEN='...'
ACB_API_TOKEN="${ACB_API_TOKEN:-}"

echo "==> Cài đặt KENIOS backend vào $WORK_DIR (port $PORT)"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC=""
if [ -f "$SCRIPT_DIR/backend/kenios.py" ]; then SRC="$SCRIPT_DIR/backend/kenios.py";
elif [ -f "$SCRIPT_DIR/kenios.py" ]; then SRC="$SCRIPT_DIR/kenios.py";
else echo "❌ Không tìm thấy kenios.py (đặt file này cùng repo)."; exit 1; fi

apt update -y
apt install -y python3 python3-venv python3-pip nginx ffmpeg curl git unzip

mkdir -p "$WORK_DIR"
cp "$SRC" "$WORK_DIR/kenios.py"
cd "$WORK_DIR"

python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install "fastapi>=0.110" "uvicorn[standard]>=0.29" "httpx>=0.27" \
            "cryptography>=42" "python-multipart>=0.0.9" "TikTokLive>=6.0" \
            "aiosmtpd>=1.4" "yt-dlp" "pypdf" "python-docx" "openpyxl" || true

cat > "$WORK_DIR/.env" << EOF
CODEBOX_SECRET=$SECRET
ADMIN_USER=$ADMIN_USER
ADMIN_PASS=$ADMIN_PASS
PORT=$PORT
ACB_API_TOKEN=$ACB_API_TOKEN
EOF

tee /etc/systemd/system/kenios.service > /dev/null << EOF
[Unit]
Description=KENIOS Backend
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=$WORK_DIR
EnvironmentFile=$WORK_DIR/.env
# 1 worker: TikTok-live & nạp tự động ACB dùng bộ nhớ/luồng nền trong 1 tiến trình
ExecStart=$WORK_DIR/venv/bin/uvicorn kenios:app --host 0.0.0.0 --port $PORT --workers 1
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kenios
systemctl restart kenios

# Nginx reverse proxy — KHÔNG giới hạn dung lượng upload (client_max_body_size 0)
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_IP")
tee /etc/nginx/sites-available/kenios > /dev/null << EOF
server {
    listen 80;
    server_name $PUBLIC_IP _;
    client_max_body_size 0;
    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 1800s;
        proxy_send_timeout 1800s;
    }
}
EOF
ln -sf /etc/nginx/sites-available/kenios /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
nginx -t && systemctl reload nginx

sleep 2
echo ""
echo "============================================================"
echo " ✅ XONG! URL backend:  http://$PUBLIC_IP"
echo " 👤 Admin: $ADMIN_USER  (mật khẩu bạn đã đặt qua ADMIN_PASS)"
echo " 🔎 Health: $(curl -s http://127.0.0.1:$PORT/health 2>/dev/null || echo FAIL)"
echo ""
echo " Lệnh hữu ích:"
echo "   systemctl restart kenios     # khởi động lại"
echo "   journalctl -u kenios -f      # xem log realtime"
echo ""
echo " Cập nhật code mới sau này:"
echo "   cd <repo> && git pull && cp backend/kenios.py $WORK_DIR/kenios.py && systemctl restart kenios"
echo "============================================================"
