#!/usr/bin/env bash
# ============================================================================
#  Tạo TÀI KHOẢN ADMIN mới cho cổng Guacamole (dùng REST API — hash đúng chuẩn).
#  KHÔNG lưu mật khẩu vào repo: truyền qua tham số hoặc nhập khi được hỏi.
#
#  Cách dùng (trên VPS):
#     cd /root/Fkfkfk/remote-gateway
#     bash add-admin.sh                 # rồi nhập tài khoản/mật khẩu khi được hỏi
#     bash add-admin.sh kenios 'matkhau' # hoặc truyền thẳng
#
#  Admin cũ mặc định: guacadmin/guacadmin. Nếu đã đổi, truyền thêm:
#     bash add-admin.sh kenios 'matkhau' guacadmin 'matkhaucu'
# ============================================================================
set -e

GUAC="${GUAC_URL:-http://localhost:8080}"
NEWU="$1"
NEWP="$2"
OLDU="${3:-guacadmin}"
OLDP="${4:-guacadmin}"

if [ -z "$NEWU" ]; then read -p "Tai khoan moi: " NEWU; fi
if [ -z "$NEWP" ]; then read -p "Mat khau moi: " NEWP; fi

echo "[*] Dang nhap admin cu ($OLDU) de lay token..."
TOKEN=$(curl -s -d "username=${OLDU}&password=${OLDP}" "${GUAC}/api/tokens" \
  | sed -n 's/.*"authToken":"\([^"]*\)".*/\1/p')

if [ -z "$TOKEN" ]; then
  echo "[!] Dang nhap admin cu THAT BAI. Kiem tra lai tai khoan/mat khau guacadmin."
  exit 1
fi

echo "[*] Tao tai khoan: $NEWU"
curl -s -o /dev/null -w "  -> tao user: HTTP %{http_code}\n" \
  -X POST "${GUAC}/api/session/data/postgresql/users?token=${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${NEWU}\",\"password\":\"${NEWP}\",\"attributes\":{}}"

echo "[*] Cap quyen ADMIN cho: $NEWU"
curl -s -o /dev/null -w "  -> cap quyen: HTTP %{http_code}\n" \
  -X PATCH "${GUAC}/api/session/data/postgresql/users/${NEWU}/permissions?token=${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '[{"op":"add","path":"/systemPermissions","value":"ADMINISTER"},{"op":"add","path":"/systemPermissions","value":"CREATE_CONNECTION"},{"op":"add","path":"/systemPermissions","value":"CREATE_USER"}]'

echo ""
echo "============================================================"
echo "  XONG! Dang nhap cong http://IP_VPS:8080 bang:"
echo "     Tai khoan: $NEWU"
echo "  (Tai khoan guacadmin cu van con — vao Settings -> Users de xoa neu muon)"
echo "============================================================"
