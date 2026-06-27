#!/usr/bin/env bash
# ============================================================
#  backup-db.sh — Sao lưu database + file upload của KENIOS
#  Chạy định kỳ bằng cron/systemd timer trên VPS.
# ============================================================
set -eo pipefail

# Thư mục cài backend (chứa kenios.db + uploads/). Đổi nếu bạn cài nơi khác.
WORK_DIR="${WORK_DIR:-/root/kenios}"
DB_FILE="${CODEBOX_DB:-$WORK_DIR/kenios.db}"
UPLOAD_DIR="$WORK_DIR/uploads"
BACKUP_DIR="${BACKUP_DIR:-$WORK_DIR/backups}"
KEEP_DAYS="${KEEP_DAYS:-14}"          # giữ bản sao lưu trong bao nhiêu ngày

STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "▸ Sao lưu KENIOS lúc $STAMP"

# 1) Database — dùng 'sqlite3 .backup' để bản sao nhất quán kể cả khi app đang chạy
if [ -f "$DB_FILE" ]; then
    OUT_DB="$BACKUP_DIR/kenios-$STAMP.db"
    if command -v sqlite3 >/dev/null 2>&1; then
        sqlite3 "$DB_FILE" ".backup '$OUT_DB'"
    else
        cp "$DB_FILE" "$OUT_DB"   # dự phòng nếu chưa cài sqlite3
    fi
    gzip -f "$OUT_DB"
    echo "  ✓ DB → $OUT_DB.gz"
else
    echo "  ⚠ Không thấy DB tại $DB_FILE"
fi

# 2) File upload (ảnh/video/bản tải) — nén nếu thư mục tồn tại & không rỗng
if [ -d "$UPLOAD_DIR" ] && [ -n "$(ls -A "$UPLOAD_DIR" 2>/dev/null)" ]; then
    OUT_UP="$BACKUP_DIR/uploads-$STAMP.tar.gz"
    tar -czf "$OUT_UP" -C "$WORK_DIR" uploads
    echo "  ✓ Uploads → $OUT_UP"
fi

# 3) Dọn bản sao lưu cũ hơn KEEP_DAYS ngày
find "$BACKUP_DIR" -type f \( -name 'kenios-*.db.gz' -o -name 'uploads-*.tar.gz' \) \
    -mtime "+$KEEP_DAYS" -delete 2>/dev/null || true

echo "▸ Xong. Các bản sao lưu hiện có:"
ls -lh "$BACKUP_DIR" | tail -n +1
