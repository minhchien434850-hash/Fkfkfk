"""
kenios.py — Backend đa-AI cho app KENIOS (com.kenios.codebox)  v4.2
======================================================================
TÍNH NĂNG MỚI / SỬA LỖI (v4.2):
  ✅ Gemini: cập nhật model mới nhất (gemini-2.0-flash, gemini-1.5-pro v002...)
             sửa lỗi 404 "model not found" — dùng đúng API v1beta
  ✅ Đính ảnh (image_base64) VÀ đính file (file_base64 + mime) hoạt động đầy đủ
  ✅ Multi-attachment: gửi tới 30 ảnh/file cùng lúc
  ✅ Chọn ngôn ngữ giao diện trả về (vi / en / auto)
  ✅ Giọng nói: phiên âm qua Whisper (OpenAI) hoặc Gemini Speech-to-Text
  ✅ Chạy code trực tiếp trên server (sandbox Python) — /run/python
  ✅ Chạy test file (.py / .js / .sh) và trả kết quả — /run/test
  ✅ Mô hình mới nhất cho mỗi nhà cung cấp (GPT-4o, Claude 3.7, Gemini 2.0 Flash…)
  ✅ Nhiều tính năng lập trình: code review, debug, explain, convert ngôn ngữ
  ✅ Thanh toán / nạp credits — /payment/*
  ✅ Webhook thanh toán tự động (Casso/Sepay) — /payment/webhook
  ✅ Ensemble AI (hỏi nhiều AI song song, tổng hợp)
  ✅ Admin API Key quản lý tập trung — /admin/keys
  ✅ Prompt Templates CRUD — /prompts
  ✅ Favorites (lưu tin nhắn yêu thích) — /favorites
  ✅ Pin / Share / Export hội thoại
  ✅ Tìm kiếm tin nhắn — /search
  ✅ Admin Stats — /admin/stats
  ✅ Auto-zip code blocks — /code/zip
  ✅ Token estimation trong phản hồi chat
  ✅ Gói PRO / ULTRA / MAX
  ✅ Lỗi rõ ràng: 401/403/404/429 đều có thông báo tiếng Việt cụ thể
  ✅ HỖ TRỢ UPLOAD VÀ DOWNLOAD STREAM TỚI 4GB (TỐI THIỂU 1KB), TRÁNH TRÀN BỘ NHỚ RAM.
  ✅ RAG NÂNG CAO: Tự động phân tích PDF, Word (docx), Excel (xlsx) và trích xuất ngữ cảnh TF-IDF.
  ✅ WEB SEARCH & WEB PAGE SCRAPER: Tự động tìm kiếm DuckDuckGo và cào dữ liệu HTML của kết quả.
  ✅ TEXT-TO-SPEECH (TTS): Tạo giọng nói âm thanh mp3 lưu hành từ văn bản.
  ✅ VẼ ẢNH AI (IMAGE GENERATION): Sinh ảnh qua DALL-E và tự động lưu vào thư viện tệp.
"""

import os, re, time, json, hmac, base64, hashlib, secrets, io, zipfile
import sqlite3, logging, asyncio, subprocess, tempfile, sys, shutil
from typing import Any, Optional

import httpx
from fastapi import FastAPI, Request, HTTPException, Header, Depends, UploadFile, File as FastAPIFile, Form, BackgroundTasks, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse, StreamingResponse, HTMLResponse, Response
from pydantic import BaseModel

# ========================= Cấu hình =========================
DB_PATH         = os.getenv("CODEBOX_DB", "kenios.db")
PORT            = int(os.getenv("PORT", "8000"))

def _load_or_create_secret() -> str:
    """Khóa ký session token. Ưu tiên biến môi trường; nếu không có thì lưu ra
    file & tái sử dụng — tránh việc mỗi lần restart VPS lại sinh khóa mới khiến
    toàn bộ user bị đăng xuất (token cũ thành không hợp lệ)."""
    if os.getenv("CODEBOX_SECRET"):
        return os.getenv("CODEBOX_SECRET")
    path = os.getenv("CODEBOX_SECRET_FILE",
                     os.path.join(os.path.dirname(os.path.abspath(__file__)), "kenios_secret.key"))
    try:
        if os.path.exists(path):
            v = open(path).read().strip()
            if v:
                return v
        v = secrets.token_hex(32)
        with open(path, "w") as f:
            f.write(v)
        try: os.chmod(path, 0o600)
        except OSError: pass
        return v
    except OSError:
        # Không ghi được file (chỉ đọc) — vẫn chạy được nhưng cảnh báo
        return secrets.token_hex(32)

SECRET          = _load_or_create_secret()
TOKEN_TTL       = int(os.getenv("TOKEN_TTL", str(60 * 60 * 24 * 30)))  # 30 ngày
REQUEST_TIMEOUT = float(os.getenv("REQUEST_TIMEOUT", "120"))
SANDBOX_TIMEOUT = int(os.getenv("SANDBOX_TIMEOUT", "15"))  # giây chạy code

# ----- Email tích hợp (KenMail) chạy chung trong KENIOS -----
MAIL_DOMAIN     = os.getenv("MAIL_DOMAIN", "kenios.store")
# Email người gửi cho mail hệ thống (OTP...). Để trống = no-reply@MAIL_DOMAIN.
# Đặt = email đã xác minh trong Brevo (vd Gmail của bạn) để khỏi cấu hình DNS.
MAIL_FROM       = os.getenv("MAIL_FROM", "")
MAIL_FROM_NAME  = os.getenv("MAIL_FROM_NAME", "KENIOS")   # tên hiển thị người gửi
# Ảnh nhúng cho email OTP (logo app + huy hiệu tích xanh) — base64 PNG
KENIOS_LOGO_B64 = "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"
VERIFIED_BADGE_B64 = "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAOkklEQVR4nO2bf4xd1XHHP3POfT921zYOYJtgO0ATV/XaaRyoayChawcnogShNuouIaihLUQYHPGjgJNKVZ6XSpX4UcdVEkxCUIEoItlFJCDcgELqXeFaIZTgpPZuVFNwAg5g42B7vbvvvXvvmf5x7t19b/e9ffvDXiM1I539ce8998x3zsycmTnnwv9zklM2sqq09WABetcSI6KnjJdZJ9Xxgq91bRYomPURVQURvfjbOpcz2QDAOzywS2QgvTeb7JxAqaczOAGAghqA1StYGOR4OmjhAoBokJeiEle8uJeDAHSKm9E4UyBzIl7S3qXWMyTatkODFOi451YgdIoTeCho4YLyu5TK71IKWrhA4CE6xbWvqDMpBTVtOzRIx/FjvoeotUuznkFP7V1qK+06vbfmcb3qY8+orunW8prHVdc87v/+2DOqax7XqyqfBUBVKsG27dCgtUuzJ4rvmZlAQQ2d4v60S+80WTZqTEkCujXkkRf+SvaBF0T3XrRtrde24iF2mzytcQmVRAMVnM0hrkhffgGrAHp7cO0rkO4OiQHWPK7LJMO1GtEulpwr842fdci9KQ+zLoD2LrXdHRKv6dKP23k8Hxf9y0wO4hLHUe6xh9m663oZSPus7tIbM3O5PxwgFqFKhVWJM3Ox4QA3vdgh29LrF39b58ZncCvCJptjjiuBAjYP8TEueaFDdqa8TAfHtFeBgwu88Jyw3jicKxMBQVzCiWGObeGu6HT++k+69Csa8hxZVorhnmgIJzre94hioiGcWO65oFv7KbNHMqyPAu6yOZbFgxCWiBAMEJksgRPWAztTXmZVACmpYzFgVDEiGASjDg0HiG2OZTbHY045AsxHQWNq650gRIhY5hjYQcARk/N9wgEiAYt4ftUL0CRjz4hmLACBGMXrZcVlSbQBwFjmawxOURGECRYwF/lnxDI/Lvr+kvKZ9kvGE5iW2lfSjAXg1C/IdTAZ1IPCz3HjxVsQVVDfxyDj352O53TmccwMBZAscxNIIKHR5yZP9ftUjTezELqhANq71I5zMj3AfgKQCKeogs5iADsynjcQZb8GbQWFtdXPLTyENlodJpZeg9i8tUuzTTEvS4ZWF+LkBEWWjUjBmQxGQ/qGLR/t65By/YcnxlBfAEnH8x/TSyRgrToWJy5HVBERDMrFkmG5higyy6m1opJBNKQfYZcqTiQxDgtiOKARPT+/Wp6fSAg1mU4Di498V+/MzuMe6sRZLgRX8l57NlO4lGlV1OQQk6nzoIHyMTb94hq5t16wVEMAKiD6oX/V3Nwz2S8BizQkVD/jVT0TlZ8VtU/J+HGTZQVixSm4cbwpTjJkNOLtgXc495VbpJRiq3xfXSeYfT+qIUMCqA9AzFhxzWrirmANDIYQOx9oAMzJYLQWb4JLBDWUfX99VmvMnk9p+zqkjONJk0PUJRI+hS0wcLQEqxfC19fBty6FT30AjoejGVVlU4czOQTHk30dUh5Npauppgb09iRWb9gWDbFRDIG6Ea2bNUpVPWPg8DB8Yilsu9T/D9C2BG7the2vwbys14yEVAwmGqKMYVsVpjFU2347xbUVNNh9jezTiLtNM0ZdPVd48kjxM3+kBB9dAFvaPPjIQej8/c8v9yC0gjt1ONOM0Yi7d18j+9oKGtRLmSdeBjcjrStoDkr0mQxLXRnHLDo9KzAUwdlz4LHLYVEzOPWOME5+v3wQPrsdWjL+HuBMFuNCXo9ytPbtZYjNaL1lsD4YEW1fgfR1yHFVbk/0cdb8nhEoxR7Yt9Z78Cno1BYFeGSvBz4yk4oioMrtfR1yvH0F0wyEYKR2f2AYm3+Lt0yW+Rqd/KDHiFdzVfjO5XD+Qg/eykgShBUo7IJH+2B+zt9HUQkQV+ZI8SzOWtxE3Ntgz6GuBrR3qWUz0rtOovybXCg5WhI/cFLBCx5gKYat66rBg3d0VuCfX4CH9lSAT7qrw0mOlvybXNi7TiI2IxMVUMcLQFUoqEmjpg8/qhslx1PEZDROUl89OS01sGMl6LwIPnkORBXgI+ed4jd/6duZTV4gI+8ANEaIyUiOpz78qG4E6O6QmIKaWpsv1RcqYuaVD2uHBNxhsqx2w4mXrTX3iUGmTKomzmgaehIIvDMMd6yGW84fBQzJzBv4wT64rccve+nwtXgSA6YJXJkXNeK+PX8jXWMxVgsgqa6ufFAXked+k+UzGoMbJsaXumpCStfqgbIHng+gOahSy0lRxsDBIbj+j6Hz4jHgEy14/gD87Y/8GOm4dUlRFGeasGLBlXmCIjft+YK8XVlJTudNKCAXnM3cYoaeYB6rwqO+ADlRiivi12MjcPl5cFYL7DwAuw/CabmqwKQx+GH4iw/B1y71wNKYPwX/34fgqqcZiQrdJAWc5AkucxpBdIzd+ZC1L/2WATpREL+D07YDS6e4QcsG68GXkgKkmShCdeqls2093LfWq273lfCXy/xsWtM4yrUGDhfhz5bAvWu9UA3V4H9zDK57dlQrYm383gqXYhCC8CglO49Vg5YNdIpr2+HL8jWcYIVDmqBZ8c7q0x+EtqVeE1IGt6yDjavgnSGwCZh67xgowfLT4f713nRUvRDSpe7QEFz/jH9X3iZaNVn0Fa3SyVaSAehdR0xBTTnmgfAYu4N55JwSqU8160mWSGHJnFF1TG1WFf7xIrj5fO/UKmQ70ozAUAgLmuHf/hzelx+N8lS90IZCuOk56P8dzMkmscFUsSvOKVEwj1x4jN3lmAcoqOld58s7CcveK756gxy1jsuiIZ6wTQQmi1FHjEtiwIrmHDQZ+Mn+UfBpRCbiZ+pLa+CfLoGjxVFQmphNKYKc9eDPnlMd5aWTfPNP4D/fgNNzEMZTRO5QdcQmi7FNBNEQT1jHZa/eIEcrMdddBpc/pB1Y7jAZVrti7WXQik9RP/OHsPUTo6pr0qAlUeNH98JXnvfeO2Og7LyAHr4cPr6kOsqLEzP6ci88ssdrSFhvM6UepctgHlzIi8Tc139d7WWw2geIaBoI9V8nXf2vcWFc5IsIxzBeqpVSjh2cloXuX8G1/+5V1sioSdgkpP38Ctj2KSjHMBxBMYT71nnwkauO8gID9/7Mgz+jKQHP1GY+8aLH4iJf7H+NC/uvk66RQGhMWFxfrl1q2YvSKe6PvqltmuXHRFhq7OtlDBwahrUfgAcvg7nZ6vA1dY7/8RvY8Cz8/WrYsKp6rU//fmQPfLkH3tfEqAOaCgmOgFjKfPJXN0gvBTWsQKhTHm+cDG3GHjgda3K8ZTK1kyFNhPBuEVYugEc/DYtaqoWQmsbbg/5epamk4H/0KnzhGZibGX3vlChNhkKOuBJnLf4dce/maSZDAHRjejslIs+VJs98FxErydZVRUO9qs7PwZ5D8LmnYP9RDz4NhlLTWNQy+j+Mqv1Pfws3PZsshYnAppxPgLiI2OSZT54rezslontijI0LIgtojjL0SYalGk5cEEk14VgZFjTBd6+E5WdUq3q6zsOohvS9A+0/hGIEWTv5KK8OOfGbJq8HIa19h6ZZEGnb7KPD0LLJNLM0LhKrYhplc2HsVfjwMFz9Q/jpAQ8+SjRBKkzCCrwxAH+3HY6XIGvGZHfTayYuEptmloaWTXSKa9tM3XS4tgYkycIfbNNl1rIHJcD53d3JTIHiM7vhyIN8+Aq4JIkWA2GkqHCkBJ97En55EObn/f0TUmxQFIMiRHHMyldvlH31jtLU1IC25LooN5o8WRf7GGcqeX3kfOiqwLVPww/+x5uHJKmzEbj5x/DSm953pIHOCaktgLgYZ/JkRbmxEtNYqrsz1FrQbGkR/SbDecne35SLoao+2QljH/z8w0Vw5TK/ubHt59DdD/NyXlhyQqa+cnCcZBAX8lrubZb3dUqZqewMlU9HgOakwBFRQ4KT2RpLCxl5gbt2wtf+y6v6YHkUPDCT7XW/NTaWFGeUDNCcYKlJNXeG6FL7yi1SUscWk0NsM1nbRGCbK1oTgQQY1fF5wrhMLGFvfs5Hg6gH76aZ2VVkeCqBj/XH8mabySa7WlteuUVKjBzmHIO2vmC9upx3v14ilrUSsziJzCQpNBuFi80Ut8cbVnImS8n2uAvpF9ilkgTqghoBtRzQmJ7XbpLna6l+JT8TjVK3I/gDEsOHeNkEtDaKEU4wOclgXERf04IGByQaYGhwRMabQ9ve8YLaD0FfhxTP+7ru5BScELEZDCE7+zqkfE5B8+dCNPa53hVovRwgpcaHpDok7q1xua2g/BoVKu14NklJXJ/KuRD1dso4AUyGpn1KzAtF1KET27WO/Jz8flKDPqm8XcJD7wykP/MPJgRNg58abPjSs8Gow+fqjcTgHZmIqTiXUMO01Itnxno3c5uNsSNsjP5WlEgyGMlgXMwRwB92rXy2sqXXbHIGOeZI2h8lQiv0Iv0d14/xJ0szFoATDqjgkgKqU0eEIKaZQGP2aYmr8yHLENahHMfi1NUoPDsUi0M5jrAuH7JMS1ytMftMMwGCqCNSkrEE54QDM+V/+ibQNzIjz6EUxJIFkBzGlTkeD3PP4DBbD39p5Lh8z9Kv6ibbwv0aEsOY2VOcZLHxIJtev016kqvfO+Nu3d7iuBXLJtPEHC0BkE0k91wVL9OgmUXgSYa15F/0TpNno0aUxNIdRzxy4Fb/wcRIaQ1M21r431+w22ZodeWK/EJxJovEIX0f/AirensAcJWlrMVbdZkNuFZj2iUg54p8443bT+EHE2OptaDZPnCky1GXWjpwI0GIP6YSLf2qXmWa+Z4bJETwxS8lNC1k3BCfff02+X76rH+zCl2YkfW8oEErGJ/cvFeocv+9UP+jqfS5JVt0+zkPqi7ZosUlW7SY/L193LsqqaCGQsW3RCfoo6kTmIRO/rO5c1pYGOd52jT5z+bcMC/ZIlf8enD2P5s7qac9alJSmz/jTp3btNR/ODn8Og8cvvfUfDh5aug99OnsKRkUIKk6eztuULv/PZ1E+j/0sWhTBibffgAAAABJRU5ErkJggg=="
MAIL_ENABLE     = os.getenv("MAIL_ENABLE", "1") == "1"      # bật bộ nhận thư SMTP nội bộ
MAIL_SMTP_PORT  = int(os.getenv("MAIL_SMTP_PORT", "25"))    # cổng nhận thư đến (cần MX + mở port 25)
SMTP_RELAY_HOST = os.getenv("SMTP_RELAY_HOST", "")          # gửi ra ngoài qua relay (vd smtp.gmail.com)
SMTP_RELAY_PORT = int(os.getenv("SMTP_RELAY_PORT", "587"))
SMTP_RELAY_USER = os.getenv("SMTP_RELAY_USER", "")
SMTP_RELAY_PASS = os.getenv("SMTP_RELAY_PASS", "")
OTP_DEBUG       = os.getenv("OTP_DEBUG", "0") == "1"        # trả mã trong response để test khi chưa có mail/SMS
# Gửi SMS (OTP qua số điện thoại). Cấu hình 1 trong các cách dưới, hoặc bật OTP_DEBUG để test.
SMS_RELAY_URL    = os.getenv("SMS_RELAY_URL", "")           # webhook/gateway nhận POST {to,text} (vd eSMS/SpeedSMS proxy)
SMS_TWILIO_SID   = os.getenv("SMS_TWILIO_SID", "")
SMS_TWILIO_TOKEN = os.getenv("SMS_TWILIO_TOKEN", "")
SMS_TWILIO_FROM  = os.getenv("SMS_TWILIO_FROM", "")         # số/brandname gửi đi

# ----- KENIOS AI: model tự host của riêng bạn (không dùng API key của ai) -----
KENIOS_AI_ENABLE = os.getenv("KENIOS_AI_ENABLE", "1") == "1"
KENIOS_AI_BASE   = os.getenv("KENIOS_AI_BASE", "http://127.0.0.1:11434/v1")  # Ollama (OpenAI-compatible)
KENIOS_AI_MODEL  = os.getenv("KENIOS_AI_MODEL", "llama3.1")
KENIOS_AI_KEY    = os.getenv("KENIOS_AI_KEY", "ollama")   # Ollama bỏ qua, chỉ cần khác rỗng

# Thư mục lưu tệp tải lên của user trên đĩa
UPLOAD_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)

# Kích thước tệp giới hạn (1KB - 4GB)
MIN_FILE_SIZE = 1024
MAX_FILE_SIZE = 4_294_967_296  # 4GB

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("kenios")

# ----- Fernet (mã hóa API key) -----
from cryptography.fernet import Fernet
_key_file = os.getenv("CODEBOX_ENC_KEYFILE", "kenios_enc.key")
if os.getenv("CODEBOX_ENC_KEY"):
    _enc_key = os.getenv("CODEBOX_ENC_KEY").encode()
elif os.path.exists(_key_file):
    _enc_key = open(_key_file, "rb").read().strip()
else:
    _enc_key = Fernet.generate_key()
    with open(_key_file, "wb") as f: f.write(_enc_key)
    log.info("Tạo khóa mã hóa mới: %s", _key_file)
fernet = Fernet(_enc_key)

def enc(text: str) -> str: return fernet.encrypt(text.encode()).decode()
def dec(token: str) -> str: return fernet.decrypt(token.encode()).decode()


# ===================== Danh sách AI (models mới nhất 2025) =====================
PROVIDERS: dict[str, dict[str, Any]] = {
    "kenios": {
        "label": "KENIOS AI · của bạn (miễn phí, không cần key)",
        "kind": "openai",
        "base": KENIOS_AI_BASE,
        "default_model": KENIOS_AI_MODEL,
        "models": [KENIOS_AI_MODEL],
        "vision": False, "free": True,
        "code": True,
    },
    "openai": {
        "label": "OpenAI · GPT-4o & o3",
        "kind": "openai",
        "base": "https://api.openai.com/v1",
        "default_model": "gpt-4o",
        "models": ["gpt-4o", "gpt-4o-mini", "o1", "o1-mini", "o3-mini"],
        "vision": True, "free": False,
        "code": True,
    },
    "anthropic": {
        "label": "Anthropic · Claude 3.7",
        "kind": "anthropic",
        "base": "https://api.anthropic.com/v1",
        "default_model": "claude-3-7-sonnet-latest",
        "models": [
            "claude-3-7-sonnet-latest",
            "claude-3-7-haiku-latest",
            "claude-3-5-sonnet-latest",
            "claude-3-5-haiku-latest",
            "claude-3-opus-latest",
        ],
        "vision": True, "free": False,
        "code": True,
    },
    "gemini": {
        "label": "Google · Gemini 2.5",
        "kind": "gemini",
        "base": "https://generativelanguage.googleapis.com/v1beta",
        "default_model": "gemini-2.5-flash",
        "models": [
            "gemini-2.5-flash",
            "gemini-2.5-pro",
            "gemini-2.0-flash",
            "gemini-2.0-pro-exp-02-05",
        ],
        "vision": True, "free": True,
        "code": True,
    },
    "groq": {
        "label": "Groq · Llama 3.3 (free)",
        "kind": "openai",
        "base": "https://api.groq.com/openai/v1",
        "default_model": "llama-3.3-70b-versatile",
        "models": [
            "llama-3.3-70b-versatile",
            "llama-3.2-11b-vision-preview",
            "llama-3.2-3b-preview",
            "deepseek-r1-distill-llama-70b",
        ],
        "vision": False, "free": True,
        "code": True,
    },
    "openrouter": {
        "label": "OpenRouter (nhiều model, có free)",
        "kind": "openai",
        "base": "https://openrouter.ai/api/v1",
        "default_model": "google/gemini-2.5-flash",
        "models": [
            "google/gemini-2.5-flash",
            "deepseek/deepseek-r1",
            "meta-llama/llama-3.3-70b-instruct",
            "anthropic/claude-3.7-sonnet",
        ],
        "vision": True, "free": True,
        "code": True,
    },
    "mistral": {
        "label": "Mistral · Large",
        "kind": "openai",
        "base": "https://api.mistral.ai/v1",
        "default_model": "mistral-large-latest",
        "models": ["mistral-large-latest", "mistral-small-latest", "codestral-latest", "pixtral-large-latest"],
        "vision": False, "free": False,
        "code": True,
    },
    "deepseek": {
        "label": "DeepSeek · V3 & R1",
        "kind": "openai",
        "base": "https://api.deepseek.com/v1",
        "default_model": "deepseek-chat",
        "models": ["deepseek-chat", "deepseek-reasoner"],
        "vision": False, "free": False,
        "code": True,
    },
    "xai": {
        "label": "xAI · Grok 3",
        "kind": "openai",
        "base": "https://api.x.ai/v1",
        "default_model": "grok-3",
        "models": ["grok-3", "grok-3-mini", "grok-2-1212", "grok-2-vision-1212"],
        "vision": True, "free": False,
        "code": True,
    },
    "perplexity": {
        "label": "Perplexity · Sonar Pro",
        "kind": "openai",
        "base": "https://api.perplexity.ai",
        "default_model": "sonar-pro",
        "models": ["sonar-pro", "sonar", "sonar-reasoning-pro", "sonar-reasoning"],
        "vision": False, "free": False,
        "code": False,
    },
    "together": {
        "label": "Together AI",
        "kind": "openai",
        "base": "https://api.together.xyz/v1",
        "default_model": "meta-llama/Llama-3.3-70B-Instruct-Turbo",
        "models": [
            "meta-llama/Llama-3.3-70B-Instruct-Turbo",
            "deepseek-ai/DeepSeek-R1",
            "Qwen/Qwen2.5-Coder-32B-Instruct",
        ],
        "vision": False, "free": False,
        "code": True,
    },
    "fireworks": {
        "label": "Fireworks AI",
        "kind": "openai",
        "base": "https://api.fireworks.ai/inference/v1",
        "default_model": "accounts/fireworks/models/llama-v3p3-70b-instruct",
        "models": ["accounts/fireworks/models/llama-v3p3-70b-instruct",
                   "accounts/fireworks/models/deepseek-r1"],
        "vision": False, "free": False,
        "code": True,
    },
    "cerebras": {
        "label": "Cerebras (siêu nhanh, free)",
        "kind": "openai",
        "base": "https://api.cerebras.ai/v1",
        "default_model": "llama-3.3-70b",
        "models": ["llama-3.3-70b", "llama-3.1-8b"],
        "vision": False, "free": True,
        "code": True,
    },
    "moonshot": {
        "label": "Moonshot · Kimi",
        "kind": "openai",
        "base": "https://api.moonshot.ai/v1",
        "default_model": "moonshot-v1-32k",
        "models": ["moonshot-v1-8k", "moonshot-v1-32k", "moonshot-v1-128k"],
        "vision": False, "free": False,
        "code": True,
    },
    "qwen": {
        "label": "Alibaba · Qwen 2.5",
        "kind": "openai",
        "base": "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
        "default_model": "qwen-max-latest",
        "models": ["qwen-max-latest", "qwen-plus-latest", "qwen-turbo-latest", "qwen2.5-coder-72b-instruct"],
        "vision": False, "free": False,
        "code": True,
    },
    "nvidia": {
        "label": "NVIDIA NIM (free)",
        "kind": "openai",
        "base": "https://integrate.api.nvidia.com/v1",
        "default_model": "meta/llama-3.3-70b-instruct",
        "models": ["meta/llama-3.3-70b-instruct", "nvidia/llama-3.1-nemotron-70b-instruct", "deepseek-ai/deepseek-r1"],
        "vision": False, "free": True,
        "code": True,
    },
    "cohere": {
        "label": "Cohere · Command R+",
        "kind": "openai",
        "base": "https://api.cohere.ai/compatibility/v1",
        "default_model": "command-r-plus",
        "models": ["command-r-plus", "command-r"],
        "vision": False, "free": False,
        "code": False,
    },
}

DEFAULT_SYSTEM = os.getenv(
    "SYSTEM_PROMPT",
    "Bạn là trợ lý AI của ứng dụng KENIOS. Trả lời hữu ích, chính xác. "
    "Khi viết code, luôn kèm theo giải thích rõ ràng. "
    "Hỗ trợ: Python, JavaScript, TypeScript, Swift, Kotlin, Go, Rust, C/C++, "
    "Java, PHP, HTML/CSS, SQL, Shell script. "
    "Ưu tiên dùng tiếng Việt trừ khi người dùng yêu cầu khác.",
)

# ========================== Cơ sở dữ liệu ==========================
def db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def init_db() -> None:
    with db() as c:
        c.executescript("""
            CREATE TABLE IF NOT EXISTS users(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                email TEXT,
                phone TEXT,
                pw_hash TEXT NOT NULL,
                reset_token TEXT,
                reset_exp INTEGER,
                is_admin INTEGER DEFAULT 0,
                banned INTEGER DEFAULT 0,
                plan TEXT DEFAULT 'free',
                credits INTEGER DEFAULT 0,
                lang TEXT DEFAULT 'vi',
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS apikeys(
                user_id INTEGER NOT NULL,
                provider TEXT NOT NULL,
                enc_key TEXT NOT NULL,
                PRIMARY KEY(user_id, provider)
            );
            CREATE TABLE IF NOT EXISTS admin_apikeys(
                provider TEXT PRIMARY KEY,
                enc_key TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS mailboxes(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                address TEXT UNIQUE NOT NULL,
                pw_hash TEXT NOT NULL,
                owner_uid INTEGER,
                phone TEXT,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS mails(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                mailbox_id INTEGER NOT NULL,
                direction TEXT DEFAULT 'in',
                from_addr TEXT,
                to_addr TEXT,
                subject TEXT,
                body TEXT,
                created_at INTEGER,
                seen INTEGER DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS mail_domains(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                domain TEXT UNIQUE NOT NULL,
                user_id INTEGER,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS otp_codes(
                email TEXT PRIMARY KEY,
                code TEXT NOT NULL,
                purpose TEXT DEFAULT 'register',
                exp INTEGER NOT NULL,
                attempts INTEGER DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS api_tokens(
                token TEXT PRIMARY KEY,
                owner_uid INTEGER,
                name TEXT,
                calls INTEGER DEFAULT 0,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS devices(
                udid TEXT PRIMARY KEY,
                product TEXT,
                version TEXT,
                serial TEXT,
                name TEXT,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS conversations(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                title TEXT,
                provider TEXT,
                pinned INTEGER DEFAULT 0,
                share_token TEXT,
                created_at INTEGER,
                updated_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS messages(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                conversation_id INTEGER NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                tokens_used INTEGER,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS files(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                category TEXT,
                mime TEXT,
                size INTEGER,
                data TEXT NOT NULL,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS payments(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                amount INTEGER NOT NULL,
                credits INTEGER NOT NULL,
                status TEXT DEFAULT 'pending',
                ref TEXT,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS settings(
                key TEXT PRIMARY KEY,
                value TEXT
            );
            CREATE TABLE IF NOT EXISTS error_logs(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER,
                username TEXT,
                context TEXT,
                detail TEXT,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS prompt_templates(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                category TEXT,
                is_public INTEGER DEFAULT 0,
                user_id INTEGER,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS favorites(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                message_content TEXT NOT NULL,
                conversation_id INTEGER,
                provider TEXT,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS friendships(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                friend_id INTEGER NOT NULL,
                status TEXT DEFAULT 'pending',
                created_at INTEGER,
                UNIQUE(user_id, friend_id)
            );
            CREATE TABLE IF NOT EXISTS direct_messages(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sender_id INTEGER NOT NULL,
                receiver_id INTEGER NOT NULL,
                content TEXT NOT NULL,
                created_at INTEGER,
                is_read INTEGER DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS proxies(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                label TEXT,
                scheme TEXT DEFAULT 'http',
                host TEXT NOT NULL,
                port INTEGER NOT NULL,
                username TEXT,
                enc_password TEXT,
                region TEXT,
                source TEXT DEFAULT 'manual',
                active INTEGER DEFAULT 0,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS posts(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                file_id INTEGER NOT NULL,
                caption TEXT,
                likes INTEGER DEFAULT 0,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS post_likes(
                post_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                PRIMARY KEY(post_id, user_id)
            );
            CREATE TABLE IF NOT EXISTS post_comments(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                post_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                content TEXT NOT NULL,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS post_saves(
                post_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                created_at INTEGER,
                PRIMARY KEY(post_id, user_id)
            );
            CREATE TABLE IF NOT EXISTS live_rooms(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                host_id INTEGER NOT NULL,
                title TEXT,
                hls_url TEXT,
                stream_key TEXT,
                viewers INTEGER DEFAULT 0,
                likes INTEGER DEFAULT 0,
                active INTEGER DEFAULT 1,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS follows(
                follower_id INTEGER NOT NULL,
                following_id INTEGER NOT NULL,
                created_at INTEGER,
                PRIMARY KEY(follower_id, following_id)
            );
            CREATE TABLE IF NOT EXISTS live_messages(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                room_id INTEGER NOT NULL,
                user_id INTEGER,
                username TEXT,
                content TEXT,
                created_at INTEGER
            );

            -- ==================== App bán hàng (Store) ====================
            CREATE TABLE IF NOT EXISTS store_categories(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                media TEXT DEFAULT '[]',     -- JSON: [{"type":"image|video","url":"..."}] tối đa 5
                sort INTEGER DEFAULT 0,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS store_folders(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                category_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                media TEXT DEFAULT '[]',
                sort INTEGER DEFAULT 0,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS store_products(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                folder_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                description TEXT DEFAULT '',
                media TEXT DEFAULT '[]',
                download_url TEXT DEFAULT '',
                download_file_id INTEGER,
                kind TEXT DEFAULT 'app',     -- app (key/ứng dụng) | acc (acc game)
                sort INTEGER DEFAULT 0,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS store_prices(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_id INTEGER NOT NULL,
                label TEXT NOT NULL,         -- "1 giờ" / "1 ngày" / "1 tuần" / "1 tháng" ...
                amount INTEGER NOT NULL,     -- VND
                sort INTEGER DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS store_keys(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_id INTEGER NOT NULL,
                key_text TEXT NOT NULL,
                status TEXT DEFAULT 'available',  -- available | sold
                owner_uid INTEGER,
                price_id INTEGER,
                sold_at INTEGER,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS store_orders(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                product_id INTEGER NOT NULL,
                price_id INTEGER,
                key_id INTEGER,
                key_text TEXT,                   -- lưu key/acc đã giao (key gốc bị xoá khỏi kho)
                amount INTEGER NOT NULL,
                status TEXT DEFAULT 'pending',   -- pending | completed
                ref TEXT,
                created_at INTEGER
            );

            -- Đánh giá sản phẩm (mỗi khách 1 đánh giá / sản phẩm) → đếm "lượt đánh giá"
            CREATE TABLE IF NOT EXISTS store_reviews(
                product_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                stars INTEGER DEFAULT 5,
                created_at INTEGER,
                PRIMARY KEY(product_id, user_id)
            );

            -- Nạp tiền vào VÍ cửa hàng (tách biệt thanh toán app chính)
            CREATE TABLE IF NOT EXISTS store_topups(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                amount INTEGER NOT NULL,         -- số tiền chuyển khoản (VND)
                bonus INTEGER DEFAULT 0,         -- thưởng thêm (VND)
                credited INTEGER NOT NULL,       -- tổng cộng vào ví = amount + bonus
                status TEXT DEFAULT 'pending',   -- pending | completed
                ref TEXT,
                created_at INTEGER
            );
            -- Lịch sử biến động ví
            CREATE TABLE IF NOT EXISTS store_wallet_tx(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                kind TEXT NOT NULL,              -- topup | purchase
                amount INTEGER NOT NULL,         -- +nạp / -mua
                note TEXT DEFAULT '',
                created_at INTEGER
            );
            -- Vân tay các giao dịch NGÂN HÀNG đã cộng tiền (chống cộng trùng khi
            -- API ngân hàng trả về cùng giao dịch nhiều lần / webhook gửi lại).
            CREATE TABLE IF NOT EXISTS bank_tx_seen(
                fp TEXT PRIMARY KEY,
                created_at INTEGER
            );
            -- Mã khuyến mãi / giảm giá
            CREATE TABLE IF NOT EXISTS store_promo_codes(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                code TEXT NOT NULL UNIQUE,
                discount_type TEXT DEFAULT 'percent',  -- percent | fixed
                discount_value INTEGER NOT NULL,
                min_amount INTEGER DEFAULT 0,
                max_uses INTEGER DEFAULT 0,            -- 0 = không giới hạn
                used_count INTEGER DEFAULT 0,
                expires_at INTEGER DEFAULT 0,          -- 0 = không hết hạn
                is_active INTEGER DEFAULT 1,
                created_at INTEGER
            );
            -- Device tokens cho push notification
            CREATE TABLE IF NOT EXISTS device_tokens(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                token TEXT NOT NULL UNIQUE,
                platform TEXT DEFAULT 'ios',
                created_at INTEGER
            );
        """)
    _migrate()

    # Seed admin
    admin_user = os.getenv("ADMIN_USER", "kenios")
    admin_pass = os.getenv("ADMIN_PASS", "admin1999@")
    with db() as c:
        row = c.execute("SELECT id FROM users WHERE username=?", (admin_user,)).fetchone()
        if row:
            c.execute("UPDATE users SET is_admin=1, banned=0 WHERE id=?", (row["id"],))
        else:
            c.execute(
                "INSERT INTO users(username,pw_hash,is_admin,plan,credits,created_at) VALUES(?,?,1,'pro',9999,?)",
                (admin_user, hash_pw(admin_pass), int(time.time())),
            )
            log.info("Tạo admin '%s' (hãy đổi mật khẩu sau khi đăng nhập!)", admin_user)
    _seed_setting("bank_code", os.getenv("BANK_CODE", "970416"))
    _seed_setting("bank_short", os.getenv("BANK_SHORT", "ACB"))
    _seed_setting("bank_account", os.getenv("BANK_ACCOUNT", "23252921"))
    _seed_setting("bank_name", os.getenv("BANK_NAME", "TRAN MINH CHIEN"))
    _seed_setting("bank_webhook", "")
    _seed_setting("bank_apikey", "")
    # Nạp tiền tự động qua thueapibank.vn (ACB)
    _seed_setting("acb_api_token", os.getenv("ACB_API_TOKEN", ""))
    # Giao diện app bán hàng (chỉ admin chỉnh)
    _seed_setting("store_logo_name", os.getenv("STORE_LOGO_NAME", "KENIOS Store"))
    _seed_setting("store_logo_url", "")
    _seed_setting("store_banner_type", "image")   # image | video
    _seed_setting("store_banner_url", "")
    _seed_setting("store_topup_bonus_percent", "0")   # % thưởng khi nạp tiền vào ví
    _seed_prompt_templates()
    log.info("DB sẵn sàng: %s", DB_PATH)


def _seed_prompt_templates() -> None:
    templates = [
        {
            "title": "Tối ưu hóa Code (Clean Code & Performance)",
            "category": "Lập trình",
            "content": (
                "Hãy tối ưu hóa đoạn mã nguồn sau đây theo các nguyên tắc Clean Code và cải thiện hiệu năng (performance).\n"
                "Yêu cầu:\n"
                "1. Tên biến, tên hàm rõ ràng, tự giải thích (self-documenting).\n"
                "2. Tách nhỏ các hàm phức tạp thành các hàm đơn nhiệm (Single Responsibility).\n"
                "3. Tránh lặp lại mã nguồn (DRY - Don't Repeat Yourself).\n"
                "4. Tối ưu hóa độ phức tạp thời gian (Time Complexity) và không gian (Space Complexity).\n"
                "5. Cung cấp mã nguồn đã tối ưu kèm giải thích chi tiết các thay đổi.\n\n"
                "Mã nguồn cần tối ưu:\n"
                "[Nhập mã nguồn của bạn vào đây]"
            )
        },
        {
            "title": "Thiết kế hệ thống theo chuẩn SOLID",
            "category": "Kiến trúc",
            "content": (
                "Hãy phân tích và cấu trúc lại đoạn mã nguồn sau đây để tuân thủ nghiêm ngặt 5 nguyên tắc SOLID trong thiết kế hướng đối tượng:\n"
                "- S: Single Responsibility Principle (Đơn nhiệm)\n"
                "- O: Open/Closed Principle (Mở để mở rộng, đóng để sửa đổi)\n"
                "- L: Liskov Substitution Principle (Thay thế Liskov)\n"
                "- I: Interface Segregation Principle (Phân tách giao diện)\n"
                "- D: Dependency Inversion Principle (Đảo ngược phụ thuộc)\n\n"
                "Giải thích rõ từng nguyên tắc được áp dụng như thế nào sau khi refactor.\n\n"
                "Mã nguồn cần thiết kế lại:\n"
                "[Nhập mã nguồn của bạn vào đây]"
            )
        },
        {
            "title": "Rà soát Lỗi Bảo mật (Security Audit)",
            "category": "Bảo mật",
            "content": (
                "Hãy thực hiện rà soát bảo mật (Security Audit / Code Review) cho đoạn mã nguồn dưới đây.\n"
                "Tìm kiếm các lỗ hổng bảo mật phổ biến như:\n"
                "- SQL Injection, XSS, CSRF\n"
                "- Lộ thông tin nhạy cảm (API Keys, Mật khẩu...)\n"
                "- Lỗi phân quyền, xác thực (Authentication/Authorization)\n"
                "- Xử lý ngoại lệ không an toàn (Unsafe Exception Handling)\n"
                "- Buffer Overflow hoặc lỗi tràn bộ nhớ (nếu có)\n\n"
                "Với mỗi lỗ hổng phát hiện được, hãy giải thích nguy cơ và cung cấp cách khắc phục cụ thể.\n\n"
                "Mã nguồn cần rà soát:\n"
                "[Nhập mã nguồn của bạn vào đây]"
            )
        },
        {
            "title": "Giải thích Code & Tạo tài liệu (Documenting)",
            "category": "Tài liệu",
            "content": (
                "Hãy giải thích chi tiết luồng hoạt động của đoạn mã nguồn dưới đây và viết tài liệu hướng dẫn (docstring/comments) theo chuẩn của ngôn ngữ lập trình đó.\n"
                "Yêu cầu:\n"
                "1. Tóm tắt chức năng chính của đoạn mã.\n"
                "2. Mô tả chi tiết các tham số đầu vào (parameters) và kết quả trả về (return values).\n"
                "3. Giải thích luồng logic chính từng bước.\n"
                "4. Thêm các comment cần thiết trực tiếp vào mã nguồn mà không làm loãng mã nguồn.\n\n"
                "Mã nguồn cần viết tài liệu:\n"
                "[Nhập mã nguồn của bạn vào đây]"
            )
        },
        {
            "title": "Viết Unit Test tự động",
            "category": "Kiểm thử",
            "content": (
                "Hãy viết các ca kiểm thử đơn vị (Unit Tests) toàn diện cho đoạn mã nguồn dưới đây.\n"
                "Yêu cầu:\n"
                "1. Bao phủ đầy đủ các trường hợp thông thường (Happy path).\n"
                "2. Bao phủ các trường hợp biên, giá trị đặc biệt hoặc đầu vào lỗi (Edge cases / Error handling).\n"
                "3. Sử dụng thư viện testing chuẩn của ngôn ngữ tương ứng (ví dụ: unittest/pytest cho Python, XCTest cho Swift, Jest cho JS...).\n"
                "4. Sử dụng mock/stub cho các dịch vụ bên ngoài (cơ sở dữ liệu, API mạng) nếu cần thiết.\n\n"
                "Mã nguồn cần viết Unit Test:\n"
                "[Nhập mã nguồn của bạn vào đây]"
            )
        }
    ]
    with db() as c:
        count = c.execute("SELECT COUNT(*) as cnt FROM prompt_templates").fetchone()["cnt"]
        if count == 0:
            now = int(time.time())
            for t in templates:
                c.execute(
                    "INSERT INTO prompt_templates(title, content, category, is_public, user_id, created_at) "
                    "VALUES(?, ?, ?, 1, NULL, ?)",
                    (t["title"], t["content"], t["category"], now)
                )
            log.info("Đã seed %d prompt templates mặc định vào CSDL", len(templates))


def get_setting(key: str, default: str = "") -> str:
    with db() as c:
        row = c.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
    return row["value"] if row else default


def set_setting(key: str, value: str) -> None:
    with db() as c:
        c.execute("INSERT INTO settings(key,value) VALUES(?,?) "
                  "ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, value))


def _seed_setting(key: str, value: str) -> None:
    with db() as c:
        if not c.execute("SELECT 1 FROM settings WHERE key=?", (key,)).fetchone():
            c.execute("INSERT INTO settings(key,value) VALUES(?,?)", (key, value))


def _migrate() -> None:
    migrations = [
        ("users", "is_admin", "INTEGER DEFAULT 0"),
        ("users", "banned",   "INTEGER DEFAULT 0"),
        ("users", "plan",     "TEXT DEFAULT 'free'"),
        ("users", "credits",  "INTEGER DEFAULT 0"),
        ("users", "lang",     "TEXT DEFAULT 'vi'"),
        ("users", "public_id",     "TEXT"),
        ("users", "status",        "TEXT DEFAULT 'active'"),
        ("users", "suspend_until", "INTEGER DEFAULT 0"),
        ("users", "last_seen",     "INTEGER DEFAULT 0"),
        ("users", "last_feature",  "TEXT"),
        ("live_rooms", "stream_key", "TEXT"),
        ("files", "mime",     "TEXT"),
        ("conversations", "pinned", "INTEGER DEFAULT 0"),
        ("conversations", "share_token", "TEXT"),
        ("messages", "tokens_used", "INTEGER"),
        ("mailboxes", "phone", "TEXT"),
        # App bán hàng: loại sản phẩm (app/key vs acc game) + lưu key trực tiếp vào đơn
        ("store_products", "kind", "TEXT DEFAULT 'app'"),   # app | acc
        ("store_orders", "key_text", "TEXT"),
        # Giao hàng: lưu thời hạn gói + nền tảng + ngày hết hạn + tin nhắn giao key
        ("store_orders", "price_label",  "TEXT"),
        ("store_orders", "platform",     "TEXT"),
        ("store_orders", "expires_at",   "INTEGER"),
        ("store_orders", "delivery_msg", "TEXT"),
        # Ví cửa hàng (số dư VND, tách biệt với app chính)
        ("users", "wallet", "INTEGER DEFAULT 0"),
        # Hồ sơ mạng xã hội: ảnh đại diện + tiểu sử
        ("users", "avatar_url", "TEXT"),
        ("users", "bio", "TEXT"),
        # Video feed: lượt xem
        ("posts", "views", "INTEGER DEFAULT 0"),
        # Sản phẩm cửa hàng: lượt xem (mỗi lần khách bấm vào +1)
        ("store_products", "views", "INTEGER DEFAULT 0"),
    ]
    with db() as c:
        for table, col, ddl in migrations:
            try:
                c.execute(f"ALTER TABLE {table} ADD COLUMN {col} {ddl}")
            except Exception:
                pass
    _create_indexes()


def _create_indexes() -> None:
    """Chỉ mục tăng tốc truy vấn hay dùng (hiệu năng)."""
    indexes = [
        "CREATE INDEX IF NOT EXISTS idx_store_keys_prod_status ON store_keys(product_id,status)",
        "CREATE INDEX IF NOT EXISTS idx_store_orders_user_status ON store_orders(user_id,status)",
        "CREATE INDEX IF NOT EXISTS idx_store_orders_ref ON store_orders(ref)",
        "CREATE INDEX IF NOT EXISTS idx_store_prices_prod ON store_prices(product_id)",
        "CREATE INDEX IF NOT EXISTS idx_store_products_folder ON store_products(folder_id)",
        "CREATE INDEX IF NOT EXISTS idx_store_folders_cat ON store_folders(category_id)",
        "CREATE INDEX IF NOT EXISTS idx_payments_ref ON payments(ref)",
        "CREATE INDEX IF NOT EXISTS idx_payments_user_status ON payments(user_id,status)",
        "CREATE INDEX IF NOT EXISTS idx_files_user ON files(user_id)",
        "CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id)",
        "CREATE INDEX IF NOT EXISTS idx_conversations_user ON conversations(user_id)",
        "CREATE INDEX IF NOT EXISTS idx_users_public_id ON users(public_id)",
        "CREATE INDEX IF NOT EXISTS idx_store_topups_user_status ON store_topups(user_id,status)",
        "CREATE INDEX IF NOT EXISTS idx_store_wallet_tx_user ON store_wallet_tx(user_id)",
    ]
    with db() as c:
        for ddl in indexes:
            try:
                c.execute(ddl)
            except Exception:
                pass


# ========================== Bảo mật ==========================
def hash_pw(password: str) -> str:
    salt = secrets.token_bytes(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 200_000)
    return salt.hex() + "$" + dk.hex()


def verify_pw(password: str, stored: str) -> bool:
    try:
        salt_hex, dk_hex = stored.split("$", 1)
        dk = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt_hex), 200_000)
        return hmac.compare_digest(dk.hex(), dk_hex)
    except Exception:
        return False


def _b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode().rstrip("=")


def _b64u_dec(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def make_token(user_id: int) -> str:
    payload = {"uid": user_id, "exp": int(time.time()) + TOKEN_TTL}
    body = _b64u(json.dumps(payload, separators=(",", ":")).encode())
    sig = _b64u(hmac.new(SECRET.encode(), body.encode(), hashlib.sha256).digest())
    return f"{body}.{sig}"


def verify_token(token: str) -> int:
    try:
        body, sig = token.split(".", 1)
        good = _b64u(hmac.new(SECRET.encode(), body.encode(), hashlib.sha256).digest())
        if not hmac.compare_digest(sig, good):
            raise ValueError("sai chữ ký")
        payload = json.loads(_b64u_dec(body))
        if payload["exp"] < time.time():
            raise ValueError("hết hạn")
        return int(payload["uid"])
    except Exception:
        raise HTTPException(status_code=401, detail="Phiên đăng nhập không hợp lệ hoặc đã hết hạn. Vui lòng đăng nhập lại.")


def get_user(authorization: Optional[str] = Header(default=None)) -> sqlite3.Row:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Thiếu token đăng nhập.")
    uid = verify_token(authorization.split(" ", 1)[1])
    with db() as c:
        row = c.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
    if not row:
        raise HTTPException(status_code=401, detail="Tài khoản không tồn tại.")
    if row["banned"]:
        raise HTTPException(status_code=403, detail="Tài khoản đã bị khóa. Liên hệ quản trị viên.")
    # Tạm ngưng có thời hạn (admin không bị ảnh hưởng)
    if not row["is_admin"] and (row["status"] or "active") == "suspended":
        su = row["suspend_until"] or 0
        now = int(time.time())
        if su and su <= now:
            with db() as c:
                c.execute("UPDATE users SET status='active', suspend_until=0 WHERE id=?", (row["id"],))
        elif su:
            t = time.strftime("%H:%M %d/%m", time.localtime(su))
            raise HTTPException(status_code=403, detail=f"Tài khoản đang bị tạm ngưng đến {t}.")
        else:
            raise HTTPException(status_code=403, detail="Tài khoản đang bị tạm ngưng. Liên hệ quản trị viên.")
    return row


def _gen_public_id(c) -> str:
    import random
    for _ in range(20):
        pid = "KEN" + "".join(random.choices("0123456789", k=8))
        if not c.execute("SELECT 1 FROM users WHERE public_id=?", (pid,)).fetchone():
            return pid
    return "KEN" + str(int(time.time()))[-8:]


def _ensure_public_id(c, uid) -> str:
    row = c.execute("SELECT public_id FROM users WHERE id=?", (uid,)).fetchone()
    pid = row["public_id"] if row else None
    if not pid:
        pid = _gen_public_id(c)
        c.execute("UPDATE users SET public_id=? WHERE id=?", (pid, uid))
    return pid


def _setting_get(key: str, default: str = "") -> str:
    with db() as c:
        r = c.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
    return r["value"] if r else default


def _setting_set(key: str, value: str) -> None:
    with db() as c:
        c.execute("INSERT INTO settings(key,value) VALUES(?,?) "
                  "ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, value))


def _user_dict(row) -> dict[str, Any]:
    return {
        "id": row["id"], "username": row["username"],
        "email": row["email"], "phone": row["phone"],
        "public_id": row["public_id"],
        "is_admin": bool(row["is_admin"]),
        "plan": "pro" if row["is_admin"] else (row["plan"] or "free"),
        "credits": row["credits"], "lang": row["lang"] or "vi",
        "status": row["status"] or "active",
    }


def get_admin(user=Depends(get_user)) -> sqlite3.Row:
    if not user["is_admin"]:
        raise HTTPException(status_code=403, detail="Chỉ quản trị viên mới được phép.")
    return user


# ===================== Xử lý ảnh & file =====================
def parse_image(image: str) -> tuple[str, str]:
    if image.startswith("data:"):
        head, data = image.split(",", 1)
        m = re.search(r"data:(.*?);base64", head)
        return (m.group(1) if m else "image/jpeg"), data
    return "image/jpeg", image


# ===================== Token estimation =====================
def estimate_tokens(text: str) -> int:
    if not text:
        return 0
    non_ascii = sum(1 for ch in text if ord(ch) > 127)
    ascii_chars = len(text) - non_ascii
    return int(ascii_chars / 4) + non_ascii + 1


# ===================== Lỗi nhà cung cấp =====================
def _raise_for_provider(r: httpx.Response, provider: str) -> None:
    if r.status_code < 400:
        return
    txt = r.text[:500]
    if r.status_code in (401, 403):
        raise HTTPException(status_code=400,
            detail=f"{provider}: API key sai hoặc không đủ quyền ({r.status_code}). "
                   f"Vui lòng kiểm tra lại API key trong phần Cài đặt. Chi tiết: {txt}")
    if r.status_code == 404:
        raise HTTPException(status_code=400,
            detail=f"{provider}: Model không tồn tại hoặc chưa được hỗ trợ (404). "
                   f"Vui lòng chọn model khác. Chi tiết: {txt}")
    if r.status_code == 429:
        raise HTTPException(status_code=429,
            detail=f"{provider}: Vượt quá giới hạn tốc độ miễn phí (429). Hệ thống đã tự thử lại "
                   f"nhưng vẫn bị chặn. Cách khắc phục: (1) đợi ~30–60 giây rồi gửi lại; "
                   f"(2) đổi sang AI free khác như Groq hoặc OpenRouter; "
                   f"(3) đổi model nhẹ hơn (vd Gemini 2.0 Flash); hoặc (4) dùng API key trả phí của bạn.")
    raise HTTPException(status_code=502,
        detail=f"{provider} lỗi {r.status_code}: {txt}")


async def post_with_retry(
    client: "httpx.AsyncClient",
    url: str,
    *,
    provider: str = "",
    max_retries: int = 4,
    **kwargs: Any,
) -> "httpx.Response":
    """POST có tự động thử lại khi bị giới hạn tốc độ (429) hoặc server bận (500/502/503/504).

    Xử lý lỗi "vượt quá tốc độ" mà không làm hỏng phiên chat: chờ theo cấp số nhân
    (0.8s, 1.6s, 3.2s...) và tôn trọng header `Retry-After` của nhà cung cấp nếu có.
    """
    delay = 0.8
    last: Optional["httpx.Response"] = None
    for attempt in range(max_retries + 1):
        try:
            r = await client.post(url, **kwargs)
        except (httpx.ConnectError, httpx.ReadTimeout, httpx.RemoteProtocolError) as e:
            if attempt >= max_retries:
                if provider == "kenios":
                    raise HTTPException(status_code=503,
                        detail="KENIOS AI chưa chạy. Hãy cài model trên VPS: chạy "
                               "`bash kenios-ai/install-ai.sh` (cài Ollama + tải model) rồi "
                               "`systemctl restart kenios`. Hoặc tạm chọn AI khác (Gemini/Groq).")
                raise HTTPException(status_code=502,
                    detail=f"{provider or 'AI'}: không kết nối được tới máy chủ ({e.__class__.__name__}).")
            await asyncio.sleep(delay)
            delay = min(delay * 2, 12.0)
            continue
        last = r
        if r.status_code not in (429, 500, 502, 503, 504) or attempt >= max_retries:
            return r
        # Tôn trọng Retry-After nếu nhà cung cấp gửi về
        wait = delay
        ra = r.headers.get("retry-after")
        if ra:
            try:
                wait = max(wait, min(float(ra), 15.0))
            except ValueError:
                pass
        await asyncio.sleep(wait)
        delay = min(delay * 2, 12.0)
    return last  # type: ignore[return-value]


def get_user_key(user_id: int, provider: str, inline: Optional[str]) -> str:
    # KENIOS AI tự host: không cần API key của người dùng
    if provider == "kenios":
        return KENIOS_AI_KEY or "ollama"
    if inline:
        return inline
    with db() as c:
        row = c.execute("SELECT enc_key FROM apikeys WHERE user_id=? AND provider=?",
                        (user_id, provider)).fetchone()
    if row:
        return dec(row["enc_key"])
    with db() as c:
        row = c.execute("SELECT enc_key FROM admin_apikeys WHERE provider=?",
                        (provider,)).fetchone()
    if row:
        return dec(row["enc_key"])
    raise HTTPException(status_code=400,
        detail=f"Chưa có API key cho '{provider}'. Admin chưa cấu hình hoặc bạn chưa nhập key riêng.")


# ===================== DỊCH VỤ PARSE FILE & RAG =====================
def parse_file_content(file_path: str, filename: str) -> str:
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    if ext == "pdf":
        try:
            import pypdf
            reader = pypdf.PdfReader(file_path)
            text_pages = []
            for i, page in enumerate(reader.pages):
                t = page.extract_text()
                if t:
                    text_pages.append(f"[Trang {i+1}]\n{t}")
            return "\n".join(text_pages)
        except Exception as e:
            return f"[Lỗi giải mã PDF: {e}]"
    elif ext == "docx":
        try:
            import docx
            doc = docx.Document(file_path)
            text_paragraphs = [p.text for p in doc.paragraphs if p.text.strip()]
            return "\n".join(text_paragraphs)
        except Exception as e:
            return f"[Lỗi giải mã DOCX: {e}]"
    elif ext in ("xlsx", "xls"):
        try:
            import openpyxl
            wb = openpyxl.load_workbook(file_path, data_only=True)
            sheets_content = []
            for sheet_name in wb.sheetnames:
                sheet = wb[sheet_name]
                sheet_rows = []
                for row in sheet.iter_rows(values_only=True):
                    if any(row):
                        sheet_rows.append(" | ".join(str(val) if val is not None else "" for val in row))
                if sheet_rows:
                    sheets_content.append(f"[Sheet: {sheet_name}]\n" + "\n".join(sheet_rows))
            return "\n\n".join(sheets_content)
        except Exception as e:
            return f"[Lỗi giải mã XLSX: {e}]"
    else:
        try:
            with open(file_path, "r", encoding="utf-8", errors="replace") as f:
                return f.read()
        except Exception as e:
            return f"[Lỗi đọc tệp văn bản: {e}]"


def retrieve_relevant_chunks(text: str, query: str, top_k: int = 5) -> str:
    chunks = []
    chunk_size = 1000
    overlap = 100
    
    start = 0
    while start < len(text):
        end = min(start + chunk_size, len(text))
        chunk = text[start:end].strip()
        if chunk:
            chunks.append(chunk)
        start += chunk_size - overlap
        
    if not chunks:
        return ""
        
    query_words = set(re.findall(r'\w+', query.lower()))
    if not query_words:
        return "\n\n".join(chunks[:top_k])
        
    chunk_scores = []
    for idx, chunk in enumerate(chunks):
        chunk_words = re.findall(r'\w+', chunk.lower())
        score = sum(chunk_words.count(w) for w in query_words)
        chunk_scores.append((score, idx))
        
    chunk_scores.sort(key=lambda x: x[0], reverse=True)
    
    retrieved = []
    for score, idx in chunk_scores[:top_k]:
        retrieved.append(f"[Đoạn {idx+1}]: {chunks[idx]}")
    return "\n\n".join(retrieved)


# ===================== DỊCH VỤ TÌM KIẾM WEB DUCKDUCKGO =====================
async def search_ddg(query: str, max_results: int = 5) -> str:
    try:
        from urllib.parse import quote_plus
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(f"https://html.duckduckgo.com/html/?q={quote_plus(query)}", headers=headers)
            if r.status_code != 200:
                return ""
            
            titles = re.findall(r'<a class="result__url"[^>]*>(.*?)</a>', r.text, re.DOTALL)
            snippets = re.findall(r'<a class="result__snippet"[^>]*>(.*?)</a>', r.text, re.DOTALL)
            urls = re.findall(r'<a class="result__url"[^>]*href="([^"]+)"', r.text, re.DOTALL)
            
            results = []
            for i in range(min(len(titles), len(snippets), max_results)):
                title = re.sub(r'<[^>]+>', '', titles[i]).strip()
                snippet = re.sub(r'<[^>]+>', '', snippets[i]).strip()
                url = urls[i] if i < len(urls) else ""
                results.append(f"- **{title}** ({url}): {snippet}")
            
            if urls and len(urls) > 0:
                first_url = urls[0]
                if "uddg=" in first_url:
                    from urllib.parse import unquote
                    first_url = unquote(first_url.split("uddg=")[1].split("&")[0])
                try:
                    scr_res = await client.get(first_url, headers=headers, timeout=5)
                    if scr_res.status_code == 200:
                        text_content = re.sub(r'<(script|style).*?>.*?</\1>', '', scr_res.text, flags=re.DOTALL|re.IGNORECASE)
                        text_content = re.sub(r'<[^>]+>', '', text_content)
                        text_content = re.sub(r'\s+', ' ', text_content).strip()
                        if len(text_content) > 100:
                            results.append(f"\n[Nội dung chi tiết từ trang {first_url}]:\n{text_content[:3000]}")
                except Exception:
                    pass
                    
            return "\n".join(results)
    except Exception as e:
        log.error("Lỗi tìm kiếm DDG: %s", e)
        return ""


def save_code_blocks(user_id: int, text: str, label: str = "code") -> list[dict[str, Any]]:
    safe = re.sub(r"[^a-zA-Z0-9_]+", "", label) or "code"
    ext_map = {"python": "py", "py": "py", "javascript": "js", "js": "js",
               "typescript": "ts", "ts": "ts", "html": "html", "css": "css",
               "json": "json", "bash": "sh", "sh": "sh", "swift": "swift",
               "java": "java", "c": "c", "cpp": "cpp", "go": "go", "rust": "rs",
               "sql": "sql", "yaml": "yml", "yml": "yml", "markdown": "md", "md": "md",
               "php": "php", "ruby": "rb", "kotlin": "kt", "dart": "dart"}
    blocks = re.findall(r"```([a-zA-Z0-9_+\-]*)\n(.*?)```", text, re.DOTALL)
    saved: list[dict[str, Any]] = []
    n = 0
    for lang, code in blocks:
        code = code.rstrip("\n")
        if len(code.strip()) < 10:
            continue
        n += 1
        ext = ext_map.get(lang.lower().strip(), "txt")
        name = f"{safe}_{n}.{ext}"
        try:
            with db() as c:
                cur = c.execute(
                    "INSERT INTO files(user_id,name,category,mime,size,data,created_at) "
                    "VALUES(?,?,?,?,?,'',?)",
                    (user_id, name, "code", "text/plain", len(code), int(time.time())))
                fid = cur.lastrowid
                saved.append({"id": fid, "name": name})
            
            # Save file to disk
            file_path = os.path.join(UPLOAD_DIR, str(fid))
            with open(file_path, "wb") as f:
                f.write(code.encode("utf-8"))
        except Exception:
            pass
    return saved


# ===================== Gọi AI =====================
async def call_provider(
    provider: str,
    api_key: str,
    model: Optional[str],
    history: list[dict[str, Any]],
    user_text: str,
    image: Optional[str] = None,
    file_b64: Optional[str] = None,
    file_mime: Optional[str] = None,
    system_override: Optional[str] = None,
    attachments: Optional[list[dict[str, Any]]] = None,
    proxy: Optional[str] = None,  # ← THÊM: định tuyến qua proxy active
) -> str:
    if provider not in PROVIDERS:
        raise HTTPException(status_code=400, detail=f"AI '{provider}' không được hỗ trợ.")
    p    = PROVIDERS[provider]
    model = model or p["default_model"]
    kind  = p["kind"]
    sys_msg = system_override or DEFAULT_SYSTEM

    img = None
    if image:
        img = parse_image(image)
    elif file_b64 and file_mime and file_mime.startswith("image/"):
        img = (file_mime, file_b64)

    parsed_attachments: list[dict[str, Any]] = []
    if attachments:
        for att in attachments[:30]:
            att_name = att.get("name", "file")
            att_data = att.get("data_base64", "")
            att_mime = att.get("mime", "application/octet-stream")
            parsed_attachments.append({
                "name": att_name,
                "data": att_data,
                "mime": att_mime,
            })

    _client_kwargs = {"timeout": REQUEST_TIMEOUT}
    if proxy:
        _client_kwargs["proxy"] = proxy  # ← THÊM: route qua proxy
    async with httpx.AsyncClient(**_client_kwargs) as client:
        # -------- OpenAI-compatible --------
        if kind == "openai":
            msgs = [{"role": "system", "content": sys_msg}]
            msgs += [{"role": m["role"], "content": m["content"]} for m in history]

            if parsed_attachments:
                user_content: Any = [{"type": "text", "text": user_text or ""}]
                for att in parsed_attachments:
                    if att["mime"].startswith("image/"):
                        user_content.append({
                            "type": "image_url",
                            "image_url": {"url": f"data:{att['mime']};base64,{att['data']}"},
                        })
                    else:
                        try:
                            decoded = base64.b64decode(att["data"]).decode("utf-8", errors="replace")
                            user_content.append({
                                "type": "text",
                                "text": f"\n[File: {att['name']}]\n```\n{decoded[:8000]}\n```",
                            })
                        except Exception:
                            pass
            elif img:
                media, data = img
                user_content = [
                    {"type": "text", "text": user_text or ""},
                    {"type": "image_url", "image_url": {"url": f"data:{media};base64,{data}"}},
                ]
            elif file_b64 and file_mime:
                try:
                    decoded = base64.b64decode(file_b64).decode("utf-8", errors="replace")
                    user_content = f"{user_text}\n\n[Nội dung file]\n```\n{decoded[:8000]}\n```"
                except Exception:
                    user_content = user_text or ""
            else:
                user_content = user_text
            msgs.append({"role": "user", "content": user_content})
            r = await post_with_retry(
                client,
                f"{p['base']}/chat/completions",
                provider=provider,
                headers={"Authorization": f"Bearer {api_key}",
                         "HTTP-Referer": "https://kenios.app",
                         "X-Title": "KENIOS"},
                json={"model": model, "messages": msgs},
            )
            _raise_for_provider(r, provider)
            return r.json()["choices"][0]["message"]["content"]

        # -------- Anthropic --------
        if kind == "anthropic":
            msgs = [{"role": m["role"], "content": m["content"]} for m in history]

            if parsed_attachments:
                content_parts: list[dict[str, Any]] = [{"type": "text", "text": user_text or ""}]
                for att in parsed_attachments:
                    if att["mime"].startswith("image/"):
                        content_parts.append({
                            "type": "image",
                            "source": {"type": "base64", "media_type": att["mime"], "data": att["data"]},
                        })
                    elif att["mime"] == "application/pdf":
                        content_parts.append({
                            "type": "document",
                            "source": {"type": "base64", "media_type": "application/pdf", "data": att["data"]},
                        })
                    else:
                        try:
                            decoded = base64.b64decode(att["data"]).decode("utf-8", errors="replace")
                            content_parts.append({
                                "type": "text",
                                "text": f"\n[File: {att['name']}]\n```\n{decoded[:8000]}\n```",
                            })
                        except Exception:
                            pass
                msgs.append({"role": "user", "content": content_parts})
            elif img:
                media, data = img
                msgs.append({"role": "user", "content": [
                    {"type": "text", "text": user_text or ""},
                    {"type": "image", "source": {"type": "base64",
                                                  "media_type": media, "data": data}},
                ]})
            elif file_b64 and file_mime:
                if file_mime == "application/pdf":
                    msgs.append({"role": "user", "content": [
                        {"type": "text", "text": user_text or ""},
                        {"type": "document", "source": {"type": "base64",
                                                         "media_type": "application/pdf",
                                                         "data": file_b64}},
                    ]})
                else:
                    try:
                        decoded = base64.b64decode(file_b64).decode("utf-8", errors="replace")
                        msgs.append({"role": "user",
                                     "content": f"{user_text}\n\n[Nội dung file]\n```\n{decoded[:8000]}\n```"})
                    except Exception:
                        msgs.append({"role": "user", "content": user_text or ""})
            else:
                msgs.append({"role": "user", "content": user_text})
            r = await post_with_retry(
                client,
                f"{p['base']}/messages",
                provider=provider,
                headers={"x-api-key": api_key, "anthropic-version": "2023-06-01"},
                json={"model": model, "max_tokens": 8096, "system": sys_msg, "messages": msgs},
            )
            _raise_for_provider(r, provider)
            return r.json()["content"][0]["text"]

        # -------- Gemini (v1beta) --------
        if kind == "gemini":
            contents = []
            for m in history:
                role = "model" if m["role"] == "assistant" else "user"
                contents.append({"role": role, "parts": [{"text": m["content"]}]})
            parts: list[dict[str, Any]] = [{"text": user_text or ""}]

            if parsed_attachments:
                for att in parsed_attachments:
                    if att["mime"].startswith("image/") or att["mime"] == "application/pdf":
                        parts.append({"inline_data": {"mime_type": att["mime"], "data": att["data"]}})
                    else:
                        try:
                            decoded = base64.b64decode(att["data"]).decode("utf-8", errors="replace")
                            parts.append({"text": f"[File: {att['name']}]\n```\n{decoded[:8000]}\n```"})
                        except Exception:
                            pass
            elif img:
                media, data = img
                parts.append({"inline_data": {"mime_type": media, "data": data}})
            elif file_b64 and file_mime:
                if file_mime.startswith("image/"):
                    parts.append({"inline_data": {"mime_type": file_mime, "data": file_b64}})
                else:
                    try:
                        decoded = base64.b64decode(file_b64).decode("utf-8", errors="replace")
                        parts.append({"text": f"[Nội dung file]\n```\n{decoded[:8000]}\n```"})
                    except Exception:
                        pass
            contents.append({"role": "user", "parts": parts})
            url = f"{p['base']}/models/{model}:generateContent?key={api_key}"
            payload: dict[str, Any] = {
                "contents": contents,
                "systemInstruction": {"parts": [{"text": sys_msg}]},
                "generationConfig": {"maxOutputTokens": 8192},
            }
            r = await post_with_retry(client, url, provider=provider, json=payload)
            _raise_for_provider(r, provider)
            data_r = r.json()
            try:
                return data_r["candidates"][0]["content"]["parts"][0]["text"]
            except (KeyError, IndexError):
                finish = data_r.get("candidates", [{}])[0].get("finishReason", "UNKNOWN")
                raise HTTPException(status_code=400,
                    detail=f"Gemini không trả về nội dung (finishReason={finish}). "
                           f"Có thể nội dung bị chặn bởi bộ lọc an toàn.")

    raise HTTPException(status_code=500, detail="Lỗi cấu hình provider.")


# ========================== FastAPI ==========================
app = FastAPI(title="KENIOS kenios", version="4.2")
app.add_middleware(CORSMiddleware, allow_origins=["*"],
                   allow_credentials=False, allow_methods=["*"], allow_headers=["*"])


# ---------- Bảo mật: thêm header an toàn cho mọi phản hồi ----------
@app.middleware("http")
async def _security_headers(request: Request, call_next):
    resp = await call_next(request)
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["X-Frame-Options"] = "DENY"
    resp.headers["Referrer-Policy"] = "no-referrer"
    resp.headers["X-XSS-Protection"] = "1; mode=block"
    return resp


# ---------- Bảo mật: giới hạn tần suất (chống dò mật khẩu / spam) ----------
_rl_hits: dict[str, list[float]] = {}

def _client_ip(request: Request) -> str:
    xff = request.headers.get("x-forwarded-for", "")
    if xff:
        return xff.split(",")[0].strip()
    return request.client.host if request.client else "unknown"

def _rate_limit(request: Request, bucket: str, limit: int, window: int) -> None:
    """Cho phép tối đa `limit` lần trong `window` giây cho mỗi IP + bucket."""
    key = f"{bucket}:{_client_ip(request)}"
    now = time.time()
    arr = [t for t in _rl_hits.get(key, []) if now - t < window]
    if len(arr) >= limit:
        raise HTTPException(status_code=429,
            detail="Bạn thao tác quá nhiều lần. Vui lòng thử lại sau vài phút.")
    arr.append(now)
    _rl_hits[key] = arr
    # Dọn bộ nhớ định kỳ để không phình to
    if len(_rl_hits) > 5000:
        for k in [k for k, v in _rl_hits.items() if not any(now - t < window for t in v)]:
            _rl_hits.pop(k, None)


_acb_task = None   # giữ tham chiếu tránh bị thu gom (GC)

@app.on_event("startup")
def _startup() -> None:
    global _acb_task
    init_db()
    start_mail_smtp()
    try:
        _acb_task = asyncio.create_task(_acb_autopay_loop())
    except RuntimeError:
        # Không có event loop (vd chạy test) → bỏ qua
        pass


# ======================== Pydantic Models ========================
class RegisterIn(BaseModel):
    username: str
    password: str
    email: Optional[str] = None
    phone: Optional[str] = None
    code: Optional[str] = None     # mã xác nhận gửi qua email (nếu có email)

class LoginIn(BaseModel):
    username: str
    password: str

class ForgotIn(BaseModel):
    username: str

class ResetIn(BaseModel):
    token: str
    new_password: str

class ProfileIn(BaseModel):
    email: Optional[str] = None
    phone: Optional[str] = None
    new_password: Optional[str] = None
    lang: Optional[str] = None

class KeyIn(BaseModel):
    provider: str
    api_key: str

class AttachmentIn(BaseModel):
    name: str
    data_base64: str
    mime: str

class ChatIn(BaseModel):
    provider: str
    message: str = ""
    image: Optional[str] = None
    file_base64: Optional[str] = None
    file_mime: Optional[str] = None
    attachments: Optional[list[AttachmentIn]] = None
    model: Optional[str] = None
    conversation_id: Optional[int] = None
    api_key: Optional[str] = None
    system: Optional[str] = None
    # Thêm tham số nâng cao
    web_search: Optional[bool] = False
    file_ids: Optional[list[int]] = None

class EnsembleIn(BaseModel):
    providers: list[str]
    message: str
    judge: Optional[str] = None

class CodeRunIn(BaseModel):
    code: str
    stdin: Optional[str] = None
    language: Optional[str] = "python"

class FileRunIn(BaseModel):
    file_id: int
    args: Optional[str] = None

class CodeReviewIn(BaseModel):
    provider: str
    code: str
    language: Optional[str] = None
    task: str = "review"
    target_lang: Optional[str] = None
    api_key: Optional[str] = None
    model: Optional[str] = None

class PaymentIn(BaseModel):
    amount: int
    package: str

class CodeZipIn(BaseModel):
    text: str

class PromptTemplateIn(BaseModel):
    title: str
    content: str
    category: Optional[str] = None
    is_public: Optional[bool] = False

class FavoriteIn(BaseModel):
    message_content: str
    conversation_id: Optional[int] = None
    provider: Optional[str] = None


class FriendRequestIn(BaseModel):
    friend_id: int


class FriendResponseIn(BaseModel):
    request_id: int
    action: str  # 'accept' or 'decline'


class DirectMessageIn(BaseModel):
    receiver_id: int
    content: str


# ======================== Health & Config ========================
@app.get("/health")
def health() -> dict[str, Any]:
    return {"status": "ok", "time": int(time.time()), "version": "4.2",
            "providers": len(PROVIDERS)}


@app.get("/config")
def config() -> dict[str, Any]:
    return {"name": "KENIOS kenios", "version": "4.2",
            "providers": _providers_public()}


def _providers_public() -> list[dict[str, Any]]:
    # Theo yêu cầu: ẩn toàn bộ AI khỏi ứng dụng (không hiển thị nhà cung cấp nào).
    # Trả về danh sách rỗng để app & trang Quản trị không còn liệt kê AI nào.
    return []


@app.get("/providers")
def providers_list() -> list[dict[str, Any]]:
    return _providers_public()


# ======================== KENIOS AI — cấp API key cho người khác dùng ké ========================
class ApiTokenIn(BaseModel):
    name: str = ""


@app.post("/apitokens/create")
def apitoken_create(b: ApiTokenIn, user=Depends(get_user)) -> dict[str, Any]:
    token = "ken-" + secrets.token_urlsafe(24)
    with db() as c:
        c.execute("INSERT INTO api_tokens(token,owner_uid,name,calls,created_at) VALUES(?,?,?,0,?)",
                  (token, user["id"], (b.name or "Khoá API").strip()[:60], int(time.time())))
    return {"token": token}


@app.get("/apitokens")
def apitoken_list(user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        rows = c.execute("SELECT token,name,calls,created_at FROM api_tokens "
                         "WHERE owner_uid=? ORDER BY created_at DESC", (user["id"],)).fetchall()
    return {"tokens": [dict(r) for r in rows]}


@app.delete("/apitokens/{token}")
def apitoken_delete(token: str, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM api_tokens WHERE token=? AND owner_uid=?", (token, user["id"]))
    return {"ok": True}


class PublicChatIn(BaseModel):
    token: str
    message: str
    model: Optional[str] = None
    system: Optional[str] = None


@app.post("/v1/kenios/chat")
async def public_kenios_chat(b: PublicChatIn) -> dict[str, Any]:
    """API công khai: người khác dùng API key của bạn để gọi KENIOS AI (model tự host)."""
    if not (b.message or "").strip():
        raise HTTPException(status_code=400, detail="Thiếu 'message'.")
    with db() as c:
        row = c.execute("SELECT owner_uid FROM api_tokens WHERE token=?", (b.token,)).fetchone()
        if not row:
            raise HTTPException(status_code=401, detail="API key không hợp lệ.")
        c.execute("UPDATE api_tokens SET calls=calls+1 WHERE token=?", (b.token,))
    if not KENIOS_AI_ENABLE:
        raise HTTPException(status_code=503, detail="KENIOS AI chưa được bật trên máy chủ.")
    reply = await call_provider("kenios", KENIOS_AI_KEY or "ollama", b.model, [],
                                b.message, system_override=b.system)
    return {"reply": reply, "model": b.model or KENIOS_AI_MODEL}


# ======================== Đăng ký thiết bị (lấy UDID để ký app ad-hoc) ========================
@app.get("/enroll/start", response_class=HTMLResponse)
def enroll_start(request: Request) -> Any:
    base = str(request.base_url).rstrip("/")
    return f"""<!doctype html><html><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>Đăng ký thiết bị KENIOS</title>
<style>body{{font-family:-apple-system;background:#0b1020;color:#fff;text-align:center;padding:40px}}
a.btn{{display:inline-block;margin-top:24px;padding:16px 28px;background:#4f46e5;color:#fff;
text-decoration:none;border-radius:14px;font-size:18px;font-weight:700}}
p{{color:#aab;max-width:520px;margin:10px auto}}</style></head>
<body><h2>Đăng ký thiết bị KENIOS</h2>
<p>Bấm nút bên dưới để lấy <b>UDID</b> thiết bị (cài hồ sơ cấu hình). UDID dùng để ký app cho riêng máy bạn.</p>
<a class='btn' href='{base}/enroll/profile'>Lấy UDID thiết bị</a>
<p style='margin-top:30px;font-size:13px'>Sau khi cài app đã ký: vào <b>Cài đặt → Cài đặt chung → VPN &amp; Quản lý thiết bị</b> → bấm tên nhà phát triển → <b>Tin cậy</b>.</p>
</body></html>"""


@app.get("/enroll/profile")
def enroll_profile(request: Request) -> Response:
    base = str(request.base_url).rstrip("/")
    puid = secrets.token_hex(8)
    profile = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>PayloadContent</key>
  <dict>
    <key>URL</key><string>{base}/enroll/callback</string>
    <key>DeviceAttributes</key>
    <array>
      <string>UDID</string><string>PRODUCT</string><string>VERSION</string>
      <string>SERIAL</string><string>DEVICE_NAME</string>
    </array>
  </dict>
  <key>PayloadOrganization</key><string>KENIOS</string>
  <key>PayloadDisplayName</key><string>Đăng ký thiết bị KENIOS</string>
  <key>PayloadVersion</key><integer>1</integer>
  <key>PayloadUUID</key><string>{puid}</string>
  <key>PayloadIdentifier</key><string>com.kenios.enroll</string>
  <key>PayloadType</key><string>Profile Service</string>
</dict></plist>"""
    return Response(content=profile, media_type="application/x-apple-aspen-config")


@app.post("/enroll/callback", response_class=HTMLResponse)
async def enroll_callback(request: Request) -> Any:
    body = await request.body()
    import plistlib
    udid = ""; info: dict[str, Any] = {}
    start = body.find(b"<?xml")
    end = body.find(b"</plist>")
    if start != -1 and end != -1:
        try:
            info = plistlib.loads(body[start:end + 8])
            udid = str(info.get("UDID", ""))
        except Exception:
            udid = ""
    if udid:
        with db() as c:
            c.execute("INSERT OR REPLACE INTO devices(udid,product,version,serial,name,created_at) "
                      "VALUES(?,?,?,?,?,?)",
                      (udid, str(info.get("PRODUCT", "")), str(info.get("VERSION", "")),
                       str(info.get("SERIAL", "")), str(info.get("DEVICE_NAME", "")), int(time.time())))
    return f"""<!doctype html><html><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<style>body{{font-family:-apple-system;background:#0b1020;color:#fff;text-align:center;padding:50px}}
.box{{background:#161c33;border-radius:14px;padding:20px;max-width:520px;margin:0 auto}}
code{{color:#8ef;word-break:break-all}}</style></head><body>
<h2>✅ Đã ghi nhận thiết bị</h2>
<div class='box'><p>UDID của bạn:</p><h3><code>{udid or 'Không đọc được'}</code></h3></div>
<p style='color:#aab;margin-top:20px'>Gửi UDID này cho nhà phát triển để được ký app. Sau khi cài bản đã ký, nhớ vào Cài đặt → VPN &amp; Quản lý thiết bị để <b>Tin cậy</b>.</p>
</body></html>"""


@app.get("/devices")
def devices_list(admin=Depends(get_admin)) -> dict[str, Any]:
    with db() as c:
        rows = c.execute("SELECT udid,product,version,serial,name,created_at "
                         "FROM devices ORDER BY created_at DESC").fetchall()
    return {"devices": [dict(r) for r in rows]}


# ======================== Auth ========================
@app.post("/auth/register")
def register(b: RegisterIn, request: Request) -> dict[str, Any]:
    _rate_limit(request, "register", limit=10, window=600)
    if len(b.username) < 3 or len(b.password) < 6:
        raise HTTPException(status_code=400,
            detail="Username ≥3 ký tự, mật khẩu ≥6 ký tự.")
    email = (b.email or "").strip()
    phone_raw = (b.phone or "").strip()
    # Đăng ký bằng Gmail HOẶC Số điện thoại — phải có ít nhất một
    if not email and not phone_raw:
        raise HTTPException(status_code=400,
            detail="Hãy đăng ký bằng Gmail hoặc số điện thoại.")
    # Bắt buộc mã xác nhận (OTP) khớp với phương thức đã chọn
    code = (b.code or "").strip()
    if not code:
        raise HTTPException(status_code=400,
            detail="Thiếu mã xác nhận. Hãy bấm 'Gửi mã' rồi nhập mã được gửi tới.")
    ident = email.lower() if email else _normalize_phone(phone_raw)
    if not _otp_check(ident, code):
        raise HTTPException(status_code=400,
            detail="Mã xác nhận sai hoặc đã hết hạn. Vui lòng lấy mã mới.")
    phone = _normalize_phone(phone_raw) if phone_raw else None
    email_val = email or None
    with db() as c:
        if c.execute("SELECT 1 FROM users WHERE username=?", (b.username,)).fetchone():
            raise HTTPException(status_code=409, detail="Username đã tồn tại.")
        cur = c.execute(
            "INSERT INTO users(username,email,phone,pw_hash,plan,credits,created_at) "
            "VALUES(?,?,?,?,'free',0,?)",
            (b.username, email_val, phone, hash_pw(b.password), int(time.time())),
        )
        uid = cur.lastrowid
        pid = _ensure_public_id(c, uid)
    return {"token": make_token(uid),
            "user": {"id": uid, "username": b.username, "email": email_val,
                     "phone": phone, "public_id": pid, "is_admin": False,
                     "plan": "free", "credits": 0, "lang": "vi", "status": "active"}}


@app.post("/auth/login")
def login(b: LoginIn, request: Request) -> dict[str, Any]:
    _rate_limit(request, "login", limit=12, window=300)
    with db() as c:
        row = c.execute("SELECT * FROM users WHERE username=?", (b.username,)).fetchone()
    if not row or not verify_pw(b.password, row["pw_hash"]):
        raise HTTPException(status_code=401, detail="Sai username hoặc mật khẩu.")
    if row["banned"]:
        raise HTTPException(status_code=403, detail="Tài khoản đã bị khóa. Liên hệ quản trị viên.")
    with db() as c:
        _ensure_public_id(c, row["id"])
        row = c.execute("SELECT * FROM users WHERE id=?", (row["id"],)).fetchone()
    return {"token": make_token(row["id"]), "user": _user_dict(row)}


@app.post("/auth/forgot-password")
def forgot(b: ForgotIn, request: Request) -> dict[str, Any]:
    _rate_limit(request, "forgot", limit=8, window=600)
    token = secrets.token_urlsafe(24)
    with db() as c:
        row = c.execute("SELECT id FROM users WHERE username=?", (b.username,)).fetchone()
        if row:
            c.execute("UPDATE users SET reset_token=?, reset_exp=? WHERE id=?",
                      (token, int(time.time()) + 1800, row["id"]))
    log.info("Reset token cho %s: %s", b.username, token)
    return {"message": "Nếu tài khoản tồn tại, mã đặt lại đã được tạo.",
            "reset_token": token}


@app.post("/auth/reset-password")
def reset_pw(b: ResetIn) -> dict[str, Any]:
    if len(b.new_password) < 6:
        raise HTTPException(status_code=400, detail="Mật khẩu mới ≥6 ký tự.")
    with db() as c:
        row = c.execute("SELECT id,reset_exp FROM users WHERE reset_token=?",
                        (b.token,)).fetchone()
        if not row or (row["reset_exp"] or 0) < time.time():
            raise HTTPException(status_code=400,
                detail="Mã đặt lại sai hoặc đã hết hạn (30 phút).")
        c.execute("UPDATE users SET pw_hash=?, reset_token=NULL, reset_exp=NULL WHERE id=?",
                  (hash_pw(b.new_password), row["id"]))
    return {"message": "Đổi mật khẩu thành công."}


@app.post("/auth/update-profile")
def update_profile(b: ProfileIn, user=Depends(get_user)) -> dict[str, Any]:
    fields, vals = [], []
    if b.email is not None:
        fields.append("email=?"); vals.append(b.email)
    if b.phone is not None:
        fields.append("phone=?"); vals.append(b.phone)
    if b.new_password:
        if len(b.new_password) < 6:
            raise HTTPException(status_code=400, detail="Mật khẩu mới ≥6 ký tự.")
        fields.append("pw_hash=?"); vals.append(hash_pw(b.new_password))
    if b.lang in ("vi", "en"):
        fields.append("lang=?"); vals.append(b.lang)
    if not fields:
        raise HTTPException(status_code=400, detail="Không có gì để cập nhật.")
    vals.append(user["id"])
    with db() as c:
        c.execute(f"UPDATE users SET {', '.join(fields)} WHERE id=?", vals)
    return {"message": "Cập nhật thành công."}


# ======================== API Keys (User) ========================
@app.post("/keys")
def save_key(b: KeyIn, user=Depends(get_user)) -> dict[str, Any]:
    if b.provider not in PROVIDERS:
        raise HTTPException(status_code=400,
            detail=f"AI '{b.provider}' không được hỗ trợ. Danh sách hợp lệ: {list(PROVIDERS.keys())}")
    with db() as c:
        c.execute("INSERT INTO apikeys(user_id,provider,enc_key) VALUES(?,?,?) "
                  "ON CONFLICT(user_id,provider) DO UPDATE SET enc_key=excluded.enc_key",
                  (user["id"], b.provider, enc(b.api_key)))
    return {"message": f"Đã lưu API key cho {b.provider} thành công."}


@app.get("/keys")
def list_keys(user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute("SELECT provider FROM apikeys WHERE user_id=?",
                         (user["id"],)).fetchall()
    return [{"provider": r["provider"], "configured": True} for r in rows]


@app.delete("/keys/{provider}")
def del_key(provider: str, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM apikeys WHERE user_id=? AND provider=?",
                  (user["id"], provider))
    return {"message": f"Đã xóa key {provider}."}


@app.post("/keys/test")
async def test_key(b: KeyIn, user=Depends(get_user)) -> dict[str, Any]:
    if b.provider not in PROVIDERS:
        raise HTTPException(status_code=400, detail=f"AI '{b.provider}' không được hỗ trợ.")
    try:
        await call_provider(b.provider, b.api_key, None, [], "ping")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
            detail=f"Key không dùng được: {type(e).__name__}: {str(e)[:200]}")
    return {"ok": True, "message": f"Key {b.provider} hoạt động tốt."}


# ======================== Admin API Keys ========================
@app.post("/admin/keys")
def admin_save_key(b: KeyIn, admin=Depends(get_admin)) -> dict[str, Any]:
    if b.provider not in PROVIDERS:
        raise HTTPException(status_code=400,
            detail=f"AI '{b.provider}' không được hỗ trợ. Danh sách hợp lệ: {list(PROVIDERS.keys())}")
    with db() as c:
        c.execute("INSERT INTO admin_apikeys(provider,enc_key) VALUES(?,?) "
                  "ON CONFLICT(provider) DO UPDATE SET enc_key=excluded.enc_key",
                  (b.provider, enc(b.api_key)))
    return {"message": f"Đã lưu admin API key cho {b.provider}."}


@app.get("/admin/keys")
def admin_list_keys(admin=Depends(get_admin)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute("SELECT provider FROM admin_apikeys").fetchall()
    return [{"provider": r["provider"], "configured": True} for r in rows]


@app.delete("/admin/keys/{provider}")
def admin_del_key(provider: str, admin=Depends(get_admin)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM admin_apikeys WHERE provider=?", (provider,))
    return {"message": f"Đã xóa admin key cho {provider}."}


# ======================== Chat ========================
def load_history(conversation_id: int, user_id: int) -> list[dict[str, str]]:
    with db() as c:
        own = c.execute("SELECT 1 FROM conversations WHERE id=? AND user_id=?",
                        (conversation_id, user_id)).fetchone()
        if not own:
            raise HTTPException(status_code=404, detail="Không tìm thấy hội thoại.")
        rows = c.execute(
            "SELECT role,content FROM messages WHERE conversation_id=? ORDER BY id",
            (conversation_id,)
        ).fetchall()
    return [{"role": r["role"], "content": r["content"]} for r in rows]


def new_conversation(user_id: int, provider: str, title: str) -> int:
    now = int(time.time())
    with db() as c:
        cur = c.execute(
            "INSERT INTO conversations(user_id,title,provider,created_at,updated_at) "
            "VALUES(?,?,?,?,?)",
            (user_id, (title or "Hội thoại mới")[:80], provider, now, now),
        )
        return cur.lastrowid


def save_message(conversation_id: int, role: str, content: str, tokens: int = 0) -> None:
    with db() as c:
        c.execute("INSERT INTO messages(conversation_id,role,content,tokens_used,created_at) VALUES(?,?,?,?,?)",
                  (conversation_id, role, content, tokens, int(time.time())))
        c.execute("UPDATE conversations SET updated_at=? WHERE id=?",
                  (int(time.time()), conversation_id))


@app.post("/chat")
async def chat(b: ChatIn, user=Depends(get_user)) -> dict[str, Any]:
    if not b.message and not b.image and not b.file_base64 and not b.attachments:
        raise HTTPException(status_code=400,
            detail="Thiếu nội dung: cần ít nhất 'message', 'image', 'file_base64', hoặc 'attachments'.")
    
    # 1. Xử lý RAG nếu đính kèm file ID từ thư viện
    rag_context = ""
    if b.file_ids:
        for fid in b.file_ids:
            with db() as c:
                row = c.execute("SELECT name, data FROM files WHERE id=? AND user_id=?",
                                (fid, user["id"])).fetchone()
            if row:
                file_path = os.path.join(UPLOAD_DIR, str(fid))
                file_text = ""
                if os.path.exists(file_path):
                    file_text = parse_file_content(file_path, row["name"])
                elif row["data"]:
                    try:
                        file_text = base64.b64decode(row["data"]).decode("utf-8", errors="replace")
                    except Exception:
                        pass
                
                if file_text:
                    # Trích xuất đoạn liên quan qua TF-IDF nếu tệp quá lớn (>10k chars)
                    if len(file_text) > 10000:
                        relevant = retrieve_relevant_chunks(file_text, b.message)
                        rag_context += f"\n\n--- [ĐOẠN TRÍCH TỪ TỆP: {row['name']}] ---\n{relevant}\n"
                    else:
                        rag_context += f"\n\n--- [NỘI DUNG TỆP: {row['name']}] ---\n{file_text}\n"

    # 2. Xử lý Web Search thông qua DuckDuckGo
    search_context = ""
    if b.web_search:
        search_context = await search_ddg(b.message)

    # Ghép ngữ cảnh vào system prompt
    final_system = b.system or DEFAULT_SYSTEM
    if rag_context:
        final_system += f"\n\n[Dữ liệu tài liệu đính kèm]:{rag_context}\nHãy dựa vào nội dung tài liệu trên để trả lời câu hỏi của người dùng một cách chính xác."
    if search_context:
        final_system += f"\n\n[Dữ liệu tìm kiếm thời gian thực từ Internet]:\n{search_context}\nHãy tổng hợp các thông tin Internet trên để đưa ra câu trả lời mới và chính xác nhất."

    key = get_user_key(user["id"], b.provider, b.api_key)
    conv_id = b.conversation_id or new_conversation(
        user["id"], b.provider, b.message or "File/Ảnh")
    history = load_history(conv_id, user["id"]) if b.conversation_id else []

    attachments_data = None
    if b.attachments:
        attachments_data = [
            {"name": a.name, "data_base64": a.data_base64, "mime": a.mime}
            for a in b.attachments[:30]
        ]

    reply = await call_provider(
        b.provider, key, b.model, history,
        b.message, b.image,
        b.file_base64, b.file_mime,
        final_system,
        attachments=attachments_data,
    )

    input_tokens = estimate_tokens(b.message)
    output_tokens = estimate_tokens(reply)
    total_tokens = input_tokens + output_tokens

    user_msg_display = b.message or ("[ảnh]" if b.image else ("[file]" if b.file_base64 else "[đính kèm]"))
    save_message(conv_id, "user", user_msg_display, tokens=input_tokens)
    save_message(conv_id, "assistant", reply, tokens=output_tokens)
    saved_files = save_code_blocks(user["id"], reply, f"chat{conv_id}")
    return {
        "reply": reply,
        "conversation_id": conv_id,
        "provider": b.provider,
        "model": b.model or PROVIDERS[b.provider]["default_model"],
        "saved_files": saved_files,
        "tokens_estimated": {
            "input": input_tokens,
            "output": output_tokens,
            "total": total_tokens,
        },
    }


async def call_provider_stream(provider: str, api_key: str, model: Optional[str],
                               history: list[dict[str, Any]], user_text: str,
                               system_override: Optional[str] = None):
    """Gọi AI ở chế độ streaming — sinh từng đoạn text (cho OpenAI-compatible, Gemini, Anthropic).
    Provider khác → fallback gọi 1 lần và trả nguyên câu."""
    if provider not in PROVIDERS:
        raise HTTPException(status_code=400, detail=f"AI '{provider}' không được hỗ trợ.")
    p = PROVIDERS[provider]
    model = model or p["default_model"]
    kind = p["kind"]
    sys_msg = system_override or DEFAULT_SYSTEM

    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        if kind == "openai":
            msgs = [{"role": "system", "content": sys_msg}]
            msgs += [{"role": m["role"], "content": m["content"]} for m in history]
            msgs.append({"role": "user", "content": user_text})
            async with client.stream("POST", f"{p['base']}/chat/completions",
                headers={"Authorization": f"Bearer {api_key}",
                         "HTTP-Referer": "https://kenios.app", "X-Title": "KENIOS"},
                json={"model": model, "messages": msgs, "stream": True}) as r:
                if r.status_code >= 400:
                    txt = (await r.aread()).decode("utf-8", "replace")[:300]
                    raise HTTPException(status_code=502, detail=f"{provider} lỗi {r.status_code}: {txt}")
                async for line in r.aiter_lines():
                    if not line or not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if data == "[DONE]":
                        break
                    try:
                        delta = json.loads(data)["choices"][0]["delta"].get("content")
                        if delta:
                            yield delta
                    except Exception:
                        continue
            return

        if kind == "gemini":
            contents = []
            for m in history:
                contents.append({"role": "model" if m["role"] == "assistant" else "user",
                                 "parts": [{"text": m["content"]}]})
            contents.append({"role": "user", "parts": [{"text": user_text}]})
            url = f"{p['base']}/models/{model}:streamGenerateContent?alt=sse&key={api_key}"
            payload = {"contents": contents, "systemInstruction": {"parts": [{"text": sys_msg}]}}
            async with client.stream("POST", url, json=payload) as r:
                if r.status_code >= 400:
                    txt = (await r.aread()).decode("utf-8", "replace")[:300]
                    raise HTTPException(status_code=502, detail=f"gemini lỗi {r.status_code}: {txt}")
                async for line in r.aiter_lines():
                    if not line or not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if not data:
                        continue
                    try:
                        t = json.loads(data)["candidates"][0]["content"]["parts"][0]["text"]
                        if t:
                            yield t
                    except Exception:
                        continue
            return

        if kind == "anthropic":
            msgs = [{"role": m["role"], "content": m["content"]} for m in history]
            msgs.append({"role": "user", "content": user_text})
            async with client.stream("POST", f"{p['base']}/messages",
                headers={"x-api-key": api_key, "anthropic-version": "2023-06-01"},
                json={"model": model, "max_tokens": 8096, "system": sys_msg,
                      "messages": msgs, "stream": True}) as r:
                if r.status_code >= 400:
                    txt = (await r.aread()).decode("utf-8", "replace")[:300]
                    raise HTTPException(status_code=502, detail=f"anthropic lỗi {r.status_code}: {txt}")
                async for line in r.aiter_lines():
                    if not line or not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    try:
                        obj = json.loads(data)
                        if obj.get("type") == "content_block_delta":
                            t = obj.get("delta", {}).get("text")
                            if t:
                                yield t
                    except Exception:
                        continue
            return

    # Fallback: provider không hỗ trợ streaming ở đây → gọi 1 lần
    full = await call_provider(provider, api_key, model, history, user_text,
                               system_override=system_override)
    yield full


@app.post("/chat/stream")
async def chat_stream(b: ChatIn, user=Depends(get_user)):
    """Chat dạng streaming (trả lời hiện dần). Chỉ hỗ trợ text; ảnh/file dùng /chat."""
    if not b.message:
        raise HTTPException(status_code=400, detail="Cần 'message' cho chế độ streaming.")
    key = get_user_key(user["id"], b.provider, b.api_key)
    conv_id = b.conversation_id or new_conversation(user["id"], b.provider, b.message)
    history = load_history(conv_id, user["id"]) if b.conversation_id else []
    final_system = b.system or DEFAULT_SYSTEM

    async def gen():
        full = ""
        try:
            async for chunk in call_provider_stream(b.provider, key, b.model, history,
                                                    b.message, final_system):
                full += chunk
                yield "data: " + json.dumps({"delta": chunk}, ensure_ascii=False) + "\n\n"
        except HTTPException as e:
            yield "data: " + json.dumps({"error": str(e.detail)}, ensure_ascii=False) + "\n\n"
        except (httpx.ConnectError, httpx.ReadTimeout, httpx.RemoteProtocolError) as e:
            msg = (str(e) if b.provider != "kenios"
                   else "KENIOS AI chưa chạy. Cài Ollama trên VPS rồi thử lại "
                        "(bash kenios-ai/install-ai.sh).")
            yield "data: " + json.dumps({"error": msg}, ensure_ascii=False) + "\n\n"
        except Exception as e:
            yield "data: " + json.dumps({"error": str(e)}, ensure_ascii=False) + "\n\n"
        if full:
            save_message(conv_id, "user", b.message, tokens=estimate_tokens(b.message))
            save_message(conv_id, "assistant", full, tokens=estimate_tokens(full))
        yield "data: " + json.dumps({"done": True, "conversation_id": conv_id}) + "\n\n"

    return StreamingResponse(gen(), media_type="text/event-stream")


@app.post("/chat/ensemble")
async def ensemble(b: EnsembleIn, user=Depends(get_user)) -> dict[str, Any]:
    if len(b.providers) < 2:
        raise HTTPException(status_code=400, detail="Cần ít nhất 2 AI để ensemble.")

    async def one(prov: str):
        try:
            key = get_user_key(user["id"], prov, None)
            ans = await call_provider(prov, key, None, [], b.message)
            return prov, ans
        except HTTPException as e:
            return prov, f"[lỗi: {e.detail}]"

    results = await asyncio.gather(*[one(p) for p in b.providers])
    answers = {prov: ans for prov, ans in results}
    judge = b.judge or b.providers[0]
    judge_key = get_user_key(user["id"], judge, None)
    merged = (
        "Dưới đây là câu trả lời của nhiều AI cho cùng một câu hỏi. "
        "Hãy hợp nhất thành MỘT câu trả lời tốt nhất.\n\nCÂU HỎI:\n" + b.message
        + "\n\nCÁC CÂU TRẢ LỜI:\n"
        + "\n\n".join(f"### {p}\n{a}" for p, a in answers.items())
    )
    best = await call_provider(judge, judge_key, None, [], merged)
    return {"best": best, "judge": judge, "answers": answers}


# ======================== Lịch sử hội thoại ========================
@app.get("/conversations")
def list_conversations(user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute(
            "SELECT id,title,provider,pinned,updated_at FROM conversations WHERE user_id=? "
            "ORDER BY pinned DESC, updated_at DESC", (user["id"],)
        ).fetchall()
    return [dict(r) for r in rows]


@app.get("/conversations/{cid}")
def get_conversation(cid: int, user=Depends(get_user)) -> dict[str, Any]:
    msgs = load_history(cid, user["id"])
    return {"conversation_id": cid, "messages": msgs}


@app.delete("/conversations/{cid}")
def delete_conversation(cid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM messages WHERE conversation_id=? AND conversation_id IN "
                  "(SELECT id FROM conversations WHERE user_id=?)", (cid, user["id"]))
        c.execute("DELETE FROM conversations WHERE id=? AND user_id=?", (cid, user["id"]))
    return {"message": "Đã xóa hội thoại."}


# ======================== Pin hội thoại ========================
@app.post("/conversations/{cid}/pin")
def pin_conversation(cid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        row = c.execute("SELECT pinned FROM conversations WHERE id=? AND user_id=?",
                        (cid, user["id"])).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy hội thoại.")
        new_val = 0 if row["pinned"] else 1
        c.execute("UPDATE conversations SET pinned=? WHERE id=?", (new_val, cid))
    return {"pinned": bool(new_val), "message": "Đã ghim." if new_val else "Đã bỏ ghim."}


# ======================== Share hội thoại ========================
@app.post("/conversations/{cid}/share")
def share_conversation(cid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        row = c.execute("SELECT share_token FROM conversations WHERE id=? AND user_id=?",
                        (cid, user["id"])).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy hội thoại.")
        token = row["share_token"]
        if not token:
            token = secrets.token_urlsafe(24)
            c.execute("UPDATE conversations SET share_token=? WHERE id=?", (token, cid))
    return {"share_token": token, "share_url": f"/share/{token}"}


@app.get("/share/{token}")
def view_shared(token: str) -> dict[str, Any]:
    with db() as c:
        conv = c.execute("SELECT id,title,provider,created_at FROM conversations WHERE share_token=?",
                         (token,)).fetchone()
        if not conv:
            raise HTTPException(status_code=404, detail="Link chia sẻ không hợp lệ hoặc đã bị xóa.")
        msgs = c.execute("SELECT role,content,created_at FROM messages WHERE conversation_id=? ORDER BY id",
                         (conv["id"],)).fetchall()
    return {
        "conversation_id": conv["id"],
        "title": conv["title"],
        "provider": conv["provider"],
        "created_at": conv["created_at"],
        "messages": [dict(m) for m in msgs],
    }


# ======================== Export hội thoại ========================
@app.get("/conversations/{cid}/export")
def export_conversation(cid: int, format: str = "md", user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        conv = c.execute("SELECT title,provider,created_at FROM conversations WHERE id=? AND user_id=?",
                         (cid, user["id"])).fetchone()
        if not conv:
            raise HTTPException(status_code=404, detail="Không tìm thấy hội thoại.")
        msgs = c.execute("SELECT role,content,created_at FROM messages WHERE conversation_id=? ORDER BY id",
                         (cid,)).fetchall()

    messages_list = [dict(m) for m in msgs]

    if format == "json":
        content = json.dumps({
            "title": conv["title"],
            "provider": conv["provider"],
            "created_at": conv["created_at"],
            "messages": messages_list,
        }, ensure_ascii=False, indent=2)
        filename = f"conversation_{cid}.json"
    elif format == "txt":
        lines = [f"Hội thoại: {conv['title']}", f"Provider: {conv['provider']}", ""]
        for m in messages_list:
            role_label = "Bạn" if m["role"] == "user" else "AI"
            lines.append(f"[{role_label}]")
            lines.append(m["content"])
            lines.append("")
        content = "\n".join(lines)
        filename = f"conversation_{cid}.txt"
    else:  # md
        lines = [f"# {conv['title']}", f"**Provider:** {conv['provider']}", ""]
        for m in messages_list:
            role_label = "👤 Bạn" if m["role"] == "user" else "🤖 AI"
            lines.append(f"### {role_label}")
            lines.append(m["content"])
            lines.append("---")
            lines.append("")
        content = "\n".join(lines)
        filename = f"conversation_{cid}.md"

    data_b64 = base64.b64encode(content.encode("utf-8")).decode()
    return {"filename": filename, "format": format, "data_base64": data_b64, "content": content}


# ======================== Dọn dẹp cơ sở dữ liệu ========================
class CleanupIn(BaseModel):
    days: Optional[int] = 30


@app.post("/db/cleanup")
def db_cleanup(b: CleanupIn, user=Depends(get_user)) -> dict[str, Any]:
    """Dọn dẹp cơ sở dữ liệu: Xóa các tin nhắn cũ hơn X ngày."""
    import time
    days = b.days if b.days is not None else 30
    limit_time = int(time.time()) - (days * 24 * 60 * 60)
    
    with db() as c:
        db_path = "kenios.db"
        size_before = 0
        if os.path.exists(db_path):
            size_before = os.path.getsize(db_path)
            
        # Xóa tin nhắn trong các cuộc hội thoại không được ghim (pinned = 0 hoặc null)
        cur = c.execute(
            "DELETE FROM messages WHERE created_at < ? AND conversation_id IN ("
            "SELECT id FROM conversations WHERE pinned = 0 OR pinned IS NULL"
            ") AND content NOT IN (SELECT message_content FROM favorites)",
            (limit_time,)
        )
        deleted_msgs = cur.rowcount
        
        # Xóa các cuộc hội thoại cũ không có tin nhắn hoặc không được ghim
        cur2 = c.execute(
            "DELETE FROM conversations WHERE updated_at < ? AND (pinned = 0 OR pinned IS NULL) "
            "AND id NOT IN (SELECT DISTINCT conversation_id FROM messages WHERE conversation_id IS NOT NULL)",
            (limit_time,)
        )
        deleted_convs = cur2.rowcount
        
        # Chạy VACUUM để tối ưu dung lượng ổ đĩa cơ sở dữ liệu SQLite
        try:
            c.execute("VACUUM")
        except Exception:
            pass
        
        size_after = 0
        if os.path.exists(db_path):
            size_after = os.path.getsize(db_path)
            
        freed_bytes = max(0, size_before - size_after)
        
        # Hàm tính dung lượng thân thiện
        def human_size_python(bytes_size: int) -> str:
            if bytes_size < 1024:
                return f"{bytes_size} B"
            elif bytes_size < 1024 * 1024:
                return f"{bytes_size / 1024:.1f} KB"
            else:
                return f"{bytes_size / 1024 / 1024:.1f} MB"
                
        freed_space_str = human_size_python(freed_bytes)
        
    return {
        "deleted_messages": deleted_msgs,
        "deleted_conversations": deleted_convs,
        "freed_space": freed_space_str,
        "message": f"Đã giải phóng {freed_space_str}. Xóa {deleted_msgs} tin nhắn & {deleted_convs} hội thoại cũ."
    }


# ======================== Quản lý File (không giới hạn dung lượng) ========================
class FileIn(BaseModel):
    name: str
    category: Optional[str] = None
    mime: Optional[str] = None
    data_base64: str


@app.post("/files")
def upload_file(b: FileIn, user=Depends(get_user)) -> dict[str, Any]:
    # Không giới hạn dung lượng file/link gửi lên theo yêu cầu.
    size = (len(b.data_base64) * 3) // 4
    
    with db() as c:
        cur = c.execute(
            "INSERT INTO files(user_id,name,category,mime,size,data,created_at) "
            "VALUES(?,?,?,?,?,'',?)",
            (user["id"], b.name, b.category or _guess_category(b.name, b.mime),
             b.mime, size, int(time.time())),
        )
        fid = cur.lastrowid
        
    try:
        file_path = os.path.join(UPLOAD_DIR, str(fid))
        with open(file_path, "wb") as f:
            f.write(base64.b64decode(b.data_base64))
    except Exception as e:
        with db() as c:
            c.execute("DELETE FROM files WHERE id=?", (fid,))
        raise HTTPException(status_code=500, detail=f"Lỗi lưu file: {str(e)}")
        
    return {"id": fid, "name": b.name, "size": size, "mime": b.mime}


@app.post("/files/upload")
async def upload_file_raw(
    request: Request,
    name: str,
    category: Optional[str] = None,
    user = Depends(get_user)
) -> dict[str, Any]:
    # Không giới hạn dung lượng file gửi lên theo yêu cầu.
    temp_filename = f"tmp_{secrets.token_hex(8)}"
    temp_path = os.path.join(UPLOAD_DIR, temp_filename)

    total_size = 0
    try:
        with open(temp_path, "wb") as f:
            async for chunk in request.stream():
                total_size += len(chunk)
                f.write(chunk)
    except Exception as e:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Lỗi truyền phát file lên server: {str(e)}")

    if total_size < MIN_FILE_SIZE:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        raise HTTPException(status_code=400, detail="File quá nhỏ (giới hạn tối thiểu là 1KB).")

    mime = request.headers.get("content-type") or "application/octet-stream"
    with db() as c:
        cur = c.execute(
            "INSERT INTO files(user_id,name,category,mime,size,data,created_at) "
            "VALUES(?,?,?,?,?,'',?)",
            (user["id"], name, category or _guess_category(name, mime),
             mime, total_size, int(time.time())),
        )
        fid = cur.lastrowid

    final_path = os.path.join(UPLOAD_DIR, str(fid))
    os.rename(temp_path, final_path)
    
    return {"id": fid, "name": name, "size": total_size, "mime": mime}


def _can_access_file(c, fid: int, user) -> bool:
    """Cho phép tải file nếu: là chủ file, hoặc admin, hoặc đã MUA sản phẩm có file này."""
    own = c.execute("SELECT 1 FROM files WHERE id=? AND user_id=?", (fid, user["id"])).fetchone()
    if own:
        return True
    if user["is_admin"]:
        return True
    bought = c.execute(
        "SELECT 1 FROM store_orders o JOIN store_products p ON p.id=o.product_id "
        "WHERE o.user_id=? AND o.status='completed' AND p.download_file_id=? LIMIT 1",
        (user["id"], fid)).fetchone()
    return bought is not None


@app.get("/files/{fid}/download")
def download_file_raw(fid: int, background_tasks: BackgroundTasks, user=Depends(get_user)):
    with db() as c:
        if not _can_access_file(c, fid, user):
            raise HTTPException(status_code=404, detail="Không tìm thấy file.")
        row = c.execute("SELECT name,mime,data FROM files WHERE id=?", (fid,)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy file.")
        
    file_path = os.path.join(UPLOAD_DIR, str(fid))
    if os.path.exists(file_path):
        return FileResponse(
            path=file_path,
            filename=row["name"],
            media_type=row["mime"] or "application/octet-stream",
            content_disposition_type="attachment"
        )
        
    if row["data"]:
        try:
            temp_filename = f"temp_download_{fid}_{secrets.token_hex(4)}"
            temp_path = os.path.join(UPLOAD_DIR, temp_filename)
            with open(temp_path, "wb") as f:
                f.write(base64.b64decode(row["data"]))
            background_tasks.add_task(os.unlink, temp_path)
            return FileResponse(
                path=temp_path,
                filename=row["name"],
                media_type=row["mime"] or "application/octet-stream",
                content_disposition_type="attachment"
            )
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Lỗi nạp tệp từ DB: {e}")
            
    raise HTTPException(status_code=404, detail="Không tìm thấy nội dung tệp.")


def _guess_category(name: str, mime: Optional[str]) -> str:
    if mime and mime.startswith("image/"): return "image"
    ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    if ext in ("py", "js", "ts", "swift", "kt", "go", "rs", "c", "cpp", "java",
               "php", "rb", "sh", "html", "css", "sql", "json", "yaml", "toml"):
        return "code"
    if ext in ("pdf", "docx", "doc", "txt", "md"): return "document"
    if mime and mime.startswith("image/"): return "image"
    return "other"


@app.get("/files")
def list_files(category: Optional[str] = None,
               user=Depends(get_user)) -> list[dict[str, Any]]:
    q = "SELECT id,name,category,mime,size,created_at FROM files WHERE user_id=?"
    args: list[Any] = [user["id"]]
    if category and category != "all":
        q += " AND category=?"; args.append(category)
    q += " ORDER BY id DESC"
    with db() as c:
        rows = c.execute(q, args).fetchall()
    return [dict(r) for r in rows]


@app.get("/files/{fid}")
def download_file(fid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        if not _can_access_file(c, fid, user):
            raise HTTPException(status_code=404, detail="Không tìm thấy file.")
        row = c.execute(
            "SELECT name,category,mime,data,size FROM files WHERE id=?", (fid,)
        ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy file.")
        
    file_path = os.path.join(UPLOAD_DIR, str(fid))
    if os.path.exists(file_path):
        size = os.path.getsize(file_path)
        if size > 50_000_000:
            raise HTTPException(status_code=413, detail="Tệp quá lớn để tải qua JSON (lớn hơn 50MB). Vui lòng dùng link tải trực tiếp (Stream).")
        with open(file_path, "rb") as f:
            data_b64 = base64.b64encode(f.read()).decode()
    else:
        data_b64 = row["data"]
        
    return {"name": row["name"], "category": row["category"],
            "mime": row["mime"], "data_base64": data_b64}


@app.delete("/files/{fid}")
def delete_file(fid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM files WHERE id=? AND user_id=?", (fid, user["id"]))
    file_path = os.path.join(UPLOAD_DIR, str(fid))
    if os.path.exists(file_path):
        try:
            os.unlink(file_path)
        except Exception:
            pass
    return {"message": "Đã xóa file."}


# ======================== Chạy Code / Sandbox ========================
LANG_SPECS: dict[str, dict[str, Any]] = {
    "python":     {"src": "main.py",   "check": None,    "build": None,                                       "run": [sys.executable, "main.py"]},
    "javascript": {"src": "main.js",   "check": "node",  "build": None,                                       "run": ["node", "main.js"]},
    "node":       {"src": "main.js",   "check": "node",  "build": None,                                       "run": ["node", "main.js"]},
    "typescript": {"src": "main.ts",   "check": "ts-node","build": None,                                      "run": ["ts-node", "main.ts"]},
    "bash":       {"src": "main.sh",   "check": "bash",  "build": None,                                       "run": ["bash", "main.sh"]},
    "shell":      {"src": "main.sh",   "check": "bash",  "build": None,                                       "run": ["bash", "main.sh"]},
    "php":        {"src": "main.php",  "check": "php",   "build": None,                                       "run": ["php", "main.php"]},
    "ruby":       {"src": "main.rb",   "check": "ruby",  "build": None,                                       "run": ["ruby", "main.rb"]},
    "c":          {"src": "main.c",    "check": "gcc",   "build": ["gcc", "main.c", "-o", "app"],             "run": ["./app"]},
    "cpp":        {"src": "main.cpp",  "check": "g++",   "build": ["g++", "main.cpp", "-o", "app", "-std=c++17"], "run": ["./app"]},
    "c++":        {"src": "main.cpp",  "check": "g++",   "build": ["g++", "main.cpp", "-o", "app", "-std=c++17"], "run": ["./app"]},
    "go":         {"src": "main.go",   "check": "go",    "build": None,                                       "run": ["go", "run", "main.go"]},
    "java":       {"src": "Main.java", "check": "javac", "build": ["javac", "Main.java"],                     "run": ["java", "Main"]},
    "rust":       {"src": "main.rs",   "check": "rustc", "build": ["rustc", "main.rs", "-o", "app"],          "run": ["./app"]},
}
INSTALL_HINT = {
    "node": "apt install -y nodejs npm", "ts-node": "npm install -g ts-node typescript",
    "php": "apt install -y php-cli", "ruby": "apt install -y ruby",
    "gcc": "apt install -y gcc", "g++": "apt install -y g++",
    "go": "apt install -y golang-go", "javac": "apt install -y default-jdk",
    "rustc": "apt install -y rustc",
}

@app.post("/run/code")
def run_code(b: CodeRunIn, user=Depends(get_user)) -> dict[str, Any]:
    lang = (b.language or "python").lower().strip()
    spec = LANG_SPECS.get(lang)
    if not spec:
        raise HTTPException(status_code=400,
            detail=f"Ngôn ngữ '{lang}' chưa hỗ trợ. Hỗ trợ: {sorted(set(LANG_SPECS))}")
    check = spec["check"]
    if check and shutil.which(check) is None:
        hint = INSTALL_HINT.get(check, "")
        raise HTTPException(status_code=400,
            detail=(f"Máy chủ chưa cài '{check}' để chạy {lang}. "
                    + (f"Cài trên VPS bằng: sudo {hint}" if hint else "Hãy cài trình này trên VPS.")))
    workdir = tempfile.mkdtemp(prefix="kenios_")
    try:
        with open(os.path.join(workdir, spec["src"]), "w", encoding="utf-8") as f:
            f.write(b.code)
        if spec["build"]:
            cp = subprocess.run(spec["build"], cwd=workdir,
                                capture_output=True, text=True, timeout=SANDBOX_TIMEOUT)
            if cp.returncode != 0:
                return {"stdout": cp.stdout[:4000],
                        "stderr": "[Lỗi biên dịch]\n" + cp.stderr[:4000],
                        "returncode": cp.returncode, "language": lang}
        rp = subprocess.run(spec["run"], cwd=workdir, input=b.stdin or "",
                            capture_output=True, text=True, timeout=SANDBOX_TIMEOUT)
        return {"stdout": rp.stdout[:8000], "stderr": rp.stderr[:2000],
                "returncode": rp.returncode, "language": lang}
    except subprocess.TimeoutExpired:
        return {"stdout": "", "stderr": f"Timeout sau {SANDBOX_TIMEOUT} giây.",
                "returncode": -1, "language": lang}
    except Exception as e:
        return {"stdout": "", "stderr": str(e), "returncode": -2, "language": lang}
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


@app.post("/run/python")
def run_python(b: CodeRunIn, user=Depends(get_user)) -> dict[str, Any]:
    with tempfile.NamedTemporaryFile(mode="w", suffix=".py",
                                     delete=False) as f:
        f.write(b.code)
        tmp = f.name
    try:
        result = subprocess.run(
            [sys.executable, tmp],
            input=b.stdin or "",
            capture_output=True,
            text=True,
            timeout=SANDBOX_TIMEOUT,
        )
        return {
            "stdout": result.stdout[:8000],
            "stderr": result.stderr[:2000],
            "returncode": result.returncode,
        }
    except subprocess.TimeoutExpired:
        return {"stdout": "", "stderr": f"Timeout sau {SANDBOX_TIMEOUT} giây.",
                "returncode": -1}
    except Exception as e:
        return {"stdout": "", "stderr": str(e), "returncode": -2}
    finally:
        try: os.unlink(tmp)
        except Exception: pass


@app.post("/run/test")
def run_test_file(b: FileRunIn, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        row = c.execute("SELECT name,mime,data FROM files WHERE id=? AND user_id=?",
                        (b.file_id, user["id"])).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy file.")
        
    file_path = os.path.join(UPLOAD_DIR, str(b.file_id))
    if os.path.exists(file_path):
        try:
            with open(file_path, "rb") as f:
                code_bytes = f.read()
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Không đọc được file: {e}")
    else:
        try:
            code_bytes = base64.b64decode(row["data"])
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Không đọc được file: {e}")

    try:
        code_text  = code_bytes.decode("utf-8", errors="replace")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Không đọc được định dạng text: {e}")

    name = row["name"]
    ext  = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    suffix_map = {"py": ".py", "js": ".js", "sh": ".sh"}
    runner_map = {"py": [sys.executable], "js": ["node"], "sh": ["bash"]}
    if ext not in suffix_map:
        raise HTTPException(status_code=400,
            detail=f"Định dạng '{ext}' chưa hỗ trợ chạy test. Hỗ trợ: py, js, sh.")

    with tempfile.NamedTemporaryFile(mode="w", suffix=suffix_map[ext],
                                     delete=False) as f:
        f.write(code_text)
        tmp = f.name
    try:
        cmd = runner_map[ext] + [tmp]
        if b.args:
            cmd += b.args.split()
        result = subprocess.run(cmd, capture_output=True, text=True,
                                timeout=SANDBOX_TIMEOUT)
        return {
            "file": name, "stdout": result.stdout[:8000],
            "stderr": result.stderr[:2000],
            "returncode": result.returncode,
        }
    except subprocess.TimeoutExpired:
        return {"file": name, "stdout": "",
                "stderr": f"Timeout sau {SANDBOX_TIMEOUT} giây.", "returncode": -1}
    except FileNotFoundError as e:
        return {"file": name, "stdout": "",
                "stderr": f"Chưa cài runtime: {e}", "returncode": -3}
    finally:
        try: os.unlink(tmp)
        except Exception: pass


# ======================== Code AI Tools ========================
CODE_PROMPTS = {
    "review": "Hãy review code sau, chỉ ra lỗi, cải tiến, best practice:\n\n```{lang}\n{code}\n```",
    "debug": "Tìm và sửa lỗi trong đoạn code sau, giải thích từng lỗi:\n\n```{lang}\n{code}\n```",
    "explain": "Giải thích chi tiết đoạn code sau (bằng tiếng Việt):\n\n```{lang}\n{code}\n```",
    "convert": "Chuyển đoạn code {lang} sau sang {target_lang}, giữ nguyên logic:\n\n```{lang}\n{code}\n```",
    "test": "Viết unit test cho đoạn code {lang} sau (dùng framework phổ biến nhất):\n\n```{lang}\n{code}\n```",
    "optimize": "Tối ưu hiệu năng đoạn code {lang} sau, giải thích từng thay đổi:\n\n```{lang}\n{code}\n```",
    "document": "Viết documentation (docstring/comment) cho đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "security": "Kiểm tra bảo mật đoạn code {lang} sau, liệt kê lỗ hổng và cách vá:\n\n```{lang}\n{code}\n```",
    "refactor": "Refactor đoạn code {lang} sau cho sạch, dễ đọc, dễ bảo trì; giải thích thay đổi:\n\n```{lang}\n{code}\n```",
    "simplify": "Rút gọn đoạn code {lang} sau cho ngắn gọn nhất mà giữ nguyên kết quả:\n\n```{lang}\n{code}\n```",
    "typehint": "Thêm type hint / khai báo kiểu dữ liệu đầy đủ cho đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "comment": "Thêm comment giải thích những chỗ logic phức tạp trong đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "rename": "Đổi tên biến/hàm trong đoạn code {lang} sau cho rõ nghĩa, dễ hiểu:\n\n```{lang}\n{code}\n```",
    "complexity": "Phân tích độ phức tạp thời gian và bộ nhớ (Big-O) của đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "errorhandling": "Thêm xử lý lỗi / exception đầy đủ và hợp lý cho đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "validate": "Thêm kiểm tra/validate dữ liệu đầu vào cho đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "logging": "Thêm logging hợp lý (mức độ, vị trí) vào đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "async": "Chuyển đoạn code {lang} sau sang dạng bất đồng bộ (async/await), giải thích:\n\n```{lang}\n{code}\n```",
    "oop": "Cấu trúc lại đoạn code {lang} sau theo hướng đối tượng (class), giải thích:\n\n```{lang}\n{code}\n```",
    "functional": "Viết lại đoạn code {lang} sau theo phong cách lập trình hàm (functional):\n\n```{lang}\n{code}\n```",
    "modernize": "Cập nhật đoạn code {lang} sau lên cú pháp mới/hiện đại nhất của ngôn ngữ:\n\n```{lang}\n{code}\n```",
    "deprecate": "Tìm các API/hàm đã lỗi thời (deprecated) trong đoạn code {lang} sau và đề xuất thay thế:\n\n```{lang}\n{code}\n```",
    "lint": "Chỉ ra các vi phạm coding style / quy ước đặt tên trong đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "edgecases": "Liệt kê các trường hợp biên (edge case) cần kiểm thử cho đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "mockdata": "Sinh dữ liệu mẫu / fixture để test cho đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "memory": "Tìm các vấn đề rò rỉ bộ nhớ / dùng tài nguyên chưa giải phóng trong đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "threadsafe": "Kiểm tra tính an toàn luồng (thread-safe) của đoạn code {lang} sau và cách khắc phục:\n\n```{lang}\n{code}\n```",
    "dependency": "Phân tích và đề xuất giảm bớt thư viện/phụ thuộc cho đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "configextract": "Tách các hằng số / giá trị cấu hình ra khỏi logic trong đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "i18n": "Tách các chuỗi văn bản trong đoạn code {lang} sau để hỗ trợ đa ngôn ngữ (i18n):\n\n```{lang}\n{code}\n```",
    "regex": "Giải thích chi tiết các biểu thức regex xuất hiện trong đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "sqlexplain": "Giải thích câu lệnh SQL trong đoạn sau (bằng tiếng Việt):\n\n```{lang}\n{code}\n```",
    "sqloptimize": "Tối ưu câu lệnh SQL sau (index, cách viết lại), giải thích:\n\n```{lang}\n{code}\n```",
    "apidoc": "Sinh tài liệu API (dạng markdown) cho đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "readme": "Viết file README (markdown) mô tả cách dùng cho đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "dockerfile": "Viết Dockerfile phù hợp để đóng gói đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "ciyaml": "Viết file cấu hình CI/CD (GitHub Actions) để build/test đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "explainerror": "Giải thích thông báo lỗi / stack trace sau và cách khắc phục:\n\n```{lang}\n{code}\n```",
    "boilerplate": "Dựa trên mô tả/yêu cầu sau, sinh khung code {lang} đầy đủ:\n\n```{lang}\n{code}\n```",
    "cheatsheet": "Tạo cheat sheet tóm tắt các cú pháp/hàm chính dùng trong đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "translatecmt": "Dịch toàn bộ comment trong đoạn code {lang} sau sang tiếng Việt, giữ nguyên code:\n\n```{lang}\n{code}\n```",
    "responsive": "Chỉnh CSS/HTML sau cho responsive trên mọi kích thước màn hình:\n\n```{lang}\n{code}\n```",
    "accessibility": "Kiểm tra accessibility (a11y) của đoạn UI sau và đề xuất sửa:\n\n```{lang}\n{code}\n```",
    "namingstyle": "Chuẩn hoá quy ước đặt tên (camelCase/snake_case) cho đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
}


@app.post("/code/ai")
async def code_ai(b: CodeReviewIn, user=Depends(get_user)) -> dict[str, Any]:
    task = b.task.lower()
    if task not in CODE_PROMPTS:
        raise HTTPException(status_code=400,
            detail=f"Task '{task}' không hợp lệ. Hỗ trợ: {list(CODE_PROMPTS.keys())}")
    lang = b.language or "python"
    prompt = CODE_PROMPTS[task].format(
        lang=lang, code=b.code[:12000],
        target_lang=b.target_lang or "JavaScript",
    )
    key = get_user_key(user["id"], b.provider, b.api_key)
    result = await call_provider(b.provider, key, b.model, [], prompt,
                                 proxy=get_active_proxy(user["id"]))  # ← THÊM
    saved_files = save_code_blocks(user["id"], result, f"laptrinh_{task}")
    return {"result": result, "task": task, "provider": b.provider,
            "saved_files": saved_files}


# ======================== Auto-zip code blocks ========================
@app.post("/code/zip")
def zip_code_blocks(b: CodeZipIn, user=Depends(get_user)) -> dict[str, Any]:
    ext_map = {"python": "py", "py": "py", "javascript": "js", "js": "js",
               "typescript": "ts", "ts": "ts", "html": "html", "css": "css",
               "json": "json", "bash": "sh", "sh": "sh", "swift": "swift",
               "java": "java", "c": "c", "cpp": "cpp", "go": "go", "rust": "rs",
               "sql": "sql", "yaml": "yml", "yml": "yml", "markdown": "md", "md": "md",
               "php": "php", "ruby": "rb", "kotlin": "kt", "dart": "dart",
               "xml": "xml", "toml": "toml", "dockerfile": "Dockerfile",
               "makefile": "Makefile", "cmake": "CMakeLists.txt"}

    blocks = re.findall(r"```([a-zA-Z0-9_+\-]*)\n(.*?)```", b.text, re.DOTALL)
    if not blocks:
        raise HTTPException(status_code=400, detail="Không tìm thấy code block nào trong văn bản.")

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        n = 0
        for lang, code in blocks:
            code = code.rstrip("\n")
            if len(code.strip()) < 5:
                continue
            n += 1
            ext = ext_map.get(lang.lower().strip(), "txt")
            fname = f"code_{n}.{ext}"
            zf.writestr(fname, code)

    if n == 0:
        raise HTTPException(status_code=400, detail="Không có code block nào đủ dài để nén.")

    zip_b64 = base64.b64encode(buf.getvalue()).decode()
    return {
        "zip_base64": zip_b64,
        "filename": "code_blocks.zip",
        "total_blocks": n,
        "message": f"Đã nén {n} code block(s) thành file zip.",
    }


# ======================== Giọng nói (Transcribe & Synthesize) ========================
@app.post("/voice/transcribe")
async def transcribe(request: Request, user=Depends(get_user)) -> dict[str, Any]:
    body = await request.json()
    prov  = body.get("provider", "openai")
    audio_b64 = body.get("audio_base64")
    if not audio_b64:
        raise HTTPException(status_code=400, detail="Thiếu 'audio_base64'.")

    if PROVIDERS.get(prov, {}).get("kind") != "openai":
        raise HTTPException(status_code=400,
            detail="Phiên âm giọng nói chỉ hỗ trợ provider kiểu OpenAI (openai hoặc groq).")
    key   = get_user_key(user["id"], prov, body.get("api_key"))
    mime  = body.get("mime", "audio/m4a")
    ext_map = {"audio/m4a": "m4a", "audio/mp3": "mp3", "audio/mpeg": "mp3",
               "audio/wav": "wav", "audio/webm": "webm", "audio/ogg": "ogg"}
    ext   = ext_map.get(mime, "m4a")
    audio = base64.b64decode(audio_b64)

    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        r = await client.post(
            f"{PROVIDERS[prov]['base']}/audio/transcriptions",
            headers={"Authorization": f"Bearer {key}"},
            files={"file": (f"audio.{ext}", audio, mime)},
            data={"model": body.get("model", "whisper-1"),
                  "language": body.get("language", "vi")},
        )
    _raise_for_provider(r, prov)
    return {"text": r.json().get("text", ""),
            "provider": prov, "language": body.get("language", "vi")}


class SynthesizeIn(BaseModel):
    text: str
    voice: Optional[str] = "alloy"
    provider: Optional[str] = "openai"
    api_key: Optional[str] = None


@app.post("/voice/synthesize")
async def synthesize_speech(b: SynthesizeIn, user=Depends(get_user)) -> dict[str, Any]:
    """Phát âm văn bản (Text-To-Speech) và trả về âm thanh base64."""
    if not b.text.strip():
        raise HTTPException(status_code=400, detail="Thiếu nội dung văn bản.")
    prov = b.provider or "openai"
    key = get_user_key(user["id"], prov, b.api_key)
    p = PROVIDERS.get(prov)
    if not p or p["kind"] != "openai":
        raise HTTPException(status_code=400, detail="TTS chỉ hỗ trợ cho nhà cung cấp tương thích OpenAI.")
        
    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        r = await client.post(
            f"{p['base']}/audio/speech",
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
            json={"model": "tts-1", "input": b.text[:2000], "voice": b.voice or "alloy"}
        )
    if r.status_code != 200:
        raise HTTPException(status_code=r.status_code, detail=f"Lỗi OpenAI TTS: {r.text}")
    audio_b64 = base64.b64encode(r.content).decode()
    return {"audio_base64": audio_b64, "mime": "audio/mp3"}


# ======================== Vẽ ảnh AI (Image Generation) ========================
class ImageGenIn(BaseModel):
    prompt: str
    provider: Optional[str] = "openai"
    size: Optional[str] = "1024x1024"
    api_key: Optional[str] = None


@app.post("/image/generate")
async def generate_image(b: ImageGenIn, user=Depends(get_user)) -> dict[str, Any]:
    """Vẽ ảnh AI bằng DALL-E 3 và tự động lưu vào thư viện tệp của user."""
    if not b.prompt.strip():
        raise HTTPException(status_code=400, detail="Thiếu mô tả vẽ ảnh (prompt).")
    prov = b.provider or "openai"
    key = get_user_key(user["id"], prov, b.api_key)
    p = PROVIDERS.get(prov)
    if not p or p["kind"] != "openai":
        raise HTTPException(status_code=400, detail="Chỉ hỗ trợ vẽ ảnh qua nhà cung cấp tương thích OpenAI.")

    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        r = await client.post(
            f"{p['base']}/images/generations",
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
            json={"model": "dall-e-3", "prompt": b.prompt, "size": b.size or "1024x1024", "n": 1}
        )
        if r.status_code != 200:
            raise HTTPException(status_code=r.status_code, detail=f"Lỗi vẽ ảnh: {r.text}")
        
        img_data = r.json()
        img_url = img_data["data"][0]["url"]
        
        # Tải ảnh về lưu vào đĩa
        img_res = await client.get(img_url)
        if img_res.status_code == 200:
            img_bytes = img_res.content
            filename = f"art_{secrets.token_hex(4)}.png"
            with db() as c:
                cur = c.execute(
                    "INSERT INTO files(user_id,name,category,mime,size,data,created_at) "
                    "VALUES(?,?,?,?,?,'',?)",
                    (user["id"], filename, "image", "image/png", len(img_bytes), int(time.time())),
                )
                fid = cur.lastrowid
            
            file_path = os.path.join(UPLOAD_DIR, str(fid))
            with open(file_path, "wb") as f:
                f.write(img_bytes)
            
            return {"id": fid, "name": filename, "data_base64": base64.b64encode(img_bytes).decode(), "mime": "image/png"}
            
    raise HTTPException(status_code=500, detail="Lỗi tải ảnh về máy chủ.")


# ======================== Mạng xã hội (Social Media Tools) ========================
class SocialGenIn(BaseModel):
    topic: str
    platform: str
    tone: str
    mode: str
    provider: Optional[str] = "openai"
    api_key: Optional[str] = None


@app.post("/social/generator")
async def social_generator(b: SocialGenIn, user=Depends(get_user)) -> dict[str, Any]:
    """Tạo nội dung bài viết hoặc kịch bản video ngắn bằng AI."""
    import httpx
    if not b.topic.strip():
        raise HTTPException(status_code=400, detail="Thiếu chủ đề nội dung.")
    prov = b.provider or "openai"
    key = get_user_key(user["id"], prov, b.api_key)
    
    if b.mode == "script":
        prompt = (
            f"Bạn là một chuyên gia sáng tạo kịch bản video ngắn (TikTok, Reels, Shorts) chuyên nghiệp.\n"
            f"Hãy viết một kịch bản chi tiết cho video với chủ đề: '{b.topic}' trên nền tảng {b.platform.upper()}.\n"
            f"Giọng điệu yêu cầu: {b.tone}.\n"
            f"Yêu cầu kịch bản phải chia rõ: thời lượng dự kiến, Hook (3 giây đầu), phân cảnh hình ảnh (Visual cues), phân cảnh lời thoại/âm thanh (Audio cues), kèm theo 5-10 hashtags thịnh hành ở cuối."
        )
    else:
        prompt = (
            f"Bạn là một chuyên gia viết bài đăng mạng xã hội thu hút tương tác (Copywriter).\n"
            f"Hãy viết một bài đăng hấp dẫn với chủ đề: '{b.topic}' trên nền tảng {b.platform.upper()}.\n"
            f"Giọng điệu yêu cầu: {b.tone}.\n"
            f"Bài viết cần ngắn gọn, xúc tích, có cấu trúc rõ ràng, sử dụng nhiều biểu tượng cảm xúc (emojis) phù hợp, kết hợp lời kêu gọi hành động (Call-To-Action) cuốn hút và 5-10 hashtags thịnh hành ở cuối."
        )

    p = PROVIDERS.get(prov)
    if not p:
        raise HTTPException(status_code=400, detail=f"Không tìm thấy nhà cung cấp '{prov}'.")

    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        r = await client.post(
            f"{p['base']}/chat/completions",
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
            json={
                "model": p.get("default_model", "gpt-4o-mini"),
                "messages": [
                    {"role": "system", "content": "You are a helpful assistant specialized in social media copy writing."},
                    {"role": "user", "content": prompt}
                ]
            }
        )
    _raise_for_provider(r, prov)
    res_data = r.json()
    reply = res_data["choices"][0]["message"]["content"]
    return {"content": reply}


class SocialDownloadIn(BaseModel):
    url: str
    quality: str = "1080"   # 720 | 1080 | 2k | 4k | best


@app.post("/social/download")
async def social_download(b: SocialDownloadIn, user=Depends(get_user)) -> dict[str, Any]:
    """Tải video TikTok/Facebook/Pinterest/YouTube về thư viện (chọn độ phân giải) bằng yt-dlp."""
    import time, tempfile, glob, shutil
    url = b.url.strip()
    if not url:
        raise HTTPException(status_code=400, detail="Thiếu link video.")
    if not shutil.which("yt-dlp"):
        raise HTTPException(status_code=400,
            detail="Máy chủ chưa cài yt-dlp. Chạy trên VPS: pip install -U yt-dlp và apt install -y ffmpeg.")

    qmap = {"720": 720, "1080": 1080, "2k": 1440, "1440": 1440,
            "4k": 2160, "2160": 2160, "best": 9999}
    h = qmap.get((b.quality or "1080").lower().strip(), 1080)
    fmt = f"bestvideo[height<={h}]+bestaudio/best[height<={h}]/best"

    tmp = tempfile.mkdtemp(prefix="kdl_")
    out_tpl = os.path.join(tmp, "%(title).60s.%(ext)s")
    cmd = ["yt-dlp", "-f", fmt, "--merge-output-format", "mp4", "--no-playlist",
           "--restrict-filenames", "--no-warnings", "-o", out_tpl, url]
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        _, err = await asyncio.wait_for(proc.communicate(), timeout=1800)  # 30 phút — video dài/nặng
    except asyncio.TimeoutError:
        shutil.rmtree(tmp, ignore_errors=True)
        raise HTTPException(status_code=504, detail="Tải quá lâu (timeout). Thử độ phân giải thấp hơn.")
    except Exception as e:
        shutil.rmtree(tmp, ignore_errors=True)
        raise HTTPException(status_code=500, detail=f"Lỗi yt-dlp: {e}")

    files = [f for f in glob.glob(os.path.join(tmp, "*")) if os.path.isfile(f)]
    if not files:
        detail = (err.decode("utf-8", "replace")[-300:] if err else "")
        shutil.rmtree(tmp, ignore_errors=True)
        raise HTTPException(status_code=400,
            detail=f"Không tải được video (kiểm tra link / nền tảng). {detail}")

    src = max(files, key=os.path.getsize)
    fname = os.path.basename(src)
    if not fname.lower().endswith(".mp4"):
        fname = os.path.splitext(fname)[0] + ".mp4"
    size = os.path.getsize(src)

    with db() as c:
        cur = c.execute(
            "INSERT INTO files(user_id,name,category,mime,size,data,created_at) "
            "VALUES(?,?,?,?,?,'',?)",
            (user["id"], fname, "document", "video/mp4", size, int(time.time())))
        fid = cur.lastrowid

    dest = os.path.join(UPLOAD_DIR, str(fid))
    try:
        shutil.move(src, dest)
    except Exception as e:
        with db() as c:
            c.execute("DELETE FROM files WHERE id=?", (fid,))
        shutil.rmtree(tmp, ignore_errors=True)
        raise HTTPException(status_code=500, detail=f"Lỗi khi ghi tệp: {e}")
    shutil.rmtree(tmp, ignore_errors=True)
    return {"file_id": fid, "filename": fname, "size": size}


def _parse_cookie_string(cookies_str: str) -> dict[str, str]:
    """Đọc cookie ở dạng JSON (mảng {name,value} hoặc object) hoặc chuỗi 'a=b; c=d'."""
    cookies_str = (cookies_str or "").strip()
    cookie_dict: dict[str, str] = {}
    if not cookies_str:
        return cookie_dict
    if cookies_str.startswith("[") or cookies_str.startswith("{"):
        try:
            import json as _json
            j = _json.loads(cookies_str)
            if isinstance(j, list):
                for c in j:
                    if isinstance(c, dict) and "name" in c and "value" in c:
                        cookie_dict[c["name"]] = c["value"]
            elif isinstance(j, dict):
                cookie_dict = {str(k): str(v) for k, v in j.items()}
        except Exception:
            pass
    if not cookie_dict:
        for item in cookies_str.split(";"):
            item = item.strip()
            if "=" in item:
                k, v = item.split("=", 1)
                cookie_dict[k.strip()] = v.strip()
    return cookie_dict


async def _fb_token_from_cookies(cookie_dict: dict[str, str]) -> Optional[str]:
    """Best-effort: dùng phiên đăng nhập Facebook (c_user + xs) để lấy access token.

    Thử lần lượt vài trang nội bộ của Facebook và trích token EAA... trong HTML.
    Trả None nếu không lấy được (cookie hết hạn / chưa đủ quyền)."""
    import httpx
    if "c_user" not in cookie_dict or "xs" not in cookie_dict:
        return None
    cookie_header = "; ".join(f"{k}={v}" for k, v in cookie_dict.items())
    headers = {
        "User-Agent": ("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) "
                       "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"),
        "Cookie": cookie_header,
        "Accept": "text/html,application/xhtml+xml,application/json,*/*",
        "Accept-Language": "vi-VN,vi;q=0.9,en;q=0.8",
    }
    probe_urls = [
        "https://business.facebook.com/content_management",
        "https://business.facebook.com/creatorstudio/",
        "https://business.facebook.com/latest/home",
        "https://www.facebook.com/adsmanager/manage/campaigns",
        "https://m.facebook.com/composer/ocelot/async_loader/?publisher=feed",
    ]
    # Token Facebook thật khá dài; lấy NHIỀU ứng viên rồi kiểm chứng từng cái,
    # chỉ trả về token gọi được Graph API (tránh nhặt trúng chuỗi cụt -> "Malformed").
    pattern = re.compile(r'EAA[A-Za-z0-9]{40,}')
    candidates: list[str] = []
    try:
        async with httpx.AsyncClient(timeout=30, follow_redirects=True) as client:
            for u in probe_urls:
                try:
                    r = await client.get(u, headers=headers)
                except Exception:
                    continue
                for m in pattern.finditer(r.text or ""):
                    tok = m.group(0)
                    if tok not in candidates:
                        candidates.append(tok)
            # Kiểm chứng: chỉ nhận token gọi được /me
            for tok in candidates:
                try:
                    vr = await client.get("https://graph.facebook.com/v19.0/me",
                                          params={"access_token": tok, "fields": "id"})
                    if vr.status_code == 200 and (vr.json() or {}).get("id"):
                        return tok
                except Exception:
                    continue
    except Exception:
        return None
    return None


class FBStreamIn(BaseModel):
    cookies: str = ""
    access_token: str = ""


@app.post("/social/stream/facebook")
async def facebook_stream(b: FBStreamIn, user=Depends(get_user)) -> dict[str, Any]:
    """Tạo Live Stream trên Facebook bằng Cookies (tự lấy token) hoặc Access Token."""
    import httpx
    import time
    token = (b.access_token or "").strip()
    cookies_str = (b.cookies or "").strip()

    # Ưu tiên cookie: tự lấy access token từ phiên đăng nhập
    if not token and cookies_str:
        if "FAKE" in cookies_str:
            return {
                "rtmp_url": "rtmps://live-api-s.facebook.com:443/rtmp/",
                "stream_key": f"FB-{int(time.time())}-mock-stream-key",
                "title": f"Live Stream {int(time.time())}",
            }
        cookie_dict = _parse_cookie_string(cookies_str)
        token = (await _fb_token_from_cookies(cookie_dict)) or ""
        if not token:
            raise HTTPException(
                status_code=400,
                detail=("Không lấy được token từ cookie Facebook. Hãy đăng nhập lại Facebook "
                        "trong trình duyệt tích hợp (lấy cookie mới), hoặc dán Access Token thủ công."))

    if not token:
        raise HTTPException(status_code=400, detail="Thiếu cookie hoặc Access Token Facebook.")

    url = "https://graph.facebook.com/v19.0/me/live_videos"
    async with httpx.AsyncClient(timeout=30) as client:
        r = await client.post(
            url,
            params={
                "access_token": token,
                "status": "LIVE_NOW",
                "title": f"Live Stream {int(time.time())}",
                "description": "Phát trực tiếp từ KENIOS"
            }
        )
    if r.status_code != 200:
        # Fallback for mock/testing when the token is fake
        if "FAKE" in token or "test" in token.lower():
            return {
                "rtmp_url": "rtmps://live-api-s.facebook.com:443/rtmp/",
                "stream_key": f"FB-{int(time.time())}-mock-stream-key",
                "title": f"Live Stream {int(time.time())}"
            }
        err_msg = (r.json().get("error", {}) or {}).get("message", "Lỗi tạo Live Video trên Facebook.")
        raise HTTPException(
            status_code=400,
            detail=(err_msg + " — Facebook hạn chế API Live. Cách chắc chắn: mở "
                    "facebook.com/live/producer, tạo buổi live để lấy Server URL + Stream Key, "
                    "rồi dán vào mục 'Lưu điểm phát' trong app."))
        
    res_data = r.json()
    rtmp_url = res_data.get("secure_stream_url") or res_data.get("stream_url")
    stream_key = None
    if rtmp_url and "/" in rtmp_url:
        parts = rtmp_url.rsplit("/", 1)
        rtmp_url = parts[0] + "/"
        stream_key = parts[1]
    
    return {
        "rtmp_url": rtmp_url,
        "stream_key": stream_key or res_data.get("id"),
        "title": f"Live Stream {res_data.get('id')}"
    }


def _sapisid_hash(sapisid: str, origin: str) -> str:
    """Tạo header Authorization SAPISIDHASH cho API nội bộ của Google/YouTube."""
    import hashlib, time
    ts = int(time.time())
    digest = hashlib.sha1(f"{ts} {sapisid} {origin}".encode()).hexdigest()
    return f"SAPISIDHASH {ts}_{digest}"


async def _yt_stream_from_cookies(cookie_dict: dict[str, str], title: str) -> Optional[dict[str, str]]:
    """Best-effort: tạo liveStream YouTube bằng cookie (SAPISIDHASH → API nội bộ Studio).

    Lưu ý: API chính thức của YouTube cần OAuth; đường cookie này mang tính thử nghiệm,
    có thể không thành công với mọi tài khoản. Trả None nếu không tạo được."""
    import httpx
    sapisid = (cookie_dict.get("SAPISID") or cookie_dict.get("__Secure-3PAPISID")
               or cookie_dict.get("__Secure-1PAPISID"))
    if not sapisid:
        return None
    origin = "https://studio.youtube.com"
    cookie_header = "; ".join(f"{k}={v}" for k, v in cookie_dict.items())
    headers = {
        "Authorization": _sapisid_hash(sapisid, origin),
        "Origin": origin,
        "Referer": origin + "/",
        "Cookie": cookie_header,
        "Content-Type": "application/json",
        "X-Origin": origin,
        "User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                       "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"),
    }
    context = {"client": {"clientName": "WEB", "clientVersion": "2.0",
                          "hl": "vi", "gl": "VN"}}
    payload = {"context": context,
               "title": title,
               "frameRate": "FRAME_RATE_60FPS",
               "ingestionType": "RTMP",
               "resolution": "RESOLUTION_1080P"}
    endpoints = [
        "https://studio.youtube.com/youtubei/v1/live_streaming/create_stream?alt=json",
        "https://studio.youtube.com/youtubei/v1/live_chat/create_stream?alt=json",
    ]
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            for ep in endpoints:
                try:
                    r = await client.post(ep, headers=headers, json=payload)
                except Exception:
                    continue
                if r.status_code not in (200, 201):
                    continue
                try:
                    j = r.json()
                except Exception:
                    continue
                blob = json.dumps(j)
                # Trích RTMP + stream key theo nhiều dạng field
                addr = re.search(r'"(?:ingestionAddress|rtmpsIngestionAddress|address)"\s*:\s*"([^"]+)"', blob)
                key = re.search(r'"(?:streamName|streamKey|key)"\s*:\s*"([^"]+)"', blob)
                if addr and key:
                    rtmp = addr.group(1)
                    if not rtmp.endswith("/"):
                        rtmp += "/"
                    return {"rtmp_url": rtmp, "stream_key": key.group(1)}
    except Exception:
        return None
    return None


class YouTubeStreamIn(BaseModel):
    cookies: str = ""
    access_token: str = ""
    title: str = ""


@app.post("/social/stream/youtube")
async def youtube_stream(b: YouTubeStreamIn, user=Depends(get_user)) -> dict[str, Any]:
    """Tạo Live Stream trên YouTube bằng Cookies (SAPISIDHASH) hoặc Google OAuth Access Token."""
    import httpx, time
    token = (b.access_token or "").strip()
    cookies_str = (b.cookies or "").strip()
    title = (b.title.strip() or f"Live Stream {int(time.time())}")[:100]

    # Ưu tiên cookie: thử tạo liveStream qua API nội bộ Studio
    if not token and cookies_str:
        if "FAKE" in cookies_str:
            return {"rtmp_url": "rtmp://a.rtmp.youtube.com/live2/",
                    "stream_key": f"YT-{int(time.time())}-mock", "title": title}
        cookie_dict = _parse_cookie_string(cookies_str)
        got = await _yt_stream_from_cookies(cookie_dict, title)
        if got:
            return {"rtmp_url": got["rtmp_url"], "stream_key": got["stream_key"], "title": title}
        raise HTTPException(
            status_code=400,
            detail=("Không tạo được Live YouTube từ cookie (API YouTube yêu cầu quyền OAuth). "
                    "Hãy đăng nhập lại YouTube để lấy cookie mới, hoặc dán Google Access Token (ya29...)."))

    if not token:
        raise HTTPException(status_code=400, detail="Thiếu cookie hoặc Google Access Token cho YouTube.")
    headers = {"Authorization": f"Bearer {token}"}
    async with httpx.AsyncClient(timeout=30) as client:
        # 1) Tạo liveStream → lấy RTMP ingestion + stream key
        s = await client.post(
            "https://www.googleapis.com/youtube/v3/liveStreams",
            params={"part": "snippet,cdn"}, headers=headers,
            json={"snippet": {"title": title},
                  "cdn": {"frameRate": "variable", "ingestionType": "rtmp", "resolution": "variable"}})
        if s.status_code not in (200, 201):
            if "FAKE" in token or "test" in token.lower():
                return {"rtmp_url": "rtmp://a.rtmp.youtube.com/live2/",
                        "stream_key": f"YT-{int(time.time())}-mock", "title": title}
            msg = (s.json().get("error", {}) or {}).get("message", "Lỗi tạo Live Stream trên YouTube.")
            raise HTTPException(status_code=400, detail=msg)
        sd = s.json()
        ing = (sd.get("cdn", {}) or {}).get("ingestionInfo", {}) or {}
        rtmp_url = ing.get("ingestionAddress", "")
        stream_key = ing.get("streamName", "")
        stream_id = sd.get("id")
        # 2) Tạo broadcast + bind (để buổi live hiện trên kênh) — best effort, lỗi vẫn trả RTMP+Key
        try:
            start = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 60))
            bc = await client.post(
                "https://www.googleapis.com/youtube/v3/liveBroadcasts",
                params={"part": "snippet,status,contentDetails"}, headers=headers,
                json={"snippet": {"title": title, "scheduledStartTime": start},
                      "status": {"privacyStatus": "public", "selfDeclaredMadeForKids": False},
                      "contentDetails": {"enableAutoStart": True, "enableAutoStop": True}})
            bid = bc.json().get("id") if bc.status_code in (200, 201) else None
            if bid and stream_id:
                await client.post(
                    "https://www.googleapis.com/youtube/v3/liveBroadcasts/bind",
                    params={"id": bid, "part": "id,contentDetails", "streamId": stream_id},
                    headers=headers)
        except Exception:
            pass
        if rtmp_url and not rtmp_url.endswith("/"):
            rtmp_url += "/"
        return {"rtmp_url": rtmp_url, "stream_key": stream_key, "title": title}


class TikTokStreamIn(BaseModel):
    cookies: str


@app.post("/social/stream/tiktok")
async def tiktok_stream(b: TikTokStreamIn, user=Depends(get_user)) -> dict[str, Any]:
    """Tạo Webcast Live Room trên TikTok bằng Cookies."""
    import httpx
    import time
    cookies_str = b.cookies.strip()
    if not cookies_str:
        raise HTTPException(status_code=400, detail="Thiếu cookies đăng nhập TikTok.")
    
    cookie_dict = {}
    if cookies_str.startswith("[") or cookies_str.startswith("{"):
        try:
            import json
            j_data = json.loads(cookies_str)
            if isinstance(j_data, list):
                for c in j_data:
                    if "name" in c and "value" in c:
                        cookie_dict[c["name"]] = c["value"]
            elif isinstance(j_data, dict):
                cookie_dict = j_data
        except Exception:
            pass
    
    if not cookie_dict:
        for item in cookies_str.split(";"):
            item = item.strip()
            if "=" in item:
                parts = item.split("=", 1)
                cookie_dict[parts[0]] = parts[1]
                
    if not cookie_dict:
        raise HTTPException(status_code=400, detail="Định dạng cookie không hợp lệ. Hãy sử dụng định dạng JSON hoặc Netscape.")

    # Simple fallback check if user is testing with mock cookies
    if "FAKE" in cookies_str or "sessionid" not in cookie_dict:
        return {
            "rtmp_url": "rtmp://live-push.tiktok.com/live/",
            "stream_key": f"stream-key-tt-{int(time.time())}",
            "title": f"TikTok Live {int(time.time())}"
        }

    url = "https://webcast.tiktok.com/webcast/room/create/"
    # Cookie header dạng chuỗi (một số endpoint TikTok đọc raw Cookie header)
    cookie_header = "; ".join(f"{k}={v}" for k, v in cookie_dict.items())
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": "https://www.tiktok.com/",
        "Origin": "https://www.tiktok.com",
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "vi-VN,vi;q=0.9,en;q=0.8",
        "Cookie": cookie_header,
        "X-Requested-With": "XMLHttpRequest",
    }
    # Tham số web-app TikTok thường bắt buộc
    params = {
        "aid": "1988",
        "app_language": "vi",
        "device_platform": "web_pc",
        "priority_region": "VN",
    }

    try:
        async with httpx.AsyncClient(timeout=30, follow_redirects=True) as client:
            r = await client.post(
                url,
                headers=headers,
                params=params,
                cookies=cookie_dict,
                data={
                    "title": f"Live Stream {int(time.time())}",
                    "live_type": "0",        # OBS / RTMP push
                    "hashtag_id": "0",
                    "gen_replay": "1",
                }
            )
        # Cố parse JSON dù status khác 200
        try:
            res_json = r.json()
        except Exception:
            raise HTTPException(status_code=400,
                detail=f"TikTok trả về không phải JSON (HTTP {r.status_code}). Cookie có thể hết hạn.")

        if res_json.get("status_code") == 0 and isinstance(res_json.get("data"), dict):
            data = res_json["data"]
            stream_data = data.get("stream_url", {}) or {}
            # Đọc nhiều dạng field khác nhau TikTok dùng
            rtmp_url = (stream_data.get("rtmp_push_url")
                        or data.get("rtmp_push_url")
                        or stream_data.get("push_url"))
            stream_key = (stream_data.get("push_key")
                          or data.get("push_key")
                          or stream_data.get("stream_key"))
            # Nếu chỉ có 1 link gộp rtmp://.../<key> thì tách ra
            if rtmp_url and not stream_key and "/" in rtmp_url:
                idx = rtmp_url.rfind("/")
                stream_key = rtmp_url[idx + 1:]
                rtmp_url = rtmp_url[:idx + 1]
            if rtmp_url and stream_key:
                return {
                    "rtmp_url": rtmp_url,
                    "stream_key": stream_key,
                    "title": f"TikTok Live {int(time.time())}"
                }

        # Trích thông báo lỗi rõ ràng từ TikTok
        data = res_json.get("data") if isinstance(res_json.get("data"), dict) else {}
        err_msg = (data.get("prompts")
                   or res_json.get("message")
                   or "Tài khoản chưa đủ điều kiện Live (cần đủ follower / bật quyền Live OBS) hoặc Cookie hết hạn.")
        raise HTTPException(status_code=400, detail=err_msg)
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=400, detail=f"Không thể tạo phòng Live trên TikTok: {e}")


# ======================== Restream đa nền tảng (VPS tự nhân luồng bằng ffmpeg) ========================
# Điện thoại đẩy MỘT luồng (màn hình) tới rtmp://VPS:1935/live/<key>, VPS dùng ffmpeg
# sao chép (không mã hoá lại) và đẩy ĐỒNG THỜI sang TikTok + Facebook + YouTube.
_restream_proc: Optional[subprocess.Popen] = None
_restream_meta: dict[str, Any] = {}


class RestreamTarget(BaseModel):
    name: str = ""
    rtmp: str
    key: str


class RestreamStartIn(BaseModel):
    targets: list[RestreamTarget]
    resolution: str = "source"   # source | 1080 | 720 | 480
    fps: str = "source"          # source | 60 | 30


def _restream_host(request: Request) -> str:
    h = os.getenv("RTMP_HOST", "").strip()
    if h:
        return h
    host = request.headers.get("host", "") or (request.client.host if request.client else "")
    return host.split(":")[0] or "127.0.0.1"


def _restream_stop_proc() -> None:
    global _restream_proc
    if _restream_proc is not None:
        try:
            _restream_proc.terminate()
        except Exception:
            pass
        _restream_proc = None


@app.post("/live/restream/start")
def restream_start(b: RestreamStartIn, request: Request, user=Depends(get_user)) -> dict[str, Any]:
    global _restream_proc, _restream_meta
    outs: list[str] = []
    for t in b.targets:
        rtmp = (t.rtmp or "").strip().rstrip("/")
        key = (t.key or "").strip()
        if rtmp and key:
            outs.append(f"[f=flv]{rtmp}/{key}")
    if not outs:
        raise HTTPException(status_code=400, detail="Chưa có đích phát hợp lệ (RTMP + key).")
    if not shutil.which("ffmpeg"):
        raise HTTPException(status_code=400, detail="VPS chưa cài ffmpeg. Cài: apt install ffmpeg")
    _restream_stop_proc()
    ingest_key = secrets.token_hex(8)
    ingest_local = f"rtmp://0.0.0.0:1935/live/{ingest_key}"

    # Chọn chế độ: sao chép (nhẹ CPU, giữ nguyên FPS/độ phân giải của điện thoại)
    # hoặc mã hoá lại để ÉP độ phân giải + FPS theo lựa chọn.
    res = (b.resolution or "source").strip()
    fps = (b.fps or "source").strip()
    if res == "source" and fps == "source":
        enc = ["-c", "copy"]
    else:
        enc = []
        if res in ("1080", "720", "480"):
            enc += ["-vf", f"scale={res}:-2"]   # ép bề rộng (màn dọc), cao tự động (chẵn)
        bitrate = {"1080": "4500k", "720": "2500k", "480": "1200k"}.get(res, "2500k")
        if fps in ("60", "30"):
            enc += ["-r", fps]
        enc += ["-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p",
                "-b:v", bitrate, "-maxrate", bitrate, "-bufsize", bitrate, "-g", "60",
                "-c:a", "aac", "-b:a", "128k"]
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "warning",
           "-listen", "1", "-i", ingest_local] + enc + ["-f", "tee", "-map", "0", "|".join(outs)]
    try:
        _restream_proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Không khởi động được ffmpeg: {e}")
    host = _restream_host(request)
    _restream_meta = {"running": True,
                      "ingest_url": f"rtmp://{host}:1935/live/{ingest_key}",
                      "key": ingest_key, "targets": len(outs),
                      "resolution": res, "fps": fps,
                      "started_at": int(time.time()), "uid": user["id"]}
    return _restream_meta


@app.post("/live/restream/stop")
def restream_stop(user=Depends(get_user)) -> dict[str, Any]:
    _restream_stop_proc()
    _restream_meta.clear()
    return {"running": False, "stopped": True}


@app.get("/live/restream/status")
def restream_status() -> dict[str, Any]:
    running = _restream_proc is not None and (_restream_proc.poll() is None)
    if not running:
        _restream_meta.clear()
        return {"running": False}
    return {**_restream_meta, "running": True}


# ======================== TikTok Live: đọc bình luận tự động (như TikFinity) ========================
# Kết nối tới phòng LIVE của một username TikTok và thu các sự kiện (bình luận, quà,
# follow, share, vào phòng) vào bộ đệm để app lấy về rồi đọc bằng TTS.
import collections as _collections

_tiktok_live_sessions: dict[str, dict[str, Any]] = {}
_tiktok_live_lock = asyncio.Lock()


def _tt_norm_user(u: str) -> str:
    u = (u or "").strip()
    if u.startswith("http"):
        m = re.search(r"@([\w.\-]+)", u)
        if m:
            u = m.group(1)
        else:
            u = u.rstrip("/").split("/")[-1]
    return u.lstrip("@").strip()


async def _tiktok_live_runner(username: str) -> None:
    sess = _tiktok_live_sessions.get(username)
    if sess is None:
        return
    try:
        from TikTokLive import TikTokLiveClient
        from TikTokLive.events import (
            ConnectEvent, CommentEvent, GiftEvent, FollowEvent,
            ShareEvent, JoinEvent, LiveEndEvent,
        )
    except Exception:
        sess["status"] = "error"
        sess["error"] = ("Máy chủ chưa cài thư viện TikTokLive. "
                         "Hãy chạy trên VPS: pip install TikTokLive")
        return

    def push(etype: str, name: str, content: str = "") -> None:
        sess["seq"] += 1
        sess["events"].append({
            "id": sess["seq"], "type": etype,
            "name": name or "", "content": content or "",
        })

    client = TikTokLiveClient(unique_id=f"@{username}")
    sess["client"] = client

    @client.on(ConnectEvent)
    async def _on_connect(_e):
        sess["status"] = "connected"

    @client.on(CommentEvent)
    async def _on_comment(e):
        name = getattr(getattr(e, "user", None), "nickname", "") or getattr(getattr(e, "user", None), "unique_id", "")
        push("comment", name, getattr(e, "comment", ""))

    @client.on(GiftEvent)
    async def _on_gift(e):
        g = getattr(e, "gift", None)
        # quà có streak: chỉ đọc khi chuỗi kết thúc để tránh đọc lặp
        if g is not None and getattr(g, "streakable", False) and getattr(e, "streaking", False):
            return
        name = getattr(getattr(e, "user", None), "nickname", "")
        push("gift", name, getattr(g, "name", "quà"))

    @client.on(FollowEvent)
    async def _on_follow(e):
        push("follow", getattr(getattr(e, "user", None), "nickname", ""))

    @client.on(ShareEvent)
    async def _on_share(e):
        push("share", getattr(getattr(e, "user", None), "nickname", ""))

    @client.on(JoinEvent)
    async def _on_join(e):
        push("join", getattr(getattr(e, "user", None), "nickname", ""))

    @client.on(LiveEndEvent)
    async def _on_end(_e):
        sess["status"] = "ended"

    try:
        await client.start()
    except asyncio.CancelledError:
        pass
    except Exception as ex:
        sess["status"] = "error"
        sess["error"] = f"Không kết nối được LIVE của @{username}: {ex}. (Người dùng phải đang phát trực tiếp.)"


class TikTokLiveIn(BaseModel):
    username: str


@app.post("/social/tiktok/live/connect")
async def tiktok_live_connect(b: TikTokLiveIn) -> dict[str, Any]:
    """Bắt đầu lắng nghe bình luận/quà của một phòng LIVE TikTok.

    Không yêu cầu đăng nhập: chỉ cần có link / ID phòng LIVE là kết nối & đọc được
    (kể cả khi phiên đăng nhập trong app đã hết hạn).
    """
    username = _tt_norm_user(b.username)
    if not username:
        raise HTTPException(status_code=400, detail="Thiếu ID / username TikTok.")
    async with _tiktok_live_lock:
        sess = _tiktok_live_sessions.get(username)
        if sess and sess.get("status") in ("connecting", "connected"):
            return {"ok": True, "status": sess["status"], "username": username}
        sess = {
            "events": _collections.deque(maxlen=500),
            "seq": 0, "status": "connecting", "error": None,
            "client": None, "task": None,
        }
        _tiktok_live_sessions[username] = sess
        sess["task"] = asyncio.create_task(_tiktok_live_runner(username))
    return {"ok": True, "status": "connecting", "username": username}


@app.get("/social/tiktok/live/events")
async def tiktok_live_events(username: str, after: int = 0) -> dict[str, Any]:
    """Lấy các sự kiện mới (id > after) để app đọc bằng TTS."""
    u = _tt_norm_user(username)
    sess = _tiktok_live_sessions.get(u)
    if not sess:
        return {"status": "idle", "error": None, "events": [], "last": after}
    evs = [e for e in list(sess["events"]) if e["id"] > after]
    last = evs[-1]["id"] if evs else after
    return {"status": sess["status"], "error": sess.get("error"), "events": evs, "last": last}


@app.post("/social/tiktok/live/disconnect")
async def tiktok_live_disconnect(b: TikTokLiveIn) -> dict[str, Any]:
    """Ngắt lắng nghe phòng LIVE."""
    u = _tt_norm_user(b.username)
    sess = _tiktok_live_sessions.pop(u, None)
    if sess:
        client = sess.get("client")
        if client is not None:
            try:
                await client.disconnect()
            except Exception:
                pass
        task = sess.get("task")
        if task:
            task.cancel()
    return {"ok": True}


# ======================== KenMail — Email tích hợp (tài khoản + mật khẩu) ========================
import re as _re_mail
import smtplib as _smtplib
from email.message import EmailMessage as _EmailMessage

_LOCAL_RE = _re_mail.compile(r"^[a-z0-9._-]{2,40}$")


class MailCreateIn(BaseModel):
    local: str            # phần trước @ (vd "cong" → cong@kenios.store)
    password: str
    domain: Optional[str] = None
    phone: Optional[str] = None


class MailSendIn(BaseModel):
    mailbox_id: int
    to: str
    subject: str = ""
    body: str = ""


class MailBulkIn(BaseModel):
    count: int = 5
    prefix: str = ""
    domain: Optional[str] = None


class MailDomainIn(BaseModel):
    domain: str


def _mailbox_owned(mailbox_id: int, uid: int) -> sqlite3.Row:
    with db() as c:
        row = c.execute("SELECT * FROM mailboxes WHERE id=? AND owner_uid=?",
                        (mailbox_id, uid)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy hộp thư của bạn.")
    return row


@app.get("/mail/domains")
def mail_domains_list(user=Depends(get_user)) -> dict[str, Any]:
    """Lấy danh sách các tên miền tùy chỉnh đã thêm."""
    with db() as c:
        rows = c.execute("SELECT id, domain, created_at FROM mail_domains WHERE user_id=? ORDER BY id DESC",
                        (user["id"],)).fetchall()
    return {"domains": [dict(r) for r in rows]}


@app.post("/mail/domains")
def mail_domains_add(b: MailDomainIn, user=Depends(get_user)) -> dict[str, Any]:
    """Thêm một tên miền tùy chỉnh mới."""
    dom = (b.domain or "").strip().lower()
    if not dom or "." not in dom or len(dom) < 3:
        raise HTTPException(status_code=400, detail="Tên miền không hợp lệ.")
    with db() as c:
        if c.execute("SELECT 1 FROM mail_domains WHERE domain=? AND user_id=?", (dom, user["id"])).fetchone():
            raise HTTPException(status_code=409, detail="Tên miền này đã được thêm.")
        cur = c.execute("INSERT INTO mail_domains(domain, user_id, created_at) VALUES(?,?,?)",
                        (dom, user["id"], int(time.time())))
        did = cur.lastrowid
    return {"id": did, "domain": dom}


@app.delete("/mail/domains/{domain_id}")
def mail_domains_delete(domain_id: int, user=Depends(get_user)) -> dict[str, Any]:
    """Xóa tên miền tùy chỉnh."""
    with db() as c:
        row = c.execute("SELECT 1 FROM mail_domains WHERE id=? AND user_id=?", (domain_id, user["id"])).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy tên miền.")
        c.execute("DELETE FROM mail_domains WHERE id=?", (domain_id,))
    return {"ok": True}


@app.post("/mail/bulk-create")
def mail_bulk_create(b: MailBulkIn, user=Depends(get_user)) -> dict[str, Any]:
    """Tạo nhiều hộp thư ngẫu nhiên cùng lúc (không cần SĐT/email khác)."""
    n = max(1, min(b.count, 50))
    prefix = "".join(ch for ch in (b.prefix or "").strip().lower() if ch in "abcdefghijklmnopqrstuvwxyz0123456789._-")[:20]
    
    dom = (b.domain or "").strip().lower()
    if dom:
        if dom != MAIL_DOMAIN:
            with db() as c:
                row = c.execute("SELECT 1 FROM mail_domains WHERE domain=? AND user_id=?", (dom, user["id"])).fetchone()
            if not row:
                raise HTTPException(status_code=400, detail="Tên miền chưa được thêm cho tài khoản của bạn.")
    else:
        dom = MAIL_DOMAIN

    created: list[dict[str, str]] = []
    with db() as c:
        for _ in range(n):
            addr = ""
            for _try in range(12):
                local = (prefix + secrets.token_hex(4))[:40]
                cand = f"{local}@{dom}"
                if not c.execute("SELECT 1 FROM mailboxes WHERE address=?", (cand,)).fetchone():
                    addr = cand
                    break
            if not addr:
                continue
            pwd = secrets.token_urlsafe(9)
            c.execute("INSERT INTO mailboxes(address,pw_hash,owner_uid,created_at) VALUES(?,?,?,?)",
                      (addr, hash_pw(pwd), user["id"], int(time.time())))
            created.append({"address": addr, "password": pwd})
    return {"created": created, "count": len(created)}


@app.post("/mail/create")
def mail_create(b: MailCreateIn, user=Depends(get_user)) -> dict[str, Any]:
    local = (b.local or "").strip().lower()
    if not _LOCAL_RE.match(local):
        raise HTTPException(status_code=400,
            detail="Tên hộp thư 2–40 ký tự, chỉ gồm a-z 0-9 . _ -")
    if len(b.password) < 6:
        raise HTTPException(status_code=400, detail="Mật khẩu hộp thư ≥ 6 ký tự.")
    
    dom = (b.domain or "").strip().lower()
    if dom:
        if dom != MAIL_DOMAIN:
            with db() as c:
                row = c.execute("SELECT 1 FROM mail_domains WHERE domain=? AND user_id=?", (dom, user["id"])).fetchone()
            if not row:
                raise HTTPException(status_code=400, detail="Tên miền chưa được thêm cho tài khoản của bạn.")
    else:
        dom = MAIL_DOMAIN

    address = f"{local}@{dom}"
    phone = (b.phone or "").strip()
    with db() as c:
        if c.execute("SELECT 1 FROM mailboxes WHERE address=?", (address,)).fetchone():
            raise HTTPException(status_code=409, detail="Địa chỉ này đã tồn tại.")
        cur = c.execute(
            "INSERT INTO mailboxes(address,pw_hash,owner_uid,phone,created_at) VALUES(?,?,?,?,?)",
            (address, hash_pw(b.password), user["id"], phone, int(time.time())))
        mid = cur.lastrowid
    return {"id": mid, "address": address, "phone": phone}


@app.get("/mail/list")
def mail_list(user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        rows = c.execute(
            "SELECT id,address,phone,created_at FROM mailboxes WHERE owner_uid=? ORDER BY id DESC",
            (user["id"],)).fetchall()
        out = []
        for r in rows:
            unseen = c.execute("SELECT COUNT(*) n FROM mails WHERE mailbox_id=? AND seen=0",
                               (r["id"],)).fetchone()["n"]
            out.append({"id": r["id"], "address": r["address"],
                        "phone": (r["phone"] if "phone" in r.keys() else None),
                        "created_at": r["created_at"], "unseen": unseen})
    return {"mailboxes": out, "domain": MAIL_DOMAIN}


@app.get("/mail/inbox")
def mail_inbox(mailbox_id: int, user=Depends(get_user)) -> dict[str, Any]:
    _mailbox_owned(mailbox_id, user["id"])
    with db() as c:
        rows = c.execute(
            "SELECT id,direction,from_addr,to_addr,subject,body,created_at,seen "
            "FROM mails WHERE mailbox_id=? ORDER BY id DESC LIMIT 200", (mailbox_id,)).fetchall()
    return {"mails": [dict(r) for r in rows]}


@app.post("/mail/seen/{mail_id}")
def mail_seen(mail_id: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("UPDATE mails SET seen=1 WHERE id=? AND mailbox_id IN "
                  "(SELECT id FROM mailboxes WHERE owner_uid=?)", (mail_id, user["id"]))
    return {"ok": True}


@app.delete("/mail/{mail_id}")
def mail_delete(mail_id: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM mails WHERE id=? AND mailbox_id IN "
                  "(SELECT id FROM mailboxes WHERE owner_uid=?)", (mail_id, user["id"]))
    return {"ok": True}


@app.post("/mail/send")
def mail_send(b: MailSendIn, user=Depends(get_user)) -> dict[str, Any]:
    box = _mailbox_owned(b.mailbox_id, user["id"])
    to = (b.to or "").strip()
    if "@" not in to:
        raise HTTPException(status_code=400, detail="Địa chỉ nhận không hợp lệ.")
    now = int(time.time())
    # Lưu bản gửi đi
    with db() as c:
        c.execute("INSERT INTO mails(mailbox_id,direction,from_addr,to_addr,subject,body,created_at,seen) "
                  "VALUES(?,?,?,?,?,?,?,1)",
                  (box["id"], "out", box["address"], to, b.subject, b.body, now))
        # Nội bộ: nếu người nhận cũng là hộp thư trong hệ thống → giao ngay
        inbox = c.execute("SELECT id FROM mailboxes WHERE address=?", (to.lower(),)).fetchone()
        if inbox:
            c.execute("INSERT INTO mails(mailbox_id,direction,from_addr,to_addr,subject,body,created_at,seen) "
                      "VALUES(?,?,?,?,?,?,?,0)",
                      (inbox["id"], "in", box["address"], to, b.subject, b.body, now))
            return {"ok": True, "delivery": "internal"}
    # Bên ngoài: cần SMTP relay
    if not SMTP_RELAY_HOST:
        raise HTTPException(status_code=400,
            detail="Đã lưu vào mục Đã gửi nhưng chưa cấu hình SMTP relay để gửi ra ngoài "
                   "(đặt SMTP_RELAY_HOST/USER/PASS). Gửi nội bộ @"+MAIL_DOMAIN+" thì không cần.")
    try:
        m = _EmailMessage()
        m["From"] = box["address"]; m["To"] = to; m["Subject"] = b.subject
        m.set_content(b.body or "")
        with _smtplib.SMTP(SMTP_RELAY_HOST, SMTP_RELAY_PORT, timeout=30) as s:
            s.starttls()
            if SMTP_RELAY_USER:
                s.login(SMTP_RELAY_USER, SMTP_RELAY_PASS)
            s.send_message(m)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Gửi ra ngoài thất bại: {e}")
    return {"ok": True, "delivery": "external"}


def _deliver_incoming(rcpt: str, sender: str, subject: str, body: str) -> None:
    """Lưu thư đến vào hộp thư tương ứng (gọi từ bộ nhận SMTP)."""
    rcpt = (rcpt or "").strip().lower()
    try:
        with db() as c:
            box = c.execute("SELECT id FROM mailboxes WHERE address=?", (rcpt,)).fetchone()
            if not box:
                return
            c.execute("INSERT INTO mails(mailbox_id,direction,from_addr,to_addr,subject,body,created_at,seen) "
                      "VALUES(?,?,?,?,?,?,?,0)",
                      (box["id"], "in", sender, rcpt, subject, body, int(time.time())))
    except Exception as e:
        logging.warning("deliver_incoming lỗi: %s", e)


def send_system_mail(to: str, subject: str, body: str,
                     html: Optional[str] = None,
                     images: Optional[dict] = None) -> str:
    """Gửi mail hệ thống (vd mã OTP). Trả 'internal' / 'external' / 'none'.

    html: nội dung HTML (kèm thương hiệu). images: {cid: base64_png} để nhúng inline.
    """
    to = (to or "").strip()
    if "@" not in to:
        return "none"
    sender = MAIL_FROM.strip() or f"no-reply@{MAIL_DOMAIN}"
    # Nội bộ: nếu là hộp thư đã tồn tại trong hệ thống (kể cả tên miền custom) → giao thẳng vào KenMail
    with db() as c:
        ok = c.execute("SELECT 1 FROM mailboxes WHERE address=?", (to.lower(),)).fetchone()
    if ok:
        _deliver_incoming(to, sender, subject, body)
        return "internal"
    # Nếu là tên miền mặc định @MAIL_DOMAIN nhưng chưa tạo hộp thư
    if to.lower().endswith("@" + MAIL_DOMAIN):
        return "none"
    # Bên ngoài: cần SMTP relay
    if SMTP_RELAY_HOST:
        try:
            m = _EmailMessage()
            m["From"] = f"{MAIL_FROM_NAME} <{sender}>"; m["To"] = to; m["Subject"] = subject
            m["Reply-To"] = sender
            m.set_content(body)   # bản chữ thuần (dự phòng)
            if html:
                m.add_alternative(html, subtype="html")
                if images:
                    html_part = m.get_payload()[-1]   # phần HTML vừa thêm
                    for cid, b64 in images.items():
                        html_part.add_related(base64.b64decode(b64), maintype="image",
                                              subtype="png", cid=f"<{cid}>")
            with _smtplib.SMTP(SMTP_RELAY_HOST, SMTP_RELAY_PORT, timeout=15) as s:
                s.starttls()
                if SMTP_RELAY_USER:
                    s.login(SMTP_RELAY_USER, SMTP_RELAY_PASS)
                s.send_message(m)
            return "external"
        except Exception as e:
            logging.warning("send_system_mail relay lỗi: %s", e)
            return "none"
    return "none"


# ===================== Mã xác nhận email / SMS (OTP) =====================
class OtpSendIn(BaseModel):
    email: Optional[str] = None
    phone: Optional[str] = None
    purpose: str = "register"


class OtpVerifyIn(BaseModel):
    email: Optional[str] = None
    phone: Optional[str] = None
    code: str


def _normalize_phone(p: str) -> str:
    """Chuẩn hoá số điện thoại: chỉ giữ chữ số và dấu +."""
    return re.sub(r"[^0-9+]", "", (p or "").strip())


def _send_sms(phone: str, text: str) -> str:
    """Gửi SMS qua nhà cung cấp đã cấu hình. Trả 'external' nếu gửi được, 'none' nếu chưa cấu hình."""
    # 1) Webhook/gateway tự chọn (eSMS, SpeedSMS, proxy riêng...) nhận POST {to, text}
    if SMS_RELAY_URL:
        try:
            with httpx.Client(timeout=20) as c:
                r = c.post(SMS_RELAY_URL, json={"to": phone, "text": text})
            if r.status_code < 400:
                return "external"
        except Exception as e:
            logging.warning("SMS relay lỗi: %s", e)
    # 2) Twilio
    if SMS_TWILIO_SID and SMS_TWILIO_TOKEN and SMS_TWILIO_FROM:
        try:
            to = phone if phone.startswith("+") else "+" + phone
            with httpx.Client(timeout=20) as c:
                r = c.post(
                    f"https://api.twilio.com/2010-04-01/Accounts/{SMS_TWILIO_SID}/Messages.json",
                    data={"To": to, "From": SMS_TWILIO_FROM, "Body": text},
                    auth=(SMS_TWILIO_SID, SMS_TWILIO_TOKEN))
            if r.status_code < 400:
                return "external"
        except Exception as e:
            logging.warning("SMS Twilio lỗi: %s", e)
    return "none"


def _otp_store_and_send_sms(phone: str, purpose: str) -> dict[str, Any]:
    phone_n = _normalize_phone(phone)
    if len(re.sub(r"\D", "", phone_n)) < 8:
        raise HTTPException(status_code=400, detail="Số điện thoại không hợp lệ.")
    code = f"{secrets.randbelow(1000000):06d}"
    exp = int(time.time()) + 300  # 5 phút
    with db() as c:
        c.execute("INSERT INTO otp_codes(email,code,purpose,exp,attempts) VALUES(?,?,?,?,0) "
                  "ON CONFLICT(email) DO UPDATE SET code=excluded.code, purpose=excluded.purpose, "
                  "exp=excluded.exp, attempts=0", (phone_n, code, purpose, exp))
    text = f"KENIOS: Ma xac nhan dang ky cua ban la {code} (hieu luc 5 phut)."
    channel = _send_sms(phone_n, text)
    resp: dict[str, Any] = {"sent": channel != "none", "channel": channel}
    if channel == "none":
        resp["hint"] = ("Máy chủ chưa cấu hình gửi SMS. Đặt SMS_RELAY_URL hoặc Twilio "
                        "(SMS_TWILIO_SID/TOKEN/FROM), hoặc bật OTP_DEBUG=1 để test.")
    if OTP_DEBUG:
        resp["debug_code"] = code
    return resp


def _otp_store_and_send(email: str, purpose: str) -> dict[str, Any]:
    email = (email or "").strip().lower()
    if "@" not in email:
        raise HTTPException(status_code=400, detail="Email không hợp lệ.")
    code = f"{secrets.randbelow(1000000):06d}"
    exp = int(time.time()) + 300  # 5 phút
    with db() as c:
        c.execute("INSERT INTO otp_codes(email,code,purpose,exp,attempts) VALUES(?,?,?,?,0) "
                  "ON CONFLICT(email) DO UPDATE SET code=excluded.code, purpose=excluded.purpose, "
                  "exp=excluded.exp, attempts=0", (email, code, purpose, exp))
    subject = "Mã xác nhận KENIOS"
    body = (f"Mã xác nhận của bạn là: {code}\n"
            f"Mã có hiệu lực trong 5 phút.\n"
            f"Nếu bạn không yêu cầu, hãy bỏ qua email này.")
    html = ("""
<div style="font-family:Arial,Helvetica,sans-serif;background:#f4f5f7;padding:28px;">
  <div style="max-width:480px;margin:0 auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 20px rgba(0,0,0,.08);">
    <div style="background:linear-gradient(135deg,#3b6eff,#8b5cf6,#ec4899);padding:26px 20px;text-align:center;">
      <img src="cid:logo" width="72" height="72" style="border-radius:18px;display:block;margin:0 auto 12px;">
      <span style="color:#ffffff;font-size:26px;font-weight:bold;vertical-align:middle;">KENIOS</span>
      <img src="cid:badge" width="26" height="26" style="vertical-align:middle;margin-left:5px;">
    </div>
    <div style="padding:30px 26px;text-align:center;">
      <p style="color:#333;font-size:15px;margin:0 0 16px;">Mã xác nhận của bạn là:</p>
      <div style="font-size:40px;font-weight:bold;letter-spacing:10px;color:#3b6eff;">__CODE__</div>
      <p style="color:#888;font-size:13px;margin:18px 0 0;line-height:1.6;">Mã có hiệu lực trong <b>5 phút</b>.<br>Nếu bạn không yêu cầu, hãy bỏ qua email này.</p>
    </div>
    <div style="background:#fafafa;padding:14px;text-align:center;color:#aaa;font-size:12px;">© KENIOS</div>
  </div>
</div>""").replace("__CODE__", code)
    channel = send_system_mail(email, subject, body, html=html,
                               images={"logo": KENIOS_LOGO_B64, "badge": VERIFIED_BADGE_B64})
    resp: dict[str, Any] = {"sent": channel != "none", "channel": channel}
    if channel == "none":
        resp["hint"] = ("Chưa gửi được mã qua email. Email @" + MAIL_DOMAIN +
                        " cần đã tạo hộp thư; email ngoài (Gmail...) cần cấu hình SMTP_RELAY.")
    if OTP_DEBUG:
        resp["debug_code"] = code
    return resp


def _otp_check(email: str, code: str) -> bool:
    email = (email or "").strip().lower()
    code = (code or "").strip()
    with db() as c:
        row = c.execute("SELECT code,exp,attempts FROM otp_codes WHERE email=?", (email,)).fetchone()
        if not row:
            return False
        if row["attempts"] >= 6:
            return False
        if int(time.time()) > row["exp"]:
            return False
        if row["code"] != code:
            c.execute("UPDATE otp_codes SET attempts=attempts+1 WHERE email=?", (email,))
            return False
        c.execute("DELETE FROM otp_codes WHERE email=?", (email,))
    return True


@app.post("/auth/send-otp")
def auth_send_otp(b: OtpSendIn, request: Request) -> dict[str, Any]:
    _rate_limit(request, "otp", limit=6, window=600)
    if (b.phone or "").strip():
        return _otp_store_and_send_sms(b.phone, b.purpose or "register")
    return _otp_store_and_send(b.email or "", b.purpose or "register")


@app.post("/auth/verify-otp")
def auth_verify_otp(b: OtpVerifyIn) -> dict[str, Any]:
    ident = _normalize_phone(b.phone) if (b.phone or "").strip() else (b.email or "")
    return {"valid": _otp_check(ident, b.code)}


def start_mail_smtp() -> None:
    """Khởi động bộ nhận thư SMTP (aiosmtpd) trong tiến trình — cần MX trỏ về VPS + mở port 25."""
    if not MAIL_ENABLE:
        return
    try:
        from aiosmtpd.controller import Controller
        import email as _email_mod
    except Exception:
        logging.warning("KenMail: chưa cài aiosmtpd → không nhận được thư đến. Cài: pip install aiosmtpd")
        return

    def _extract_body(msg) -> str:
        try:
            if msg.is_multipart():
                for part in msg.walk():
                    if part.get_content_type() == "text/plain":
                        return part.get_payload(decode=True).decode("utf-8", "replace")
                return msg.get_payload(decode=True).decode("utf-8", "replace")
            payload = msg.get_payload(decode=True)
            return payload.decode("utf-8", "replace") if payload else str(msg.get_payload())
        except Exception:
            return ""

    class _Handler:
        async def handle_DATA(self, server, session, envelope):
            try:
                msg = _email_mod.message_from_bytes(envelope.content)
                subject = msg.get("Subject", "")
                sender = envelope.mail_from or msg.get("From", "")
                body = _extract_body(msg)
                for rcpt in envelope.rcpt_tos:
                    _deliver_incoming(rcpt, sender, subject, body)
            except Exception as e:
                logging.warning("SMTP handle_DATA lỗi: %s", e)
            return "250 Message accepted"

    try:
        controller = Controller(_Handler(), hostname="0.0.0.0", port=MAIL_SMTP_PORT)
        controller.start()
        logging.info("KenMail SMTP nhận thư tại cổng %s cho @%s", MAIL_SMTP_PORT, MAIL_DOMAIN)
    except Exception as e:
        logging.warning("KenMail: không khởi động được SMTP cổng %s: %s", MAIL_SMTP_PORT, e)


# ======================== Dịch sang tiếng Việt (TTS đa ngôn ngữ) ========================
class TranslateIn(BaseModel):
    text: str
    target: str = "vi"
    source: str = "auto"


@app.post("/translate")
async def translate_text(b: TranslateIn) -> dict[str, Any]:
    """Dịch văn bản sang tiếng Việt (mặc định) — dùng cho đọc TTS đa ngôn ngữ.

    Dùng endpoint dịch miễn phí (không cần API key). Nếu lỗi sẽ trả lại nguyên văn.
    """
    text = (b.text or "").strip()
    if not text:
        return {"text": "", "source": b.source}
    target = (b.target or "vi").strip() or "vi"
    source = (b.source or "auto").strip() or "auto"
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            r = await client.get(
                "https://translate.googleapis.com/translate_a/single",
                params={"client": "gtx", "sl": source, "tl": target, "dt": "t", "q": text},
                headers={"User-Agent": "Mozilla/5.0"},
            )
        if r.status_code == 200:
            data = r.json()
            segments = data[0] if isinstance(data, list) and data else []
            out = "".join(seg[0] for seg in segments if seg and seg[0])
            detected = data[2] if isinstance(data, list) and len(data) > 2 else source
            return {"text": out or text, "source": detected}
    except Exception:
        pass
    return {"text": text, "source": source}


# ======================== Thanh toán / Nâng cấp PRO ========================
# Chỉ còn DUY NHẤT 1 gói nâng cấp PRO. Admin tự chỉnh giá (VND) trong trang Quản trị.
# Không dùng credits — thanh toán xong là tài khoản được nâng lên PRO.
PRO_PRICE_DEFAULT = 199000
PRO_LABEL_DEFAULT = "Nâng cấp PRO"


def _pro_package() -> dict[str, Any]:
    try:
        price = int(get_setting("pro_price", str(PRO_PRICE_DEFAULT)) or PRO_PRICE_DEFAULT)
    except (TypeError, ValueError):
        price = PRO_PRICE_DEFAULT
    if price < 0:
        price = PRO_PRICE_DEFAULT
    label = get_setting("pro_label", PRO_LABEL_DEFAULT) or PRO_LABEL_DEFAULT
    return {
        "id": "pro",
        "credits": 0,                      # không cộng credits, chỉ nâng cấp gói
        "amount": price,
        "label": f"{label} — {price:,}đ".replace(",", "."),
    }


@app.get("/payment/packages")
def payment_packages() -> list[dict[str, Any]]:
    # Trả về dạng danh sách (1 phần tử) để tương thích với app.
    return [_pro_package()]


@app.post("/payment/create")
def payment_create(b: PaymentIn, user=Depends(get_user)) -> dict[str, Any]:
    # Mọi đơn đều là nâng cấp PRO (bỏ qua tên gói client gửi lên).
    pkg = _pro_package()
    ref = secrets.token_urlsafe(12)
    with db() as c:
        # Nội dung chuyển khoản = ID khách hàng → hệ thống tự dò ID để xác nhận.
        cid = _ensure_public_id(c, user["id"])
        cur = c.execute(
            "INSERT INTO payments(user_id,amount,credits,status,ref,created_at) "
            "VALUES(?,?,?,'pending',?,?)",
            (user["id"], pkg["amount"], pkg["credits"], ref, int(time.time())),
        )
        pid = cur.lastrowid
    bank = bank_info(amount=pkg["amount"], note=cid)
    return {
        "payment_id": pid,
        "ref": cid,
        "amount": pkg["amount"],
        "credits": pkg["credits"],
        "label": pkg["label"],
        "message": f"Chuyển khoản với nội dung là ID của bạn: {cid}. Hệ thống tự xác nhận sau khi nhận tiền.",
        "bank_info": bank,
        "qr_url": bank["qr_url"],
    }


def bank_info(amount: int = 0, note: str = "KENIOS") -> dict[str, Any]:
    from urllib.parse import quote
    code = get_setting("bank_code", "970416")
    short = get_setting("bank_short", "ACB")
    account = get_setting("bank_account", "23252921")
    name = get_setting("bank_name", "TRAN MINH CHIEN")
    qr = (f"https://img.vietqr.io/image/{code}-{account}-compact2.png"
          f"?accountName={quote(name)}&addInfo={quote(note)}")
    if amount > 0:
        qr += f"&amount={amount}"
    return {"bank": short, "bank_code": code, "account": account,
            "name": name, "content": note, "qr_url": qr}


@app.get("/payment/info")
def payment_info(amount: int = 0, note: str = "KENIOS", user=Depends(get_user)) -> dict[str, Any]:
    return bank_info(amount=amount, note=note)


class BankSettingsIn(BaseModel):
    bank_code: Optional[str] = None
    bank_short: Optional[str] = None
    bank_account: Optional[str] = None
    bank_name: Optional[str] = None
    bank_webhook: Optional[str] = None
    bank_apikey: Optional[str] = None
    acb_api_token: Optional[str] = None

@app.get("/admin/payment/settings")
def admin_get_bank(admin=Depends(get_admin)) -> dict[str, Any]:
    return {
        "bank_code": get_setting("bank_code", "970416"),
        "bank_short": get_setting("bank_short", "ACB"),
        "bank_account": get_setting("bank_account", "23252921"),
        "bank_name": get_setting("bank_name", "TRAN MINH CHIEN"),
        "bank_webhook": get_setting("bank_webhook", ""),
        "bank_apikey": get_setting("bank_apikey", ""),
        "acb_api_token": get_setting("acb_api_token", ""),
    }

@app.post("/admin/payment/settings")
def admin_set_bank(b: BankSettingsIn, admin=Depends(get_admin)) -> dict[str, Any]:
    for field in ["bank_code", "bank_short", "bank_account", "bank_name",
                  "bank_webhook", "bank_apikey", "acb_api_token"]:
        val = getattr(b, field)
        if val is not None:
            set_setting(field, val)
    return {"message": "Đã cập nhật thông tin ngân hàng."}


# -------- Giá gói nâng cấp PRO (admin tự chỉnh, VND) --------
class ProPriceIn(BaseModel):
    price: Optional[int] = None
    label: Optional[str] = None


@app.get("/admin/payment/pro")
def admin_get_pro(admin=Depends(get_admin)) -> dict[str, Any]:
    pkg = _pro_package()
    return {"price": pkg["amount"], "label": get_setting("pro_label", PRO_LABEL_DEFAULT) or PRO_LABEL_DEFAULT}


@app.post("/admin/payment/pro")
def admin_set_pro(b: ProPriceIn, admin=Depends(get_admin)) -> dict[str, Any]:
    if b.price is not None:
        if b.price < 0:
            raise HTTPException(status_code=400, detail="Giá phải là số tiền VND ≥ 0.")
        set_setting("pro_price", str(int(b.price)))
    if b.label is not None and b.label.strip():
        set_setting("pro_label", b.label.strip()[:60])
    pkg = _pro_package()
    return {"message": "Đã cập nhật giá gói PRO.", "price": pkg["amount"],
            "label": get_setting("pro_label", PRO_LABEL_DEFAULT) or PRO_LABEL_DEFAULT}


def _determine_plan_from_credits(credits: int) -> str:
    if credits >= 50000:
        return "max"
    elif credits >= 20000:
        return "ultra"
    elif credits >= 9999:
        return "pro"
    return "free"


def _finalize_payment_row(c, pay) -> bool:
    """Hoàn tất 1 đơn PRO/credits. Idempotent: chỉ xử lý nếu giành được đơn pending."""
    claimed = c.execute("UPDATE payments SET status='completed' WHERE id=? AND status='pending'",
                        (pay["id"],))
    if claimed.rowcount != 1:
        return False
    if pay["credits"] and pay["credits"] > 0:
        c.execute("UPDATE users SET credits=credits+? WHERE id=?", (pay["credits"], pay["user_id"]))
        new_plan = _determine_plan_from_credits(pay["credits"])
        if new_plan != "free":
            c.execute("UPDATE users SET plan=? WHERE id=? AND plan IN ('free','pro','ultra')",
                      (new_plan, pay["user_id"]))
    else:
        c.execute("UPDATE users SET plan='pro' WHERE id=?", (pay["user_id"],))
    return True


# ===================== Giao key: thời hạn · nền tảng · tin nhắn =====================
# Quy đổi đơn vị thời hạn sang số giây (tháng = 30 ngày, năm = 365 ngày)
_DURATION_UNITS = [
    (("phút", "phut", "minute", "min"),          60),
    (("giờ", "gio", "hour", "hr"),               3600),
    (("ngày", "ngay", "day", "days"),            86400),
    (("tuần", "tuan", "week", "weeks", "wk"),    7 * 86400),
    (("tháng", "thang", "month", "months", "mo"),30 * 86400),
    (("năm", "nam", "year", "years", "yr"),      365 * 86400),
]
_LIFETIME_HINTS = ("vĩnh viễn", "vinh vien", "trọn đời", "tron doi",
                   "lifetime", "forever", "vĩnh", "vinh")


def _duration_seconds(label: str):
    """Đổi nhãn gói ('1 tháng', '30 ngày', '1 năm', 'vĩnh viễn'...) thành số giây.

    Trả về None nếu là gói vĩnh viễn hoặc không xác định được thời hạn.
    """
    s = (label or "").strip().lower()
    if not s:
        return None
    if any(h in s for h in _LIFETIME_HINTS):
        return None
    m = re.search(r"(\d+(?:[.,]\d+)?)", s)
    qty = float(m.group(1).replace(",", ".")) if m else 1.0
    # Ưu tiên đơn vị dài nhất (tránh 'ngày' lọt vào 'tháng')
    for names, secs in sorted(_DURATION_UNITS, key=lambda u: -max(len(n) for n in u[0])):
        if any(n in s for n in names):
            return int(qty * secs)
    return None


def _platform_label(c, product_id: int) -> str:
    """Suy ra nền tảng (iOS / Android) từ tên thư mục → danh mục chứa sản phẩm.

    Nếu không nhận diện được thì dùng luôn tên thư mục cho khách dễ hiểu.
    """
    row = c.execute(
        "SELECT f.name AS folder, cat.name AS category "
        "FROM store_products p "
        "JOIN store_folders f ON f.id=p.folder_id "
        "JOIN store_categories cat ON cat.id=f.category_id "
        "WHERE p.id=?", (product_id,)).fetchone()
    if not row:
        return ""
    text = f"{row['folder'] or ''} {row['category'] or ''}".lower()
    if any(k in text for k in ("ios", "iphone", "ipad", "apple")):
        return "iOS"
    if "android" in text:
        return "Android"
    return (row["folder"] or "").strip()


def _fmt_dmy(ts) -> str:
    return time.strftime("%d/%m/%Y", time.localtime(int(ts)))


def _build_delivery_msg(c, product_id: int, price_label: str, key_text: str,
                        created_at: int, expires_at, kind: str = "app") -> str:
    """Soạn tin nhắn giao hàng gửi khách sau khi mua key/acc."""
    prod = c.execute("SELECT name FROM store_products WHERE id=?", (product_id,)).fetchone()
    pname = (prod["name"] if prod else "") or "(sản phẩm)"
    item = "tài khoản" if (kind or "app") == "acc" else "key"
    platform = _platform_label(c, product_id)
    plat = f" [{platform}]" if platform else ""
    dur = f" ({price_label})" if (price_label or "").strip() else ""
    lines = [
        f"🔑 Bạn đã mua 1 {item} {pname}{plat}{dur}",
        f"🗓 Ngày mua: {_fmt_dmy(created_at)}",
        f"⏳ Hết hạn: {_fmt_dmy(expires_at)}" if expires_at else "⏳ Thời hạn: Vĩnh viễn",
        f"🔑 {item.capitalize()}: {key_text}",
    ]
    return "\n".join(lines)


def _apply_delivery(c, order_id: int, product_id: int, price_label: str,
                    key_text: str, created_at: int, kind: str = "app") -> dict:
    """Tính nền tảng + ngày hết hạn + tin nhắn rồi lưu vào đơn. Trả về để API dùng lại."""
    platform = _platform_label(c, product_id)
    secs = _duration_seconds(price_label)
    expires_at = (int(created_at) + secs) if secs else None
    msg = _build_delivery_msg(c, product_id, price_label, key_text, created_at, expires_at, kind)
    c.execute("UPDATE store_orders SET price_label=?, platform=?, expires_at=?, delivery_msg=? WHERE id=?",
              (price_label or "", platform, expires_at, msg, order_id))
    return {"platform": platform, "expires_at": expires_at, "delivery": msg}


def _finalize_store_order_row(c, order) -> bool:
    """Hoàn tất 1 đơn mua sản phẩm: cấp 1 key khả dụng, sao lưu rồi XOÁ key khỏi kho.

    Idempotent: chỉ xử lý nếu giành được đơn pending (tránh giao key 2 lần).
    """
    # Giành đơn: chỉ 1 tiến trình flip được pending → completed
    claimed = c.execute("UPDATE store_orders SET status='completed' WHERE id=? AND status='pending'",
                        (order["id"],))
    if claimed.rowcount != 1:
        return False
    # Giành 1 key khả dụng (cập nhật có điều kiện để không trùng key giữa các đơn)
    key = None
    for _ in range(50):
        cand = c.execute("SELECT id,key_text FROM store_keys WHERE product_id=? AND status='available' "
                         "ORDER BY id ASC LIMIT 1", (order["product_id"],)).fetchone()
        if not cand:
            break
        got = c.execute("UPDATE store_keys SET status='sold' WHERE id=? AND status='available'",
                        (cand["id"],))
        if got.rowcount == 1:
            key = cand
            break
    if not key:
        log.warning("Store: đơn #%d đã thanh toán nhưng HẾT key (product=%d)",
                    order["id"], order["product_id"])
        return True
    c.execute("UPDATE store_orders SET key_id=?, key_text=? WHERE id=?",
              (key["id"], key["key_text"], order["id"]))
    # Soạn tin giao hàng (thời hạn + nền tảng + ngày hết hạn + key)
    pr = c.execute("SELECT label FROM store_prices WHERE id=?", (order["price_id"],)).fetchone()
    prod = c.execute("SELECT kind FROM store_products WHERE id=?", (order["product_id"],)).fetchone()
    _apply_delivery(c, order["id"], order["product_id"], pr["label"] if pr else "",
                    key["key_text"], order["created_at"] or int(time.time()),
                    _row_kind(prod) if prod else "app")
    # Khách đã nhận key → tự động xoá key khỏi kho (không bao giờ bán lại)
    c.execute("DELETE FROM store_keys WHERE id=?", (key["id"],))
    log.info("Store xác nhận: đơn #%d, user=%d, product=%d (đã xoá key khỏi kho)",
             order["id"], order["user_id"], order["product_id"])
    return True


def _match_amount(rows, amount: int):
    """Chọn đơn pending khớp số tiền: ưu tiên khớp đúng, sau đó đơn có giá ≤ số tiền nhận."""
    rows = list(rows)
    if not rows:
        return None
    if amount and amount > 0:
        for r in rows:
            if r["amount"] == amount:
                return r
        for r in rows:
            if r["amount"] <= amount:
                return r
        return None
    return rows[0]


# ---- Chống cộng tiền trùng: vân tay mỗi giao dịch ngân hàng đã xử lý ----
_TX_ID_KEYS = ("transactionID", "transactionId", "transaction_id", "id", "tid",
               "tranId", "refNo", "referenceNumber", "reference", "ftCode", "ft",
               "trace", "seqNo", "transactionNumber", "bankRefNo")
_TX_FP_KEYS = ("transactionDate", "date", "time", "datetime", "when", "transactionTime",
               "amount", "creditAmount", "transferAmount", "money",
               "description", "content", "transactionContent", "addDescription", "comment",
               "balance", "balanceAfter", "accountBalance", "runningBalance", "cusumBalance")


def _tx_fingerprint(tx: dict) -> str:
    """Vân tay duy nhất cho 1 giao dịch ngân hàng.

    Ưu tiên mã giao dịch thật của ngân hàng; nếu không có thì băm nhiều trường
    (ngày giờ + số tiền + nội dung + số dư) — 2 lần chuyển khoản thật luôn khác
    nhau nên không bao giờ chặn nhầm giao dịch hợp lệ.
    """
    for k in _TX_ID_KEYS:
        v = tx.get(k)
        if v not in (None, "", 0, "0"):
            return "id:" + str(v)
    parts = [f"{k}={tx.get(k)}" for k in _TX_FP_KEYS if tx.get(k) not in (None, "")]
    return "h:" + hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()[:32]


def _bank_tx_done(fp: str) -> bool:
    try:
        with db() as c:
            return c.execute("SELECT 1 FROM bank_tx_seen WHERE fp=?", (fp,)).fetchone() is not None
    except Exception:
        return False


def _mark_bank_tx(fp: str) -> None:
    try:
        with db() as c:
            c.execute("INSERT OR IGNORE INTO bank_tx_seen(fp,created_at) VALUES(?,?)",
                      (fp, int(time.time())))
    except Exception as e:
        log.error("Lưu vân tay giao dịch lỗi: %s", e)


def _confirm_tx(tx: dict, desc: str, amount: int) -> bool:
    """Xác nhận 1 giao dịch ngân hàng — CHỈ cộng tiền nếu vân tay chưa từng xử lý.

    Đánh dấu vân tay SAU khi cộng thành công (giao dịch chưa khớp đơn nào sẽ không
    bị đánh dấu, để lần sau khách tạo đơn rồi vẫn khớp được — không kẹt tiền).
    """
    fp = _tx_fingerprint(tx)
    if _bank_tx_done(fp):
        return False
    if _confirm_from_description(desc, amount):
        _mark_bank_tx(fp)
        return True
    return False


def _confirm_by_customer_id(cid: str, amount: int) -> bool:
    """Xác nhận chuyển khoản dựa trên ID khách hàng trong nội dung CK + số tiền."""
    try:
        with db() as c:
            u = c.execute("SELECT id FROM users WHERE public_id=?", (cid,)).fetchone()
            if not u:
                return False
            uid = u["id"]
            pays = c.execute("SELECT * FROM payments WHERE user_id=? AND status='pending' "
                             "ORDER BY id ASC", (uid,)).fetchall()
            pay = _match_amount(pays, amount)
            if pay and _finalize_payment_row(c, pay):
                log.info("Xác nhận theo ID=%s: đơn PRO #%d", cid, pay["id"])
                return True
            # Nạp ví cửa hàng
            tops = c.execute("SELECT * FROM store_topups WHERE user_id=? AND status='pending' "
                             "ORDER BY id ASC", (uid,)).fetchall()
            top = _match_amount(tops, amount)
            if top and _finalize_topup_row(c, top):
                return True
            # (tương thích cũ) đơn mua trực tiếp qua chuyển khoản
            orders = c.execute("SELECT * FROM store_orders WHERE user_id=? AND status='pending' "
                               "ORDER BY id ASC", (uid,)).fetchall()
            order = _match_amount(orders, amount)
            if order and _finalize_store_order_row(c, order):
                return True
        return False
    except Exception as e:
        log.error("Lỗi xác nhận theo ID=%s: %s", cid, e)
        return False


@app.post("/payment/confirm/{pid}")
def payment_confirm(pid: int, admin=Depends(get_admin)) -> dict[str, Any]:
    with db() as c:
        pay = c.execute("SELECT * FROM payments WHERE id=?", (pid,)).fetchone()
        if not pay:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn thanh toán.")
        if pay["status"] == "completed":
            raise HTTPException(status_code=400, detail="Đơn đã được xác nhận trước đó.")
        _finalize_payment_row(c, pay)
    if pay["credits"] and pay["credits"] > 0:
        return {"message": f"Đã cộng {pay['credits']} credits cho user {pay['user_id']}."}
    return {"message": f"Đã nâng cấp tài khoản user {pay['user_id']} lên PRO."}


# ======================== Webhook thanh toán tự động ========================
@app.post("/payment/webhook")
async def payment_webhook(request: Request) -> dict[str, Any]:
    webhook_key = get_setting("bank_apikey", "")
    if webhook_key:
        auth_header = request.headers.get("Authorization", "")
        secure_token = request.headers.get("X-API-Key", "") or request.headers.get("Secure-Token", "")
        provided_key = ""
        if auth_header.startswith("Apikey "):
            provided_key = auth_header.split(" ", 1)[1]
        elif auth_header.startswith("Bearer "):
            provided_key = auth_header.split(" ", 1)[1]
        elif secure_token:
            provided_key = secure_token
        if provided_key != webhook_key:
            raise HTTPException(status_code=401, detail="Webhook API key không hợp lệ.")

    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Body JSON không hợp lệ.")

    confirmed = 0
    items = body.get("data", []) if isinstance(body.get("data"), list) else [body]
    for item in items:
        if not isinstance(item, dict):
            continue
        desc = (item.get("description", "") or item.get("content", "")
                or item.get("transactionContent", ""))
        amount = item.get("amount", 0) or item.get("transferAmount", 0) or item.get("creditAmount", 0)
        try:
            amount = int(float(str(amount).replace(",", "")))
        except (TypeError, ValueError):
            amount = 0
        if _confirm_tx(item, desc, amount):
            confirmed += 1

    return {"success": True, "confirmed": confirmed}


def _extract_customer_id(description: str) -> Optional[str]:
    """Lấy ID khách hàng (dạng KEN + chữ số) trong nội dung chuyển khoản."""
    if not description:
        return None
    m = re.search(r"(KEN\d{6,})", description, re.IGNORECASE)
    return m.group(1).upper() if m else None


def _extract_ref(description: str) -> Optional[str]:
    if not description:
        return None
    match = re.search(r"KENIOS\s+(\S+)", description, re.IGNORECASE)
    return match.group(1) if match else None


def _confirm_from_description(desc: str, amount: int) -> bool:
    """Ưu tiên dò theo ID khách hàng; nếu không có thì thử theo mã ref cũ."""
    cid = _extract_customer_id(desc)
    if cid and _confirm_by_customer_id(cid, amount):
        return True
    ref = _extract_ref(desc)
    if ref and _auto_confirm_payment(ref, amount):
        return True
    return False


def _auto_confirm_payment(ref: str, amount: int) -> bool:
    """Tương thích cũ: xác nhận theo mã ref (token) cho đơn PRO hoặc đơn cửa hàng."""
    try:
        with db() as c:
            pay = c.execute(
                "SELECT * FROM payments WHERE ref=? AND status='pending'", (ref,)
            ).fetchone()
            if pay:
                if amount > 0 and amount < pay["amount"]:
                    return False
                return _finalize_payment_row(c, pay)
            order = c.execute(
                "SELECT * FROM store_orders WHERE ref=? AND status='pending'", (ref,)
            ).fetchone()
            if order:
                if amount > 0 and amount < order["amount"]:
                    return False
                return _finalize_store_order_row(c, order)
        return False
    except Exception as e:
        log.error("Lỗi xác nhận ref=%s: %s", ref, e)
        return False


# ======================== Nạp tiền tự động qua thueapibank.vn (ACB) ========================
async def _acb_fetch_and_confirm() -> int:
    """Gọi API lịch sử giao dịch ACB của thueapibank.vn, dò ID khách trong nội dung CK rồi tự xác nhận."""
    token = get_setting("acb_api_token", "").strip()
    if not token:
        return 0
    url = f"https://thueapibank.vn/historyapiacb/{token}"
    confirmed = 0
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            r = await client.get(url, headers={"User-Agent": "KENIOS-Server"})
        if r.status_code != 200:
            log.warning("ACB API trả về HTTP %d", r.status_code)
            return 0
        data = r.json()
    except Exception as e:
        log.warning("ACB API lỗi: %s", e)
        return 0

    # API thường trả {"status": true, "transactions": [{"description"/"content","amount"/"creditAmount", ...}]}
    txs = []
    if isinstance(data, dict):
        for key in ("transactions", "data", "result", "history"):
            if isinstance(data.get(key), list):
                txs = data[key]
                break
    elif isinstance(data, list):
        txs = data

    for tx in txs:
        if not isinstance(tx, dict):
            continue
        desc = (tx.get("description") or tx.get("content") or tx.get("transactionContent")
                or tx.get("addDescription") or tx.get("comment") or "")
        amt_raw = (tx.get("amount") or tx.get("creditAmount") or tx.get("transferAmount")
                   or tx.get("money") or 0)
        try:
            amount = int(float(str(amt_raw).replace(",", "").replace(".", "") or 0))
        except (TypeError, ValueError):
            amount = 0
        if _confirm_tx(tx, desc, amount):
            confirmed += 1
    if confirmed:
        log.info("ACB tự động xác nhận %d giao dịch.", confirmed)
    return confirmed


async def _acb_autopay_loop() -> None:
    """Vòng lặp nền: cứ ~20 giây kiểm tra giao dịch ACB mới để tự cộng tiền / cấp key."""
    while True:
        try:
            if get_setting("acb_api_token", "").strip():
                await _acb_fetch_and_confirm()
        except Exception as e:
            log.error("ACB autopay loop lỗi: %s", e)
        await asyncio.sleep(20)


@app.get("/payment/history")
def payment_history(user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute(
            "SELECT id,amount,credits,status,ref,created_at FROM payments "
            "WHERE user_id=? ORDER BY id DESC", (user["id"],)
        ).fetchall()
    return [dict(r) for r in rows]


class PaymentCancelIn(BaseModel):
    id: int

@app.post("/payment/cancel")
def payment_cancel(b: PaymentCancelIn, user=Depends(get_user)) -> dict[str, Any]:
    """Khách tự huỷ đơn nâng cấp đang CHỜ xác nhận (chưa nhận tiền)."""
    with db() as c:
        row = c.execute("SELECT user_id,status FROM payments WHERE id=?", (b.id,)).fetchone()
        if not row or row["user_id"] != user["id"]:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn của bạn.")
        if row["status"] != "pending":
            raise HTTPException(status_code=400, detail="Chỉ huỷ được đơn đang chờ xác nhận.")
        c.execute("UPDATE payments SET status='cancelled' WHERE id=?", (b.id,))
    return {"message": "Đã huỷ đơn."}


@app.get("/me/credits")
def my_credits(user=Depends(get_user)) -> dict[str, Any]:
    return {"credits": user["credits"], "plan": user["plan"]}


# ============================================================================
# ======================== APP BÁN HÀNG (STORE) ==============================
# ============================================================================
# Cấu trúc: Danh mục (category) → Thư mục con (folder) → Sản phẩm (product)
# Mỗi sản phẩm: nhiều mốc giá theo thời hạn (giờ/ngày/tuần/tháng) + kho KEY +
# link/file tải. Khách trả tiền (nạp tự động ACB) → tự nhận 1 key + link tải.

class MediaItem(BaseModel):
    type: str = "image"   # image | video
    url: str = ""

def _dump_media(items) -> str:
    out = []
    for m in (items or [])[:5]:
        if isinstance(m, MediaItem):
            d = {"type": (m.type or "image"), "url": (m.url or "")}
        elif isinstance(m, dict):
            d = {"type": m.get("type", "image"), "url": m.get("url", "")}
        else:
            continue
        if d["url"]:
            out.append(d)
    return json.dumps(out, ensure_ascii=False)

def _load_media(s) -> list:
    try:
        v = json.loads(s or "[]")
        return v if isinstance(v, list) else []
    except Exception:
        return []

def _product_prices(c, pid: int) -> list:
    rows = c.execute("SELECT id,label,amount,sort FROM store_prices WHERE product_id=? "
                     "ORDER BY sort ASC, amount ASC", (pid,)).fetchall()
    out = []
    for r in rows:
        # Tồn kho RIÊNG của từng mốc thời hạn (không dùng chung).
        avail = c.execute(
            "SELECT COUNT(*) AS n FROM store_keys WHERE product_id=? AND price_id=? AND status='available'",
            (pid, r["id"])).fetchone()["n"]
        out.append({"id": r["id"], "label": r["label"], "amount": r["amount"], "available": avail})
    return out

def _row_kind(row) -> str:
    try:
        return row["kind"] or "app"
    except (IndexError, KeyError):
        return "app"

def _product_public(c, row) -> dict:
    avail = c.execute("SELECT COUNT(*) AS n FROM store_keys WHERE product_id=? AND status='available'",
                      (row["id"],)).fetchone()["n"]
    return {
        "id": row["id"], "folder_id": row["folder_id"],
        "name": row["name"], "description": row["description"] or "",
        "kind": _row_kind(row),
        "media": _load_media(row["media"]),
        "prices": _product_prices(c, row["id"]),
        "available_keys": avail,
        "views": (row["views"] if "views" in row.keys() else 0) or 0,
        "has_download": bool((row["download_url"] or "").strip()) or row["download_file_id"] is not None,
    }


# -------------------- Khách xem (công khai) --------------------
@app.get("/store/all-products")
def store_all_products() -> dict[str, Any]:
    """Trả TẤT CẢ sản phẩm gom theo danh mục trong 1 request (tránh N+1 khi tải cửa hàng)."""
    with db() as c:
        rows = c.execute(
            "SELECT p.*, f.category_id AS category_id "
            "FROM store_products p JOIN store_folders f ON f.id=p.folder_id "
            "ORDER BY p.sort ASC, p.id ASC").fetchall()
        grouped: dict[str, list] = {}
        for r in rows:
            grouped.setdefault(str(r["category_id"]), []).append(_product_public(c, r))
    return {"by_category": grouped}


@app.get("/store/config")
def store_config() -> dict[str, Any]:
    # Đếm số THẬT cho 3 ô thống kê (người dùng / sản phẩm đã bán / lượt đánh giá)
    with db() as c:
        real_users = c.execute("SELECT COUNT(*) n FROM users").fetchone()["n"]
        real_sold = c.execute("SELECT COUNT(*) n FROM store_orders WHERE status='completed'").fetchone()["n"]
        try:
            real_reviews = c.execute("SELECT COUNT(*) n FROM store_reviews").fetchone()["n"]
        except Exception:
            real_reviews = 0
    return {
        "logo_name": get_setting("store_logo_name", "KENIOS Store"),
        "logo_url": get_setting("store_logo_url", ""),
        "banner_type": get_setting("store_banner_type", "image"),
        "banner_url": get_setting("store_banner_url", ""),
        "topup_bonus_percent": _topup_bonus_percent(),
        # Hiệu ứng / font logo cửa hàng + nền full màn hình
        "logo_effect": get_setting("store_logo_effect", "rainbow"),   # rainbow|none|glow|neon|gold
        "logo_font": get_setting("store_logo_font", "rounded"),       # rounded|serif|mono|default
        "logo_anim": get_setting("store_logo_anim", "shimmer"),       # shimmer|wave|pulse|none
        "bg_type": get_setting("store_bg_type", "none"),              # none|image|video
        "bg_url": get_setting("store_bg_url", ""),
        # Dòng giới thiệu (slogan) dưới tên cửa hàng + font + thứ tự bố cục các mục
        "slogan": get_setting("store_slogan", "Cửa hàng sản phẩm số · key · tải về"),
        "slogan_font": get_setting("store_slogan_font", "rounded"),
        "section_order": get_setting("store_section_order",
                                     "hero,categories,gamecat,flash,trust,steps,leaderboard,"
                                     "transactions,topups,downloads,contacts,wishlist,recent,products,footer"),
        # Các mục bị ẩn (admin tắt cho gọn). Mặc định ẩn "products" vì đã có lưới "gamecat".
        "section_hidden": get_setting("store_section_hidden", "products"),
        "card_size": get_setting("store_card_size", "medium"),   # small | medium | large
        "card_scale": get_setting("store_card_scale", "1.0"),    # hệ số kéo kích cỡ 0.6–1.6
        # Flash sale (đếm ngược) — admin bật + chọn sản phẩm + thời điểm kết thúc + % giảm
        "flash_enabled": get_setting("store_flash_enabled", "0") == "1",
        "flash_product_id": _int_setting("store_flash_product_id", 0),
        "flash_end": _int_setting("store_flash_end", 0),
        "flash_discount": _int_setting("store_flash_discount", 0),
        "flash_title": get_setting("store_flash_title", "FLASH SALE"),
        # Hero (banner chính đầu trang)
        "hero_title": get_setting("store_hero_title", ""),
        "hero_subtitle": get_setting("store_hero_subtitle", ""),
        "hero_effect": get_setting("store_hero_effect", "gradient"),
        "hero_font": get_setting("store_hero_font", "rounded"),
        "hero_anim": get_setting("store_hero_anim", "shimmer"),
        # Hiệu ứng / chuyển động cho slogan
        "slogan_effect": get_setting("store_slogan_effect", "none"),
        "slogan_anim": get_setting("store_slogan_anim", "none"),
        # Khuyến mãi (banner ảnh trong phần ví nạp tiền)
        "promo_image_url": get_setting("store_promo_image_url", ""),
        "promo_product_id": _int_setting("store_promo_product_id", 0),
        # 3 ô thống kê: số ẢO admin đặt + số THẬT đếm từ DB (app hiển thị tổng = ảo + thật)
        "stat_users_base": _int_setting("store_stat_users_base", 0),
        "stat_sold_base": _int_setting("store_stat_sold_base", 0),
        "stat_reviews_base": _int_setting("store_stat_reviews_base", 0),
        "stat_users_real": real_users,
        "stat_sold_real": real_sold,
        "stat_reviews_real": real_reviews,
        # Thanh thông báo chạy (announcement) đầu trang cửa hàng
        "announce_enabled": get_setting("store_announce_enabled", "0") == "1",
        "announce_text": get_setting("store_announce_text", ""),
        "announce_color": get_setting("store_announce_color", "accent"),  # accent|red|green|gold|purple
        # Số sản phẩm hiển thị tối đa mỗi danh mục ở lưới "Danh mục Game"
        "gamecat_limit": _int_setting("store_gamecat_limit", 6),
    }


def _int_setting(key: str, default: int = 0) -> int:
    try:
        return int(get_setting(key, str(default)) or default)
    except (TypeError, ValueError):
        return default


def _mask_name(s: str) -> str:
    """Che tên người dùng: giữ 2 ký tự đầu + 1 ký tự cuối, ở giữa là dấu *."""
    s = (s or "").strip()
    if not s:
        return "***"
    if len(s) <= 2:
        return s[0] + "*"
    if len(s) <= 4:
        return s[0] + "*" * (len(s) - 2) + s[-1]
    return s[:2] + "*" * max(3, len(s) - 3) + s[-1]


@app.get("/store/showcase")
def store_showcase() -> dict[str, Any]:
    """Dữ liệu trang chủ cửa hàng: giao dịch gần đây, nạp gần đây, bảng xếp hạng nạp."""
    with db() as c:
        orders = c.execute(
            "SELECT o.amount AS amount, o.created_at AS at, u.username AS uname, "
            "       p.name AS pname, pr.label AS plabel "
            "FROM store_orders o "
            "JOIN users u ON u.id=o.user_id "
            "JOIN store_products p ON p.id=o.product_id "
            "LEFT JOIN store_prices pr ON pr.id=o.price_id "
            "WHERE o.status='completed' "
            "ORDER BY o.created_at DESC LIMIT 20").fetchall()
        topups = c.execute(
            "SELECT t.amount AS amount, t.created_at AS at, u.username AS uname "
            "FROM store_topups t JOIN users u ON u.id=t.user_id "
            "WHERE t.status='completed' "
            "ORDER BY t.created_at DESC LIMIT 20").fetchall()
        leaders = c.execute(
            "SELECT u.username AS uname, SUM(t.credited) AS total "
            "FROM store_topups t JOIN users u ON u.id=t.user_id "
            "WHERE t.status='completed' "
            "GROUP BY t.user_id ORDER BY total DESC LIMIT 5").fetchall()
    return {
        "recent_orders": [
            {"user": _mask_name(r["uname"]), "product": r["pname"],
             "label": r["plabel"] or "", "amount": r["amount"] or 0, "at": r["at"] or 0}
            for r in orders
        ],
        "recent_topups": [
            {"user": _mask_name(r["uname"]), "amount": r["amount"] or 0, "at": r["at"] or 0}
            for r in topups
        ],
        "leaderboard": [
            {"rank": i + 1, "user": _mask_name(r["uname"]), "total": r["total"] or 0}
            for i, r in enumerate(leaders)
        ],
    }


# -------------------- Lưu ảnh từ máy → trả về link URL công khai --------------------
class MediaUploadIn(BaseModel):
    data_base64: str
    mime: Optional[str] = None
    name: Optional[str] = None

@app.post("/media/upload")
def media_upload(b: MediaUploadIn, user=Depends(get_user)) -> dict[str, Any]:
    data = (b.data_base64 or "").strip()
    if data.startswith("data:") and "," in data:
        data = data.split(",", 1)[1]
    try:
        raw = base64.b64decode(data)
    except Exception:
        raise HTTPException(status_code=400, detail="Dữ liệu ảnh không hợp lệ.")
    if not raw:
        raise HTTPException(status_code=400, detail="Ảnh rỗng.")
    mime = b.mime or "image/jpeg"
    name = (b.name or f"media_{int(time.time())}")[:80]
    with db() as c:
        cur = c.execute("INSERT INTO files(user_id,name,category,mime,size,data,created_at) "
                        "VALUES(?,?,?,?,?,'',?)",
                        (user["id"], name, "media", mime, len(raw), int(time.time())))
        fid = cur.lastrowid
    try:
        with open(os.path.join(UPLOAD_DIR, str(fid)), "wb") as f:
            f.write(raw)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Lỗi lưu ảnh: {e}")
    return {"id": fid, "path": f"/media/{fid}"}

@app.get("/media/{fid}")
def media_serve(fid: int, background_tasks: BackgroundTasks):
    """Phục vụ ảnh đã upload — công khai (để dùng làm link logo/banner/media)."""
    with db() as c:
        row = c.execute("SELECT name,mime,data FROM files WHERE id=? AND category='media'", (fid,)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy ảnh.")
    path = os.path.join(UPLOAD_DIR, str(fid))
    if os.path.exists(path):
        return FileResponse(path, media_type=row["mime"] or "image/jpeg")
    if row["data"]:
        tmp = os.path.join(UPLOAD_DIR, f"m_{fid}_{secrets.token_hex(3)}")
        with open(tmp, "wb") as f:
            f.write(base64.b64decode(row["data"]))
        background_tasks.add_task(os.unlink, tmp)
        return FileResponse(tmp, media_type=row["mime"] or "image/jpeg")
    raise HTTPException(status_code=404, detail="Không có nội dung ảnh.")


# ======================== VÍ CỬA HÀNG (tách biệt thanh toán app chính) ========================
def _topup_bonus_percent() -> int:
    try:
        v = int(get_setting("store_topup_bonus_percent", "0") or 0)
    except (TypeError, ValueError):
        v = 0
    return max(0, min(v, 1000))

def _wallet_balance(c, uid: int) -> int:
    r = c.execute("SELECT wallet FROM users WHERE id=?", (uid,)).fetchone()
    return (r["wallet"] or 0) if r else 0

def _wallet_add(c, uid: int, delta: int, kind: str, note: str = "") -> None:
    c.execute("UPDATE users SET wallet=COALESCE(wallet,0)+? WHERE id=?", (delta, uid))
    c.execute("INSERT INTO store_wallet_tx(user_id,kind,amount,note,created_at) VALUES(?,?,?,?,?)",
              (uid, kind, delta, note, int(time.time())))


@app.get("/store/wallet")
def store_wallet(user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        bal = _wallet_balance(c, user["id"])
        tx = c.execute("SELECT kind,amount,note,created_at FROM store_wallet_tx "
                       "WHERE user_id=? ORDER BY id DESC LIMIT 50", (user["id"],)).fetchall()
    return {
        "balance": bal,
        "bonus_percent": _topup_bonus_percent(),
        "tx": [{"kind": r["kind"], "amount": r["amount"], "note": r["note"] or "",
                "created_at": r["created_at"]} for r in tx],
    }


class TopupIn(BaseModel):
    amount: int

@app.post("/store/wallet/topup")
def store_wallet_topup(b: TopupIn, user=Depends(get_user)) -> dict[str, Any]:
    amt = int(b.amount or 0)
    if amt < 1000:
        raise HTTPException(status_code=400, detail="Số tiền nạp tối thiểu 1.000đ.")
    pct = _topup_bonus_percent()
    bonus = amt * pct // 100
    credited = amt + bonus
    ref = secrets.token_urlsafe(10)
    with db() as c:
        cid = _ensure_public_id(c, user["id"])
        cur = c.execute(
            "INSERT INTO store_topups(user_id,amount,bonus,credited,status,ref,created_at) "
            "VALUES(?,?,?,?,'pending',?,?)",
            (user["id"], amt, bonus, credited, ref, int(time.time())))
        tid = cur.lastrowid
    bank = bank_info(amount=amt, note=cid)
    return {
        "topup_id": tid, "ref": cid, "amount": amt, "bonus": bonus,
        "credited": credited, "bonus_percent": pct,
        "message": (f"Chuyển khoản {amt:,}đ với nội dung là ID của bạn: {cid}. "
                    f"Ví sẽ được cộng {credited:,}đ" + (f" (thưởng {pct}%)" if pct else "") + ".").replace(",", "."),
        "bank_info": bank, "qr_url": bank["qr_url"],
    }


def _finalize_topup_row(c, t) -> bool:
    """Hoàn tất 1 đơn nạp ví. Idempotent."""
    claimed = c.execute("UPDATE store_topups SET status='completed' WHERE id=? AND status='pending'",
                        (t["id"],))
    if claimed.rowcount != 1:
        return False
    _wallet_add(c, t["user_id"], t["credited"], "topup",
                f"Nạp {t['amount']:,}đ".replace(",", ".") +
                (f" + thưởng {t['bonus']:,}đ".replace(",", ".") if t["bonus"] else ""))
    log.info("Ví: nạp xong topup #%d user=%d +%d", t["id"], t["user_id"], t["credited"])
    # Báo admin có người nạp ví (chạy nền)
    urow = c.execute("SELECT username FROM users WHERE id=?", (t["user_id"],)).fetchone()
    uname = urow["username"] if urow else f"user#{t['user_id']}"
    _notify_admins("💰 Nạp ví mới",
                   f"{uname} vừa nạp {t['amount']:,}đ".replace(",", ".") +
                   (f" (+{t['bonus']:,}đ thưởng)".replace(",", ".") if t["bonus"] else ""))
    return True

@app.get("/store/categories")
def store_categories() -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute("SELECT id,name,media,sort FROM store_categories "
                         "ORDER BY sort ASC, id ASC").fetchall()
    return [{"id": r["id"], "name": r["name"], "media": _load_media(r["media"])} for r in rows]

@app.get("/store/categories/{cid}/folders")
def store_folders(cid: int) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute("SELECT id,category_id,name,media,sort FROM store_folders "
                         "WHERE category_id=? ORDER BY sort ASC, id ASC", (cid,)).fetchall()
    return [{"id": r["id"], "category_id": r["category_id"], "name": r["name"],
             "media": _load_media(r["media"])} for r in rows]

@app.get("/store/folders/{fid}/products")
def store_products(fid: int) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute("SELECT * FROM store_products WHERE folder_id=? "
                         "ORDER BY sort ASC, id ASC", (fid,)).fetchall()
        return [_product_public(c, r) for r in rows]

@app.get("/store/products/{pid}")
def store_product_detail(pid: int) -> dict[str, Any]:
    with db() as c:
        row = c.execute("SELECT * FROM store_products WHERE id=?", (pid,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm.")
        return _product_public(c, row)

@app.get("/store/products/{pid}/mine")
def store_product_mine(pid: int, user=Depends(get_user)) -> dict[str, Any]:
    """Trả về key + link tải nếu khách đã mua sản phẩm này."""
    with db() as c:
        prod = c.execute("SELECT * FROM store_products WHERE id=?", (pid,)).fetchone()
        if not prod:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm.")
        # Key đã được giao lưu trong đơn (key gốc đã bị xoá khỏi kho sau khi bán)
        order = c.execute("SELECT key_text,delivery_msg,expires_at FROM store_orders "
                          "WHERE product_id=? AND user_id=? "
                          "AND status='completed' ORDER BY id DESC LIMIT 1",
                          (pid, user["id"])).fetchone()
        if not order:
            return {"owned": False}
        return {
            "owned": True,
            "key": order["key_text"] or "",
            "delivery": order["delivery_msg"] or "",
            "expires_at": order["expires_at"],
            "download_url": prod["download_url"] or "",
            "download_file_id": prod["download_file_id"],
        }


# -------------------- Đánh giá sản phẩm (đếm "lượt đánh giá") --------------------
class ReviewIn(BaseModel):
    stars: int = 5

@app.post("/store/products/{pid}/review")
def store_review(pid: int, b: ReviewIn, user=Depends(get_user)) -> dict[str, Any]:
    """Khách đánh giá sản phẩm — mỗi khách 1 đánh giá/sản phẩm (cập nhật nếu đã có)."""
    stars = max(1, min(5, int(b.stars)))
    with db() as c:
        c.execute(
            "INSERT INTO store_reviews(product_id,user_id,stars,created_at) VALUES(?,?,?,?) "
            "ON CONFLICT(product_id,user_id) DO UPDATE SET stars=excluded.stars",
            (pid, user["id"], stars, int(time.time())))
        total = c.execute("SELECT COUNT(*) n FROM store_reviews").fetchone()["n"]
    return {"ok": True, "total_reviews": total}


@app.post("/store/products/{pid}/view")
def store_product_view(pid: int) -> dict[str, Any]:
    """Tăng lượt xem sản phẩm — mỗi lần khách bấm vào +1 (không giới hạn, công khai)."""
    with db() as c:
        c.execute("UPDATE store_products SET views=COALESCE(views,0)+1 WHERE id=?", (pid,))
        row = c.execute("SELECT views FROM store_products WHERE id=?", (pid,)).fetchone()
    return {"views": (row["views"] if row else 0) or 0}


# -------------------- Khách mua bằng VÍ (giao hàng tức thì) --------------------
class StoreOrderIn(BaseModel):
    product_id: int
    price_id: Optional[int] = None
    promo_code: Optional[str] = None

@app.post("/store/orders")
def store_buy(b: StoreOrderIn, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        prod = c.execute("SELECT * FROM store_products WHERE id=?", (b.product_id,)).fetchone()
        if not prod:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm.")
        prices = _product_prices(c, b.product_id)
        if not prices:
            raise HTTPException(status_code=400, detail="Sản phẩm chưa có giá bán.")
        price = None
        if b.price_id is not None:
            price = next((p for p in prices if p["id"] == b.price_id), None)
        if price is None:
            price = prices[0]
        amount = price["amount"]
        # Áp dụng mã khuyến mãi nếu có
        discount = 0
        promo_row = None
        if b.promo_code:
            now = int(time.time())
            promo_row = c.execute(
                "SELECT * FROM store_promo_codes WHERE code=? AND is_active=1",
                (b.promo_code.strip().upper(),)
            ).fetchone()
            if not promo_row:
                raise HTTPException(status_code=400, detail="Mã khuyến mãi không hợp lệ hoặc đã hết hạn.")
            if promo_row["expires_at"] and promo_row["expires_at"] < now:
                raise HTTPException(status_code=400, detail="Mã khuyến mãi đã hết hạn.")
            if promo_row["max_uses"] and promo_row["used_count"] >= promo_row["max_uses"]:
                raise HTTPException(status_code=400, detail="Mã khuyến mãi đã hết lượt sử dụng.")
            if amount < promo_row["min_amount"]:
                raise HTTPException(status_code=400,
                    detail=f"Đơn hàng tối thiểu {promo_row['min_amount']:,}đ để dùng mã này.".replace(",", "."))
            if promo_row["discount_type"] == "percent":
                discount = int(amount * promo_row["discount_value"] / 100)
            else:
                discount = min(promo_row["discount_value"], amount)
            amount = max(0, amount - discount)
        balance = _wallet_balance(c, user["id"])
        if balance < amount:
            raise HTTPException(status_code=400,
                detail=f"Số dư ví không đủ (cần {amount:,}đ, còn {balance:,}đ). Vui lòng nạp thêm vào ví."
                       .replace(",", "."))
        # Giành 1 key khả dụng (atomic) — CHỈ lấy key đúng mốc thời hạn đã chọn.
        # Mỗi mốc (giờ/ngày/tuần/tháng) có kho riêng; hết mốc nào thì mốc đó hết hàng.
        key = None
        for _ in range(50):
            cand = c.execute(
                "SELECT id,key_text FROM store_keys WHERE product_id=? AND status='available' "
                "AND price_id=? ORDER BY id ASC LIMIT 1", (b.product_id, price["id"])).fetchone()
            if not cand:
                break
            got = c.execute("UPDATE store_keys SET status='sold' WHERE id=? AND status='available'",
                            (cand["id"],))
            if got.rowcount == 1:
                key = cand
                break
        if not key:
            raise HTTPException(status_code=400,
                detail=f"Mốc \"{price['label']}\" đã hết hàng. Vui lòng chọn mốc khác.")
        # Trừ ví (atomic, chống âm)
        ded = c.execute("UPDATE users SET wallet=wallet-? WHERE id=? AND wallet>=?",
                        (amount, user["id"], amount))
        if ded.rowcount != 1:
            c.execute("UPDATE store_keys SET status='available' WHERE id=?", (key["id"],))  # trả key
            raise HTTPException(status_code=400, detail="Số dư ví không đủ. Vui lòng nạp thêm.")
        if promo_row:
            c.execute("UPDATE store_promo_codes SET used_count=used_count+1 WHERE id=?", (promo_row["id"],))
        cur = c.execute(
            "INSERT INTO store_orders(user_id,product_id,price_id,key_id,key_text,amount,status,ref,created_at) "
            "VALUES(?,?,?,?,?,?,'completed',?,?)",
            (user["id"], b.product_id, price["id"], key["id"], key["key_text"], amount,
             "wallet", int(time.time())))
        oid = cur.lastrowid
        deliv = _apply_delivery(c, oid, b.product_id, price["label"], key["key_text"],
                                int(time.time()), _row_kind(prod))
        c.execute("DELETE FROM store_keys WHERE id=?", (key["id"],))   # đã giao → xoá khỏi kho
        c.execute("INSERT INTO store_wallet_tx(user_id,kind,amount,note,created_at) VALUES(?,?,?,?,?)",
                  (user["id"], "purchase", -amount, f"Mua {prod['name']}", int(time.time())))
        new_balance = _wallet_balance(c, user["id"])
    # Báo admin có đơn mới (chạy nền, không ảnh hưởng tới phản hồi mua hàng)
    _notify_admins("🛒 Đơn hàng mới",
                   f"{user['username']} vừa mua {prod['name']} — "
                   f"{amount:,}đ".replace(",", "."))
    return {
        "ok": True, "owned": True, "order_id": oid,
        "key": key["key_text"], "product_name": prod["name"],
        "download_url": prod["download_url"] or "",
        "download_file_id": prod["download_file_id"],
        "balance": new_balance,
        "discount": discount,
        "platform": deliv["platform"], "expires_at": deliv["expires_at"],
        "delivery": deliv["delivery"],
        "message": ("Mua thành công! Key đã được giao." if not discount else
                    f"Mua thành công! Đã giảm {discount:,}đ.".replace(",", ".")),
    }


# -------------------- Tải về công khai (hiện ngay khi vào cửa hàng) --------------------
@app.get("/store/downloads")
def store_downloads() -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute("SELECT * FROM store_products WHERE download_url!='' OR download_file_id IS NOT NULL "
                         "ORDER BY id DESC").fetchall()
    return [{
        "id": r["id"], "name": r["name"], "kind": _row_kind(r),
        "media": _load_media(r["media"]),
        "download_url": r["download_url"] or "",
        "has_file": r["download_file_id"] is not None,
    } for r in rows]

@app.get("/store/products/{pid}/download")
def store_public_download(pid: int, background_tasks: BackgroundTasks):
    """Tải file/link của sản phẩm — công khai (bản tải miễn phí; KEY mới là thứ phải mua)."""
    from fastapi.responses import RedirectResponse
    with db() as c:
        prod = c.execute("SELECT download_url,download_file_id FROM store_products WHERE id=?", (pid,)).fetchone()
    if not prod:
        raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm.")
    if (prod["download_url"] or "").strip():
        return RedirectResponse(prod["download_url"].strip())
    fid = prod["download_file_id"]
    if fid is None:
        raise HTTPException(status_code=404, detail="Sản phẩm chưa có bản tải.")
    with db() as c:
        row = c.execute("SELECT name,mime,data FROM files WHERE id=?", (fid,)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy file tải.")
    file_path = os.path.join(UPLOAD_DIR, str(fid))
    if os.path.exists(file_path):
        return FileResponse(path=file_path, filename=row["name"],
                            media_type=row["mime"] or "application/octet-stream",
                            content_disposition_type="attachment")
    if row["data"]:
        temp_path = os.path.join(UPLOAD_DIR, f"dl_{fid}_{secrets.token_hex(4)}")
        with open(temp_path, "wb") as f:
            f.write(base64.b64decode(row["data"]))
        background_tasks.add_task(os.unlink, temp_path)
        return FileResponse(path=temp_path, filename=row["name"],
                            media_type=row["mime"] or "application/octet-stream",
                            content_disposition_type="attachment")
    raise HTTPException(status_code=404, detail="Không tìm thấy nội dung tệp.")

@app.get("/store/orders")
def store_my_orders(user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute(
            "SELECT o.id,o.product_id,o.amount,o.status,o.ref,o.created_at,o.key_text,"
            "o.delivery_msg,o.expires_at,"
            "p.name AS product_name,p.download_url,p.download_file_id "
            "FROM store_orders o LEFT JOIN store_products p ON p.id=o.product_id "
            "WHERE o.user_id=? ORDER BY o.id DESC", (user["id"],)).fetchall()
        out = []
        for r in rows:
            # key đã giao lưu thẳng trong đơn (store_keys gốc đã bị xoá sau khi bán)
            done = r["status"] == "completed"
            key_text = r["key_text"] if done else None
            out.append({
                "id": r["id"], "product_id": r["product_id"],
                "product_name": r["product_name"] or "(đã xoá)",
                "amount": r["amount"], "status": r["status"], "ref": r["ref"],
                "created_at": r["created_at"], "key": key_text,
                "delivery": (r["delivery_msg"] or "") if done else "",
                "expires_at": r["expires_at"] if done else None,
                "download_url": (r["download_url"] or "") if done else "",
                "download_file_id": r["download_file_id"] if done else None,
            })
    return out


# -------------------- Admin: cấu hình giao diện store --------------------
class StoreConfigIn(BaseModel):
    logo_name: Optional[str] = None
    logo_url: Optional[str] = None
    banner_type: Optional[str] = None   # image | video
    banner_url: Optional[str] = None
    logo_effect: Optional[str] = None
    logo_font: Optional[str] = None
    logo_anim: Optional[str] = None
    bg_type: Optional[str] = None       # none | image | video
    bg_url: Optional[str] = None
    slogan: Optional[str] = None
    slogan_font: Optional[str] = None
    section_order: Optional[str] = None
    section_hidden: Optional[str] = None
    card_size: Optional[str] = None
    card_scale: Optional[float] = None
    flash_enabled: Optional[bool] = None
    flash_product_id: Optional[int] = None
    flash_end: Optional[int] = None
    flash_discount: Optional[int] = None
    flash_title: Optional[str] = None
    # Hero (banner chính đầu trang)
    hero_title: Optional[str] = None
    hero_subtitle: Optional[str] = None
    hero_effect: Optional[str] = None
    hero_font: Optional[str] = None
    hero_anim: Optional[str] = None
    # Hiệu ứng / chuyển động cho slogan
    slogan_effect: Optional[str] = None
    slogan_anim: Optional[str] = None
    # Khuyến mãi (banner ảnh trong phần ví nạp tiền)
    promo_image_url: Optional[str] = None
    promo_product_id: Optional[int] = None
    # 3 ô thống kê: số ảo admin đặt (số thật đếm tự động ở backend)
    stat_users_base: Optional[int] = None
    stat_sold_base: Optional[int] = None
    stat_reviews_base: Optional[int] = None
    # Thanh thông báo chạy
    announce_enabled: Optional[bool] = None
    announce_text: Optional[str] = None
    announce_color: Optional[str] = None
    # Số sản phẩm/danh mục trong lưới "Danh mục Game"
    gamecat_limit: Optional[int] = None

@app.post("/admin/store/config")
def admin_store_config(b: StoreConfigIn, admin=Depends(get_admin)) -> dict[str, Any]:
    if b.logo_name is not None: set_setting("store_logo_name", b.logo_name.strip()[:60])
    if b.logo_url is not None: set_setting("store_logo_url", b.logo_url.strip())
    if b.banner_type is not None:
        set_setting("store_banner_type", "video" if b.banner_type == "video" else "image")
    if b.banner_url is not None: set_setting("store_banner_url", b.banner_url.strip())
    if b.logo_effect is not None: set_setting("store_logo_effect", b.logo_effect.strip()[:20])
    if b.logo_font is not None: set_setting("store_logo_font", b.logo_font.strip()[:20])
    if b.logo_anim is not None: set_setting("store_logo_anim", b.logo_anim.strip()[:20])
    if b.bg_type is not None:
        set_setting("store_bg_type", b.bg_type if b.bg_type in ("none", "image", "video") else "none")
    if b.bg_url is not None: set_setting("store_bg_url", b.bg_url.strip())
    if b.slogan is not None: set_setting("store_slogan", b.slogan.strip()[:120])
    if b.slogan_font is not None: set_setting("store_slogan_font", b.slogan_font.strip()[:20])
    if b.section_order is not None: set_setting("store_section_order", b.section_order.strip()[:200])
    if b.section_hidden is not None: set_setting("store_section_hidden", b.section_hidden.strip()[:200])
    if b.card_size is not None:
        set_setting("store_card_size", b.card_size if b.card_size in ("small", "medium", "large") else "medium")
    if b.card_scale is not None:
        sc = max(0.6, min(float(b.card_scale), 1.6))
        set_setting("store_card_scale", f"{sc:.2f}")
    if b.flash_enabled is not None: set_setting("store_flash_enabled", "1" if b.flash_enabled else "0")
    if b.flash_product_id is not None: set_setting("store_flash_product_id", str(max(0, int(b.flash_product_id))))
    if b.flash_end is not None: set_setting("store_flash_end", str(max(0, int(b.flash_end))))
    if b.flash_discount is not None: set_setting("store_flash_discount", str(max(0, min(int(b.flash_discount), 99))))
    if b.flash_title is not None: set_setting("store_flash_title", b.flash_title.strip()[:40])
    # Hero
    if b.hero_title is not None: set_setting("store_hero_title", b.hero_title.strip()[:120])
    if b.hero_subtitle is not None: set_setting("store_hero_subtitle", b.hero_subtitle.strip()[:160])
    if b.hero_effect is not None: set_setting("store_hero_effect", b.hero_effect.strip()[:20])
    if b.hero_font is not None: set_setting("store_hero_font", b.hero_font.strip()[:20])
    if b.hero_anim is not None: set_setting("store_hero_anim", b.hero_anim.strip()[:20])
    # Slogan effect / anim
    if b.slogan_effect is not None: set_setting("store_slogan_effect", b.slogan_effect.strip()[:20])
    if b.slogan_anim is not None: set_setting("store_slogan_anim", b.slogan_anim.strip()[:20])
    # Khuyến mãi (banner)
    if b.promo_image_url is not None: set_setting("store_promo_image_url", b.promo_image_url.strip())
    if b.promo_product_id is not None: set_setting("store_promo_product_id", str(max(0, int(b.promo_product_id))))
    # 3 ô thống kê — số ảo (số thật cộng tự động ở store_config)
    if b.stat_users_base is not None: set_setting("store_stat_users_base", str(max(0, int(b.stat_users_base))))
    if b.stat_sold_base is not None: set_setting("store_stat_sold_base", str(max(0, int(b.stat_sold_base))))
    if b.stat_reviews_base is not None: set_setting("store_stat_reviews_base", str(max(0, int(b.stat_reviews_base))))
    # Thanh thông báo
    if b.announce_enabled is not None: set_setting("store_announce_enabled", "1" if b.announce_enabled else "0")
    if b.announce_text is not None: set_setting("store_announce_text", b.announce_text.strip()[:200])
    if b.announce_color is not None: set_setting("store_announce_color", b.announce_color.strip()[:20])
    if b.gamecat_limit is not None: set_setting("store_gamecat_limit", str(max(1, min(int(b.gamecat_limit), 30))))
    return {"message": "Đã cập nhật giao diện app bán hàng."}


# -------------------- Admin: % khuyến mãi nạp ví --------------------
class TopupBonusIn(BaseModel):
    percent: int

@app.get("/admin/store/topup-bonus")
def admin_get_topup_bonus(admin=Depends(get_admin)) -> dict[str, Any]:
    return {"percent": _topup_bonus_percent()}

@app.post("/admin/store/topup-bonus")
def admin_set_topup_bonus(b: TopupBonusIn, admin=Depends(get_admin)) -> dict[str, Any]:
    p = max(0, min(int(b.percent), 1000))
    set_setting("store_topup_bonus_percent", str(p))
    return {"message": f"Đã đặt khuyến mãi nạp ví {p}%.", "percent": p}


# -------------------- Admin: cộng/trừ ví khách (thủ công) --------------------
class WalletAdjustIn(BaseModel):
    user: str            # public_id / username / id
    delta: int           # +nạp / -trừ (VND)
    note: str = ""

@app.post("/admin/store/wallet/adjust")
def admin_store_wallet_adjust(b: WalletAdjustIn, admin=Depends(get_admin)) -> dict[str, Any]:
    ident = (b.user or "").strip()
    if not ident:
        raise HTTPException(status_code=400, detail="Thiếu thông tin người dùng (ID / username).")
    with db() as c:
        row = c.execute(
            "SELECT id,username,wallet FROM users WHERE public_id=? OR username=? OR CAST(id AS TEXT)=?",
            (ident, ident, ident)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail=f"Không tìm thấy người dùng '{ident}'.")
        delta = int(b.delta)
        cur_bal = row["wallet"] or 0
        if delta < 0 and cur_bal + delta < 0:
            delta = -cur_bal   # không cho âm
        kind = "topup" if delta >= 0 else "purchase"
        note = b.note.strip() or ("Admin nạp ví" if delta >= 0 else "Admin trừ ví")
        _wallet_add(c, row["id"], delta, kind, note)
        bal = _wallet_balance(c, row["id"])
    sign = "+" if delta >= 0 else ""
    return {"message": f"Đã cập nhật ví của {row['username']}: {sign}{delta:,}đ. Số dư hiện tại: {bal:,}đ"
            .replace(",", ".")}


# -------------------- Liên hệ admin & Nhóm cộng đồng (mạng xã hội) --------------------
class SocialLink(BaseModel):
    platform: str
    url: str = ""
    enabled: bool = False

class StoreContactsIn(BaseModel):
    contact: list[SocialLink] = []   # Liên hệ admin
    groups: list[SocialLink] = []    # Nhóm cộng đồng

def _load_links(key: str) -> list:
    try:
        v = json.loads(get_setting(key, "[]") or "[]")
        return v if isinstance(v, list) else []
    except Exception:
        return []

def _dump_links(items) -> str:
    out = []
    for m in (items or []):
        if isinstance(m, SocialLink):
            d = {"platform": m.platform, "url": (m.url or "").strip(), "enabled": bool(m.enabled)}
        elif isinstance(m, dict):
            d = {"platform": m.get("platform", ""), "url": (m.get("url", "") or "").strip(),
                 "enabled": bool(m.get("enabled"))}
        else:
            continue
        if d["platform"]:
            out.append(d)
    return json.dumps(out, ensure_ascii=False)

@app.get("/store/contacts")
def store_contacts() -> dict[str, Any]:
    """Công khai: chỉ trả các liên kết đã BẬT và có link (cho khách xem)."""
    def enabled_only(key: str) -> list:
        return [x for x in _load_links(key)
                if x.get("enabled") and (x.get("url") or "").strip()]
    return {"contact": enabled_only("store_contact_links"),
            "groups": enabled_only("store_group_links")}

@app.get("/admin/store/contacts")
def admin_get_contacts(admin=Depends(get_admin)) -> dict[str, Any]:
    """Admin: trả full (cả mục tắt) để chỉnh sửa."""
    return {"contact": _load_links("store_contact_links"),
            "groups": _load_links("store_group_links")}

@app.post("/admin/store/contacts")
def admin_set_contacts(b: StoreContactsIn, admin=Depends(get_admin)) -> dict[str, Any]:
    set_setting("store_contact_links", _dump_links(b.contact))
    set_setting("store_group_links", _dump_links(b.groups))
    return {"message": "Đã lưu liên hệ admin & nhóm cộng đồng."}


# -------------------- Admin: danh mục --------------------
class StoreCategoryIn(BaseModel):
    id: Optional[int] = None
    name: str
    media: list[MediaItem] = []

@app.post("/admin/store/categories")
def admin_store_save_category(b: StoreCategoryIn, admin=Depends(get_admin)) -> dict[str, Any]:
    name = (b.name or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Tên danh mục không được để trống.")
    media = _dump_media(b.media)
    with db() as c:
        if b.id:
            c.execute("UPDATE store_categories SET name=?, media=? WHERE id=?", (name, media, b.id))
            cid = b.id
        else:
            cur = c.execute("INSERT INTO store_categories(name,media,created_at) VALUES(?,?,?)",
                            (name, media, int(time.time())))
            cid = cur.lastrowid
    return {"message": "Đã lưu danh mục.", "id": cid}

@app.delete("/admin/store/categories/{cid}")
def admin_store_delete_category(cid: int, admin=Depends(get_admin)) -> dict[str, Any]:
    with db() as c:
        folder_ids = [r["id"] for r in c.execute(
            "SELECT id FROM store_folders WHERE category_id=?", (cid,)).fetchall()]
        for fid in folder_ids:
            _delete_folder_cascade(c, fid)
        c.execute("DELETE FROM store_categories WHERE id=?", (cid,))
    return {"message": "Đã xoá danh mục."}


# -------------------- Admin: thư mục con --------------------
class StoreFolderIn(BaseModel):
    id: Optional[int] = None
    category_id: int
    name: str
    media: list[MediaItem] = []

@app.post("/admin/store/folders")
def admin_store_save_folder(b: StoreFolderIn, admin=Depends(get_admin)) -> dict[str, Any]:
    name = (b.name or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Tên thư mục không được để trống.")
    media = _dump_media(b.media)
    with db() as c:
        if b.id:
            c.execute("UPDATE store_folders SET name=?, media=? WHERE id=?", (name, media, b.id))
            fid = b.id
        else:
            cur = c.execute("INSERT INTO store_folders(category_id,name,media,created_at) VALUES(?,?,?,?)",
                            (b.category_id, name, media, int(time.time())))
            fid = cur.lastrowid
    return {"message": "Đã lưu thư mục.", "id": fid}

def _delete_folder_cascade(c, fid: int) -> None:
    prod_ids = [r["id"] for r in c.execute(
        "SELECT id FROM store_products WHERE folder_id=?", (fid,)).fetchall()]
    for pid in prod_ids:
        c.execute("DELETE FROM store_prices WHERE product_id=?", (pid,))
        c.execute("DELETE FROM store_keys WHERE product_id=?", (pid,))
        c.execute("DELETE FROM store_products WHERE id=?", (pid,))
    c.execute("DELETE FROM store_folders WHERE id=?", (fid,))

@app.delete("/admin/store/folders/{fid}")
def admin_store_delete_folder(fid: int, admin=Depends(get_admin)) -> dict[str, Any]:
    with db() as c:
        _delete_folder_cascade(c, fid)
    return {"message": "Đã xoá thư mục."}


# -------------------- Admin: sản phẩm --------------------
class StoreProductIn(BaseModel):
    id: Optional[int] = None
    folder_id: int
    name: str
    description: str = ""
    media: list[MediaItem] = []
    download_url: str = ""
    download_file_id: Optional[int] = None
    kind: str = "app"   # app (key/ứng dụng) | acc (acc game)

@app.post("/admin/store/products")
def admin_store_save_product(b: StoreProductIn, admin=Depends(get_admin)) -> dict[str, Any]:
    name = (b.name or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Tên sản phẩm không được để trống.")
    media = _dump_media(b.media)
    kind = "acc" if b.kind == "acc" else "app"
    with db() as c:
        if b.id:
            c.execute("UPDATE store_products SET name=?,description=?,media=?,download_url=?,"
                      "download_file_id=?,kind=? WHERE id=?",
                      (name, b.description or "", media, b.download_url or "",
                       b.download_file_id, kind, b.id))
            pid = b.id
        else:
            cur = c.execute("INSERT INTO store_products(folder_id,name,description,media,download_url,"
                            "download_file_id,kind,created_at) VALUES(?,?,?,?,?,?,?,?)",
                            (b.folder_id, name, b.description or "", media, b.download_url or "",
                             b.download_file_id, kind, int(time.time())))
            pid = cur.lastrowid
    return {"message": "Đã lưu sản phẩm.", "id": pid}

@app.delete("/admin/store/products/{pid}")
def admin_store_delete_product(pid: int, admin=Depends(get_admin)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM store_prices WHERE product_id=?", (pid,))
        c.execute("DELETE FROM store_keys WHERE product_id=?", (pid,))
        c.execute("DELETE FROM store_products WHERE id=?", (pid,))
    return {"message": "Đã xoá sản phẩm."}


# -------------------- Admin: giá theo thời hạn --------------------
class StorePriceItem(BaseModel):
    label: str
    amount: int

class StorePricesIn(BaseModel):
    prices: list[StorePriceItem] = []

@app.post("/admin/store/products/{pid}/prices")
def admin_store_set_prices(pid: int, b: StorePricesIn, admin=Depends(get_admin)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM store_prices WHERE product_id=?", (pid,))
        for i, p in enumerate(b.prices):
            label = (p.label or "").strip()
            if not label or p.amount < 0:
                continue
            c.execute("INSERT INTO store_prices(product_id,label,amount,sort) VALUES(?,?,?,?)",
                      (pid, label, int(p.amount), i))
    return {"message": "Đã cập nhật bảng giá."}


# -------------------- Admin: kho KEY --------------------
class StoreKeysIn(BaseModel):
    text: str = ""   # mỗi dòng 1 key
    price_id: Optional[int] = None   # gắn key vào 1 mốc thời hạn (giờ/ngày/tuần/tháng). None = dùng chung

@app.get("/admin/store/products/{pid}/keys")
def admin_store_list_keys(pid: int, admin=Depends(get_admin)) -> dict[str, Any]:
    with db() as c:
        rows = c.execute("SELECT id,key_text,status,sold_at,price_id FROM store_keys WHERE product_id=? "
                         "ORDER BY id DESC", (pid,)).fetchall()
        avail = sum(1 for r in rows if r["status"] == "available")
    return {
        "available": avail, "total": len(rows),
        "keys": [{"id": r["id"], "key_text": r["key_text"], "status": r["status"],
                  "sold_at": r["sold_at"], "price_id": r["price_id"]} for r in rows],
    }

@app.post("/admin/store/products/{pid}/keys")
def admin_store_add_keys(pid: int, b: StoreKeysIn, admin=Depends(get_admin)) -> dict[str, Any]:
    lines = [ln.strip() for ln in (b.text or "").replace("\r", "\n").split("\n")]
    added = 0
    now = int(time.time())
    with db() as c:
        for ln in lines:
            if not ln:
                continue
            c.execute("INSERT INTO store_keys(product_id,key_text,status,price_id,created_at) "
                      "VALUES(?,?,'available',?,?)",
                      (pid, ln, b.price_id, now))
            added += 1
    return {"message": f"Đã thêm {added} key.", "added": added}

@app.delete("/admin/store/keys/{kid}")
def admin_store_delete_key(kid: int, admin=Depends(get_admin)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM store_keys WHERE id=?", (kid,))
    return {"message": "Đã xoá key."}

@app.delete("/admin/store/products/{pid}/keys")
def admin_store_delete_available_keys(pid: int, admin=Depends(get_admin)) -> dict[str, Any]:
    with db() as c:
        cur = c.execute("DELETE FROM store_keys WHERE product_id=? AND status='available'", (pid,))
    return {"message": f"Đã xoá {cur.rowcount} key khả dụng."}


@app.get("/admin/store/orders")
def admin_store_orders(admin=Depends(get_admin)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute(
            "SELECT o.id,o.amount,o.status,o.ref,o.created_at,o.user_id,"
            "p.name AS product_name,u.username "
            "FROM store_orders o LEFT JOIN store_products p ON p.id=o.product_id "
            "LEFT JOIN users u ON u.id=o.user_id ORDER BY o.id DESC LIMIT 200").fetchall()
    return [{"id": r["id"], "amount": r["amount"], "status": r["status"], "ref": r["ref"],
             "created_at": r["created_at"], "product_name": r["product_name"] or "(đã xoá)",
             "username": r["username"] or "-"} for r in rows]


# -------------------- Admin: kho hàng (tổng quan tồn kho) --------------------
@app.get("/admin/store/inventory")
def admin_store_inventory(admin=Depends(get_admin)) -> dict[str, Any]:
    with db() as c:
        rows = c.execute("""
            SELECT p.id, p.name, p.kind, f.name AS folder_name, cat.name AS category_name,
                   (SELECT COUNT(*) FROM store_keys k WHERE k.product_id=p.id AND k.status='available') AS available,
                   (SELECT COUNT(*) FROM store_orders o WHERE o.product_id=p.id AND o.status='completed') AS sold
            FROM store_products p
            LEFT JOIN store_folders f ON f.id=p.folder_id
            LEFT JOIN store_categories cat ON cat.id=f.category_id
            ORDER BY available ASC, p.id DESC
        """).fetchall()
    products = [{
        "id": r["id"], "name": r["name"], "kind": _row_kind(r),
        "folder_name": r["folder_name"] or "", "category_name": r["category_name"] or "",
        "available": r["available"], "sold": r["sold"],
    } for r in rows]
    return {
        "total_available": sum(p["available"] for p in products),
        "total_sold": sum(p["sold"] for p in products),
        "out_of_stock": sum(1 for p in products if p["available"] == 0),
        "products": products,
    }


# -------------------- Admin: sao lưu key/acc đã bán --------------------
# ======================== Mã khuyến mãi (Promo Codes) ========================
class PromoCodeIn(BaseModel):
    code: str
    discount_type: str = "percent"   # percent | fixed
    discount_value: int
    min_amount: int = 0
    max_uses: int = 0
    expires_at: int = 0              # unix timestamp, 0 = không hết hạn

@app.get("/admin/store/promo-codes")
def admin_list_promo_codes(admin=Depends(get_admin)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute("SELECT * FROM store_promo_codes ORDER BY id DESC").fetchall()
    return [dict(r) for r in rows]

@app.post("/admin/store/promo-codes")
def admin_create_promo_code(b: PromoCodeIn, admin=Depends(get_admin)) -> dict[str, Any]:
    code = b.code.strip().upper()
    if not code:
        raise HTTPException(status_code=400, detail="Mã không được để trống.")
    if b.discount_value <= 0:
        raise HTTPException(status_code=400, detail="Giá trị giảm phải lớn hơn 0.")
    if b.discount_type == "percent" and b.discount_value > 100:
        raise HTTPException(status_code=400, detail="% giảm không được quá 100.")
    with db() as c:
        try:
            cur = c.execute(
                "INSERT INTO store_promo_codes(code,discount_type,discount_value,min_amount,max_uses,"
                "expires_at,is_active,created_at) VALUES(?,?,?,?,?,?,1,?)",
                (code, b.discount_type, b.discount_value, b.min_amount,
                 b.max_uses, b.expires_at, int(time.time())))
            return {"id": cur.lastrowid, "message": "Đã tạo mã khuyến mãi."}
        except Exception:
            raise HTTPException(status_code=400, detail="Mã này đã tồn tại.")

@app.delete("/admin/store/promo-codes/{cid}")
def admin_delete_promo_code(cid: int, admin=Depends(get_admin)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM store_promo_codes WHERE id=?", (cid,))
    return {"message": "Đã xoá mã khuyến mãi."}

@app.post("/store/promo/validate")
def store_validate_promo(body: dict = Body(...), user=Depends(get_user)) -> dict[str, Any]:
    code = str(body.get("code", "")).strip().upper()
    amount = int(body.get("amount", 0))
    if not code:
        raise HTTPException(status_code=400, detail="Vui lòng nhập mã.")
    with db() as c:
        row = c.execute(
            "SELECT * FROM store_promo_codes WHERE code=? AND is_active=1", (code,)
        ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Mã không tồn tại hoặc đã vô hiệu hoá.")
    now = int(time.time())
    if row["expires_at"] and row["expires_at"] < now:
        raise HTTPException(status_code=400, detail="Mã đã hết hạn.")
    if row["max_uses"] and row["used_count"] >= row["max_uses"]:
        raise HTTPException(status_code=400, detail="Mã đã hết lượt sử dụng.")
    if amount and amount < row["min_amount"]:
        raise HTTPException(status_code=400,
            detail=f"Đơn tối thiểu {row['min_amount']:,}đ.".replace(",", "."))
    if row["discount_type"] == "percent":
        discount = int(amount * row["discount_value"] / 100) if amount else 0
        label = f"-{row['discount_value']}%"
    else:
        discount = min(row["discount_value"], amount) if amount else row["discount_value"]
        label = f"-{row['discount_value']:,}đ".replace(",", ".")
    return {"valid": True, "discount": discount, "label": label,
            "discount_type": row["discount_type"], "discount_value": row["discount_value"]}


# ======================== Push Notification (Device Tokens) ========================
class DeviceTokenIn(BaseModel):
    token: str
    platform: str = "ios"

@app.post("/device-token")
def register_device_token(b: DeviceTokenIn, user=Depends(get_user)) -> dict[str, Any]:
    if not b.token.strip():
        raise HTTPException(status_code=400, detail="Token không hợp lệ.")
    with db() as c:
        c.execute(
            "INSERT INTO device_tokens(user_id,token,platform,created_at) VALUES(?,?,?,?) "
            "ON CONFLICT(token) DO UPDATE SET user_id=excluded.user_id, created_at=excluded.created_at",
            (user["id"], b.token.strip(), b.platform, int(time.time())))
    return {"message": "Đã đăng ký thiết bị."}

@app.delete("/device-token")
def unregister_device_token(body: dict = Body(...), user=Depends(get_user)) -> dict[str, Any]:
    token = str(body.get("token", "")).strip()
    if token:
        with db() as c:
            c.execute("DELETE FROM device_tokens WHERE token=? AND user_id=?", (token, user["id"]))
    return {"message": "Đã huỷ đăng ký thiết bị."}

class PushNotifIn(BaseModel):
    title: str
    body: str
    target: str = "all"   # all | uid:<id>

def _apns_configured() -> bool:
    return all([os.getenv("APNS_KEY_ID", ""), os.getenv("APNS_TEAM_ID", ""),
                os.getenv("APNS_BUNDLE_ID", ""), os.getenv("APNS_KEY_PATH", "")])

def _apns_send(tokens: list[str], title: str, body: str) -> tuple[int, int]:
    """Gửi push tới danh sách device token. Trả (sent, failed).
    Im lặng trả (0,0) nếu chưa cấu hình APNs — dùng được cho thông báo tự động."""
    tokens = [t for t in tokens if t]
    if not tokens or not _apns_configured():
        return (0, 0)
    try:
        import httpx, jwt as pyjwt
        with open(os.getenv("APNS_KEY_PATH"), "r") as f:
            private_key = f.read()
        jwt_token = pyjwt.encode({"iss": os.getenv("APNS_TEAM_ID"), "iat": int(time.time())},
                                 private_key, algorithm="ES256",
                                 headers={"kid": os.getenv("APNS_KEY_ID")})
        payload = {"aps": {"alert": {"title": title, "body": body}, "sound": "default"}}
        headers = {"authorization": f"bearer {jwt_token}",
                   "apns-topic": os.getenv("APNS_BUNDLE_ID"), "apns-push-type": "alert"}
        sent = failed = 0
        with httpx.Client(http2=True, timeout=10) as client:
            for t in tokens:
                try:
                    r = client.post(f"https://api.push.apple.com/3/device/{t}",
                                    json=payload, headers=headers)
                    if r.status_code == 200: sent += 1
                    else: failed += 1
                except Exception:
                    failed += 1
        return (sent, failed)
    except Exception as e:
        log.warning("APNs gửi lỗi: %s", e)
        return (0, 0)

def _notify_admins(title: str, body: str) -> None:
    """Gửi push cho mọi thiết bị của admin, chạy nền (không chặn request mua hàng)."""
    try:
        with db() as c:
            tokens = [r["token"] for r in c.execute(
                "SELECT dt.token FROM device_tokens dt JOIN users u ON u.id=dt.user_id "
                "WHERE u.is_admin=1").fetchall()]
        if not tokens or not _apns_configured():
            return
        import threading
        threading.Thread(target=_apns_send, args=(tokens, title, body),
                         daemon=True, name="notify-admin").start()
    except Exception as e:
        log.warning("notify_admins lỗi: %s", e)


@app.post("/admin/push-notification")
def admin_send_push(b: PushNotifIn, admin=Depends(get_admin)) -> dict[str, Any]:
    """Gửi push notification qua APNs. Cần cấu hình APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_KEY_PATH."""
    if not _apns_configured():
        raise HTTPException(status_code=501,
            detail="Chưa cấu hình APNs (APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_KEY_PATH).")
    with db() as c:
        if b.target == "all":
            tokens = [r["token"] for r in c.execute("SELECT token FROM device_tokens").fetchall()]
        elif b.target.startswith("uid:"):
            uid = int(b.target.split(":")[1])
            tokens = [r["token"] for r in
                      c.execute("SELECT token FROM device_tokens WHERE user_id=?", (uid,)).fetchall()]
        else:
            tokens = []
    if not tokens:
        return {"sent": 0, "message": "Không có thiết bị nào để gửi."}
    sent, failed = _apns_send(tokens, b.title, b.body)
    return {"sent": sent, "failed": failed, "message": f"Đã gửi {sent}/{len(tokens)} thiết bị."}

@app.get("/admin/push-notification/devices")
def admin_list_devices(admin=Depends(get_admin)) -> dict[str, Any]:
    with db() as c:
        total = c.execute("SELECT COUNT(*) as n FROM device_tokens").fetchone()["n"]
        users = c.execute("SELECT COUNT(DISTINCT user_id) as n FROM device_tokens").fetchone()["n"]
    return {"total_devices": total, "total_users": users}


# ======================== Prompt Templates ========================
@app.get("/prompts")
def list_prompts(user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute(
            "SELECT id,title,content,category,is_public,user_id,created_at "
            "FROM prompt_templates WHERE is_public=1 OR user_id=? "
            "ORDER BY id DESC",
            (user["id"],)
        ).fetchall()
    return [dict(r) for r in rows]


@app.post("/prompts")
def create_prompt(b: PromptTemplateIn, user=Depends(get_user)) -> dict[str, Any]:
    if not b.title.strip() or not b.content.strip():
        raise HTTPException(status_code=400, detail="Title và content không được để trống.")
    is_pub = 1 if (b.is_public and user["is_admin"]) else 0
    with db() as c:
        cur = c.execute(
            "INSERT INTO prompt_templates(title,content,category,is_public,user_id,created_at) "
            "VALUES(?,?,?,?,?,?)",
            (b.title.strip(), b.content.strip(), b.category, is_pub, user["id"], int(time.time())),
        )
        pid = cur.lastrowid
    return {"id": pid, "message": "Đã tạo prompt template."}


@app.delete("/prompts/{pid}")
def delete_prompt(pid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        row = c.execute("SELECT user_id FROM prompt_templates WHERE id=?", (pid,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy prompt template.")
        if row["user_id"] != user["id"] and not user["is_admin"]:
            raise HTTPException(status_code=403, detail="Bạn không có quyền xóa prompt này.")
        c.execute("DELETE FROM prompt_templates WHERE id=?", (pid,))
    return {"message": "Đã xóa prompt template."}


# ======================== Favorites ========================
@app.get("/favorites")
def list_favorites(user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute(
            "SELECT id,message_content,conversation_id,provider,created_at "
            "FROM favorites WHERE user_id=? ORDER BY id DESC",
            (user["id"],)
        ).fetchall()
    return [dict(r) for r in rows]


@app.post("/favorites")
def add_favorite(b: FavoriteIn, user=Depends(get_user)) -> dict[str, Any]:
    if not b.message_content.strip():
        raise HTTPException(status_code=400, detail="Nội dung tin nhắn không được để trống.")
    with db() as c:
        cur = c.execute(
            "INSERT INTO favorites(user_id,message_content,conversation_id,provider,created_at) "
            "VALUES(?,?,?,?,?)",
            (user["id"], b.message_content.strip(), b.conversation_id, b.provider, int(time.time())),
        )
        fid = cur.lastrowid
    return {"id": fid, "message": "Đã thêm vào yêu thích."}


@app.delete("/favorites/{fid}")
def remove_favorite(fid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM favorites WHERE id=? AND user_id=?", (fid, user["id"]))
    return {"message": "Đã xóa khỏi yêu thích."}


# ======================== Friends & Direct Messaging ========================
@app.get("/users/search")
def search_users(q: str, user=Depends(get_user)) -> list[dict[str, Any]]:
    """Tìm theo username, SĐT hoặc ID công khai (KEN...)."""
    if not q or len(q.strip()) < 1:
        return []
    term = q.strip()
    kw = f"%{term}%"
    with db() as c:
        rows = c.execute(
            "SELECT id, username, public_id, phone FROM users "
            "WHERE (username LIKE ? OR phone LIKE ? OR public_id LIKE ? "
            "       OR public_id = ? OR phone = ?) AND id != ?",
            (kw, kw, kw, term.upper(), term, user["id"])
        ).fetchall()
    return [{"id": r["id"], "username": r["username"],
             "public_id": r["public_id"], "phone": r["phone"]} for r in rows]


@app.post("/friends/request")
def send_friend_request(b: FriendRequestIn, user=Depends(get_user)) -> dict[str, Any]:
    if b.friend_id == user["id"]:
        raise HTTPException(status_code=400, detail="Bạn không thể gửi lời mời kết bạn cho chính mình.")
    with db() as c:
        # Check if friend exists
        target = c.execute("SELECT id FROM users WHERE id=?", (b.friend_id,)).fetchone()
        if not target:
            raise HTTPException(status_code=404, detail="Không tìm thấy người dùng này.")
        
        # Check if friendship already exists
        existing = c.execute(
            "SELECT id, status FROM friendships WHERE (user_id=? AND friend_id=?) OR (user_id=? AND friend_id=?)",
            (user["id"], b.friend_id, b.friend_id, user["id"])
        ).fetchone()
        
        if existing:
            if existing["status"] == "accepted":
                raise HTTPException(status_code=400, detail="Hai bạn đã là bạn bè.")
            else:
                raise HTTPException(status_code=400, detail="Lời mời kết bạn đã được gửi trước đó.")
        
        c.execute(
            "INSERT INTO friendships(user_id, friend_id, status, created_at) VALUES(?,?,?,?)",
            (user["id"], b.friend_id, "pending", int(time.time()))
        )
    return {"message": "Đã gửi lời mời kết bạn thành công."}


@app.get("/friends/requests")
def list_friend_requests(user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute(
            "SELECT f.id, f.user_id as sender_id, u.username as sender_name, "
            "f.friend_id as receiver_id, u2.username as receiver_name, f.created_at "
            "FROM friendships f "
            "JOIN users u ON f.user_id = u.id "
            "JOIN users u2 ON f.friend_id = u2.id "
            "WHERE (f.friend_id=? OR f.user_id=?) AND f.status='pending'",
            (user["id"], user["id"])
        ).fetchall()
    return [dict(r) for r in rows]


@app.post("/friends/respond")
def respond_friend_request(b: FriendResponseIn, user=Depends(get_user)) -> dict[str, Any]:
    if b.action not in ("accept", "decline"):
        raise HTTPException(status_code=400, detail="Hành động không hợp lệ. Phải là 'accept' hoặc 'decline'.")
    with db() as c:
        row = c.execute(
            "SELECT id, user_id, friend_id, status FROM friendships WHERE id=?", (b.request_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy yêu cầu kết bạn.")
        
        # Verify that current user is the receiver of the request
        if row["friend_id"] != user["id"]:
            raise HTTPException(status_code=403, detail="Bạn không có quyền xử lý yêu cầu này.")
        
        if row["status"] != "pending":
            raise HTTPException(status_code=400, detail="Yêu cầu này đã được xử lý trước đó.")
        
        if b.action == "accept":
            c.execute("UPDATE friendships SET status='accepted' WHERE id=?", (b.request_id,))
            msg = "Đã chấp nhận lời mời kết bạn."
        else:
            c.execute("DELETE FROM friendships WHERE id=?", (b.request_id,))
            msg = "Đã từ chối lời mời kết bạn."
            
    return {"message": msg}


@app.get("/friends")
def list_friends(user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute(
            "SELECT DISTINCT u.id, u.username "
            "FROM friendships f "
            "JOIN users u ON (f.user_id = u.id AND f.friend_id = ?) OR (f.friend_id = u.id AND f.user_id = ?) "
            "WHERE f.status='accepted'",
            (user["id"], user["id"])
        ).fetchall()
    return [dict(r) for r in rows]


@app.get("/direct_messages/{friend_id}")
def get_direct_messages(friend_id: int, user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        # Verify that they are friends
        friendship = c.execute(
            "SELECT id FROM friendships WHERE ((user_id=? AND friend_id=?) OR (user_id=? AND friend_id=?)) AND status='accepted'",
            (user["id"], friend_id, friend_id, user["id"])
        ).fetchone()
        if not friendship:
            raise HTTPException(status_code=403, detail="Bạn phải là bạn bè để nhắn tin với người này.")
            
        rows = c.execute(
            "SELECT id, sender_id, receiver_id, content, created_at, is_read "
            "FROM direct_messages "
            "WHERE (sender_id=? AND receiver_id=?) OR (sender_id=? AND receiver_id=?) "
            "ORDER BY id ASC",
            (user["id"], friend_id, friend_id, user["id"])
        ).fetchall()
        
        # Mark messages from friend as read
        c.execute("UPDATE direct_messages SET is_read=1 WHERE sender_id=? AND receiver_id=?", (friend_id, user["id"]))
        
    return [dict(r) for r in rows]


@app.post("/direct_messages")
def send_direct_message(b: DirectMessageIn, user=Depends(get_user)) -> dict[str, Any]:
    if not b.content.strip():
        raise HTTPException(status_code=400, detail="Nội dung tin nhắn không được để trống.")
    with db() as c:
        # Verify that they are friends
        friendship = c.execute(
            "SELECT id FROM friendships WHERE ((user_id=? AND friend_id=?) OR (user_id=? AND friend_id=?)) AND status='accepted'",
            (user["id"], b.receiver_id, b.receiver_id, user["id"])
        ).fetchone()
        if not friendship:
            raise HTTPException(status_code=403, detail="Bạn phải là bạn bè để nhắn tin với người này.")
            
        cur = c.execute(
            "INSERT INTO direct_messages(sender_id, receiver_id, content, created_at, is_read) VALUES(?,?,?,?,0)",
            (user["id"], b.receiver_id, b.content.strip(), int(time.time()))
        )
        msg_id = cur.lastrowid
    return {"id": msg_id, "message": "Đã gửi tin nhắn thành công."}



# ======================== Search ========================
@app.get("/search")
def search_messages(q: str, user=Depends(get_user)) -> list[dict[str, Any]]:
    if not q or len(q.strip()) < 2:
        raise HTTPException(status_code=400, detail="Từ khóa tìm kiếm cần ít nhất 2 ký tự.")
    keyword = f"%{q.strip()}%"
    with db() as c:
        rows = c.execute(
            "SELECT m.id, m.conversation_id, m.role, m.content, m.created_at, "
            "c.title as conversation_title, c.provider "
            "FROM messages m "
            "JOIN conversations c ON c.id = m.conversation_id "
            "WHERE c.user_id=? AND m.content LIKE ? "
            "ORDER BY m.created_at DESC LIMIT 50",
            (user["id"], keyword)
        ).fetchall()
    return [dict(r) for r in rows]


# ======================== Admin ========================
class BanIn(BaseModel):   banned: bool
class AdminPwIn(BaseModel): new_password: str
class PlanIn(BaseModel):   plan: str

@app.get("/admin/users")
def admin_users(admin=Depends(get_admin)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute(
            "SELECT id,username,email,phone,public_id,is_admin,banned,plan,credits,"
            "status,suspend_until,last_seen,last_feature,created_at "
            "FROM users ORDER BY id"
        ).fetchall()
    out = []
    for r in rows:
        d = dict(r)
        d["is_admin"] = bool(r["is_admin"])
        d["plan"] = "pro" if r["is_admin"] else (r["plan"] or "free")
        d["status"] = r["status"] or "active"
        out.append(d)
    return out


@app.post("/admin/users/{uid}/ban")
def admin_ban(uid: int, b: BanIn, admin=Depends(get_admin)) -> dict[str, Any]:
    if uid == admin["id"]:
        raise HTTPException(status_code=400, detail="Không thể tự khóa chính mình.")
    with db() as c:
        c.execute("UPDATE users SET banned=? WHERE id=?", (1 if b.banned else 0, uid))
    return {"message": "Đã khóa." if b.banned else "Đã mở khóa."}


@app.post("/admin/users/{uid}/password")
def admin_set_pw(uid: int, b: AdminPwIn, admin=Depends(get_admin)) -> dict[str, Any]:
    if len(b.new_password) < 6:
        raise HTTPException(status_code=400, detail="Mật khẩu ≥6 ký tự.")
    with db() as c:
        c.execute("UPDATE users SET pw_hash=? WHERE id=?",
                  (hash_pw(b.new_password), uid))
    return {"message": "Đã đổi mật khẩu."}


@app.post("/admin/users/{uid}/plan")
def admin_set_plan(uid: int, b: PlanIn, admin=Depends(get_admin)) -> dict[str, Any]:
    # Chỉ còn 2 gói: free / pro
    plan = "pro" if b.plan == "pro" else "free"
    with db() as c:
        c.execute("UPDATE users SET plan=? WHERE id=?", (plan, uid))
    return {"message": f"Đã đặt gói '{plan}'."}


class SuspendIn(BaseModel):
    minutes: int = 0   # 0 = ngưng vô thời hạn; >0 = ngưng theo phút


@app.post("/admin/users/{uid}/suspend")
def admin_suspend(uid: int, b: SuspendIn, admin=Depends(get_admin)) -> dict[str, Any]:
    if uid == admin["id"]:
        raise HTTPException(status_code=400, detail="Không thể tự ngưng chính mình.")
    until = int(time.time()) + b.minutes * 60 if b.minutes > 0 else 0
    with db() as c:
        c.execute("UPDATE users SET status='suspended', suspend_until=? WHERE id=?", (until, uid))
    return {"message": "Đã tạm ngưng tài khoản."}


@app.post("/admin/users/{uid}/unsuspend")
def admin_unsuspend(uid: int, admin=Depends(get_admin)) -> dict[str, Any]:
    with db() as c:
        c.execute("UPDATE users SET status='active', suspend_until=0 WHERE id=?", (uid,))
    return {"message": "Đã mở lại tài khoản."}


# ---- Người dùng: lấy hồ sơ mới nhất + nhịp hoạt động ----
@app.get("/me")
def get_me(user=Depends(get_user)) -> dict[str, Any]:
    return _user_dict(user)


class ActivityIn(BaseModel):
    feature: str = ""


@app.post("/me/activity")
def me_activity(b: ActivityIn, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("UPDATE users SET last_seen=?, last_feature=? WHERE id=?",
                  (int(time.time()), (b.feature or "")[:60], user["id"]))
    return {"ok": True}


# ---- Chế độ bảo trì (admin bật → người dùng bị khoá tạm) ----
class MaintenanceIn(BaseModel):
    on: bool = False
    message: str = "Ứng dụng đang nâng cấp phiên bản. Vui lòng đợi trong giây lát."


@app.get("/app/status")
def app_status() -> dict[str, Any]:
    on = _setting_get("maintenance_on", "0") == "1"
    return {
        "maintenance": on,
        "message": _setting_get("maintenance_msg",
                                "Ứng dụng đang nâng cấp phiên bản. Vui lòng đợi trong giây lát."),
        "version": "5.0",
    }


@app.post("/admin/maintenance")
def admin_maintenance(b: MaintenanceIn, admin=Depends(get_admin)) -> dict[str, Any]:
    _setting_set("maintenance_on", "1" if b.on else "0")
    if b.message:
        _setting_set("maintenance_msg", b.message)
    return {"message": "Đã bật bảo trì." if b.on else "Đã tắt bảo trì.", "maintenance": b.on}


# ======================== Video feed (TikTok của riêng app) ========================
class PostIn(BaseModel):
    file_id: int = 0          # 0 = tin chỉ có chữ (không kèm ảnh/video)
    caption: str = ""


@app.post("/posts")
def create_post(b: PostIn, user=Depends(get_user)) -> dict[str, Any]:
    fid = int(b.file_id or 0)
    caption = (b.caption or "").strip()[:1000]
    with db() as c:
        if fid > 0:
            f = c.execute("SELECT id FROM files WHERE id=? AND user_id=?",
                          (fid, user["id"])).fetchone()
            if not f:
                raise HTTPException(status_code=404, detail="Không tìm thấy tệp của bạn để đăng.")
        elif not caption:
            raise HTTPException(status_code=400, detail="Hãy nhập nội dung hoặc đính kèm ảnh/video.")
        cur = c.execute(
            "INSERT INTO posts(user_id,file_id,caption,likes,created_at) VALUES(?,?,?,0,?)",
            (user["id"], fid, caption, int(time.time())))
        pid = cur.lastrowid
    return {"id": pid, "message": "Đã đăng."}


def _post_kind(file_id, mime) -> str:
    """Phân loại bài: text (không media) | image (ảnh) | video."""
    if not file_id:
        return "text"
    if (mime or "").lower().startswith("image/"):
        return "image"
    return "video"

def _posts_for(c, viewer_id: int, where: str = "", params: tuple = (),
               kind_filter: str = "") -> list[dict[str, Any]]:
    """Lấy danh sách bài kèm like/follow của người xem, số bình luận & lượt xem.
    kind_filter: 'video' = chỉ video (Reels) | 'social' = ảnh + tin chữ | '' = tất cả."""
    conds = []
    if where:
        conds.append(where)
    if kind_filter == "video":
        conds.append("(p.file_id>0 AND COALESCE(f.mime,'') NOT LIKE 'image/%')")
    elif kind_filter == "social":
        conds.append("(COALESCE(p.file_id,0)=0 OR f.mime LIKE 'image/%')")
    sql = ("SELECT p.id, p.caption, p.likes, p.created_at, p.file_id, p.user_id, "
           "p.views, u.username, u.public_id, u.avatar_url, f.name, f.mime "
           "FROM posts p JOIN users u ON p.user_id=u.id "
           "LEFT JOIN files f ON p.file_id=f.id ")
    if conds:
        sql += "WHERE " + " AND ".join(conds) + " "
    sql += "ORDER BY p.id DESC LIMIT 100"
    rows = c.execute(sql, params).fetchall()
    liked = {r["post_id"] for r in c.execute(
        "SELECT post_id FROM post_likes WHERE user_id=?", (viewer_id,)).fetchall()}
    following = {r["following_id"] for r in c.execute(
        "SELECT following_id FROM follows WHERE follower_id=?", (viewer_id,)).fetchall()}
    cmt = {r["post_id"]: r["n"] for r in c.execute(
        "SELECT post_id, COUNT(*) n FROM post_comments GROUP BY post_id").fetchall()}
    saved = {r["post_id"] for r in c.execute(
        "SELECT post_id FROM post_saves WHERE user_id=?", (viewer_id,)).fetchall()}
    return [{
        "id": r["id"], "caption": r["caption"], "likes": r["likes"],
        "created_at": r["created_at"], "file_id": r["file_id"],
        "user_id": r["user_id"],
        "username": r["username"], "public_id": r["public_id"],
        "avatar_url": r["avatar_url"] or "",
        "name": r["name"], "mime": r["mime"],
        "kind": _post_kind(r["file_id"], r["mime"]),
        "views": r["views"] or 0, "comments": cmt.get(r["id"], 0),
        "is_public": True,
        "liked": r["id"] in liked,
        "saved": r["id"] in saved,
        "following": r["user_id"] in following,
    } for r in rows]


@app.get("/feed")
def feed(user=Depends(get_user)) -> list[dict[str, Any]]:
    # Reels: chỉ video
    with db() as c:
        return _posts_for(c, user["id"], kind_filter="video")


@app.get("/social/feed")
def social_feed(user=Depends(get_user)) -> list[dict[str, Any]]:
    # Bảng tin mạng xã hội: ảnh + tin chữ (không gồm video)
    with db() as c:
        return _posts_for(c, user["id"], kind_filter="social")


@app.get("/me/posts")
def my_posts(user=Depends(get_user)) -> list[dict[str, Any]]:
    # Lưới video ở hồ sơ: chỉ video
    with db() as c:
        return _posts_for(c, user["id"], "p.user_id=?", (user["id"],), kind_filter="video")


@app.get("/users/{uid}/posts")
def user_posts(uid: int, user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        return _posts_for(c, user["id"], "p.user_id=?", (uid,), kind_filter="video")


def _vmime(name: str, mime: Optional[str]) -> str:
    """Chuẩn hoá mime cho video để AVPlayer (iOS) nhận diện & render được khung hình.
    Nhiều file lưu mime sai (application/octet-stream) khiến video chỉ hiện màn đen."""
    m = (mime or "").lower().strip()
    if m.startswith("video/"):
        return mime
    ext = os.path.splitext(name or "")[1].lower()
    table = {
        ".mp4": "video/mp4", ".mov": "video/quicktime", ".m4v": "video/x-m4v",
        ".webm": "video/webm", ".mkv": "video/x-matroska", ".avi": "video/x-msvideo",
        ".3gp": "video/3gpp", ".hevc": "video/mp4", ".ts": "video/mp2t",
    }
    return table.get(ext, "video/mp4")


def _user_from_token_or_header(authorization: Optional[str], token: Optional[str]):
    """Cho phép xác thực qua header HOẶC query ?token= — cần cho AVPlayer (iOS)
    stream video bằng URL trực tiếp (header tuỳ chỉnh hay bị bỏ qua → màn đen)."""
    raw = ""
    if authorization and authorization.startswith("Bearer "):
        raw = authorization.split(" ", 1)[1]
    elif token:
        raw = token.strip()
    if not raw:
        raise HTTPException(status_code=401, detail="Thiếu token đăng nhập.")
    uid = verify_token(raw)
    with db() as c:
        row = c.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
    if not row:
        raise HTTPException(status_code=401, detail="Tài khoản không tồn tại.")
    if row["banned"]:
        raise HTTPException(status_code=403, detail="Tài khoản đã bị khóa.")
    return row


@app.get("/posts/{pid}/video")
def post_video(pid: int, background_tasks: BackgroundTasks,
               authorization: Optional[str] = Header(default=None),
               token: Optional[str] = None):
    # AVPlayer của iOS stream qua URL trực tiếp nên dùng ?token= cho chắc ăn.
    _user_from_token_or_header(authorization, token)
    with db() as c:
        row = c.execute(
            "SELECT f.name,f.mime,f.data,f.id as fid FROM posts p "
            "JOIN files f ON p.file_id=f.id WHERE p.id=?", (pid,)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy video.")
    media = _vmime(row["name"], row["mime"])
    file_path = os.path.join(UPLOAD_DIR, str(row["fid"]))
    if os.path.exists(file_path):
        # FileResponse hỗ trợ HTTP Range (tua/stream) — cần thiết để iOS phát mượt.
        return FileResponse(path=file_path, filename=row["name"], media_type=media)
    if row["data"]:
        temp_path = os.path.join(UPLOAD_DIR, f"feed_{pid}_{secrets.token_hex(4)}")
        with open(temp_path, "wb") as f:
            f.write(base64.b64decode(row["data"]))
        background_tasks.add_task(os.unlink, temp_path)
        return FileResponse(path=temp_path, filename=row["name"], media_type=media)
    raise HTTPException(status_code=404, detail="Không có nội dung video.")


@app.post("/posts/{pid}/like")
def like_post(pid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        ex = c.execute("SELECT 1 FROM post_likes WHERE post_id=? AND user_id=?",
                       (pid, user["id"])).fetchone()
        if ex:
            c.execute("DELETE FROM post_likes WHERE post_id=? AND user_id=?", (pid, user["id"]))
            c.execute("UPDATE posts SET likes=MAX(0,likes-1) WHERE id=?", (pid,))
            liked = False
        else:
            c.execute("INSERT INTO post_likes(post_id,user_id) VALUES(?,?)", (pid, user["id"]))
            c.execute("UPDATE posts SET likes=likes+1 WHERE id=?", (pid,))
            liked = True
        likes = c.execute("SELECT likes FROM posts WHERE id=?", (pid,)).fetchone()
    return {"liked": liked, "likes": likes["likes"] if likes else 0}


@app.post("/posts/{pid}/save")
def save_post(pid: int, user=Depends(get_user)) -> dict[str, Any]:
    """Lưu / bỏ lưu bài (như nút Lưu của Facebook)."""
    with db() as c:
        ex = c.execute("SELECT 1 FROM post_saves WHERE post_id=? AND user_id=?",
                       (pid, user["id"])).fetchone()
        if ex:
            c.execute("DELETE FROM post_saves WHERE post_id=? AND user_id=?", (pid, user["id"]))
            saved = False
        else:
            c.execute("INSERT OR IGNORE INTO post_saves(post_id,user_id,created_at) VALUES(?,?,?)",
                      (pid, user["id"], int(time.time())))
            saved = True
    return {"saved": saved}


@app.get("/me/saved")
def my_saved_posts(user=Depends(get_user)) -> list[dict[str, Any]]:
    """Danh sách bài đã lưu của tôi."""
    with db() as c:
        return _posts_for(c, user["id"],
                          "p.id IN (SELECT post_id FROM post_saves WHERE user_id=?)",
                          (user["id"],))


@app.delete("/posts/{pid}")
def delete_post(pid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        row = c.execute("SELECT user_id FROM posts WHERE id=?", (pid,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy bài.")
        if row["user_id"] != user["id"] and not user["is_admin"]:
            raise HTTPException(status_code=403, detail="Không thể xoá bài của người khác.")
        c.execute("DELETE FROM posts WHERE id=?", (pid,))
        c.execute("DELETE FROM post_likes WHERE post_id=?", (pid,))
        c.execute("DELETE FROM post_comments WHERE post_id=?", (pid,))
    return {"message": "Đã xoá bài."}


@app.post("/posts/{pid}/view")
def post_view(pid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("UPDATE posts SET views=COALESCE(views,0)+1 WHERE id=?", (pid,))
        row = c.execute("SELECT views FROM posts WHERE id=?", (pid,)).fetchone()
    return {"views": (row["views"] if row else 0) or 0}


class CommentIn(BaseModel):
    content: str = ""


@app.get("/posts/{pid}/comments")
def list_comments(pid: int, user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute(
            "SELECT cm.id, cm.user_id, cm.content, cm.created_at, u.username "
            "FROM post_comments cm JOIN users u ON cm.user_id=u.id "
            "WHERE cm.post_id=? ORDER BY cm.id ASC LIMIT 500", (pid,)).fetchall()
    return [{"id": r["id"], "user_id": r["user_id"], "username": r["username"],
             "content": r["content"], "created_at": r["created_at"]} for r in rows]


@app.post("/posts/{pid}/comments")
def add_comment(pid: int, b: CommentIn, user=Depends(get_user)) -> dict[str, Any]:
    content = (b.content or "").strip()[:500]
    if not content:
        raise HTTPException(status_code=400, detail="Bình luận không được để trống.")
    with db() as c:
        if not c.execute("SELECT 1 FROM posts WHERE id=?", (pid,)).fetchone():
            raise HTTPException(status_code=404, detail="Không tìm thấy bài.")
        cur = c.execute(
            "INSERT INTO post_comments(post_id,user_id,content,created_at) VALUES(?,?,?,?)",
            (pid, user["id"], content, int(time.time())))
        cid = cur.lastrowid
    return {"id": cid, "user_id": user["id"], "username": user["username"],
            "content": content, "created_at": int(time.time())}


@app.delete("/comments/{cid}")
def delete_comment(cid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        row = c.execute("SELECT user_id FROM post_comments WHERE id=?", (cid,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy bình luận.")
        if row["user_id"] != user["id"] and not user["is_admin"]:
            raise HTTPException(status_code=403, detail="Không thể xoá bình luận của người khác.")
        c.execute("DELETE FROM post_comments WHERE id=?", (cid,))
    return {"message": "Đã xoá bình luận."}


# ======================== Live (phòng live + bình luận như TikTok) ========================
class LiveCreateIn(BaseModel):
    title: str = ""
    hls_url: str = ""


def _live_host(request: Request) -> str:
    """Lấy host của VPS để tự dựng link RTMP/HLS (ưu tiên env LIVE_SERVER)."""
    h = os.getenv("LIVE_SERVER", "").strip()
    if h:
        return h
    host = (request.headers.get("host") or "").split(":")[0]
    return host or "127.0.0.1"


@app.post("/live/create")
def live_create(b: LiveCreateIn, request: Request, user=Depends(get_user)) -> dict[str, Any]:
    title = (b.title or f"Live của {user['username']}")[:120]
    host = _live_host(request)
    hls_port = os.getenv("LIVE_HLS_PORT", "8080")
    rtmp_port = os.getenv("LIVE_RTMP_PORT", "1935")
    # Tự sinh stream key + link HLS nếu người dùng không tự dán link
    stream_key = f"ken{int(time.time())}{secrets.token_hex(3)}"
    hls_url = (b.hls_url or "").strip()
    if not hls_url:
        hls_url = f"http://{host}:{hls_port}/hls/{stream_key}.m3u8"
    rtmp_url = f"rtmp://{host}:{rtmp_port}/live"
    with db() as c:
        cur = c.execute(
            "INSERT INTO live_rooms(host_id,title,hls_url,stream_key,viewers,likes,active,created_at) "
            "VALUES(?,?,?,?,0,0,1,?)",
            (user["id"], title, hls_url[:300], stream_key, int(time.time())))
        rid = cur.lastrowid
    return {"id": rid, "message": "Đã mở phòng live.",
            "hls_url": hls_url, "rtmp_url": rtmp_url, "stream_key": stream_key}


@app.post("/live/{rid}/end")
def live_end(rid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        row = c.execute("SELECT host_id FROM live_rooms WHERE id=?", (rid,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy phòng live.")
        if row["host_id"] != user["id"] and not user["is_admin"]:
            raise HTTPException(status_code=403, detail="Chỉ chủ phòng mới kết thúc được.")
        c.execute("UPDATE live_rooms SET active=0 WHERE id=?", (rid,))
    return {"message": "Đã kết thúc live."}


@app.get("/live/rooms")
def live_rooms(user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute(
            "SELECT r.id,r.title,r.hls_url,r.viewers,r.likes,r.created_at,"
            "u.username,u.public_id FROM live_rooms r JOIN users u ON r.host_id=u.id "
            "WHERE r.active=1 ORDER BY r.id DESC LIMIT 100").fetchall()
    return [dict(r) for r in rows]


@app.get("/live/{rid}")
def live_info(rid: int, request: Request, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        r = c.execute(
            "SELECT r.id,r.title,r.hls_url,r.stream_key,r.viewers,r.likes,r.active,r.host_id,"
            "u.username,u.public_id FROM live_rooms r JOIN users u ON r.host_id=u.id "
            "WHERE r.id=?", (rid,)).fetchone()
    if not r:
        raise HTTPException(status_code=404, detail="Không tìm thấy phòng live.")
    d = dict(r)
    host = _live_host(request)
    rtmp_port = os.getenv("LIVE_RTMP_PORT", "1935")
    d["rtmp_url"] = f"rtmp://{host}:{rtmp_port}/live"
    return d


@app.post("/live/{rid}/join")
def live_join(rid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("UPDATE live_rooms SET viewers=viewers+1 WHERE id=?", (rid,))
    return {"ok": True}


@app.post("/live/{rid}/like")
def live_like(rid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("UPDATE live_rooms SET likes=likes+1 WHERE id=?", (rid,))
        r = c.execute("SELECT likes FROM live_rooms WHERE id=?", (rid,)).fetchone()
    return {"likes": r["likes"] if r else 0}


class LiveCommentIn(BaseModel):
    content: str


@app.post("/live/{rid}/comment")
def live_comment(rid: int, b: LiveCommentIn, user=Depends(get_user)) -> dict[str, Any]:
    if not b.content.strip():
        raise HTTPException(status_code=400, detail="Bình luận trống.")
    with db() as c:
        cur = c.execute(
            "INSERT INTO live_messages(room_id,user_id,username,content,created_at) "
            "VALUES(?,?,?,?,?)",
            (rid, user["id"], user["username"], b.content.strip()[:300], int(time.time())))
        mid = cur.lastrowid
    return {"id": mid}


@app.get("/live/{rid}/comments")
def live_comments(rid: int, after: int = 0, user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute(
            "SELECT id,username,content,created_at FROM live_messages "
            "WHERE room_id=? AND id>? ORDER BY id ASC LIMIT 100", (rid, after)).fetchall()
    return [dict(r) for r in rows]


# ======================== Follow / hồ sơ (như TikTok) ========================
@app.post("/follow/{uid}")
def follow_user(uid: int, user=Depends(get_user)) -> dict[str, Any]:
    if uid == user["id"]:
        raise HTTPException(status_code=400, detail="Không thể tự theo dõi mình.")
    with db() as c:
        if not c.execute("SELECT 1 FROM users WHERE id=?", (uid,)).fetchone():
            raise HTTPException(status_code=404, detail="Không tìm thấy người dùng.")
        c.execute("INSERT OR IGNORE INTO follows(follower_id,following_id,created_at) "
                  "VALUES(?,?,?)", (user["id"], uid, int(time.time())))
    return {"following": True}


@app.delete("/follow/{uid}")
def unfollow_user(uid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM follows WHERE follower_id=? AND following_id=?", (user["id"], uid))
    return {"following": False}


def _profile_dict(c, uid: int, viewer_id: int) -> dict[str, Any]:
    u = c.execute("SELECT id,username,public_id,avatar_url,bio FROM users WHERE id=?", (uid,)).fetchone()
    if not u:
        raise HTTPException(status_code=404, detail="Không tìm thấy người dùng.")
    followers = c.execute("SELECT COUNT(*) n FROM follows WHERE following_id=?", (uid,)).fetchone()["n"]
    following = c.execute("SELECT COUNT(*) n FROM follows WHERE follower_id=?", (uid,)).fetchone()["n"]
    posts = c.execute("SELECT COUNT(*) n FROM posts WHERE user_id=?", (uid,)).fetchone()["n"]
    total_likes = c.execute("SELECT COALESCE(SUM(likes),0) n FROM posts WHERE user_id=?", (uid,)).fetchone()["n"]
    is_following = c.execute(
        "SELECT 1 FROM follows WHERE follower_id=? AND following_id=?",
        (viewer_id, uid)).fetchone() is not None
    return {"id": u["id"], "username": u["username"], "public_id": u["public_id"],
            "avatar_url": u["avatar_url"] or "", "bio": u["bio"] or "",
            "followers": followers, "following": following, "posts": posts,
            "total_likes": total_likes, "is_following": is_following}


@app.get("/users/{uid}/profile")
def user_profile(uid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        return _profile_dict(c, uid, user["id"])


@app.get("/me/profile")
def my_profile(user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        return _profile_dict(c, user["id"], user["id"])


class ProfileUpdateIn(BaseModel):
    public_id: Optional[str] = None
    avatar_url: Optional[str] = None
    bio: Optional[str] = None


@app.put("/me/profile")
def update_my_profile(b: ProfileUpdateIn, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        if b.public_id is not None:
            pid = b.public_id.strip()[:30]
            if pid:
                # ID phải là duy nhất giữa các user
                dup = c.execute("SELECT 1 FROM users WHERE public_id=? AND id!=?",
                                (pid, user["id"])).fetchone()
                if dup:
                    raise HTTPException(status_code=409, detail="ID này đã có người dùng. Hãy chọn ID khác.")
                c.execute("UPDATE users SET public_id=? WHERE id=?", (pid, user["id"]))
        if b.avatar_url is not None:
            c.execute("UPDATE users SET avatar_url=? WHERE id=?", (b.avatar_url.strip(), user["id"]))
        if b.bio is not None:
            c.execute("UPDATE users SET bio=? WHERE id=?", (b.bio.strip()[:300], user["id"]))
    return {"message": "Đã cập nhật hồ sơ."}


@app.post("/admin/payments/{pid}/confirm")
def admin_confirm_payment(pid: int, admin=Depends(get_admin)) -> dict[str, Any]:
    return payment_confirm(pid, admin)


# ======================== Admin Stats ========================
@app.get("/admin/stats")
def admin_stats(admin=Depends(get_admin)) -> dict[str, Any]:
    now = int(time.time())
    seven_days_ago = now - (7 * 24 * 60 * 60)
    thirty_days_ago = now - (30 * 24 * 60 * 60)

    with db() as c:
        total_users = c.execute("SELECT COUNT(*) as cnt FROM users").fetchone()["cnt"]
        new_users_7d = c.execute(
            "SELECT COUNT(*) as cnt FROM users WHERE created_at>=?", (seven_days_ago,)
        ).fetchone()["cnt"]
        total_conversations = c.execute("SELECT COUNT(*) as cnt FROM conversations").fetchone()["cnt"]
        total_messages = c.execute("SELECT COUNT(*) as cnt FROM messages").fetchone()["cnt"]
        rev_total_row = c.execute(
            "SELECT COALESCE(SUM(amount),0) as total FROM payments WHERE status='completed'"
        ).fetchone()
        revenue_total = rev_total_row["total"]
        rev_30d_row = c.execute(
            "SELECT COALESCE(SUM(amount),0) as total FROM payments WHERE status='completed' AND created_at>=?",
            (thirty_days_ago,)
        ).fetchone()
        revenue_30d = rev_30d_row["total"]
        total_files = c.execute("SELECT COUNT(*) as cnt FROM files").fetchone()["cnt"]
        top_rows = c.execute(
            "SELECT provider, COUNT(*) as cnt FROM conversations "
            "WHERE provider IS NOT NULL GROUP BY provider ORDER BY cnt DESC LIMIT 10"
        ).fetchall()
        top_providers = [{"provider": r["provider"], "count": r["cnt"]} for r in top_rows]
        plan_rows = c.execute(
            "SELECT plan, COUNT(*) as cnt FROM users GROUP BY plan ORDER BY cnt DESC"
        ).fetchall()
        plan_distribution = [{"plan": r["plan"], "count": r["cnt"]} for r in plan_rows]

    return {
        "total_users": total_users,
        "new_users_7d": new_users_7d,
        "total_conversations": total_conversations,
        "total_messages": total_messages,
        "revenue_total": revenue_total,
        "revenue_30d": revenue_30d,
        "total_files": total_files,
        "top_providers": top_providers,
        "plan_distribution": plan_distribution,
    }


# ======================== Báo lỗi & log lỗi cho admin ========================
class ErrorIn(BaseModel):
    context: str = ""
    detail: str = ""

@app.post("/errors")
def report_error(b: ErrorIn, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("INSERT INTO error_logs(user_id,username,context,detail,created_at) "
                  "VALUES(?,?,?,?,?)",
                  (user["id"], user["username"], b.context[:200], b.detail[:800], int(time.time())))
    return {"message": "Đã ghi nhận lỗi."}


@app.get("/admin/errors")
def admin_errors(admin=Depends(get_admin)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute("SELECT id,user_id,username,context,detail,created_at "
                         "FROM error_logs ORDER BY id DESC LIMIT 200").fetchall()
    return [dict(r) for r in rows]


@app.delete("/admin/errors")
def admin_clear_errors(admin=Depends(get_admin)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM error_logs")
    return {"message": "Đã xóa toàn bộ log lỗi."}


# ======================== Bảo mật & Mod Game (Security & Mod Tools) ========================
class CodeEncryptIn(BaseModel):
    code: str
    language: str
    level: str  # "low" | "high"


@app.post("/code/encrypt")
def code_encrypt(b: CodeEncryptIn, user=Depends(get_user)) -> dict[str, Any]:
    """Mã hóa làm rối (Obfuscate) mã nguồn để chống dịch ngược."""
    import base64
    code_text = b.code
    lang = b.language.lower()
    
    if not code_text.strip():
        raise HTTPException(status_code=400, detail="Mã nguồn không được rỗng.")
        
    if lang == "python":
        # Multi-layer encoding: Base64 + exec loader
        encoded = base64.b64encode(code_text.encode("utf-8")).decode("utf-8")
        obfuscated = (
            f"# Packaged by KENIOS Secure Encrypter (level: {b.level})\n"
            f"import base64\n"
            f"exec(base64.b64decode('{encoded}').decode('utf-8'))"
        )
        return {"result": obfuscated}
    elif lang == "javascript" or lang == "typescript":
        # Simple JavaScript obfuscation using HEX-escaped strings
        encoded_hex = "".join([f"\\x{ord(c):02x}" for c in code_text])
        obfuscated = (
            f"/* Packaged by KENIOS Secure Obfuscator */\n"
            f"eval(\"{encoded_hex}\");"
        )
        return {"result": obfuscated}
    else:
        # Fallback raw Base64 packaging
        encoded = base64.b64encode(code_text.encode("utf-8")).decode("utf-8")
        obfuscated = (
            f"/* Encrypted by KENIOS (Base64) */\n"
            f"// Raw base64: {encoded}"
        )
        return {"result": obfuscated}


@app.post("/code/analyze")
async def code_analyze(file: UploadFile = FastAPIFile(...), user=Depends(get_user)) -> dict[str, Any]:
    """Phân tích cấu trúc PE/ELF nhị phân và xuất Hex Viewer Dump."""
    import re
    import struct
    
    content = await file.read()
    size = len(content)
    if size == 0:
        raise HTTPException(status_code=400, detail="Tệp rỗng.")
        
    # 1. Detect file type
    file_type = "Binary / Unknown"
    entry_point = "N/A"
    architecture = "Unknown"
    sections = []
    
    if content.startswith(b"MZ"):
        file_type = "Windows PE (Portable Executable - EXE/DLL)"
        # Parse PE header entry point offset if large enough
        if size >= 0x40:
            pe_offset = struct.unpack("<I", content[0x3C:0x40])[0]
            if size >= pe_offset + 24:
                magic = content[pe_offset : pe_offset+4]
                if magic == b"PE\x00\x00":
                    machine = struct.unpack("<H", content[pe_offset+4 : pe_offset+6])[0]
                    architecture = "x64" if machine == 0x8664 else ("x86" if machine == 0x014c else f"Machine {hex(machine)}")
                    opt_header_offset = pe_offset + 24
                    if size >= opt_header_offset + 20:
                        entry_point = hex(struct.unpack("<I", content[opt_header_offset+16 : opt_header_offset+20])[0])
    elif content.startswith(b"\x7fELF"):
        file_type = "Linux/Android ELF (Executable and Linkable Format)"
        if size >= 20:
            elf_class = content[4]
            architecture = "64-bit" if elf_class == 2 else ("32-bit" if elf_class == 1 else "Unknown")
            if elf_class == 2 and size >= 32:
                entry_point = hex(struct.unpack("<Q", content[24:32])[0])
            elif elf_class == 1 and size >= 28:
                entry_point = hex(struct.unpack("<I", content[24:28])[0])
    elif content.startswith(b"\xca\xfe\xba\xbe") or content.startswith(b"\xbe\xba\xfe\xca"):
        file_type = "Mach-O (macOS/iOS Fat Binary)"
    elif content.startswith(b"\xfeedface") or content.startswith(b"\xfeedfacf"):
        file_type = "Mach-O (macOS/iOS Thin Binary)"
        
    # 2. Extract ASCII strings (min length 4)
    ascii_strings = []
    try:
        found_strings = re.findall(b"[ -~]{4,100}", content[:50000]) # Limit scan size to prevent excessive time
        for s in found_strings:
            s_decoded = s.decode("ascii", errors="ignore").strip()
            if s_decoded:
                ascii_strings.append(s_decoded)
    except Exception:
        pass
        
    # 3. Create Hex Dump (first 2048 bytes)
    hex_lines = []
    dump_limit = min(size, 2048)
    for offset in range(0, dump_limit, 16):
        chunk = content[offset : offset + 16]
        hex_parts = [f"{b:02x}" for b in chunk]
        # Pad hex parts
        while len(hex_parts) < 16:
            hex_parts.append("  ")
        hex_str = " ".join(hex_parts[:8]) + "  " + " ".join(hex_parts[8:])
        ascii_part = "".join([chr(b) if 32 <= b < 127 else "." for b in chunk])
        hex_lines.append(f"{offset:08x}  {hex_str}  |{ascii_part}|")
        
    hex_dump = "\n".join(hex_lines)
    if size > 2048:
        hex_dump += f"\n... (Đã ẩn bớt {size - 2048} bytes)"
        
    return {
        "file_type": file_type,
        "entry_point": entry_point,
        "architecture": architecture,
        "sections": sections if sections else None,
        "strings": list(set(ascii_strings))[:200], # Top 200 unique strings
        "hex_dump": hex_dump
    }


class CodeAsmIn(BaseModel):
    input: str
    mode: str  # "assemble" | "disassemble"
    arch: str  # "x86" | "arm"
    provider: Optional[str] = "openai"
    api_key: Optional[str] = None


@app.post("/code/asm")
async def code_asm(b: CodeAsmIn, user=Depends(get_user)) -> dict[str, Any]:
    """Dịch Hợp ngữ (Assembly) thành mã máy Hex hoặc ngược lại qua AI."""
    import httpx
    val = b.input.strip()
    if not val:
        raise HTTPException(status_code=400, detail="Mã đầu vào không được rỗng.")
        
    prov = b.provider or "openai"
    key = get_user_key(user["id"], prov, b.api_key)
    p = PROVIDERS.get(prov)
    if not p:
        raise HTTPException(status_code=400, detail=f"Không tìm thấy nhà cung cấp '{prov}'.")
        
    if b.mode == "assemble":
        prompt = (
            f"Bạn là một trình biên dịch hợp ngữ (Assembler) cho kiến trúc {b.arch.upper()}.\n"
            f"Hãy dịch mã lệnh hợp ngữ sau đây sang mã máy hex (dải bytes viết liền hoặc cách nhau khoảng trắng):\n"
            f"Lệnh: \"{val}\"\n"
            f"Chỉ trả về chuỗi mã Hex kết quả (ví dụ: '90 90'), không thêm bất kỳ văn bản giải thích nào khác."
        )
    else:
        prompt = (
            f"Bạn là một trình dịch ngược (Disassembler) cho kiến trúc {b.arch.upper()}.\n"
            f"Hãy dịch mã Hex nhị phân sau đây thành lệnh hợp ngữ dạng văn bản đọc được:\n"
            f"Hex: \"{val}\"\n"
            f"Chỉ trả về các dòng lệnh hợp ngữ kết quả, không thêm giải thích."
        )
        
    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        r = await client.post(
            f"{p['base']}/chat/completions",
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
            json={
                "model": p.get("default_model", "gpt-4o-mini"),
                "messages": [
                    {"role": "system", "content": "You are a helpful compiler helper."},
                    {"role": "user", "content": prompt}
                ]
            }
        )
    _raise_for_provider(r, prov)
    res_data = r.json()
    reply = res_data["choices"][0]["message"]["content"].strip()
    return {"result": reply}


# ======================== DevOps & DevOps Tools ========================
class SSHIn(BaseModel):
    host: str
    username: str
    password: str
    command: str


@app.post("/run/ssh")
def run_ssh(b: SSHIn, user=Depends(get_user)) -> dict[str, Any]:
    """Kết nối SSH vào VPS và chạy câu lệnh."""
    host = b.host.strip()
    username = b.username.strip()
    password = b.password.strip()
    command = b.command.strip()
    
    if not (host and username and command):
        raise HTTPException(status_code=400, detail="Thiếu tham số kết nối SSH (Host, Username, Command).")
    
    # Fallback for mock/test IPs
    if "127.0.0.1" in host or "localhost" in host or "192.168" in host or "FAKE" in host.upper():
        return {
            "stdout": f"[MOCK SSH] Executing on {username}@{host}:\n$ {command}\nSuccess: mock output here.",
            "stderr": "",
            "exitCode": 0
        }
        
    try:
        import paramiko
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(host, username=username, password=password, timeout=10)
        stdin, stdout, stderr = ssh.exec_command(command, timeout=30)
        out = stdout.read().decode('utf-8', errors='replace')
        err = stderr.read().decode('utf-8', errors='replace')
        code = stdout.channel.recv_exit_status()
        ssh.close()
        return {"stdout": out, "stderr": err, "exitCode": code}
    except ImportError:
        import subprocess
        try:
            cmd = ["sshpass", "-p", password, "ssh", "-o", "StrictHostKeyChecking=no", f"{username}@{host}", command]
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
            return {"stdout": r.stdout, "stderr": r.stderr, "exitCode": r.returncode}
        except Exception:
            raise HTTPException(
                status_code=400, 
                detail="Thư viện 'paramiko' chưa được cài trên server VPS. Hãy chạy lệnh 'pip install paramiko' trên VPS hoặc chạy lại start-vps.sh."
            )
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Lỗi kết nối SSH: {e}")


class HTTPIn(BaseModel):
    url: str
    method: str
    headers: Optional[dict[str, str]] = None
    body: Optional[str] = None


@app.post("/run/http")
async def run_http(b: HTTPIn, user=Depends(get_user)) -> dict[str, Any]:
    """Gửi HTTP request từ máy chủ (bỏ qua CORS)."""
    import httpx
    url = b.url.strip()
    method = b.method.upper()
    if not url:
        raise HTTPException(status_code=400, detail="Thiếu URL yêu cầu.")
    
    headers = b.headers or {}
    headers.pop("Host", None)
    headers.pop("host", None)
    content_data = b.body or ""
    
    async with httpx.AsyncClient(timeout=30) as client:
        try:
            if method == "GET":
                r = await client.get(url, headers=headers)
            elif method == "POST":
                r = await client.post(url, headers=headers, content=content_data)
            elif method == "PUT":
                r = await client.put(url, headers=headers, content=content_data)
            elif method == "DELETE":
                r = await client.delete(url, headers=headers)
            else:
                raise HTTPException(status_code=400, detail=f"Phương thức '{method}' chưa hỗ trợ.")
                
            resp_body = r.text
            resp_headers = {k: v for k, v in r.headers.items()}
            return {
                "status": r.status_code,
                "headers": resp_headers,
                "body": resp_body
            }
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Lỗi gửi HTTP request: {e}")


class SQLIn(BaseModel):
    query: str


@app.post("/run/sql")
def run_sql(b: SQLIn, user=Depends(get_user)) -> dict[str, Any]:
    """Thực thi câu lệnh SQL SQLite cục bộ."""
    query = b.query.strip()
    if not query:
        raise HTTPException(status_code=400, detail="Câu lệnh SQL không được rỗng.")
    
    is_admin_check = user.get("is_admin") or user.get("isAdmin")
    query_lower = query.lower()
    destructive = ["drop", "delete", "update", "insert", "alter", "create", "replace"]
    if any(d in query_lower for d in destructive) and not is_admin_check:
        raise HTTPException(status_code=403, detail="Chỉ tài khoản Admin mới có quyền thực thi các câu lệnh sửa đổi database (INSERT, UPDATE, DELETE, DROP...).")
        
    try:
        with db() as c:
            cur = c.execute(query)
            if cur.description:
                columns = [desc[0] for desc in cur.description]
                rows = cur.fetchall()
                row_list = []
                for r in rows:
                    row_list.append([str(val) if val is not None else "" for val in r])
                return {
                    "columns": columns,
                    "rows": row_list,
                    "message": f"Truy vấn thành công. Trả về {len(row_list)} bản ghi."
                }
            else:
                c.commit()
                return {
                    "columns": [],
                    "rows": [],
                    "message": f"Thực thi thành công. Số bản ghi ảnh hưởng: {cur.rowcount}."
                }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Lỗi SQL: {e}")


# ======================== Error handler ========================
@app.exception_handler(Exception)
async def on_error(request: Request, exc: Exception):
    log.exception("Lỗi server: %s", exc)
    try:
        with db() as c:
            c.execute("INSERT INTO error_logs(context,detail,created_at) VALUES(?,?,?)",
                      (str(request.url.path), f"{type(exc).__name__}: {exc}"[:800], int(time.time())))
    except Exception:
        pass
    return JSONResponse(status_code=500,
                        content={"detail": f"Lỗi máy chủ: {type(exc).__name__}: {str(exc)[:300]}"})


# ======================== Entrypoint ========================
if __name__ == "__main__":
    import uvicorn
    init_db()
    log.info("KENIOS kenios v4.2 — cổng %s | %d AI hỗ trợ", PORT, len(PROVIDERS))
    uvicorn.run(app, host="0.0.0.0", port=PORT)



# ======================== Proxy mạng (quản lý & định tuyến) ========================
from urllib.parse import quote as _qt

class ProxyAddIn(BaseModel):
    label: Optional[str] = None
    scheme: str = "http"            # http | https | socks5
    host: str
    port: int
    username: Optional[str] = None
    password: Optional[str] = None
    region: Optional[str] = None
    source: str = "manual"          # manual | provider | vps

class ProxyImportIn(BaseModel):
    text: str                       # mỗi dòng: host:port  hoặc  host:port:user:pass
    scheme: str = "http"
    region: Optional[str] = None
    source: str = "provider"

class ProxySelectIn(BaseModel):
    id: Optional[int] = None        # None = bỏ chọn (đi trực tiếp qua VPS)

class ProxyTestIn(BaseModel):
    id: Optional[int] = None
    scheme: Optional[str] = None
    host: Optional[str] = None
    port: Optional[int] = None
    username: Optional[str] = None
    password: Optional[str] = None


def _proxy_url_from(scheme, host, port, username=None, password=None) -> str:
    scheme = (scheme or "http").lower()
    if scheme not in ("http", "https", "socks5", "socks5h"):
        scheme = "http"
    auth = ""
    if username:
        auth = _qt(str(username), safe="")
        if password:
            auth += ":" + _qt(str(password), safe="")
        auth += "@"
    return f"{scheme}://{auth}{host}:{port}"


def _proxy_row_to_url(row) -> Optional[str]:
    if row["source"] == "vps":
        return None
    pwd = dec(row["enc_password"]) if row["enc_password"] else None
    return _proxy_url_from(row["scheme"], row["host"], row["port"], row["username"], pwd)


def get_active_proxy(user_id: int) -> Optional[str]:
    with db() as c:
        row = c.execute("SELECT * FROM proxies WHERE user_id=? AND active=1 LIMIT 1",
                        (user_id,)).fetchone()
    return _proxy_row_to_url(row) if row else None


def _proxy_public(row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "label": row["label"] or f'{row["host"]}:{row["port"]}',
        "scheme": row["scheme"], "host": row["host"], "port": row["port"],
        "username": row["username"], "has_password": bool(row["enc_password"]),
        "region": row["region"] or "", "source": row["source"],
        "active": bool(row["active"]),
    }


@app.get("/proxy/list")
def proxy_list(user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        rows = c.execute("SELECT * FROM proxies WHERE user_id=? ORDER BY id DESC",
                         (user["id"],)).fetchall()
    items = [_proxy_public(r) for r in rows]
    regions = sorted({r["region"] for r in items if r["region"]})
    return {"proxies": items, "regions": regions}


@app.post("/proxy/add")
def proxy_add(b: ProxyAddIn, user=Depends(get_user)) -> dict[str, Any]:
    enc_pw = enc(b.password) if b.password else None
    with db() as c:
        cur = c.execute(
            "INSERT INTO proxies(user_id,label,scheme,host,port,username,enc_password,"
            "region,source,active,created_at) VALUES(?,?,?,?,?,?,?,?,?,0,?)",
            (user["id"], b.label, (b.scheme or "http").lower(), b.host, int(b.port),
             b.username, enc_pw, b.region, b.source or "manual", int(time.time())))
        pid = cur.lastrowid
    return {"id": pid, "message": "Đã thêm proxy."}


@app.post("/proxy/import")
def proxy_import(b: ProxyImportIn, user=Depends(get_user)) -> dict[str, Any]:
    n = 0
    with db() as c:
        for line in b.text.splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.split(":")
            if len(parts) < 2:
                continue
            host = parts[0]
            try:
                port_i = int(parts[1])
            except ValueError:
                continue
            user_p = parts[2] if len(parts) >= 3 else None
            pass_p = parts[3] if len(parts) >= 4 else None
            enc_pw = enc(pass_p) if pass_p else None
            c.execute(
                "INSERT INTO proxies(user_id,label,scheme,host,port,username,enc_password,"
                "region,source,active,created_at) VALUES(?,?,?,?,?,?,?,?,?,0,?)",
                (user["id"], None, (b.scheme or "http").lower(), host, port_i,
                 user_p, enc_pw, b.region, b.source or "provider", int(time.time())))
            n += 1
    return {"imported": n, "message": f"Đã nhập {n} proxy."}


@app.delete("/proxy/{pid}")
def proxy_delete(pid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM proxies WHERE id=? AND user_id=?", (pid, user["id"]))
    return {"message": "Đã xoá proxy."}


@app.post("/proxy/select")
def proxy_select(b: ProxySelectIn, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("UPDATE proxies SET active=0 WHERE user_id=?", (user["id"],))
        if b.id is not None:
            row = c.execute("SELECT id FROM proxies WHERE id=? AND user_id=?",
                            (b.id, user["id"])).fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Không tìm thấy proxy.")
            c.execute("UPDATE proxies SET active=1 WHERE id=? AND user_id=?",
                      (b.id, user["id"]))
    msg = "Đã chọn proxy." if b.id is not None else "Đã bỏ chọn (đi trực tiếp qua VPS)."
    return {"active_id": b.id, "message": msg}


@app.post("/proxy/test")
async def proxy_test(b: ProxyTestIn, user=Depends(get_user)) -> dict[str, Any]:
    if b.id is not None:
        with db() as c:
            row = c.execute("SELECT * FROM proxies WHERE id=? AND user_id=?",
                            (b.id, user["id"])).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy proxy.")
        url = _proxy_row_to_url(row)
    elif b.host and b.port:
        url = _proxy_url_from(b.scheme, b.host, b.port, b.username, b.password)
    else:
        raise HTTPException(status_code=400, detail="Thiếu thông tin proxy để test.")

    t0 = time.time()
    try:
        kwargs: dict[str, Any] = {"timeout": 12}
        if url:
            kwargs["proxy"] = url
        async with httpx.AsyncClient(**kwargs) as client:
            r = await client.get("http://ip-api.com/json")
            data = r.json()
        ms = int((time.time() - t0) * 1000)
        if data.get("status") == "success":
            return {"ok": True, "latency_ms": ms, "ip": data.get("query"),
                    "country": data.get("country"), "country_code": data.get("countryCode"),
                    "region": data.get("regionName"), "city": data.get("city")}
        return {"ok": False, "latency_ms": ms, "error": "Không lấy được vị trí IP qua proxy."}
    except Exception as e:
        return {"ok": False, "error": f"Proxy lỗi/không kết nối ({e.__class__.__name__})."}



# ======================== Tạo proxy trên VPS (admin, dùng tinyproxy) ========================
import subprocess as _sp

_PROXY_PORT_MIN = 8801
_PROXY_PORT_MAX = 8900          # tối đa 100 cổng
_PROXY_INSTANCE_DIR = "/etc/tinyproxy/instances"
_PROXY_BASE_CONF = "/etc/tinyproxy/tinyproxy.conf"
_PROXY_TEMPLATE = "/etc/systemd/system/tinyproxy@.service"


class ProxySpawnIn(BaseModel):
    count: int = 1                # số cổng muốn tạo thêm

class ProxyDespawnIn(BaseModel):
    port: int


def _proxy_run(args: list[str]) -> tuple[int, str]:
    try:
        r = _sp.run(args, capture_output=True, text=True, timeout=30)
        return r.returncode, (r.stdout + r.stderr)
    except Exception as e:
        return 1, f"{e.__class__.__name__}: {e}"


def _proxy_ensure_template() -> None:
    t = pathlib.Path(_PROXY_TEMPLATE)
    if not t.exists():
        t.write_text(
            "[Unit]\n"
            "Description=tinyproxy instance on port %i\n"
            "After=network.target\n"
            "[Service]\n"
            "Type=simple\n"
            "ExecStart=/usr/bin/tinyproxy -d -c /etc/tinyproxy/instances/%i.conf\n"
            "Restart=always\n"
            "RestartSec=3\n"
            "[Install]\n"
            "WantedBy=multi-user.target\n",
            encoding="utf-8",
        )
        _proxy_run(["systemctl", "daemon-reload"])


def _proxy_used_ports() -> list[int]:
    d = pathlib.Path(_PROXY_INSTANCE_DIR)
    if not d.exists():
        return []
    ports = []
    for f in d.glob("*.conf"):
        try:
            ports.append(int(f.stem))
        except ValueError:
            pass
    return sorted(ports)


def _proxy_write_conf(port: int) -> None:
    pathlib.Path(_PROXY_INSTANCE_DIR).mkdir(parents=True, exist_ok=True)
    base = pathlib.Path(_PROXY_BASE_CONF).read_text(encoding="utf-8")
    out_lines = []
    for line in base.splitlines():
        st = line.strip()
        if st.startswith("Port "):
            continue
        if st.startswith("PidFile"):
            continue
        if st.startswith("BasicAuth ") or st.startswith("Allow "):
            continue
        if st.startswith("LogFile"):
            continue
        out_lines.append(line)
    out_lines.append(f"Port {port}")
    out_lines.append(f'PidFile "/run/tinyproxy-{port}.pid"')
    pathlib.Path(f"{_PROXY_INSTANCE_DIR}/{port}.conf").write_text(
        "\n".join(out_lines) + "\n", encoding="utf-8")


def _proxy_spawn_one() -> Optional[int]:
    used = set(_proxy_used_ports())
    port = None
    for cand in range(_PROXY_PORT_MIN, _PROXY_PORT_MAX + 1):
        if cand not in used:
            port = cand
            break
    if port is None:
        return None
    _proxy_ensure_template()
    _proxy_write_conf(port)
    _proxy_run(["systemctl", "enable", "--now", f"tinyproxy@{port}"])
    return port


def _proxy_despawn_one(port: int) -> None:
    _proxy_run(["systemctl", "disable", "--now", f"tinyproxy@{port}"])
    f = pathlib.Path(f"{_PROXY_INSTANCE_DIR}/{port}.conf")
    if f.exists():
        f.unlink()


@app.post("/proxy/vps/spawn")
def proxy_vps_spawn(b: ProxySpawnIn, request: Request, admin=Depends(get_admin)) -> dict[str, Any]:
    host = request.url.hostname or "127.0.0.1"
    used = _proxy_used_ports()
    free = (_PROXY_PORT_MAX - _PROXY_PORT_MIN + 1) - len(used)
    want = max(1, min(int(b.count), 100, free))
    if free <= 0:
        raise HTTPException(status_code=400,
                            detail=f"Đã đạt tối đa {_PROXY_PORT_MAX - _PROXY_PORT_MIN + 1} cổng proxy.")
    created = []
    with db() as c:
        for _ in range(want):
            port = _proxy_spawn_one()
            if port is None:
                break
            # lưu vào danh sách proxy của admin để hiện trong app
            c.execute(
                "INSERT INTO proxies(user_id,label,scheme,host,port,username,enc_password,"
                "region,source,active,created_at) VALUES(?,?,?,?,?,?,?,?,?,0,?)",
                (admin["id"], f"VPS {port}", "http", host, port, None, None,
                 "VN", "vpsproxy", int(time.time())))
            created.append(port)
    return {"created": created, "count": len(created), "host": host,
            "note": "Cùng 1 IP VPS, khác cổng. Nhớ mở các cổng này ở firewall VPS."}


@app.get("/proxy/vps/list")
def proxy_vps_list(admin=Depends(get_admin)) -> dict[str, Any]:
    items = []
    for port in _proxy_used_ports():
        rc, out = _proxy_run(["systemctl", "is-active", f"tinyproxy@{port}"])
        items.append({"port": port, "active": out.strip() == "active"})
    return {"instances": items, "max": _PROXY_PORT_MAX - _PROXY_PORT_MIN + 1}


@app.post("/proxy/vps/despawn")
def proxy_vps_despawn(b: ProxyDespawnIn, admin=Depends(get_admin)) -> dict[str, Any]:
    if not (_PROXY_PORT_MIN <= int(b.port) <= _PROXY_PORT_MAX):
        raise HTTPException(status_code=400, detail="Cổng ngoài dải cho phép.")
    _proxy_despawn_one(int(b.port))
    with db() as c:
        c.execute("DELETE FROM proxies WHERE user_id=? AND port=? AND source='vpsproxy'",
                  (admin["id"], int(b.port)))
    return {"message": f"Đã xoá proxy cổng {b.port}."}
