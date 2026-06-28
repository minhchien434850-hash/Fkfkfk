#!/usr/bin/env bash
# ============================================================
#  capnhat-vps.sh — Cập nhật backend KENIOS lên bản mới nhất
#  Chạy bất cứ lúc nào (1 lệnh duy nhất):
#
#    bash <(curl -s https://raw.githubusercontent.com/minhchien434850-hash/Fkfkfk/claude/read-branch-file-2lxkte/capnhat-vps.sh)
#
# ============================================================
set -e
BRANCH="claude/read-branch-file-2lxkte"
REPO="https://github.com/minhchien434850-hash/Fkfkfk.git"
WORK="/root/kenios"

echo "==> Tải code mới nhất từ GitHub..."
cd /root
rm -rf kenios-new
git clone -q -b "$BRANCH" "$REPO" kenios-new

echo "==> Chép backend mới đè lên..."
cp kenios-new/backend/kenios.py "$WORK/kenios.py"
rm -rf kenios-new

echo "==> Khởi động lại dịch vụ..."
systemctl restart kenios
sleep 2

echo "==> Kiểm tra sức khoẻ:"
if curl -s http://127.0.0.1/health | grep -q '"status"'; then
  echo ""
  echo "✅ XONG! Backend đã cập nhật & đang chạy."
else
  echo ""
  echo "⚠️  Chưa thấy phản hồi health. Xem log: journalctl -u kenios -n 30 --no-pager"
fi
