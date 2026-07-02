#!/usr/bin/env bash
# ============================================================================
#  KENIOS Remote Gateway (Apache Guacamole) — cài trên VPS Ubuntu
#  Biến VPS thành cổng RDP/VNC → HTML5. App KENIOS mở web này để điều khiển
#  bất kỳ máy nào (chỉ cần nhập IP + tài khoản + mật khẩu của máy đó).
#
#  Chạy 1 lệnh trên VPS:
#     cd /root/Fkfkfk/remote-gateway && sudo bash setup.sh
# ============================================================================
set -e

echo "============================================================"
echo "  KENIOS Remote Gateway (Guacamole) - Cai dat"
echo "============================================================"

# 1) Cài Docker nếu chưa có
if ! command -v docker >/dev/null 2>&1; then
  echo "[1/4] Cai Docker..."
  curl -fsSL https://get.docker.com | sh
else
  echo "[1/4] Docker da co."
fi

# Xác định lệnh docker compose (plugin mới hoặc bản cũ)
if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  echo "[!] Cai docker compose plugin..."
  apt-get update -y && apt-get install -y docker-compose-plugin
  DC="docker compose"
fi

cd "$(dirname "$0")"

# 2) Tạo mật khẩu CSDL ngẫu nhiên (lưu vào .env, KHÔNG đưa lên repo)
if [ ! -f .env ]; then
  echo "[2/4] Tao mat khau CSDL ngau nhien..."
  DB_PASSWORD="$(openssl rand -hex 24)"
  echo "DB_PASSWORD=${DB_PASSWORD}" > .env
else
  echo "[2/4] Da co .env, dung lai."
fi

# 3) Sinh file khởi tạo CSDL cho Guacamole (chỉ làm 1 lần)
if [ ! -f init/initdb.sql ]; then
  echo "[3/4] Sinh so do CSDL Guacamole..."
  mkdir -p init
  docker run --rm guacamole/guacamole:1.5.5 \
    /opt/guacamole/bin/initdb.sh --postgresql > init/initdb.sql
fi

# 4) Khởi động
echo "[4/4] Khoi dong Guacamole..."
$DC up -d

# In thông tin truy cập
IP="$(curl -s https://api.ipify.org || echo 'IP_VPS')"
echo ""
echo "============================================================"
echo "  DA XONG! Cong dieu khien chay tai:"
echo "     http://${IP}:8080/"
echo "  Dang nhap lan dau:  guacadmin  /  guacadmin"
echo "  >>> DOI MAT KHAU guacadmin NGAY sau khi vao (Settings)."
echo ""
echo "  Trong app KENIOS -> Kham pha -> Remote PC:"
echo "     - Dia chi cong:  http://${IP}:8080"
echo "     - Tai khoan/mat khau Guacamole (guacadmin...)"
echo "     - Them may: nhap IP + user + pass cua may can dieu khien"
echo "============================================================"
