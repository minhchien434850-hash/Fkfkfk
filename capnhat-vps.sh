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

# Cài thư viện SSH (asyncssh) cho tính năng Remote Server — nếu thiếu thì cài, có rồi thì bỏ qua.
echo "==> Đảm bảo thư viện asyncssh (cho SSH/Remote Server)..."
if [ -x "$WORK/venv/bin/pip" ]; then
  "$WORK/venv/bin/pip" install -q "asyncssh>=2.14" 2>/dev/null \
    && echo "    ✓ asyncssh sẵn sàng." \
    || echo "    ⚠️ Cài asyncssh chưa được (tính năng SSH sẽ báo lỗi cho tới khi cài)."
else
  pip install -q "asyncssh>=2.14" 2>/dev/null || true
fi

# Cài zsign (KÝ IPA ở máy chủ để cài OTA) — nếu thiếu thì build.
echo "==> Đảm bảo zsign (ký IPA)..."
if ! command -v zsign >/dev/null 2>&1; then
  apt-get install -y -qq git g++ pkg-config libssl-dev zip unzip >/dev/null 2>&1 || true
  rm -rf /opt/zsign
  git clone -q --depth 1 https://github.com/zhlynn/zsign.git /opt/zsign 2>/dev/null || true
  ( cd /opt/zsign/build/linux 2>/dev/null && make >/dev/null 2>&1 && cp -f zsign /usr/local/bin/zsign ) \
    || ( cd /opt/zsign 2>/dev/null && g++ *.cpp common/*.cpp -o /usr/local/bin/zsign -lcrypto -std=c++14 -O3 -I. >/dev/null 2>&1 ) \
    || true
  command -v zsign >/dev/null 2>&1 \
    && echo "    ✓ zsign sẵn sàng." \
    || echo "    ⚠️ Build zsign chưa được — cài thủ công (github.com/zhlynn/zsign) rồi để vào /usr/local/bin/zsign."
else
  echo "    ✓ zsign đã có."
fi

# Cài thư viện PUSH APNs (gửi thông báo cả khi tắt app) — nếu thiếu thì cài.
echo "==> Đảm bảo thư viện APNs (PyJWT + httpx[http2])..."
if [ -x "$WORK/venv/bin/pip" ]; then
  "$WORK/venv/bin/pip" install -q "pyjwt[crypto]>=2.8" "httpx[http2]>=0.27" 2>/dev/null \
    && echo "    ✓ Thư viện APNs sẵn sàng." \
    || echo "    ⚠️ Cài thư viện APNs chưa được (push sẽ báo lỗi tới khi cài)."
else
  pip install -q "pyjwt[crypto]>=2.8" "httpx[http2]>=0.27" 2>/dev/null || true
fi

# Cài công cụ CẦU NỐI RDP (điều khiển máy thuê chỉ bằng IP+user+pass) — thiếu thì cài.
echo "==> Đảm bảo công cụ RDP (FreeRDP + Xvfb + ffmpeg + xdotool)..."
if ! command -v xfreerdp >/dev/null 2>&1 || ! command -v Xvfb >/dev/null 2>&1 \
   || ! command -v ffmpeg >/dev/null 2>&1 || ! command -v xdotool >/dev/null 2>&1; then
  (apt-get update -qq && apt-get install -y -qq freerdp2-x11 xvfb ffmpeg xdotool >/dev/null 2>&1 \
     && echo "    ✓ Đã cài công cụ RDP.") \
     || echo "    ⚠️ Cài công cụ RDP chưa được (tính năng 'Kết nối bằng IP' sẽ báo cho tới khi cài xong)."
else
  echo "    ✓ Công cụ RDP đã sẵn sàng."
fi

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

# Backend nạp nhiều thư viện (TikTokLive, yt-dlp...) nên có thể mất vài giây mới
# trả lời. Thử lại tối đa ~20 giây, kiểm tra CẢ cổng 8000 (uvicorn) lẫn cổng 80 (nginx).
echo "==> Kiểm tra sức khoẻ (chờ backend khởi động)..."
OK=""
for i in $(seq 1 20); do
  if curl -s http://127.0.0.1:8000/health | grep -q '"status"' \
     || curl -s http://127.0.0.1/health | grep -q '"status"'; then
    OK="1"; break
  fi
  sleep 1
done

echo ""
if [ -n "$OK" ]; then
  echo "✅ XONG! Backend đã cập nhật ($NEW_COMMIT) & đang chạy."
  echo "   → Vào app lấy lại mã OTP mới để thấy email nội dung mới."
elif systemctl is-active --quiet kenios; then
  echo "✅ Dịch vụ kenios ĐANG CHẠY ($NEW_COMMIT) — nhưng health chưa trả lời."
  echo "   Có thể backend còn đang khởi động. Thử lại sau 10 giây:"
  echo "     curl -s http://127.0.0.1:8000/health; echo"
else
  echo "⚠️  Dịch vụ kenios CHƯA chạy được. Xem log lỗi:"
  echo "     journalctl -u kenios -n 30 --no-pager"
fi
