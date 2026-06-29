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

echo "==> Tải code mới nhất từ GitHub (branch: $BRANCH)..."
cd /root
rm -rf kenios-new
git clone -q -b "$BRANCH" "$REPO" kenios-new
NEW_COMMIT="$(cd kenios-new && git rev-parse --short HEAD)"
echo "    Commit mới nhất: $NEW_COMMIT"

echo "==> Chép backend mới đè lên..."
cp kenios-new/backend/kenios.py "$WORK/kenios.py"

# Xoá cache bytecode cũ (lý do hay gặp: restart nhưng vẫn chạy code cũ)
echo "==> Xoá cache Python cũ..."
rm -rf "$WORK/__pycache__" 2>/dev/null || true
find "$WORK" -name "*.pyc" -delete 2>/dev/null || true

# Kiểm tra file mới có đúng nội dung email OTP mới không (mốc nhận biết)
echo "==> Kiểm tra nội dung email OTP mới..."
if grep -q "EULA của Apple" "$WORK/kenios.py"; then
  echo "    ✓ Đã có nội dung email mới (kèm Điều khoản & Chính sách Apple)."
else
  echo "    ⚠️ Không thấy nội dung email mới trong file — kiểm tra lại branch/đường dẫn $WORK."
fi

rm -rf kenios-new

echo "==> Khởi động lại dịch vụ..."
systemctl restart kenios
sleep 2

echo "==> Kiểm tra sức khoẻ:"
if curl -s http://127.0.0.1/health | grep -q '"status"'; then
  echo ""
  echo "✅ XONG! Backend đã cập nhật ($NEW_COMMIT) & đang chạy."
  echo "   → Vào app lấy lại mã OTP mới để thấy email nội dung mới."
else
  echo ""
  echo "⚠️  Chưa thấy phản hồi health. Xem log: journalctl -u kenios -n 30 --no-pager"
fi
