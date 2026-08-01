#!/bin/bash
# KENIOS PC Agent — chạy trên macOS (nhấp đúp để chạy)
cd "$(dirname "$0")"

echo "============================================================"
echo "  KENIOS PC Agent - điều khiển máy này từ app/web KENIOS"
echo "============================================================"

if ! command -v python3 >/dev/null 2>&1; then
  echo "[!] Chưa có Python 3. Cài tại: https://www.python.org/downloads/"
  read -n1 -r -p "Nhấn phím bất kỳ để thoát..."
  exit 1
fi

echo "[1/2] Cài thư viện..."
python3 -m pip install --upgrade pip >/dev/null 2>&1
python3 -m pip install requests pyautogui mss pillow

echo "[2/2] Đang chạy agent (sẽ hỏi Tài khoản + Mật khẩu KENIOS)..."
echo "  Lưu ý: Cài đặt hệ thống → Quyền riêng tư & Bảo mật → cấp"
echo "  Trợ năng (Accessibility) + Ghi màn hình cho Terminal."
echo "  Sau khi đăng nhập: mở app KENIOS → Khám phá → Windows App để điều khiển."
python3 pc_remote.py
