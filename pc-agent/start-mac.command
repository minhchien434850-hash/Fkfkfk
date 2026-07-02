#!/bin/bash
# KENIOS PC Remote Agent — chạy trên macOS (nhấp đúp để chạy)
cd "$(dirname "$0")"

echo "============================================================"
echo "  KENIOS PC Remote Agent - macOS"
echo "============================================================"

if ! command -v python3 >/dev/null 2>&1; then
  echo "[!] Chưa có Python 3. Cài tại: https://www.python.org/downloads/"
  read -n1 -r -p "Nhấn phím bất kỳ để thoát..."
  exit 1
fi

echo "[1/2] Cài thư viện..."
python3 -m pip install --upgrade pip >/dev/null 2>&1
python3 -m pip install fastapi uvicorn pyautogui mss pillow

read -p "Đặt TÀI KHOẢN (vd admin): " PC_USER
read -p "Đặt MẬT KHẨU: " PASSWORD
export PC_USER="${PC_USER:-admin}"
export PASSWORD="${PASSWORD:-kenios}"

echo "[2/2] Đang chạy agent (cổng 8765)..."
echo "  Lưu ý: vào Cài đặt hệ thống → Quyền riêng tư & Bảo mật → cấp"
echo "  Trợ năng (Accessibility) + Ghi màn hình cho Terminal."
python3 pc_remote.py
