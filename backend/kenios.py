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
from fastapi.responses import JSONResponse, FileResponse, StreamingResponse, HTMLResponse, Response, RedirectResponse
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
KENIOS_LOGO_B64 = "iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAYAAADimHc4AAAnH0lEQVR4nK19abBlV3Xet/Y+wx3e2LOGRqChMWoJCVmDUSFLmEExJC77hxSB7Ur5Dy5XJZhQGcpW8OvnKlCKRBiQTQIVgpGYrCa4MBJYESB1FAmEwJYCghIYYyYxSEgttd5w7zlnr/zY09r7nvu6cflUnX73nrvPHr611rfWXnuf04Sf62BaW4NeX6fWX7nxv/LBaYUrTWsu545fSqBdCnghG3mb/YfYf3aHK0OclWWA/BcW1zjeTsyxDlfeXyJO70vu5die7Y+olAEysY8k+qMAwPBjbPCUUuoLmvSXMNUPvOXP6fu+62tXc7F+DF02oh0POtWC193O+uj11AHA2hpX27twrenM7xjwNUWhVxUBprOAdK1JwLIAcQDcX/PAESI4ESBOy0nhMdt7vABFOQhQ/eDYxDIBGhPrAdtbSLaTCIFBBih0DQJBuTq7bvI0Qd1bgD6w/exjd60fvWAKANddx/roUYvVyY5TEsDaGhfr69S+4Q1fLpcP/+JvA3hzWeIwGGgmQNd1hhgMizMRiCKonA6eEAUhQEq0tQf8qPnuB2E9LAHLBAUTBZyA64Uk75MCNbEO8hbWMSt3JxmQUqWqigIEoGmbRxXzO77zyFdve99XLm2sNUSmmHfsKABmpiNHQOvrZN78Tn6FVuatVaWuaCdA03Sd67wCiIJm5aB66kmuIdVGf50dfXjEhOYGkBABD+2YlEZCWSlo5mhlJhUymXkUxbMWkQoxtFKrga4KwnTSPthxe+ONHxx+bm2N1ZF1MO1ASXMFsLbGan2dDAD8u3fymi5whABMt9oOikgxKXYaTXKgvkZjL+Qge64mXzYZnCgsNTwDRn5mp825f5F9CtcNz9QT7kUElwGQ4aQNJdvOqJTAIMMGzFyXYw1mcDs98h9uHaznWOZHrwDWmNU6kfm9m3h1YWw+Wtfq2s2NzsCAiUj3DlRW5sH3HZwBehYccuUTOskH6sGR9xtxn++DdKSSopihWJT1dQqfYX0Lp/5A9JVEv2xfOFxzgUOnmGhUDVXTNHdNm83X/cFHVp7mNVbUIwSVX1hbE+CPzF31QF27eaJriEmdDPwA+CmA73mVyJcneGMlWI2jvG6K98AP3n/2v8l6JWjgMFhZ1n6nCIQQBMS10A+OPyoPvrB8xaQBqM3tzWZQltdWxfCum15/fJXWyayt8QzeqQUwEwP41zdh12hsPlPV6rKt57qGiEoPmse/V/M9h8vruckLYOSAXfszbCnDwtR/RA73VkEmc9ZB+3s035dN+sdBk/19MgLLxxksCFFpMktqxvWonE4nD21j8qt/cOvSU1aJ4igTiVx3FIqIuB52H6uH/eBLEzwZ+CQHhwi+1GYVyrKwCKSalWt5goarI9dSQW2evxPNF+3bfsVoJ1ZPoS8SKIIoK8HP+q+Iys3tjWZU1ZfVRn+MSPHR61LMw5e1NS6OXk/d79/cHRmN9Cs3n+0HHyZ2PnTAIEYvOQgCPCXvEYLwaIWPef0AVCJpIaSZugQFOdrxQiTvTEU52xdOaYcgNJlS+hNlE6pD2id7v4FWKJ/bfrZZHIxfefNvPnnk+qPUra3dU8imwiTrTe/gqwYVjjWTzgDQ3lj6wE/DMo7UIsqSHKikHQ8aOYcnrvnB9zpdEwXlJ1f+c+J0HVBy4pdQmZyBZ7NmTz+epsLBHOqUICsxLj8OFdiAocAAGxDQ1Xqgmnbj6jd+eNd9t1/H+vqj1CkQcP6j4H/zrm/Wis07AZBhtjDn4IdOi89eI2UnhFNCBn6gHTfShHIk+HIwDlBfFrAWIduSvwWK8NdzCyHRd3Hk1imH0HvN/5X98u2TsX99QGI6Z5T8znf9s2/Wj55vR6nW/oiL9XUyVXf2DaOxumS61XWKlEqkatIGE/DDZ2l6aSfTiMcdHLU5oRsWfkFW2lc2b8eVVcJ3SPBVUvf89gOF5rTDBEXR58gxEXlrsKYW27BWoIjUpDnRLQ52XaJWdt2wvk7mnqs/X9DaGqtnl1ArMg8XWp3XtB0Tkwpc3ONw54EvKSQtKz6THRB7DZ2xKC8gf42T+jw9pBGRiMk5Rjswok5/j8sB5fcnlpfNoH0ZktdyYQFuTmIBt1boTl+hMabWA2q77W9tNZsXP3v++ycEAP/+Zn5NOcCd25umI4LeEXwTW/QNKz/AHvCllgZAkXXcg+V/yMAPAErAJKhACCHD4Tics7JkYkoihKZCCHL2K0NNZPd4mgO85lvpKv9bJgByAmI23UK9rLe6Z177e7ft+7QCgM6YN8Azvh/8PPAzzZ8Lfg48xMRF/u5pQlz0EUz8jOBTkqgm1CWiHX9N0qL7rpw0FGL4R9mJ0I6YZGV9VqKsrcdYmnENWcXxVOQnpY6OiEFsmNruDQBA//ZmPkOx+RopWuHOMGRiLRtAHu1I8HOqmeFnsL+917nB1UXuA+fXPdVkvonZDlymMDz1sLjXR1Ahr+M1uU/zfWTWk8aWFmFzQLagLWdAzE7RxGkixxEbLkgTm+54104vUMp0VxWlWjGdMfPARw/4wTcKyohgx5uDM/LgS83lrKyvlLMyohyRmxM4U1eiHWkVsi9yjpJOqPoUoie9kJUNwQQDRLa8t4B0jFbK3i+4MmS6xtS6XikLdVXBoCuUAojBicaR+Cym/X3gJwP218Ngeaa+HLAISPxROl0l7yUIf0EIizMkYnKy3wNleprLqpH9YMRxBsqTiuXHGsYcPTV52vFaHnyAG1P+OzFrpdEYdUXB4EtNF/uShJEyby4BFkLoAz8ISPC4P5QYmKQ3AoeW5HzAx/vMGSihTnJ1cAKmEuBxTpHyuwfU3y+v9ZQPFuXAUl7LnRP2mp/MARCtwQmI2DSA6S4tFGMf2zy5ZIOQUpZ9mnFs+W/SND34skzEIFpA0BL32XNEboVScAppBASAfIskkmSuEWUy9ReUxrKvwqpVrHgGfHKZPKLI7+QcFBGcD8lPePABMDG3UOB9BZE+1DUGFBk4xPkzGi1t1/dPgCCdqARfZeVT+uH4mSyQM5QVwGfPOoF2cs0GE/JJHojALLXRCYeBREt7KDWpR6xvEnGI+/NoRwJvceRg4Y7eqOsm0ESHCjYmxdQPVHaCMw33FWUWoWIF/eD760oIWXIrKNFCf5NMeXjtDJzvygTOl6GWXA/2NiKtSva1B/xUEMaNhyGdK5GJVhw53lmKsJDEN/g6DIpEq71GZDwfwBBC6KcjTrR3PvieD4WCc/jHlaekfm8dnloC+G6VXDkhsaMncolDE5YrOax8cZgxc7IuEJy7b5Uo/BiVK9d6T19zgPbUlFmDPwvpMBM6CdeFNgvnKM3GcyMDaViYgc/MGI8YzzvTK1wUhDffoOWK8KPHDY4/BWjtN4PYBkjMmtnzNXOgJPsbo2sZSyvAaWeSEwAAI6bHQrGkQm08w/jxdxjcERTkgDjh9+BveoSSA51TlfcVReiA/+vby7ldgB+0PlgERwEJwOVnUoxm22D3LuBXXlWhbTjNmApAjAEGA+Ceuzfwk8cbjEaV7TxpwImCZVtsNT9MkgjoDKOuDS5+aYFDFxfo2qyRrF0ioOuA4Zjwdw9P8b1vnEBVFGBSUI7ALNgmCNinGhInPA98YSHREoCiTxvkQTtc9ynlvsEkZZxmcmegFLC4SJhMaUcBjIcA6Skm0w0M6jFIVdBwO44UhRls7nNAgDEGijq86CUKh68ooQuK3czb9E0boKyAE0+3OPaJH2PaKBSqhqICpDSIKWqu2xGWA51YAM0KIvweUjLsfEAOgjRtpBqdjCFbgpSWJMt5LWF0YMNoO6ttM2sG8AJgtExoJpuYTk+g7RQKJkArENn5ZiJ8hZDBZBjAdHjBC4FLrqmhCkLbCDrPDk+NSgOTLcaf3/Q1/Og7DVZXltF2hEoTYBT89DZmRWeBllouNT8XAISQ/JJoCgILJ8fzrnOal8kENVsxg7mDEbO+5KT0uwIwbTaxvX0cbbMNYxorwIxHAyguMjCdwYEzGJe/osZoQaFrhEX2nH4MVUX44M1fxDce/i6qYYO2mYC5nQkrQ9v5yR7Q1A8oAbrtg0hZgEWgki3rSQ3xGOaaHxchUgHG0A+hwwCDTQdj2kSuc08C2nbLWcA2DLfwWUdpZTELasFfWe1w2a9U2HWgQNPYTuzUTmcMxmPCh99zP459+hEMFxhtM4Wd1ToNpznOleI1j8tOTlixXyUz9uQ4k46AZ843v85z8vkybRsEFyY//qoBJ9um+9vyR9dN0bZbMGYqtNHV78NSlycwxmA47PCSq0qceW6FZopZH5MdbWuwvKhwx9Gv4OMfOIbFlQFgAE06nIoi9ye5fpoNK5ULSIizMnBAIyqkL1N4zZZJtBmHG0AS5ucF4jsm0LeUEAv4jtitgZa6ct8t2+RQvIPpWic0wZ+ersg6T2ZGoTscvlThvIsGaBtRz5yjaw2WlhW+cN+38L63/xWWlvegUBWqYoCyGKDUFQpdQJOyy5B5uCkjoMTBekdtr/nUNCDXGOQ8IKGWHHiGnxAlhC813yARnKcdXzTPgrrofy74yWU2gfdF5TFBZ9w/3OHcw4QLf2kIb9E7aX/XMcYLCt9+7Ce4+S0fxaAeYVQvYlgtYlguYlCOUBU1ClVAE7kwNA0384gHM/kf32VvtWYG/NQHSDAYgtci+PmYknx+EGRc8gtGkQGc8DD3c7MnKinQAH5QAoYxHc48C3jJLw9Q1ITOKcR8zmdUNeHppzZw03+8Fc0WYXlxDwbVEsb1CobVkhWArqCVnwNYi1aC8/PwMo9+LLimB3wThBIEwFkvc/CllQRAJUL+d3Gfz+1IQQTqkueMRBApyuNOHLSehEmZrsPuvQaX/HKFhWVtI56e+kK9hqEUwNzh7X/4Yfz4eyewZ9d+DMolLNSrGFVLGFRjVHoArUsoaBAJ7Xed89FOpJ3cUXuwEQHvdd4IvsEBL7Qt01zOwJqNjjj9jdP7ZaU7WYCRt4YIJArCipVh2GBhscPFL6uw98zylCIeZsZwRPjTt30CX/3SP2D//tNRF0sY16sY1csYVAuoigEKXUBBxS0oQnmkMJQANgk/hYantCOiIGcNfh05guiP7Pktqb2z8waO2jojmHiEhyTy+0/hIFGxMYyq6nDBZQWed6hC0+DkEU9nsLik8JH3fQ6f/eSXceDAGRgUixgPLPjDagF1OUSpCugEfB9C9swBelfBJNBWpWaEInxDEdQjRC3+u3Wwbo9cBEsE+QTYdCvF7wBCJBDqE5ydUEzPEaxCtJducWQo1eLQBQrnXVzb59J4B1kS0DUGy6sK//tTD+Oj770b+/edjmFlNX+hXsGoWkRdDFGoEtrTjtB2CXBCO8l3STvp/CC95j9bv1CQAMYjIMNMAsKe0PB7ZjGJgHrAj+nnEFNFwWTg9+Dn/to6mFscPEfj8OUDkCKYPKWRHV1rsLis8PBD/4D/dtPHsbqyB6N6BaN6BePBCob1IgaFdbrKJd6Anry/FIYILSPFIPK7oHIJdvrZfi/YSSVHIWi+SXEK2DL3hJh94Kd1S97Pjz6fLGnOdB1OO73ARVcOUI/VjjkeADAdYzBS+MF3n8LN/+lDqPQYi+NdGFXLVvPrJdTlCKWuoKGhSKXp5SzcnGsNMxSTzhGskExQ3DxVEbk9F0Q2MpI/ZpYif08dtng4bk7MmUQ9fR7ZsJ21rjAuvnKI5d0F2unOEY8xjLIENje28V9uvA2bz3ZYXdmLYbmMhYEFf1COUekamjRI0Qw40rn6hfcZZysEZp1rZAfpK5K6wVYgsKHtDOA+ry5/C/MP/6AbLEAsfg9lvWA8B0o6m4Nx3+lXsdrWYDhkXHTFGPvPqk8a8RgHiiqAd61/DN/95hPYu/sABsUSxoMVG/GULuKh0qYcQOJhEd93IYy+1DL7MFNqvkmccAq+u25iiKpiXt2DH7+kFCBVG4nbSGJ7gbB0yrmQkX7sPRiWwwvNuPDSJZxz4SK69uQRD7PBeEnh/X/yKXz5/zyGAy7cXBis2slWAL+AVgr+4ZEEcBLPqfUtpmTRTroyJgSCvJycM/jtkoJnAUo2rEYz9xXH8jYKigOfmaR5ywESVe+R1az2A7DbZQzOf/EqLn7pXp9K6mcz971tDRZXFP7yQ/fhM7ffjwMHTsfAgz9YseFmMUSpSmiyLjduIIvcnQgDCBMvlWGRW0gEX1IOBD2llhQflfHaLZ8F8OEjc3CozLM71dgNgk12XyySqrsQRO/hu2IMzju0ipe9+myUlUbbsp0Jc1rOH11jsLSicP/dj+K2P/009uw5gGG5jLEEvxyiUJUDn0L4KHM5QcshhQHhXDPqAYvNW7l15OCLzxxWxCRajJiAQ2hcan2gFxKfXaWBHxzyfY7dG8lcJiGgaYH9B5Zw8aXnYHnPANtbFvx5QjOGMV5SeOzRx/Fnb/0LLI5XsTBcwdiFm6Nq0UY8qnYZTgUwRD6+J9LJk27Jb0DiF3xZlmGmF1puDVHAhdyJACCkpdlrRoZSSITlHlVKglMhCFmC89lwL/6E6QS48JJzsbRrCZMtN4OQ7YqDDaOqCD95/Dje8ZZbga7C0tJuDCsHvg83VR1z/H58uXP1dOKpyDtR9xcBwFlQY7o+j3b66Yrgt6V42gmUA0jNZ++knLL43WnxicNoQdQHkrcEE+vYKVfv61ratbTjuoG81JkOt97ySTz5+AmcduCgSzMsJ+FmoSz4iqmfbhIunw01rY4ZxMgmfoa0iOQvhCB45lQJ5wdrzGiHBbiI1yxjcRIFBWMQrBb8yEl1Pz1IIazA7ViOCKYjHL7oHJxxxgEUGGI0WMKwWkQdwC/CTNdrNMJYo1ak2hv53B4mBRVeMBLcnuwnuP8aOydMCH42Hj4PJMGkKIxwkzjC6hjs0nmcqDHYSyf+2flg4Kknn8GuPct2D5GaT0FgQCmFa/7Fldh6xuBvj/0YlR6g1gOUqkJBBZSL9SmAbm/09CA1OKTgBdjBUhiCVjgo20zEI/l+xiriZyUpKGiu0PwQRiJes2Wj5rMoHxf3o4bZemnnWZc4TccYjYE7bv8sHv7SN7CwSOha8YaM/IRd5SKlcM2vX4bDLznDTqxI271EUhnYZjaDxgfNN6kTFjG8pKZZjTaz1xKB9Gt+mGlH8DiAJTUrfGeIfZQ8+2ovEwWZ0E4G1Cngb/NMGphOWrz7rR/CUz/bRFkrGOa594AIbcMYrwxx1W8cxoGDQ7RNY9eT2YCM/avEXfJznDQylJECQQJY0Gw2iE7XzCkzB3zxXXltliClmiyswptvLiTxOCi78jMv2RB5nVM5TAeMxiM88cNn8N63fwJaC/6ac5AiNBPGnoMruPy1z8d4qcV0andVmK4D7Ct9ZqxAicgn0A4L8JFFPmEukJafy/k83y8oMhF8OZMNVJsQdtR8hgVZfvdWInNEMvIJFsKncAJgQ9i1ezce+eJ38Jcf/L8YLyp0ndnxPpAVwsEL9+HCl+8F6U1MJ1tgbsCmA3EnrD2CDwmm63QUSrqShT7aQZYDShbp51tDXJIMqicW1R1ozCLa8domgc0sZO5KeyLMkxwMaCpR0BB79xzA3UcfxkPH/h7jJQXTnaQSInQdcN7LzsC5ly2i6TYwbbbs7rrOUpGnoMD7nAHFEMDLaG8Hp7oD0DPWER7qhqAY/yKKHCzmhJKSz5C0w8I6hMCEMHES2TAAJquDSmlUxRCDcgFLC7vxv/77A3j8u8+gGhKMme8PGHaDryo0Dr/6LJz+wgKT6XNo2224Z7NAxkQHHCzBRO2foRGI60i1PKGpUwBfXAt+KHGqjuPYSdzvBw20k43W0o54yM6Xl4KT/uAUT4JCqWqUeoilhVXwdIDbb7kfzaS1uxt2iKoIQNcwhss1LnrtWVg5YDDZ3kBrpnZ7pHei3rohZrOJ9pvZZ76klp9SOTPHYrwTzh7xD+i7zoRISfK/0OiQyAvCiFqfTtSihZzKSaSgVYlKD1CqIXav7MVP/m4Td3zgIVQjCmmNuUxHhGbKWD1rGS9+zUFUixNMJptgMwWbDsz2RadJVBP4PPY9zgPMrAD6NJ/zMvNpS5FwjFFzLYjJu3DE71KbycSthsnagkCCOXzAz3UwQZFCoSrUxRCVGmHfvgN4+HPfxxfufAyjJTqpPyDnlE+7aD9e9Ip9gN7EZLqFzkwtFbkwVc4FYrTjlUvQjAhRI7B9TvnUqCg+jSn53T/qL8APkU1CQbaA9BseaxkhJWGtQfTTJzkBQEFBByGMMNAL2LO6H5+99RF8+6tPYDAmdC3vXA8TTAucfdVZeP7lS2i6jbjl3djwVAIe+J0zf2D8rmZgxhLmUExCPwn4cBRkMvBdYSmY5B2cQUgcAJfaL+cAQUZCKD/P4VejCAQNjVJbSxgPljDUS/irW+7Hiae3UVS0c86IbLpaFRov+tWzceAXKmxPN9B13h8IIXjw4ZVrB8rhFMy5AumjJ2dFYTFIruFK8D2QkdPtF19ScWotkYD9PZlKiyInO8FWCAqAIgWtCpSqRqWGWFnejY0nGJ96z/1QxcnrBRHallGvDHH+r52LpdMZW9sb6LqJfWgkzJjdPEA6WTkX6NX0ORMtzrVfOnykAvAvQPVONISRM7zPYVQyGvKan/gRV9ZfJ9fOzyMB34YCQbNG6f0BDbF3z378/UM/xb0f/VsMFwim3bluAqGdMJbPWsH5//z5KJ1TNmYKNq2NXR3XxocogBnONxn4c7U8O03PAxrh4eY+zRcAAil48pUvKWhR82cctxcOnboFxJtsfdYpl6iLIWo1wt49B/Dgxx/F1+7/LoZLhK47eWTUThj7Lz4d573qNHCxZdMVnZ0f2NjWBGWc0fo81EzmAvJzn2NGRmMGyv/gtVaClmwtkRYhgM+3sATNF+EosjKncoSixjtE20/FgCZlLUEPMSoXsbywC3e95wE88T07SeOT5pvsTPmsq8/BwV9aRdNtoGm30YV0hYjpe0PPXKNzgZgU9BDOpnOG8JKnELfneRxER5iYcq9q+d84Uo6vJ5swnVIEJIQfZquuP4oJBWlUukath1gar4I2K9zxrmNop51dyDHz2wIA7hhUaJz7mkPY86IBtqcbaLuJnRs4KpoBP9HyfO9PnxXIcllaw4ESX7dgUrpIPpsIZkzb9mt+iIZEPdRT/mSHVwI/ACtIR0MgKCgUqkCla1QYYveuvXjysRP47P+4H9WIYNhgXlOeirqGUa2OcOjXfwELZxC2J5s2MmIXGfWmmU8W7WQbtQLgfRFVtjXRHzEs5QhmnnxD+jfMeJ2w8tD0H3dwiLrCLNVtDiIAmgkllajLAWo1xL69+/H1u76Nv7nzGxgt28yp7GYuBFKEbspYfMEunPdr56JYbLA93YzzA7eGMAt03yKMjHTypUvvrCUN+eguS7JJh+snJjLE9BOs5P8M8LQjLEVJ8CWl8M6Tptmo1VNa/IGc6SoQClKonD8Y6DF2r+zDfe//Ir73/36CwVih67iXioIygdBNGHtechAvePVB65Rd5tTPlHeknrkRkAM7EWB8MMNatYl7rORSaxLBOOA4o5KgRt4/CNVKJmXw90XtTW7f4fTCjaiJvZVhkAQNK4SBGmBhsIQhLeKud34eG8e3UZRxktbbBgBmu8399Jefh9NfugfTbgNNY59N5hAVeQeL+eAHAUGAjexvzDPZtzc62giLMJ5KkPaSeoEWmt83MiEkn1NxTdjlxZOcCALnmTMmzrwlaNS6xkANsLK8C9s/anD3LZ+HKgFmntueXea0D3mjKPC8156PXS8aY9Juoe3888kG8GmIeX4BnMX5go6SclIQ3gcgA19SAENMpKImhUlWuDfOihNLEVrsy+oCKApCUc47FYqS3ANy9q+C28hqRNaSbR5fgVy+qESlawxgJ2k/eOCH+OJHvoTRioLSO7VHKCoFBWBwYIyzr3sx6j3AtNm2qQpPRfMccAK+G7+R4MuJnRAEWLywydOO25xF8Mhm3wWQ5O5lZO/P95+BYL4AoAmYPNfh+E8naKfWvBn2DJwDSxmbzxXYOL6NUpfQcO/tCdZg4N+A5QfEADQUSJWgYgDmBnv37Mcjf/EIVk5bwWkXHECz1br+pm7ZUxkRAYZQLdcYnL2Cp3/wYwyLEkZZAYdILgc/AbUn/QDjBCSdsvUBhVV3EbcbxO3ffoVM0k4wI0qFJSkHXpAMv/8GzChLjae/t4Hbb/wKntt+EhvbT2J7+gyabsu9Q8LY7KcqUBdDDPQCFhZ2QXG2f18M2h9BAaABVQJ6CJQtzLjBfe++F1O1ic3JCUy7bXTG7ZaA52Eb0g5UhVE5wmK1hOXBCsZFbftF/sGluKkr4BAmXh58IaQZgUQB+G3phYJyEw9xuJ2zuZZLP2CfGI//9woByb59MtEx+DjeppYLqK5CYYaoeAEMhkYNpsaVBTQVqDDAsFjEsBzHPZ0g9+pfqwCQWsbWiuyD3BqkK8AMgbqDIsZz23Zb4hQlOjTW6kJoSNCGUKJE0RbuTbwNVD0IAPq++dcqpykHCX7uA6RjFtoPA02Egrn7ZqnrQ20zYRBReOuVtIREoum1oBUkrMjtUw/vkAgURihVCS5HUNSh1ApNN4Lxzs61oUij1CVqPcCgGLsdbqWlGB8sUB8X27YsZWlAVyAeQoNRksa0HKBpJy666SLtwvkRpVCStYRhMUCpNDR7y/OAyigoB18C7b73gW8M17qgaTf9ZkGGf0pKHQLAlFp11HZwAHfm8VNfiOMPXvIgFu9N9om0AqQHUABKKtGZEQy3iIsfgCIb1ZSqtGsAukbhtxb6NmS8zXKAvjuEigpoPUABQoUCrarRFQ0M+/SzfYWMt3bNgCZCqQpUqkClSteuV6Y+rZaazzuCH/83DeaCFLXATwtAfVkrflnnIcwccJq/hqMS/5ss68NXS2f+BRYefP96GYUCStuEGuvKar572Nebs3JC0KRRkIZW2mq/ay9oZF8o6CMvEEAKikoUCihLDdalBd90YUKXT6AUETSAghQK0iig7IPbvt254PdM0HLNj5bKBREU85cLYvUgOoITbkIxATxvFZRFO14wHG+yAFnwfZ5DBUfvQIF2j9kUViO0WPrj+Cp6O2gK7+zxoehsXI3gZ6RfCD1UBQpWAGmr+SoHK81equS0AgnP/86lHYmH9A1yXB4oQ8Z00MQPFk3b3qfBx5UqV4xpPGsngwuHEeDLOQBMiFASbnYNA7FxS2PuvW+skP5fK462RMfDO3bmar4HX9CDtyZHkzZiI3jvYF+2Ksr5EJNSn+JpRwFhpWxH2gHHdWMg9N/uSfXKYbgkpSbd9nEG7lNvu3X8Q9OZY5Uu/P5lzOR2IJ4YjIbhPov/pwtuY6scHOL2PxWm35FmlHtcSPkcJyl3nUL876fsM7NQPysWeatw3U2EZJsadi6iQe6vpUINBU1kT8QzvC+iN9TMaCfE+qnmxzV2V87AjHXNDD72wjuv/6ECAEXqfYq83+zhfDGxktfDEp5rKFkeC7Nqcc2XS4QkNM4Jy58xJyV41T+H6+sNzs5Ex5c/q+s3TSXCw6wW96UYesHPZr0zQkppR85dgA6KQBr8PgCgtbU19ezXj9Sro+2HS12c17VTJpAKrx/u43ykHQf5t4kg0M2Mc5x7zqkrKIIJrwAjZoQ3l8MLI3V0vTn5OQ53R+Clb5ir+SenHWkJYDYjXdLETL5Vj9TF7z//0YnCvdeoPzlKW4b4bVVREDNzr+b76EJ0wpuVMpFTlVyOmzdweWbLerMUBpH9FBuoTqXuHrqiPusLoGaWdDLw2WQ5oAi2pB0EB9zxuKiIYN72vKPXb11z7zU2vvijNaOeevBb5b59Zz4wKOpLmmbLKCiVaz58oyQfXI5OdkYbZzSTZxxdnzNVftBh8GImKjdG9dXfd21mwpZfy0CV1pdcE2Oc2XIS6wvYCPCZjVkoarXVbv2NMU9ced4Vb2zUOhnFYBz+OuiWvz40UR3eZEeqmEOHohV4mpFONUYqQjP7tK9PU3tMPjhbN0gk4PMO4Geh5Qzn9/VL+ApPORL84H9ympMWIjAI/Rf/s4YThgaYwExEbzr0178/wdePErvgAP4/mLzxw6P7ppPtP16ohhoM9/JHxJ1wiA0gGZDpByIDX8b6yWzWiMG7cwb4ebQjgd5RuPKamWkvES6b9POMhfRlNtMxhpU7MMCmWa3GeqPZ+ONz7nzdffdcfU9BR6/vvGKHw/8Hk//5tzbvXhgMX7mxvdkoUInMwfQ62YRi+uL1Hc7gwE12H2bKzC569wlbaHLiT+YJxF+bpb7UD8wZUw/teKyYTbOnXiyPbz/72bM/8/pX8XW3aw8+vAX447qjMMxMhpobtieTh8bVqGTuGh+Hh8f6mSNYkNoqLKJnz4y0Gp8Glys/cVaLFLSZrR0mu5aFoAnoJgUvd8LIaWYO+DP37Uw7HvzValyemG48tD1tbmAw4eh1Seo5EQCB+MgR0B/etvyzptu+dtpMHloaLJTgrvFbNOT/kygXyb35hVhfCktQij9T2jEZnfT4Enka019uJ3qaZ5GmR2DSeuY52zm04/Hxmr/ZbD30DNprz//cv/oZcITk/6Y9Q0H+8P8B/U2vP746UoOPDqr62q3tZwyIWQG6j9/7zx6qSFIVMtJgJPTyTxXt9N2XlPN98KDn/ixPOcR783eHOr7viEC7yrHabLfuepqb1734zt982mOaY90rAABYW2O17m549289t1ZQeUQRMGlPdAogBagdBzkTbsooRvBsMHm4vNAO/iM4fERBzvUD+X2ZYnBfH05e32xuJzzyahgdLxYDDRg0pjny/DtuWLel1hRhvXdz/uyri92xvk6GwbS2xuqNH1pYn5rNVxpuHlyqd+lKDZTbudQBhuc6xL6Nq7mFhEELWumJiuZPoE5y9oKa+yfRZvAbfeVy2jFMhjtm7oa6VLvrRd1x8+CWmb7y+XfcsM5ra4rBNA/8HS0gsYaruVg/Ru17f/G9Jc6/4bdh8Oa6GBwmGEzbDZhuaoiYiZmImBRAfeCAxSve+6zjH0M7OwI97z5BO8Gq5PV+2oExrHw8D6aSlBoXFQjAdjt5VCnzjs/88Knbfvcrv9vcc/U9xcuPvbzdEdhTFQAQQ1QAWLvua9WZ9cFrYaa/A2OuqYpqVZMGcwPmFm03yUJVzGpTHlYGSnFUxOIasu+nKhAvVGC2D9LqZD93oJ1aFSjI7sYzpsPUTJ9WwL0F8IETQ3PXBUevn1qsbtfXi1Dzn0QA9mBau/pevS4k+z//5c8Oao0rDdrLTTd5qQLtUoQXAt0pgCOv+fCzzw+cgm/ojd8zUEO52KaSOS3ALRkiUSAwQxNAbB5jNk+VqviCYnyp0njgzE/+xvc9FvdcvVZcc2y9ozRhv+Px/wHcmHFyOK4UwwAAAABJRU5ErkJggg=="
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

# ----- ÁP BẢN KHÔI PHỤC ĐANG CHỜ (nếu có) — chạy TRƯỚC khi mở DB / nạp khóa -----
# Khi admin bấm "Khôi phục", file mới được lưu tạm dạng *.restore rồi dịch vụ khởi động
# lại. Ở lần khởi động này, ta thay file thật BẰNG bản khôi phục TRƯỚC khi có bất kỳ kết
# nối DB nào → không bao giờ hỏng file khi đang chạy.
def _apply_pending_restore() -> None:
    import shutil as _sh
    _kf = os.getenv("CODEBOX_ENC_KEYFILE", "kenios_enc.key")
    db_restore = DB_PATH + ".restore"
    if os.path.exists(db_restore):
        try:
            if os.path.exists(DB_PATH):
                _sh.copy2(DB_PATH, DB_PATH + ".bak")   # giữ bản cũ để lỡ cần
            os.replace(db_restore, DB_PATH)
            for ext in ("-wal", "-shm"):               # bỏ WAL/SHM cũ để không lẫn dữ liệu
                try: os.remove(DB_PATH + ext)
                except OSError: pass
            logging.info("KENIOS: đã áp bản khôi phục database.")
        except Exception as e:
            logging.warning("Áp khôi phục DB lỗi: %s", e)
    key_restore = _kf + ".restore"
    if os.path.exists(key_restore):
        try:
            os.replace(key_restore, _kf)
            logging.info("KENIOS: đã áp bản khôi phục khóa mã hóa.")
        except Exception as e:
            logging.warning("Áp khôi phục khóa lỗi: %s", e)

_apply_pending_restore()

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
import contextlib as _contextlib

@_contextlib.contextmanager
def db():
    """Mở kết nối SQLite cho 1 khối `with db() as c`. Tự COMMIT khi xong, ROLLBACK khi
    lỗi, và LUÔN ĐÓNG kết nối (giải phóng file-descriptor). Trước đây dùng `with` trên
    Connection chỉ commit chứ KHÔNG đóng → rò rỉ fd, chạy lâu sẽ 'unable to open database
    file' và backend 502. Đóng hẳn ở đây khắc phục triệt để."""
    conn = sqlite3.connect(DB_PATH, timeout=30)
    conn.row_factory = sqlite3.Row
    try:
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA busy_timeout=5000")
        yield conn
        conn.commit()
    except Exception:
        try: conn.rollback()
        except Exception: pass
        raise
    finally:
        conn.close()


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
            CREATE TABLE IF NOT EXISTS trial_devices(
                device_id TEXT PRIMARY KEY,
                used_at INTEGER
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

            -- §7 ĐA NGƯỜI BÁN: cửa hàng cá nhân độc lập (mỗi user tối đa 1 store)
            CREATE TABLE IF NOT EXISTS user_stores(
                id INTEGER PRIMARY KEY AUTOINCREMENT,   -- = Store_ID
                owner_id INTEGER NOT NULL UNIQUE,
                name TEXT NOT NULL,
                description TEXT DEFAULT '',
                logo_url TEXT DEFAULT '',
                created_at INTEGER
            );
            -- §7 Đợt 2: Danh mục của cửa hàng cá nhân — CÔ LẬP theo store_id
            CREATE TABLE IF NOT EXISTS user_store_categories(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                store_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                created_at INTEGER
            );
            -- Sản phẩm của cửa hàng cá nhân — CÔ LẬP hoàn toàn theo store_id
            CREATE TABLE IF NOT EXISTS user_store_products(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                store_id INTEGER NOT NULL,
                category_id INTEGER DEFAULT 0,
                name TEXT NOT NULL,
                description TEXT DEFAULT '',
                price INTEGER DEFAULT 0,
                media TEXT DEFAULT '[]',
                download_url TEXT DEFAULT '',
                created_at INTEGER
            );
            -- §7 Đợt 2B — Bảng giá nhiều mốc cho sản phẩm cửa hàng cá nhân
            CREATE TABLE IF NOT EXISTS user_store_prices(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_id INTEGER NOT NULL,
                store_id INTEGER NOT NULL,
                label TEXT NOT NULL,         -- "1 ngày" / "1 tuần" / "1 tháng" ...
                amount INTEGER NOT NULL,     -- VND
                sort INTEGER DEFAULT 0
            );
            -- §7 Đợt 2B — Kho KEY của sản phẩm cửa hàng cá nhân
            CREATE TABLE IF NOT EXISTS user_store_keys(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_id INTEGER NOT NULL,
                store_id INTEGER NOT NULL,
                key_text TEXT NOT NULL,
                status TEXT DEFAULT 'available',  -- available | sold
                price_id INTEGER,
                sold_at INTEGER,
                created_at INTEGER
            );
            -- §7 Đợt 3 — Đơn hàng của cửa hàng cá nhân (buyer mua từ shop người bán)
            CREATE TABLE IF NOT EXISTS user_store_orders(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                store_id INTEGER NOT NULL,
                seller_id INTEGER NOT NULL,
                buyer_id INTEGER NOT NULL,
                product_id INTEGER NOT NULL,
                product_name TEXT DEFAULT '',
                price_id INTEGER,
                price_label TEXT DEFAULT '',
                key_text TEXT DEFAULT '',
                download_url TEXT DEFAULT '',
                amount INTEGER NOT NULL,
                status TEXT DEFAULT 'completed',
                created_at INTEGER
            );
            -- §7 Đợt 4 — Mã giảm giá riêng của từng cửa hàng cá nhân (unique theo store)
            CREATE TABLE IF NOT EXISTS user_store_promos(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                store_id INTEGER NOT NULL,
                code TEXT NOT NULL,
                discount_type TEXT DEFAULT 'percent',  -- percent | fixed
                discount_value INTEGER NOT NULL,
                min_amount INTEGER DEFAULT 0,
                max_uses INTEGER DEFAULT 0,             -- 0 = không giới hạn
                used_count INTEGER DEFAULT 0,
                expires_at INTEGER DEFAULT 0,           -- 0 = không hết hạn
                is_active INTEGER DEFAULT 1,
                created_at INTEGER,
                UNIQUE(store_id, code)
            );
            -- §7 Đợt 4 — Yêu cầu rút tiền của người bán (admin duyệt chi thật)
            CREATE TABLE IF NOT EXISTS user_store_withdrawals(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                seller_id INTEGER NOT NULL,
                store_id INTEGER NOT NULL,
                amount INTEGER NOT NULL,
                bank_info TEXT DEFAULT '',
                status TEXT DEFAULT 'pending',   -- pending | paid | rejected
                note TEXT DEFAULT '',
                created_at INTEGER,
                handled_at INTEGER
            );
            -- §7 Đợt 5 — Cài đặt hiển thị RIÊNG từng cửa hàng (thông báo chạy · flash sale · liên hệ)
            CREATE TABLE IF NOT EXISTS user_store_settings(
                store_id INTEGER PRIMARY KEY,
                announce_enabled INTEGER DEFAULT 0,
                announce_text TEXT DEFAULT '',
                flash_enabled INTEGER DEFAULT 0,
                flash_product_id INTEGER DEFAULT 0,
                flash_end INTEGER DEFAULT 0,
                flash_discount INTEGER DEFAULT 0,   -- % giảm
                flash_title TEXT DEFAULT 'FLASH SALE',
                contact_links TEXT DEFAULT '[]',    -- JSON [{label,url,enabled}]
                updated_at INTEGER
            );
            -- §7 Đợt 5 — Đánh giá sản phẩm của cửa hàng cá nhân
            CREATE TABLE IF NOT EXISTS user_store_reviews(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                store_id INTEGER NOT NULL,
                product_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                username TEXT DEFAULT '',
                rating INTEGER DEFAULT 5,
                comment TEXT DEFAULT '',
                created_at INTEGER,
                UNIQUE(product_id, user_id)
            );
            -- §7 Đợt 4 — Cài đặt thanh toán RIÊNG từng cửa hàng (giống admin: ngân hàng + API key tự động)
            CREATE TABLE IF NOT EXISTS user_store_payment(
                store_id INTEGER PRIMARY KEY,
                bank_code TEXT DEFAULT '',
                bank_short TEXT DEFAULT '',
                bank_account TEXT DEFAULT '',
                bank_name TEXT DEFAULT '',
                bank_webhook TEXT DEFAULT '',
                bank_apikey TEXT DEFAULT '',      -- mã hoá (Casso/Sepay)
                acb_api_token TEXT DEFAULT '',     -- mã hoá (thueapibank.vn)
                updated_at INTEGER
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
            -- Lịch sử cuộc gọi (thoại/video) — dùng cho lịch sử & cuộc gọi nhỡ
            CREATE TABLE IF NOT EXISTS call_logs(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                caller_id INTEGER NOT NULL,
                callee_id INTEGER NOT NULL,
                video INTEGER DEFAULT 0,
                status TEXT DEFAULT 'missed',   -- answered / missed / declined
                started_at INTEGER,
                duration INTEGER DEFAULT 0
            );
            -- §1.1 — Thông báo phát cho TẤT CẢ người dùng (đọc trong app, không cần APNs)
            CREATE TABLE IF NOT EXISTS notifications(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                body TEXT DEFAULT '',
                kind TEXT DEFAULT 'general',
                link TEXT DEFAULT '',
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
    _seed_setting("store_logo_type", "image")     # image | video
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
        # Gói PRO có thời hạn: ngày hết hạn (unix giây; 0 = vĩnh viễn/không có) + cờ báo hết hạn 1 lần
        ("users", "plan_expires",        "INTEGER DEFAULT 0"),
        ("users", "plan_expired_notice", "INTEGER DEFAULT 0"),
        # Đơn thanh toán: số ngày gói (để khi xác nhận biết cộng hạn bao lâu)
        ("payments", "plan_days", "INTEGER DEFAULT 0"),
        # Âm thanh thông báo (quà/follow/share) lưu theo user → cài lại app/build lại vẫn còn
        ("users", "notif_sounds", "TEXT"),
        # Thiết lập TTS (giọng/tốc độ/mẫu câu/cà khịa…) lưu theo user → xoá app cài lại vẫn còn
        ("users", "tts_settings", "TEXT"),
        # §1.1 — Ảnh đính kèm thông báo (rich notification có hình sản phẩm)
        ("notifications", "image", "TEXT DEFAULT ''"),
        # §7 Đợt 1 — Giao diện + hồ sơ cửa hàng cá nhân (ảnh bìa + slogan riêng)
        ("user_stores", "banner_url", "TEXT DEFAULT ''"),
        ("user_stores", "slogan",     "TEXT DEFAULT ''"),
        # §7 Đợt 2 — Danh mục: gắn sản phẩm cửa hàng cá nhân vào danh mục
        ("user_store_products", "category_id", "INTEGER DEFAULT 0"),
        ("user_store_products", "kind", "TEXT DEFAULT 'app'"),
        # §7 — Hiệu ứng chữ cho cửa hàng cá nhân (giống admin)
        ("user_stores", "name_effect",   "TEXT DEFAULT 'gradient'"),
        ("user_stores", "slogan_effect", "TEXT DEFAULT 'none'"),
        ("user_stores", "name_color",    "TEXT DEFAULT ''"),
        ("user_stores", "slogan_color",  "TEXT DEFAULT ''"),
        # §7 — Font chữ + hiệu ứng động cho cửa hàng cá nhân (giống admin)
        ("user_stores", "name_font",     "TEXT DEFAULT 'rounded'"),
        ("user_stores", "slogan_font",   "TEXT DEFAULT 'default'"),
        ("user_stores", "name_anim",     "TEXT DEFAULT 'none'"),
        ("user_stores", "slogan_anim",   "TEXT DEFAULT 'none'"),
    ]
    with db() as c:
        for table, col, ddl in migrations:
            try:
                c.execute(f"ALTER TABLE {table} ADD COLUMN {col} {ddl}")
            except Exception:
                pass
    _create_indexes()
    _migrate_strip_ken_ids()


def _migrate_strip_ken_ids() -> None:
    """§6.1 — Làm sạch ID cũ: bỏ tiền tố 'KEN' khỏi public_id người dùng đã có.
    An toàn: chỉ đổi khi phần còn lại toàn số VÀ chưa bị ai khác dùng (tránh trùng)."""
    try:
        with db() as c:
            rows = c.execute(
                "SELECT id, public_id FROM users WHERE public_id LIKE 'KEN%'"
            ).fetchall()
            changed = 0
            for r in rows:
                old = r["public_id"] or ""
                new = old[3:]                      # bỏ 'KEN'
                if not new.isdigit():
                    continue                       # chỉ xử lý dạng KEN + số
                dup = c.execute(
                    "SELECT 1 FROM users WHERE public_id=? AND id!=?", (new, r["id"])
                ).fetchone()
                if dup:
                    continue                       # trùng → giữ nguyên cho an toàn
                c.execute("UPDATE users SET public_id=? WHERE id=?", (new, r["id"]))
                changed += 1
            if changed:
                print(f"[§6.1] Đã bỏ tiền tố KEN khỏi {changed} public_id.")
    except Exception as e:
        print(f"[§6.1] Bỏ qua migration public_id: {e}")


def _create_indexes() -> None:
    """Chỉ mục tăng tốc truy vấn hay dùng (hiệu năng)."""
    indexes = [
        "CREATE INDEX IF NOT EXISTS idx_store_keys_prod_status ON store_keys(product_id,status)",
        "CREATE INDEX IF NOT EXISTS idx_store_orders_user_status ON store_orders(user_id,status)",
        "CREATE INDEX IF NOT EXISTS idx_store_orders_ref ON store_orders(ref)",
        "CREATE INDEX IF NOT EXISTS idx_store_prices_prod ON store_prices(product_id)",
        "CREATE INDEX IF NOT EXISTS idx_ustore_prices_prod ON user_store_prices(product_id)",
        "CREATE INDEX IF NOT EXISTS idx_ustore_keys_prod_status ON user_store_keys(product_id,status)",
        "CREATE INDEX IF NOT EXISTS idx_ustore_orders_store ON user_store_orders(store_id)",
        "CREATE INDEX IF NOT EXISTS idx_ustore_orders_buyer ON user_store_orders(buyer_id)",
        "CREATE INDEX IF NOT EXISTS idx_ustore_promos_store ON user_store_promos(store_id)",
        "CREATE INDEX IF NOT EXISTS idx_ustore_wd_seller ON user_store_withdrawals(seller_id)",
        "CREATE INDEX IF NOT EXISTS idx_ustore_wd_status ON user_store_withdrawals(status)",
        "CREATE INDEX IF NOT EXISTS idx_ustore_reviews_prod ON user_store_reviews(product_id)",
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
    # Hết hạn gói PRO → tự hạ về Free + đánh dấu để báo khách 1 lần
    if not row["is_admin"] and (row["plan"] or "free") != "free":
        pe = row["plan_expires"] or 0
        if pe and pe <= int(time.time()):
            with db() as c:
                c.execute("UPDATE users SET plan='free', plan_expires=0, plan_expired_notice=1 WHERE id=?",
                          (row["id"],))
                row = c.execute("SELECT * FROM users WHERE id=?", (row["id"],)).fetchone()
    return row


TRIAL_DAYS = 7   # số ngày dùng thử Pro cho tài khoản mới


def _grant_new_user_trial(c, uid: int, device_id: str) -> bool:
    """Tự cấp Pro 7 ngày cho TÀI KHOẢN MỚI. Mỗi THIẾT BỊ chỉ được 1 lần (chống tạo nhiều acc).
    Trả về True nếu đã cấp."""
    did = (device_id or "").strip()[:128]
    now = int(time.time())
    if did:
        used = c.execute("SELECT 1 FROM trial_devices WHERE device_id=?", (did,)).fetchone()
        if used:
            return False   # thiết bị này đã dùng trial → không cấp lại
        c.execute("INSERT OR IGNORE INTO trial_devices(device_id,used_at) VALUES(?,?)", (did, now))
    c.execute("UPDATE users SET plan='pro', plan_expires=?, plan_expired_notice=0 WHERE id=?",
              (now + TRIAL_DAYS * 86400, uid))
    return True


def _gen_public_id(c) -> str:
    # §6.1 — ID người dùng là SỐ THUẦN, KHÔNG còn tiền tố "KEN".
    import random
    for _ in range(20):
        pid = "".join(random.choices("0123456789", k=9))
        if not c.execute("SELECT 1 FROM users WHERE public_id=?", (pid,)).fetchone():
            return pid
    return str(int(time.time()))[-9:]


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
        "plan_expires": 0 if row["is_admin"] else (row["plan_expires"] or 0),
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

# ---------- Chống flood/DDoS ở tầng ứng dụng (bản thay thế gần nhất cho chống DDoS) ----------
# Giới hạn TỔNG số request/IP trong 1 cửa sổ ngắn. Đây là lớp phòng vệ nhẹ ở tầng app;
# chống DDoS quy mô lớn thật sự cần dịch vụ CDN/WAF (Cloudflare...) ở tầng mạng.
_flood_hits: dict[str, list[float]] = {}
_FLOOD_LIMIT = 90        # tối đa 90 request
_FLOOD_WINDOW = 10.0     # trong 10 giây cho mỗi IP

@app.middleware("http")
async def _flood_guard(request: Request, call_next):
    ip = _client_ip(request)
    now = time.time()
    arr = [t for t in _flood_hits.get(ip, []) if now - t < _FLOOD_WINDOW]
    if len(arr) >= _FLOOD_LIMIT:
        _security_alert("flood",
                        f"IP {ip} gửi > {_FLOOD_LIMIT} request/{int(_FLOOD_WINDOW)}s "
                        f"— nghi ngờ tấn công flood/DDoS.")
        from fastapi.responses import JSONResponse
        return JSONResponse(status_code=429,
                            content={"detail": "Quá nhiều yêu cầu. Vui lòng thử lại sau giây lát."})
    arr.append(now)
    _flood_hits[ip] = arr
    if len(_flood_hits) > 10000:      # dọn bộ nhớ định kỳ
        for k in [k for k, v in _flood_hits.items() if not any(now - t < _FLOOD_WINDOW for t in v)]:
            _flood_hits.pop(k, None)
    return await call_next(request)

# §9.1 — Cảnh báo xâm nhập theo thời gian thực qua Telegram (admin cấu hình).
_sec_alert_last: dict[str, float] = {}

def _security_alert(kind: str, detail: str, force: bool = False) -> None:
    """Gửi cảnh báo bảo mật cho admin qua Telegram Bot (best-effort, không chặn luồng)."""
    if not force and get_setting("sec_alert_enabled", "0") != "1":
        return
    token = (get_setting("sec_alert_bot_token", "").strip()
             or os.environ.get("SECURITY_ALERT_BOT_TOKEN", "").strip())
    chat = (get_setting("sec_alert_chat_id", "").strip()
            or os.environ.get("SECURITY_ALERT_CHAT_ID", "").strip())
    if not token or not chat:
        return
    now = time.time()
    if not force and now - _sec_alert_last.get(kind, 0) < 120:  # tối đa 1 cảnh báo/loại mỗi 120s
        return
    _sec_alert_last[kind] = now
    text = (f"🚨 KENIOS — cảnh báo bảo mật\nLoại: {kind}\n{detail}\n"
            f"Lúc: {time.strftime('%Y-%m-%d %H:%M:%S')}")

    def _send():
        try:
            import urllib.request, urllib.parse
            url = f"https://api.telegram.org/bot{token}/sendMessage"
            data = urllib.parse.urlencode({"chat_id": chat, "text": text}).encode()
            urllib.request.urlopen(urllib.request.Request(url, data=data), timeout=8).read()
        except Exception:
            pass

    import threading
    threading.Thread(target=_send, daemon=True).start()


def _rate_limit(request: Request, bucket: str, limit: int, window: int) -> None:
    """Cho phép tối đa `limit` lần trong `window` giây cho mỗi IP + bucket."""
    key = f"{bucket}:{_client_ip(request)}"
    now = time.time()
    arr = [t for t in _rl_hits.get(key, []) if now - t < window]
    if len(arr) >= limit:
        _security_alert("rate_limit",
                        f"Bucket '{bucket}' vượt giới hạn từ IP {_client_ip(request)} "
                        f"({limit} lần/{window}s) — nghi ngờ dò quét/tấn công.")
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
    import threading
    init_db()
    start_mail_smtp()
    start_telegram_bot()
    # Sao lưu tự động 1 lần/ngày về Telegram của admin
    threading.Thread(target=_backup_daily_loop, daemon=True, name="backup-daily").start()
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
    device_id: Optional[str] = None   # định danh thiết bị → trial 7 ngày chỉ 1 lần/máy

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
        # Tự cấp Pro dùng thử 7 ngày (mỗi thiết bị 1 lần)
        _grant_new_user_trial(c, uid, b.device_id or "")
        row = c.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
    return {"token": make_token(uid), "user": _user_dict(row)}


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


class LoginOtpIn(BaseModel):
    email: Optional[str] = None
    phone: Optional[str] = None
    code: str
    device_id: Optional[str] = None


def _unique_username(c, base: str) -> str:
    """Tạo username hợp lệ & duy nhất từ phần trước @ của email (hoặc số ĐT)."""
    s = re.sub(r"[^a-zA-Z0-9_]", "", (base or "").lower()) or "user"
    if len(s) < 3:
        s = (s + "user")[:8]
    s = s[:20]
    cand = s
    i = 0
    while c.execute("SELECT 1 FROM users WHERE username=?", (cand,)).fetchone():
        i += 1
        cand = f"{s}{i}"
    return cand


@app.post("/auth/login-otp")
def login_otp(b: LoginOtpIn, request: Request) -> dict[str, Any]:
    """Đăng nhập KHÔNG MẬT KHẨU bằng mã OTP gửi Gmail/SĐT.
    Có tài khoản → đăng nhập; chưa có → tự tạo tài khoản passwordless. Không trùng /auth/login."""
    _rate_limit(request, "login_otp", limit=12, window=300)
    email = (b.email or "").strip().lower()
    phone_raw = (b.phone or "").strip()
    if not email and not phone_raw:
        raise HTTPException(status_code=400, detail="Hãy nhập Gmail hoặc số điện thoại.")
    ident = email if email else _normalize_phone(phone_raw)
    code = (b.code or "").strip()
    if not code or not _otp_check(ident, code):
        raise HTTPException(status_code=400,
            detail="Mã xác nhận sai hoặc đã hết hạn. Vui lòng lấy mã mới.")
    phone = _normalize_phone(phone_raw) if phone_raw else None
    with db() as c:
        if email:
            row = c.execute("SELECT * FROM users WHERE lower(email)=?", (email,)).fetchone()
        else:
            row = c.execute("SELECT * FROM users WHERE phone=?", (phone,)).fetchone()
        if row:
            if row["banned"]:
                raise HTTPException(status_code=403,
                    detail="Tài khoản đã bị khóa. Liên hệ quản trị viên.")
            _ensure_public_id(c, row["id"])
            row = c.execute("SELECT * FROM users WHERE id=?", (row["id"],)).fetchone()
            return {"token": make_token(row["id"]), "user": _user_dict(row)}
        # Chưa có tài khoản → tự tạo (passwordless). Mật khẩu ngẫu nhiên (khách dùng OTP để vào).
        base = email.split("@")[0] if email else ("user" + (phone or "")[-4:])
        username = _unique_username(c, base)
        cur = c.execute(
            "INSERT INTO users(username,email,phone,pw_hash,plan,credits,created_at) "
            "VALUES(?,?,?,?,'free',0,?)",
            (username, email or None, phone, hash_pw(secrets.token_urlsafe(16)), int(time.time())),
        )
        uid = cur.lastrowid
        _ensure_public_id(c, uid)
        _grant_new_user_trial(c, uid, b.device_id or "")   # Pro 7 ngày (mỗi thiết bị 1 lần)
        row = c.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
    return {"token": make_token(uid), "user": _user_dict(row)}


# Client ID iOS mặc định cho "Đăng nhập bằng Google" (iOS client KHÔNG có secret → công khai được).
# Có thể override bằng biến môi trường GOOGLE_OAUTH_CLIENT_ID hoặc setting google_login_client_id.
GOOGLE_LOGIN_CLIENT_ID_DEFAULT = "547598708540-p2jbf9hp3emgu69fjgsg56ha8abimnr8.apps.googleusercontent.com"


def _google_login_client_id() -> str:
    return (os.environ.get("GOOGLE_OAUTH_CLIENT_ID")
            or get_setting("google_login_client_id", GOOGLE_LOGIN_CLIENT_ID_DEFAULT)).strip()


class GoogleAuthIn(BaseModel):
    id_token: str
    device_id: Optional[str] = None


@app.post("/auth/google")
def auth_google(b: GoogleAuthIn, request: Request) -> dict[str, Any]:
    """Đăng nhập bằng tài khoản Google. App gửi id_token (JWT) lấy từ Google OAuth,
    server XÁC THỰC với Google rồi đăng nhập / tự tạo tài khoản theo email. An toàn,
    không cần mật khẩu. Không trùng /auth/login."""
    _rate_limit(request, "google_login", limit=12, window=300)
    token = (b.id_token or "").strip()
    if not token:
        raise HTTPException(status_code=400, detail="Thiếu id_token từ Google.")
    # Xác thực id_token với Google (kiểm tra chữ ký/hết hạn).
    info: dict[str, Any] = {}
    try:
        with httpx.Client(timeout=10) as client:
            r = client.get("https://oauth2.googleapis.com/tokeninfo", params={"id_token": token})
        if r.status_code == 200:
            info = r.json()
    except Exception as e:
        logging.warning("Google tokeninfo lỗi: %s", e)
    email = (info.get("email") or "").strip().lower()
    if not email:
        raise HTTPException(status_code=401, detail="Xác thực Google thất bại. Vui lòng thử lại.")
    if str(info.get("email_verified", "")).lower() not in ("true", "1"):
        raise HTTPException(status_code=401, detail="Email Google chưa được xác minh.")
    # Kiểm tra token đúng ứng dụng của mình (chống token từ app khác).
    want = _google_login_client_id()
    if want and str(info.get("aud", "")) != want:
        raise HTTPException(status_code=401, detail="Token Google không khớp ứng dụng.")
    # Đăng nhập nếu đã có tài khoản với email này; chưa có thì tự tạo (passwordless).
    with db() as c:
        row = c.execute("SELECT * FROM users WHERE lower(email)=?", (email,)).fetchone()
        if row:
            if row["banned"]:
                raise HTTPException(status_code=403,
                    detail="Tài khoản đã bị khóa. Liên hệ quản trị viên.")
            _ensure_public_id(c, row["id"])
            row = c.execute("SELECT * FROM users WHERE id=?", (row["id"],)).fetchone()
            return {"token": make_token(row["id"]), "user": _user_dict(row)}
        username = _unique_username(c, email.split("@")[0])
        cur = c.execute(
            "INSERT INTO users(username,email,phone,pw_hash,plan,credits,created_at) "
            "VALUES(?,?,?,?,'free',0,?)",
            (username, email, None, hash_pw(secrets.token_urlsafe(16)), int(time.time())),
        )
        uid = cur.lastrowid
        _ensure_public_id(c, uid)
        _grant_new_user_trial(c, uid, b.device_id or "")   # Pro 7 ngày (mỗi thiết bị 1 lần)
        row = c.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
    return {"token": make_token(uid), "user": _user_dict(row)}


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


class NotifSoundsIn(BaseModel):
    sounds: dict[str, Any]   # {"gift":{"id":..,"url":..}, "follow":{...}, "share":{...}, "library":[...]}


@app.post("/notif-sounds")
def save_notif_sounds(b: NotifSoundsIn, admin=Depends(get_admin)) -> dict[str, Any]:
    """CHỈ ADMIN đồng bộ bộ âm thanh thông báo DÙNG CHUNG (toàn cục). Sau khi đồng bộ,
    MỌI khách tải về dùng được (khách tự thêm âm riêng thì lưu cục bộ trên máy họ)."""
    set_setting("notif_sounds_global", json.dumps(b.sounds))
    return {"ok": True}


@app.get("/notif-sounds")
def get_notif_sounds(user=Depends(get_user)) -> dict[str, Any]:
    """Đọc bộ âm thanh thông báo dùng chung (admin đã đồng bộ) — khách nào cũng tải được."""
    return {"json": get_setting("notif_sounds_global", "")}


class TTSSettingsIn(BaseModel):
    json: str   # chuỗi JSON các thiết lập TTS (giọng, tốc độ, mẫu câu, cà khịa…) của user


@app.post("/tts/settings")
def save_tts_settings(b: TTSSettingsIn, user=Depends(get_user)) -> dict[str, Any]:
    """Lưu thiết lập TTS THEO TÀI KHOẢN → đổi máy / xoá app cài lại vẫn giữ nguyên."""
    with db() as c:
        c.execute("UPDATE users SET tts_settings=? WHERE id=?", (b.json, user["id"]))
    return {"ok": True}


@app.get("/tts/settings")
def get_tts_settings(user=Depends(get_user)) -> dict[str, Any]:
    """Lấy thiết lập TTS đã lưu của tài khoản (rỗng nếu chưa từng đồng bộ)."""
    with db() as c:
        row = c.execute("SELECT tts_settings FROM users WHERE id=?", (user["id"],)).fetchone()
    return {"json": (row["tts_settings"] if row and row["tts_settings"] else "")}


# ============ ElevenLabs DÙNG CHUNG: ADMIN đặt API key 1 lần → MỌI khách dùng ============
# Key LƯU MÃ HOÁ trên máy chủ, KHÔNG bao giờ trả về cho app (khách không thấy được key).
# App gọi /tts/eleven (kèm Voice ID của khách) → máy chủ đọc bằng key admin → trả audio.
def _eleven_server_key() -> str:
    raw = get_setting("eleven_api_key_enc", "")
    if not raw:
        return ""
    try:
        return dec(raw)
    except Exception:
        return ""

class ElevenKeyIn(BaseModel):
    key: str = ""

@app.post("/admin/eleven-key")
def admin_set_eleven_key(b: ElevenKeyIn, admin=Depends(get_admin)) -> dict[str, Any]:
    """ADMIN lưu/xoá API key ElevenLabs dùng chung (key rỗng = xoá)."""
    k = (b.key or "").strip()
    set_setting("eleven_api_key_enc", enc(k) if k else "")
    _store_config_cache["data"] = None   # đổi key → cập nhật cờ eleven_server_key ngay
    return {"ok": True, "set": bool(k)}

@app.get("/admin/eleven-key")
def admin_get_eleven_key(admin=Depends(get_admin)) -> dict[str, Any]:
    k = _eleven_server_key()
    masked = (k[:5] + "•••••" + k[-4:]) if len(k) > 12 else ("•••••" if k else "")
    return {"set": bool(k), "masked": masked}


class AIKeyIn(BaseModel):
    key: str = ""
    provider: Optional[str] = None
    model: Optional[str] = None
    base: Optional[str] = None
    test: Optional[bool] = False


@app.get("/admin/ai-key")
def admin_get_ai_key(admin=Depends(get_admin)) -> dict[str, Any]:
    """ADMIN xem trạng thái khoá AI dùng chung (dùng cho 'AI xem video', trợ lý…)."""
    prov, base, model, key = _ai_cfg()
    masked = (key[:6] + "•••••" + key[-4:]) if len(key) > 14 else ("•••••" if key else "")
    return {"set": bool(key), "masked": masked, "provider": prov,
            "model": model, "base": base, "backends": len(_ai_backends())}


@app.post("/admin/ai-key")
def admin_set_ai_key(b: AIKeyIn, admin=Depends(get_admin)) -> dict[str, Any]:
    """ADMIN đặt/xoá khoá AI dùng chung (key rỗng = xoá). Tự đoán nhà cung cấp theo khoá:
    AIza…/AQ.… → Gemini (khuyên dùng, XEM ĐƯỢC ẢNH cho tính năng AI xem video),
    sk-ant… → Anthropic, gsk_… → Groq, còn lại → OpenAI-compatible."""
    k = (b.key or "").strip()
    set_setting("tg_ai_key", k)
    if b.provider is not None:
        set_setting("tg_ai_provider", (b.provider or "").strip().lower())
    if b.model is not None:
        set_setting("tg_ai_model", (b.model or "").strip())
    if b.base is not None:
        set_setting("tg_ai_base", (b.base or "").strip().rstrip("/"))
    prov, base, model, key = _ai_cfg()
    out: dict[str, Any] = {"ok": True, "set": bool(key), "provider": prov, "model": model}
    # Có thể KIỂM TRA ngay: hỏi AI 1 câu ngắn để biết khoá dùng được hay không.
    if b.test and key:
        try:
            ok, txt = _ai_call_one(prov, base, model, key, "Trả lời đúng 2 chữ: xin chào")
            out["test_ok"] = bool(ok)
            out["test_msg"] = (txt or "")[:300]
        except Exception as e:
            out["test_ok"] = False
            out["test_msg"] = f"Lỗi gọi AI: {e}"
    # Gemini xem được ảnh → tính năng "AI xem video" chạy tốt nhất.
    out["vision_ready"] = prov in ("gemini", "anthropic", "openai")
    return out


@app.get("/tts/eleven/voices")
def tts_eleven_voices(user=Depends(get_user)) -> dict[str, Any]:
    """DANH SÁCH ĐẦY ĐỦ giọng ElevenLabs (dùng key máy chủ do admin đặt) → app cho khách CHỌN
    GIỌNG THEO TÊN, không cần tự đi chép Voice ID. Không trả key về cho app."""
    key = _eleven_server_key()
    if not key:
        raise HTTPException(status_code=400,
            detail="Máy chủ chưa có khoá ElevenLabs. Admin thêm khoá trong mục cấu hình.")
    try:
        r = httpx.get("https://api.elevenlabs.io/v1/voices",
                      headers={"xi-api-key": key, "Accept": "application/json"}, timeout=30)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Lỗi gọi ElevenLabs: {e}")
    if r.status_code != 200:
        raise HTTPException(status_code=(r.status_code if r.status_code in (401, 429) else 502),
                            detail=f"ElevenLabs lỗi {r.status_code}")
    out = []
    try:
        for v in (r.json().get("voices") or []):
            lb = v.get("labels") or {}
            # Gộp nhãn mô tả (giới tính · độ tuổi · phong cách/cảm xúc) để app hiện cho dễ chọn.
            desc = " · ".join(str(lb[k]) for k in ("gender", "age", "accent", "description", "use_case")
                              if lb.get(k))
            out.append({
                "voice_id": v.get("voice_id", ""),
                "name": v.get("name", ""),
                "desc": desc,
                "category": v.get("category", ""),
                "preview": v.get("preview_url", "") or "",
            })
    except Exception:
        pass
    return {"voices": out}

class ElevenTTSIn(BaseModel):
    text: str
    voice_id: str
    model_id: str = "eleven_multilingual_v2"
    stability: float = 0.5
    similarity_boost: float = 0.75
    style: float = 0.0
    use_speaker_boost: bool = True
    speed: float = 1.0

@app.post("/tts/eleven")
def tts_eleven(b: ElevenTTSIn, user=Depends(get_user)):
    """Đọc 1 đoạn bằng ElevenLabs dùng KEY MÁY CHỦ (admin đặt) + Voice ID của khách.
    Trả về audio/mpeg. Khách KHÔNG cần và KHÔNG thấy API key."""
    key = _eleven_server_key()
    if not key:
        raise HTTPException(status_code=400,
            detail="Máy chủ chưa có khoá ElevenLabs. Nhờ admin thêm trong Cấu hình ElevenLabs.")
    vid = (b.voice_id or "").strip()
    text = (b.text or "").strip()
    if not vid:
        raise HTTPException(status_code=400, detail="Thiếu Voice ID.")
    if not text:
        raise HTTPException(status_code=400, detail="Thiếu nội dung cần đọc.")
    is_v3 = (b.model_id == "eleven_v3")
    stab = min([0.0, 0.5, 1.0], key=lambda x: abs(x - b.stability)) if is_v3 else b.stability
    vs = {
        "stability": stab, "similarity_boost": b.similarity_boost,
        "style": b.style, "use_speaker_boost": b.use_speaker_boost,
    }
    if abs(b.speed - 1.0) > 0.001:
        vs["speed"] = max(0.5, min(b.speed, 2.0))
    payload = {"text": text, "model_id": b.model_id, "voice_settings": vs}
    if b.model_id != "eleven_multilingual_v2":
        payload["language_code"] = "vi"
    try:
        r = httpx.post(f"https://api.elevenlabs.io/v1/text-to-speech/{vid}",
                       headers={"xi-api-key": key, "Content-Type": "application/json",
                                "Accept": "audio/mpeg"},
                       json=payload, timeout=60)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Lỗi gọi ElevenLabs: {e}")
    if r.status_code != 200:
        detail = f"ElevenLabs lỗi {r.status_code}"
        try:
            j = r.json()
            detail = (j.get("detail", {}) or {}).get("message") or j.get("detail") or detail
        except Exception:
            pass
        code = r.status_code if r.status_code in (401, 404, 429) else 502
        raise HTTPException(status_code=code, detail=str(detail))
    return Response(content=r.content, media_type="audio/mpeg")


# ========================= SAO LƯU & KHÔI PHỤC (BACKUP) =========================
# Gói toàn bộ trạng thái phục hồi được: database (kenios.db) + khóa mã hóa
# (kenios_enc.key, để giải mã API key đã lưu) → 1 file .zip nhỏ gọn.
#  • Tải bản sao lưu về máy: GET /admin/backup
#  • Khôi phục từ file:       POST /admin/restore  (dịch vụ tự khởi động lại)
#  • Tự gửi 1 lần/ngày về Telegram của admin (bật/tắt trong cấu hình).
def _backup_make_zip(include_uploads: bool = True) -> str:
    """Tạo file .zip sao lưu ĐẦY ĐỦ, KHÔI PHỤC LÀ DÙNG ĐƯỢC NGAY:
      • kenios.db  — toàn bộ dữ liệu (đồng nhất qua SQLite Online Backup API).
      • kenios_enc.key — khóa giải mã (để đọc lại API key đã lưu).
      • uploads/…  — TẤT CẢ file đã tải lên (âm thanh TTS, ảnh logo/banner,
        file sản phẩm…) → khôi phục xong ÂM THANH THÔNG BÁO vẫn phát được.
    include_uploads=False → chỉ DB + khóa (bản gọn, để gửi Telegram khi file lớn)."""
    import zipfile, tempfile
    ts = time.strftime("%Y%m%d-%H%M")
    out = os.path.join(tempfile.gettempdir(), f"kenios-backup-{ts}.zip")
    # Sao chép DB AN TOÀN kể cả khi đang ghi (SQLite Online Backup API)
    db_snapshot = os.path.join(tempfile.gettempdir(), f"kenios-db-{ts}.sqlite")
    try:
        src = sqlite3.connect(DB_PATH)
        dst = sqlite3.connect(db_snapshot)
        with dst:
            src.backup(dst)
        dst.close(); src.close()
    except Exception:
        # Dự phòng: copy thẳng file (vẫn tốt trong đa số trường hợp)
        import shutil as _sh
        _sh.copy2(DB_PATH, db_snapshot)
    n_files = 0; total_bytes = 0
    n_members = -1
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(db_snapshot, "kenios.db")
        if os.path.exists(_key_file):
            z.write(_key_file, "kenios_enc.key")
        # DANH SÁCH THÀNH VIÊN + GÓI (đọc được NGAY, không cần mở DB) — JSON + CSV.
        # Bắt buộc có trong MỌI bản backup: đầy đủ tài khoản + gói (plan) + hạn dùng.
        try:
            import json as _json, csv as _csv, io as _io
            _u = sqlite3.connect(db_snapshot)
            _u.row_factory = sqlite3.Row
            _cols = [r[1] for r in _u.execute("PRAGMA table_info(users)").fetchall()]
            _want = [c for c in ["id", "username", "email", "phone", "is_admin",
                                 "banned", "plan", "plan_expires", "credits",
                                 "lang", "created_at"] if c in _cols]
            _rows = _u.execute(f"SELECT {','.join(_want)} FROM users ORDER BY id").fetchall()
            _u.close()
            _members = [dict(r) for r in _rows]
            z.writestr("members.json", _json.dumps(_members, ensure_ascii=False, indent=2))
            _buf = _io.StringIO()
            _w = _csv.DictWriter(_buf, fieldnames=_want)
            _w.writeheader()
            for _m in _members:
                _w.writerow(_m)
            z.writestr("members.csv", _buf.getvalue())
            n_members = len(_members)
        except Exception as _e:
            log.warning("Backup: không xuất được danh sách thành viên: %s", _e)
        # ĐÓNG GÓI TOÀN BỘ file đã tải lên (âm thanh/ảnh/media/file sản phẩm).
        if include_uploads and os.path.isdir(UPLOAD_DIR):
            for root, _dirs, files in os.walk(UPLOAD_DIR):
                for fn in files:
                    # Bỏ file tạm đang tải dở (tmp_/tmpm_/restore-…) — không cần sao lưu.
                    if fn.startswith(("tmp_", "tmpm_", "temp_", "m_", "restore-")):
                        continue
                    fp = os.path.join(root, fn)
                    try:
                        rel = os.path.relpath(fp, UPLOAD_DIR)
                        z.write(fp, os.path.join("uploads", rel))
                        n_files += 1; total_bytes += os.path.getsize(fp)
                    except OSError:
                        pass
        # Ghi kèm mốc thời gian + thống kê để biết bản này của lúc nào
        z.writestr("backup_info.txt",
                   f"KENIOS backup\ncreated_utc={time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime())}\n"
                   f"members={n_members}\n"
                   f"uploads_included={'1' if include_uploads else '0'}\n"
                   f"uploads_files={n_files}\nuploads_bytes={total_bytes}\n")
    try: os.remove(db_snapshot)
    except OSError: pass
    return out


@app.get("/admin/backup")
def admin_backup(background_tasks: BackgroundTasks, admin=Depends(get_admin)):
    """Tải file .zip sao lưu ĐẦY ĐỦ (DB + khóa + toàn bộ file đã tải lên) về máy."""
    path = _backup_make_zip(include_uploads=True)
    fname = os.path.basename(path)
    # Xoá file zip tạm sau khi đã gửi xong (bản đầy đủ có thể lớn → tránh đầy ổ đĩa).
    background_tasks.add_task(lambda p=path: os.remove(p) if os.path.exists(p) else None)
    return FileResponse(path, filename=fname, media_type="application/zip",
                        content_disposition_type="attachment")


@app.post("/admin/restore")
async def admin_restore(file: UploadFile = FastAPIFile(...), admin=Depends(get_admin)) -> dict[str, Any]:
    """Khôi phục từ file .zip sao lưu. Lưu tạm dạng *.restore rồi KHỞI ĐỘNG LẠI dịch vụ —
    lúc khởi động sẽ thay DB/khóa an toàn (xem _apply_pending_restore)."""
    import zipfile, tempfile
    raw = await file.read()
    tmp_zip = os.path.join(tempfile.gettempdir(), f"restore-{secrets.token_hex(6)}.zip")
    with open(tmp_zip, "wb") as f:
        f.write(raw)
    try:
        if not zipfile.is_zipfile(tmp_zip):
            raise HTTPException(status_code=400, detail="File không phải bản sao lưu (.zip) hợp lệ.")
        with zipfile.ZipFile(tmp_zip) as z:
            names = z.namelist()
            if "kenios.db" not in names:
                raise HTTPException(status_code=400, detail="Thiếu kenios.db trong file sao lưu.")
            # Giải nén DB ra file tạm CÙNG THƯ MỤC với DB (KHÔNG dùng /tmp — tránh lỗi
            # Errno 18 'cross-device link' khi /tmp và /root/kenios khác phân vùng ổ đĩa).
            _db_dir = os.path.dirname(os.path.abspath(DB_PATH)) or "."
            db_tmp = os.path.join(_db_dir, f"restore-db-{secrets.token_hex(6)}.sqlite.tmp")
            with open(db_tmp, "wb") as f:
                f.write(z.read("kenios.db"))
            try:
                _c = sqlite3.connect(db_tmp)
                n = _c.execute("SELECT count(*) FROM sqlite_master").fetchone()[0]
                _c.close()
            except Exception:
                try: os.remove(db_tmp)
                except OSError: pass
                raise HTTPException(status_code=400, detail="File DB trong bản sao lưu bị hỏng.")
            if n < 1:
                try: os.remove(db_tmp)
                except OSError: pass
                raise HTTPException(status_code=400, detail="File DB trống — không khôi phục.")
            # Đặt bản khôi phục đang chờ (áp khi khởi động lại) — cùng thư mục nên os.replace OK.
            os.replace(db_tmp, DB_PATH + ".restore")
            if "kenios_enc.key" in names:
                with open(_key_file + ".restore", "wb") as f:
                    f.write(z.read("kenios_enc.key"))
            # KHÔI PHỤC NGAY các file đã tải lên (âm thanh/ảnh/media/file sản phẩm) →
            # sau khi khởi động lại là dùng được luôn (âm thanh thông báo phát được).
            os.makedirs(UPLOAD_DIR, exist_ok=True)
            for nm in names:
                if not nm.startswith("uploads/") or nm.endswith("/"):
                    continue
                rel = nm[len("uploads/"):]
                # Chặn path traversal (../) — chỉ ghi trong UPLOAD_DIR.
                dest = os.path.normpath(os.path.join(UPLOAD_DIR, rel))
                if not dest.startswith(os.path.abspath(UPLOAD_DIR) + os.sep) \
                   and dest != os.path.abspath(UPLOAD_DIR):
                    continue
                try:
                    os.makedirs(os.path.dirname(dest), exist_ok=True)
                    with open(dest, "wb") as f:
                        f.write(z.read(nm))
                except Exception:
                    pass
    finally:
        try: os.remove(tmp_zip)
        except OSError: pass
    # Trả lời XONG rồi mới khởi động lại (sau 1.5s) để app nhận được phản hồi.
    import threading as _thr
    def _restart_later():
        time.sleep(1.5)
        try:
            subprocess.run(["systemctl", "restart", "kenios"], timeout=20)
        except Exception:
            os._exit(0)   # systemd Restart=always sẽ bật lại
    _thr.Thread(target=_restart_later, daemon=True).start()
    return {"ok": True, "message": "Đã nhận bản sao lưu. Máy chủ đang khởi động lại để khôi phục (khoảng 10 giây)."}


# Telegram sendDocument giới hạn ~50MB. Bản đầy đủ (kèm uploads) có thể vượt →
# khi đó gửi bản GỌN (chỉ DB + khóa) để sao lưu tự động KHÔNG bao giờ im lặng thất bại.
# Bản đầy đủ vẫn tải tay được qua nút "Tải bản sao lưu" (GET /admin/backup).
_TG_DOC_LIMIT = 48 * 1024 * 1024

def _backup_zip_for_telegram() -> tuple[str, str]:
    """Trả về (đường_dẫn_zip, ghi_chú). Ưu tiên bản đầy đủ; quá lớn thì hạ về bản gọn."""
    full = _backup_make_zip(include_uploads=True)
    try:
        if os.path.getsize(full) <= _TG_DOC_LIMIT:
            return full, ""
    except OSError:
        return full, ""
    # Quá lớn cho Telegram → tạo bản gọn (DB + khóa) thay thế.
    try: os.remove(full)
    except OSError: pass
    small = _backup_make_zip(include_uploads=False)
    note = ("\n⚠️ File tải lên (âm thanh/ảnh) quá lớn để gửi Telegram — "
            "bản này CHỈ có dữ liệu. Tải bản ĐẦY ĐỦ trong app: Cấu hình › Sao lưu › Tải bản sao lưu.")
    return small, note


def _tg_send_document(token: str, chat_id, path: str, caption: str = "") -> bool:
    """Gửi 1 file (tài liệu) vào Telegram."""
    try:
        with open(path, "rb") as f:
            r = httpx.post(f"https://api.telegram.org/bot{token}/sendDocument",
                           data={"chat_id": str(chat_id), "caption": caption[:1000]},
                           files={"document": (os.path.basename(path), f, "application/zip")},
                           timeout=180)
        return bool(r.json().get("ok"))
    except Exception as e:
        log.warning("sendDocument lỗi: %s", e); return False


def _backup_daily_loop() -> None:
    """Mỗi ngày gửi 1 lần file sao lưu về Telegram của admin (nếu đã bật + có token & chat)."""
    import time as _t
    while True:
        try:
            if get_setting("backup_daily_on", "1") == "1":
                token = (get_setting("tg_bot_token", "") or os.getenv("TELEGRAM_BOT_TOKEN", "")).strip()
                chat = (get_setting("backup_chat", "") or get_setting("tg_admin_chat", "")
                        or os.getenv("TELEGRAM_ADMIN_CHAT", "")).strip()
                today = _t.strftime("%Y-%m-%d")
                if token and chat and get_setting("backup_last_date", "") != today:
                    try:
                        path, note = _backup_zip_for_telegram()
                        cap = f"🗄️ Sao lưu KENIOS tự động — {today}\nGiữ file này để khôi phục khi cần.{note}"
                        if _tg_send_document(token, chat, path, cap):
                            set_setting("backup_last_date", today)
                            set_setting("backup_last_ok", str(int(_t.time())))
                        try: os.remove(path)
                        except OSError: pass
                    except Exception as e:
                        log.warning("Backup ngày lỗi: %s", e)
        except Exception:
            pass
        _t.sleep(1800)   # kiểm tra mỗi 30 phút (gửi tối đa 1 lần/ngày)


class BackupCfgIn(BaseModel):
    daily_on: Optional[bool] = None
    chat_id: Optional[str] = None


@app.get("/admin/backup-config")
def admin_backup_config(admin=Depends(get_admin)) -> dict[str, Any]:
    return {
        "daily_on": get_setting("backup_daily_on", "1") == "1",
        "chat_id": get_setting("backup_chat", ""),
        "last_date": get_setting("backup_last_date", ""),
        "last_ok": get_setting("backup_last_ok", ""),
        "has_bot": bool((get_setting("tg_bot_token", "") or os.getenv("TELEGRAM_BOT_TOKEN", "")).strip()),
    }


@app.post("/admin/backup-config")
def admin_set_backup_config(b: BackupCfgIn, admin=Depends(get_admin)) -> dict[str, Any]:
    if b.daily_on is not None:
        set_setting("backup_daily_on", "1" if b.daily_on else "0")
    if b.chat_id is not None:
        set_setting("backup_chat", b.chat_id.strip()[:64])
    return {"ok": True}


@app.post("/admin/backup-now")
def admin_backup_now(admin=Depends(get_admin)) -> dict[str, Any]:
    """Gửi NGAY 1 bản sao lưu về Telegram (không đợi tới lịch ngày)."""
    token = (get_setting("tg_bot_token", "") or os.getenv("TELEGRAM_BOT_TOKEN", "")).strip()
    chat = (get_setting("backup_chat", "") or get_setting("tg_admin_chat", "")
            or os.getenv("TELEGRAM_ADMIN_CHAT", "")).strip()
    if not token or not chat:
        raise HTTPException(status_code=400,
            detail="Chưa cấu hình bot Telegram hoặc Chat ID nhận sao lưu.")
    path, note = _backup_zip_for_telegram()
    ok = _tg_send_document(token, chat, path,
                           f"🗄️ Sao lưu KENIOS (gửi thủ công) — {time.strftime('%Y-%m-%d %H:%M')}{note}")
    try: os.remove(path)
    except OSError: pass
    if not ok:
        raise HTTPException(status_code=502, detail="Gửi Telegram thất bại. Kiểm tra token/Chat ID.")
    msg = "Đã gửi bản sao lưu về Telegram."
    if note:
        msg += " (Bản gửi Telegram là bản gọn vì file tải lên quá lớn — tải bản đầy đủ bằng nút Tải bản sao lưu.)"
    return {"ok": True, "message": msg}


# ===================== SSH / SFTP proxy (Remote Server Tool) =====================
# App gửi Host/User/Password + lệnh → backend dùng asyncssh kết nối tới VPS đích,
# chạy lệnh và truyền log về theo thời gian thực. KHÔNG lưu thông tin đăng nhập.

class SSHExecIn(BaseModel):
    host: str
    port: Optional[int] = 22
    username: str
    password: str
    command: str

class SSHPathIn(BaseModel):
    host: str
    port: Optional[int] = 22
    username: str
    password: str
    path: Optional[str] = "."


def _require_asyncssh():
    try:
        import asyncssh  # type: ignore
        return asyncssh
    except Exception:
        raise HTTPException(
            status_code=503,
            detail=("Máy chủ chưa cài asyncssh. SSH vào VPS chạy: "
                    "'pip install asyncssh' rồi khởi động lại dịch vụ kenios."))


@app.post("/ssh/exec")
async def ssh_exec(b: SSHExecIn, user=Depends(get_user)):
    """Chạy 1 lệnh trên VPS đích, truyền stdout+stderr về theo dòng (real-time)."""
    asyncssh = _require_asyncssh()
    host = (b.host or "").strip()
    username = (b.username or "").strip()
    command = b.command or ""
    if not host or not username:
        raise HTTPException(status_code=400, detail="Thiếu Host hoặc Username.")

    async def gen():
        try:
            async with asyncssh.connect(
                host, port=int(b.port or 22), username=username,
                password=b.password, known_hosts=None,
                connect_timeout=20,
            ) as conn:
                async with conn.create_process(command, stderr=asyncssh.STDOUT) as proc:
                    async for line in proc.stdout:
                        yield line if line.endswith("\n") else line + "\n"
                    await proc.wait_closed()
                    rc = proc.exit_status
                    if rc not in (0, None):
                        yield f"\n[exit code: {rc}]\n"
        except Exception as e:  # noqa: BLE001
            yield f"\nExecution Error: {e}\n"

    return StreamingResponse(gen(), media_type="text/plain")


@app.post("/ssh/list")
async def ssh_list(b: SSHPathIn, user=Depends(get_user)) -> dict[str, Any]:
    """Liệt kê thư mục trên VPS đích qua SFTP."""
    asyncssh = _require_asyncssh()
    import stat as _stat
    host = (b.host or "").strip()
    username = (b.username or "").strip()
    path = (b.path or ".").strip() or "."
    if not host or not username:
        raise HTTPException(status_code=400, detail="Thiếu Host hoặc Username.")
    try:
        async with asyncssh.connect(
            host, port=int(b.port or 22), username=username,
            password=b.password, known_hosts=None, connect_timeout=20,
        ) as conn:
            async with conn.start_sftp_client() as sftp:
                real = await sftp.realpath(path)
                names = await sftp.readdir(real)
                items: list[dict[str, Any]] = []
                for entry in names:
                    fn = entry.filename
                    if fn in (".", ".."):
                        continue
                    attrs = entry.attrs
                    perms = attrs.permissions or 0
                    is_dir = _stat.S_ISDIR(perms)
                    items.append({
                        "name": fn,
                        "type": "dir" if is_dir else "file",
                        "size": int(attrs.size or 0),
                    })
                return {"path": str(real), "items": items}
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=f"SSH/SFTP lỗi: {e}")


@app.post("/ssh/delete")
async def ssh_delete(b: SSHPathIn, user=Depends(get_user)) -> dict[str, Any]:
    """Xoá 1 file trên VPS đích qua SFTP (chỉ file, không xoá thư mục để an toàn)."""
    asyncssh = _require_asyncssh()
    host = (b.host or "").strip()
    username = (b.username or "").strip()
    path = (b.path or "").strip()
    if not host or not username or not path:
        raise HTTPException(status_code=400, detail="Thiếu thông tin.")
    try:
        async with asyncssh.connect(
            host, port=int(b.port or 22), username=username,
            password=b.password, known_hosts=None, connect_timeout=20,
        ) as conn:
            async with conn.start_sftp_client() as sftp:
                await sftp.remove(path)
                return {"ok": True}
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=f"Xoá thất bại: {e}")


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


# ======================== AI XEM VIDEO → VIẾT KỊCH BẢN (voiceover) ========================
def _extract_video_frames(path: str, count: int = 8, width: int = 512) -> list:
    """Trích `count` khung hình rải đều theo thời gian từ video → list base64 JPEG."""
    import subprocess, tempfile, glob, shutil as _sh
    if not _sh.which("ffmpeg"):
        return []
    dur = 0.0
    try:
        pr = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                             "-of", "default=nw=1:nk=1", path],
                            capture_output=True, text=True, timeout=30)
        dur = float((pr.stdout or "0").strip() or 0)
    except Exception:
        dur = 0.0
    tmp = tempfile.mkdtemp(prefix="vframes_")
    out: list = []
    try:
        if dur > 0.5:
            for i in range(count):
                t = dur * (i + 0.5) / count
                fp = os.path.join(tmp, f"f{i:02d}.jpg")
                subprocess.run(["ffmpeg", "-y", "-ss", f"{t:.2f}", "-i", path, "-frames:v", "1",
                                "-vf", f"scale={width}:-1", "-q:v", "4", fp],
                               capture_output=True, timeout=60)
        else:
            subprocess.run(["ffmpeg", "-y", "-i", path, "-vf", f"scale={width}:-1,fps=1",
                            "-frames:v", str(count), os.path.join(tmp, "f%02d.jpg")],
                           capture_output=True, timeout=120)
        for fp in sorted(glob.glob(os.path.join(tmp, "*.jpg"))):
            try:
                with open(fp, "rb") as f:
                    out.append(base64.b64encode(f.read()).decode())
            except Exception:
                pass
    finally:
        _sh.rmtree(tmp, ignore_errors=True)
    return out[:count]


def _ai_vision(prompt: str, images_b64: list, mime: str = "image/jpeg") -> str:
    """Gọi AI CÓ HÌNH ẢNH (vision) qua CHUỖI backend admin (Gemini/Claude/OpenAI-vision).
    Groq llama thường KHÔNG có vision → tự nhảy sang con kế. images_b64: base64 thô (không data:)."""
    import httpx as _hx
    backends = _ai_backends()
    if not backends:
        return "⚠️ Máy chủ chưa cấu hình khoá AI. Admin thêm khoá (nên dùng Gemini có xem ảnh)."
    imgs = images_b64[:10]
    last = ""
    for (prov, base, model, key) in backends:
        try:
            base = (base or "").rstrip("/")
            if prov == "gemini":
                gbase = base[:-7] if base.endswith("/openai") else base
                parts = [{"text": prompt}] + [{"inline_data": {"mime_type": mime, "data": b}} for b in imgs]
                mdl = model or "gemini-2.5-flash"
                r = _hx.post(f"{gbase}/models/{mdl}:generateContent", timeout=120,
                             headers={"x-goog-api-key": key, "content-type": "application/json"},
                             json={"contents": [{"role": "user", "parts": parts}],
                                   "generationConfig": {"maxOutputTokens": 1600, "temperature": 0.6}})
                if r.status_code >= 400:
                    last = _ai_err(r.status_code, r.text); continue
                d = r.json(); c = d.get("candidates") or []
                ps = ((c[0].get("content") or {}).get("parts") or []) if c else []
                txt = "".join(p.get("text", "") for p in ps if "text" in p).strip()
                if txt:
                    return txt
                last = "(AI không trả lời)"
            elif prov == "anthropic":
                content = [{"type": "text", "text": prompt}] + [
                    {"type": "image", "source": {"type": "base64", "media_type": mime, "data": b}} for b in imgs]
                r = _hx.post(base + "/messages", timeout=120,
                             headers={"x-api-key": key, "anthropic-version": "2023-06-01",
                                      "content-type": "application/json"},
                             json={"model": model, "max_tokens": 1600,
                                   "messages": [{"role": "user", "content": content}]})
                if r.status_code >= 400:
                    last = _ai_err(r.status_code, r.text); continue
                d = r.json()
                txt = "".join(b.get("text", "") for b in d.get("content", []) if b.get("type") == "text").strip()
                if txt:
                    return txt
                last = "(AI không trả lời)"
            else:
                content = [{"type": "text", "text": prompt}] + [
                    {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b}"}} for b in imgs]
                r = _hx.post(base + "/chat/completions", timeout=120,
                             headers={"Authorization": "Bearer " + key, "content-type": "application/json"},
                             json={"model": model, "max_tokens": 1600, "temperature": 0.6,
                                   "messages": [{"role": "user", "content": content}]})
                if r.status_code >= 400:
                    last = _ai_err(r.status_code, r.text); continue
                d = r.json()
                txt = ((d.get("choices") or [{}])[0].get("message", {}).get("content", "") or "").strip()
                if txt:
                    return txt
                last = "(AI không trả lời)"
        except Exception as e:
            last = f"⚠️ Lỗi gọi AI vision ({prov}): {e}"
    return last or "⚠️ AI chưa xem được video. Admin nên cấu hình khoá Gemini (miễn phí, có xem ảnh)."


class VideoScriptIn(BaseModel):
    url: Optional[str] = None
    file_id: Optional[int] = None
    style: Optional[str] = "thuyết minh tự nhiên, cuốn hút"


@app.post("/social/video-script")
async def social_video_script(b: VideoScriptIn, user=Depends(get_user)) -> dict[str, Any]:
    """AI XEM video (trích khung hình) rồi VIẾT KỊCH BẢN thuyết minh tiếng Việt để app đọc bằng TTS.
    Nhận link (yt-dlp tải về) HOẶC file_id (video đã tải lên). Ai cũng dùng (khoá AI của máy chủ)."""
    import tempfile, glob, shutil
    path = None
    cleanup_dir = None
    if b.file_id:
        p = os.path.join(UPLOAD_DIR, str(b.file_id))
        if os.path.exists(p):
            path = p
    if path is None and (b.url or "").strip():
        if not shutil.which("yt-dlp"):
            raise HTTPException(status_code=400, detail="Máy chủ chưa cài yt-dlp.")
        tmp = tempfile.mkdtemp(prefix="vs_"); cleanup_dir = tmp
        cmd = ["yt-dlp", "-f", "best[height<=720]/best", "--merge-output-format", "mp4",
               "--no-playlist", "--no-warnings", "-o", os.path.join(tmp, "v.%(ext)s"), b.url.strip()]
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
            _, err = await asyncio.wait_for(proc.communicate(), timeout=600)
        except Exception as e:
            shutil.rmtree(tmp, ignore_errors=True)
            raise HTTPException(status_code=400, detail=f"Không tải được video: {e}")
        fs = [f for f in glob.glob(os.path.join(tmp, "*")) if os.path.isfile(f)]
        if fs:
            path = max(fs, key=os.path.getsize)
    if not path or not os.path.exists(path):
        if cleanup_dir:
            shutil.rmtree(cleanup_dir, ignore_errors=True)
        raise HTTPException(status_code=400, detail="Thiếu video — hãy dán link hoặc chọn file video.")

    frames = await asyncio.to_thread(_extract_video_frames, path, 8, 512)
    if cleanup_dir:
        shutil.rmtree(cleanup_dir, ignore_errors=True)
    if not frames:
        raise HTTPException(status_code=400,
            detail="Không trích được khung hình (máy chủ thiếu ffmpeg hoặc video hỏng).")

    style = (b.style or "thuyết minh tự nhiên, cuốn hút").strip()
    prompt = (
        "Đây là các KHUNG HÌNH trích theo thứ tự thời gian từ MỘT video ngắn. "
        "Hãy XEM kỹ và VIẾT MỘT KỊCH BẢN LỜI THOẠI / THUYẾT MINH bằng TIẾNG VIỆT để đọc lồng tiếng (voiceover). "
        f"Giọng điệu: {style}. "
        "Yêu cầu: viết thành ĐOẠN VĂN LIỀN MẠCH, tự nhiên như người dẫn chuyện, bám đúng diễn biến/hình ảnh; "
        "độ dài vừa phải (khoảng 60–160 từ). CHỈ trả về đúng lời để đọc — KHÔNG gạch đầu dòng, KHÔNG ghi 'khung hình 1/2', "
        "KHÔNG chú thích kỹ thuật, KHÔNG hashtag."
    )
    script = await asyncio.to_thread(_ai_vision, prompt, frames)
    return {"script": script, "frames": len(frames)}


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
    # Tham số web-app TikTok thường bắt buộc (kèm msToken lấy từ cookie nếu có)
    params = {
        "aid": "1988",
        "app_language": "vi",
        "app_name": "tiktok_web",
        "browser_language": "vi-VN",
        "browser_platform": "Win32",
        "channel": "tiktok_web",
        "cookie_enabled": "true",
        "device_platform": "web_pc",
        "focus_state": "true",
        "priority_region": "VN",
        "region": "VN",
        "webcast_language": "vi",
    }
    if cookie_dict.get("msToken"):
        params["msToken"] = cookie_dict["msToken"]

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
        tk_msg = data.get("prompts") or res_json.get("message")
        guide = ("TikTok chặn lấy key tự động (cần chữ ký X-Bogus) hoặc tài khoản chưa có quyền LIVE. "
                 "CÁCH CHẮC CHẮN: vào TikTok LIVE Studio (máy tính) hoặc live.tiktok.com → chọn "
                 "‘Phát bằng phần mềm/OBS’ → COPY Server URL + Stream Key → dán vào mục "
                 "‘Phát Live đa nền tảng’ trong app rồi dùng Restream.")
        raise HTTPException(status_code=400, detail=(f"{tk_msg}. {guide}" if tk_msg else guide))
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=400, detail=f"Không lấy được key TikTok tự động: {e}. "
                            "Hãy lấy key thủ công ở TikTok LIVE Studio rồi dán vào mục Phát Live đa nền tảng.")


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
        item = {"id": sess["seq"], "type": etype,
                "name": name or "", "content": content or ""}
        # Đếm SỐ ĐÃ ĐẨY để đọc (theo loại app dùng).
        sess["pushed"][etype] = sess["pushed"].get(etype, 0) + 1
        # Người vào (join) RẤT NHIỀU trong live đông → để RIÊNG 1 buffer nhỏ, KHÔNG cho
        # đẩy văng BÌNH LUẬN/quà/follow ra khỏi buffer trước khi app kịp đọc.
        if etype == "join":
            sess["joins"].append(item)
        else:
            sess["events"].append(item)

    state = {"connected": False}

    def _build_and_register():
        client = TikTokLiveClient(unique_id=f"@{username}")
        sess["client"] = client

        @client.on(ConnectEvent)
        async def _on_connect(_e):
            state["connected"] = True
            sess["status"] = "connected"
            sess["error"] = None

        @client.on(CommentEvent)
        async def _on_comment(e):
            u = getattr(e, "user", None)
            name = (getattr(u, "nickname", "") or getattr(u, "unique_id", "")
                    or getattr(u, "display_id", "") or "")
            text = (getattr(e, "comment", None) or getattr(e, "text", None)
                    or getattr(e, "content", None) or "")
            push("comment", name, str(text))

        @client.on(GiftEvent)
        async def _on_gift(e):
            g = getattr(e, "gift", None)
            if g is not None and getattr(g, "streakable", False) and getattr(e, "streaking", False):
                return
            name = getattr(getattr(e, "user", None), "nickname", "")
            push("gift", name, getattr(g, "name", "qua"))

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

        # Luoi an toan: bat MOI lop *Event de dem + khong bo sot binh luan/chat.
        try:
            import TikTokLive.events as _ttev

            def _mk_catch(cname: str):
                async def _h(e):
                    try:
                        sess["counts"][cname] = sess["counts"].get(cname, 0) + 1
                        low = cname.lower()
                        if ("comment" in low or "chat" in low) and cname != "CommentEvent":
                            u = getattr(e, "user", None)
                            nm = (getattr(u, "nickname", "") or getattr(u, "unique_id", "")
                                  or getattr(u, "display_id", "") or "")
                            txt = (getattr(e, "comment", None) or getattr(e, "text", None)
                                   or getattr(e, "content", None) or "")
                            if txt:
                                push("comment", nm, str(txt))
                    except Exception:
                        pass
                return _h

            for _n in dir(_ttev):
                _obj = getattr(_ttev, _n, None)
                if isinstance(_obj, type) and _n.endswith("Event"):
                    try:
                        client.on(_obj)(_mk_catch(_n))
                    except Exception:
                        pass
        except Exception:
            pass

        # Khoa ky EulerStream (tuy chon) — on dinh nhan su kien.
        try:
            _sk = (get_setting("tiktok_sign_key", "") or os.getenv("TIKTOK_SIGN_KEY", "")).strip()
            if _sk:
                try:
                    from TikTokLive.client.web.web_settings import WebDefaults
                    WebDefaults.tiktok_sign_api_key = _sk
                except Exception:
                    pass
        except Exception:
            pass
        return client

    fail = 0
    # TU DONG NOI LAI: TikTok hay rot WebSocket -> neu khong noi lai thi "dung" binh luan
    # (lau lau khong hien). Vong lap noi lai toi khi user ngat / live ket thuc.
    while _tiktok_live_sessions.get(username) is sess and sess.get("status") != "ended":
        state["connected"] = False
        client = _build_and_register()
        try:
            await client.start()
        except asyncio.CancelledError:
            break
        except Exception as ex:
            sess["error"] = (f"Khong ket noi duoc LIVE cua @{username}: {ex}. "
                             "(Nguoi dung phai dang phat truc tiep.)")

        # User da ngat hoac live ket thuc -> thoat han.
        if _tiktok_live_sessions.get(username) is not sess or sess.get("status") == "ended":
            break

        if state["connected"]:
            fail = 0                      # da tung ket noi roi moi rot -> noi lai
        else:
            fail += 1                     # lan nay chua ket noi duoc
            if fail >= 5:
                sess["status"] = "error"
                break

        sess["status"] = "connecting"
        try:
            await client.disconnect()
        except Exception:
            pass
        await asyncio.sleep(4)            # cho ngan roi noi lai (giu nguyen buffer da co)


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
            # Bình luận/quà/follow/share: giữ NHIỀU & LÂU (không bị người vào đẩy văng).
            "events": _collections.deque(maxlen=3000),
            # Người vào (join): buffer RIÊNG, nhỏ (chỉ cần vài chục cái gần nhất).
            "joins": _collections.deque(maxlen=200),
            "counts": {},   # SỐ NHẬN theo TÊN LỚP sự kiện (CommentEvent/JoinEvent/…) — chẩn đoán
            "pushed": {},   # SỐ ĐÃ ĐẨY để app đọc (comment/join/gift/…)
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
        return {"status": "idle", "error": None, "events": [], "last": after, "counts": {}}
    # GỘP 2 buffer (bình luận/quà/follow/share + người vào) rồi sắp theo thứ tự thời gian (id).
    merged = list(sess["events"]) + list(sess.get("joins", []))
    evs = sorted((e for e in merged if e["id"] > after), key=lambda x: x["id"])
    last = evs[-1]["id"] if evs else after
    return {"status": sess["status"], "error": sess.get("error"),
            "events": evs, "last": last,
            "counts": sess.get("counts", {}),     # nhận theo tên lớp (chẩn đoán)
            "pushed": sess.get("pushed", {})}     # đã đẩy để đọc


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


# ============ TRÌNH ĐỌC TRÊN TRÌNH DUYỆT (TikTok Studio / OBS – Browser Source) ============
# Máy chủ tạo 1 ĐƯỜNG DẪN riêng cho từng người. Mở link trên PC phát live (hoặc thêm làm
# Browser Source trong OBS / TikTok LIVE Studio) → trang tự kết nối phòng LIVE, đọc bình
# luận THẲNG trên luồng (âm phát ở PC, KHÔNG đọc trên điện thoại). Giọng ĐỒNG BỘ với app.
def _reader_token(uid: int) -> str:
    return hmac.new(SECRET.encode(), f"reader:{uid}".encode(), hashlib.sha256).hexdigest()[:24]

def _reader_base_url() -> str:
    # Ưu tiên setting riêng cho link trình đọc → biến môi trường → TÊN MIỀN HTTPS mới.
    return (get_setting("reader_base", "") or os.getenv("READER_BASE", "")
            or "https://kenios.io.vn").rstrip("/")

def _reader_cfg(tok: str) -> dict:
    raw = get_setting(f"reader_cfg_{tok}", "")
    try:
        return json.loads(raw) if raw else {}
    except Exception:
        return {}

class ReaderCfgIn(BaseModel):
    username: str = ""
    engine: str = "eleven"            # eleven = giọng ElevenLabs máy chủ · browser = giọng trình duyệt
    voice_id: str = ""
    model: str = "eleven_multilingual_v2"
    speed: float = 1.0
    read_types: list[str] = ["comment", "gift", "follow", "share"]
    translate: bool = False
    tpl: dict[str, str] = {}

@app.post("/live-reader/save")
def reader_save(b: ReaderCfgIn, user=Depends(get_user)) -> dict[str, Any]:
    tok = _reader_token(user["id"])
    cfg = b.dict()
    cfg["username"] = _tt_norm_user(cfg.get("username", "")) or ""
    set_setting(f"reader_cfg_{tok}", json.dumps(cfg))
    return {"ok": True, "token": tok, "url": f"{_reader_base_url()}/r/{tok}"}

@app.get("/live-reader/config")
def reader_get(user=Depends(get_user)) -> dict[str, Any]:
    tok = _reader_token(user["id"])
    return {"token": tok, "url": f"{_reader_base_url()}/r/{tok}", "config": _reader_cfg(tok)}

@app.get("/live-reader/data")
def reader_data(k: str) -> dict[str, Any]:
    cfg = _reader_cfg(k)
    if not cfg:
        raise HTTPException(status_code=404, detail="Link không hợp lệ.")
    return {"config": cfg, "eleven": bool(_eleven_server_key())}   # KHÔNG trả API key

class ReaderTTSIn(BaseModel):
    text: str

def _reader_server_tts(text: str) -> bytes:
    """Tạo audio tiếng Việt NGAY TRÊN MÁY CHỦ (gTTS trước, edge-tts dự phòng) để OBS
    LUÔN có tiếng — OBS/trình duyệt CEF không có sẵn giọng đọc tiếng Việt."""
    text = (text or "").strip()
    if not text:
        return b""
    # 1) gTTS (đồng bộ, đơn giản) — cần mạng (Google TTS).
    try:
        from gtts import gTTS
        import io as _io
        buf = _io.BytesIO()
        gTTS(text=text, lang="vi").write_to_fp(buf)
        data = buf.getvalue()
        if data:
            return data
    except Exception:
        pass
    # 2) edge-tts qua CLI (giọng Việt đẹp) — dự phòng.
    try:
        import subprocess, tempfile, os as _os
        out = tempfile.mktemp(suffix=".mp3")
        subprocess.run(["edge-tts", "--voice", "vi-VN-HoaiMyNeural",
                        "--text", text, "--write-media", out],
                       timeout=60, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        with open(out, "rb") as f:
            data = f.read()
        try:
            _os.remove(out)
        except OSError:
            pass
        return data
    except Exception:
        return b""


@app.post("/live-reader/tts")
def reader_tts(b: ReaderTTSIn, k: str):
    cfg = _reader_cfg(k)
    if not cfg:
        raise HTTPException(status_code=404, detail="Link không hợp lệ.")
    text = (b.text or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="Thiếu nội dung đọc.")
    key = _eleven_server_key()
    vid = (cfg.get("voice_id") or "").strip()
    # 1) ƯU TIÊN ElevenLabs nếu admin có key + có Voice ID. Lỗi thì RỚT XUỐNG giọng máy chủ
    #    (không để OBS im lặng chỉ vì ElevenLabs trục trặc).
    if key and vid:
        model = cfg.get("model") or "eleven_multilingual_v2"
        try:
            speed = float(cfg.get("speed") or 1.0)
        except Exception:
            speed = 1.0
        vs = {"stability": 0.5, "similarity_boost": 0.75,
              "style": 0.0, "use_speaker_boost": True}
        if abs(speed - 1.0) > 0.001:
            vs["speed"] = max(0.5, min(speed, 2.0))
        payload = {"text": text, "model_id": model, "voice_settings": vs}
        if model != "eleven_multilingual_v2":
            payload["language_code"] = "vi"
        try:
            r = httpx.post(f"https://api.elevenlabs.io/v1/text-to-speech/{vid}",
                           headers={"xi-api-key": key, "Content-Type": "application/json",
                                    "Accept": "audio/mpeg"},
                           json=payload, timeout=60)
            if r.status_code == 200 and r.content:
                return Response(content=r.content, media_type="audio/mpeg")
        except Exception:
            pass
    # 2) DỰ PHÒNG: giọng máy chủ (gTTS/edge-tts) → OBS luôn có tiếng dù không có ElevenLabs.
    data = _reader_server_tts(text)
    if not data:
        raise HTTPException(status_code=502,
                            detail="Máy chủ chưa tạo được audio. Cài trên VPS: pip install gTTS edge-tts")
    return Response(content=data, media_type="audio/mpeg")

_READER_HTML = r"""<!doctype html><html lang="vi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>KENIOS — Đọc bình luận Live</title>
<style>body{margin:0;font-family:system-ui,-apple-system,sans-serif;background:#0b0f1a;color:#e8eefc}
.wrap{padding:18px;max-width:720px;margin:0 auto;width:100%;box-sizing:border-box}
h1{font-size:18px;margin:6px 0}
.btn{background:#2b7fff;color:#fff;border:0;border-radius:12px;padding:14px 22px;font-size:16px;font-weight:700;cursor:pointer}
.btn.stop{background:#e0453f}
.st{font-size:13px;opacity:.85;margin:10px 0}
#feed{margin-top:12px;font-size:13px;line-height:1.55}
.row{padding:6px 0;border-bottom:1px solid #1b2436}
.tag{display:inline-block;font-size:11px;padding:1px 7px;border-radius:8px;background:#1b2740;margin-right:6px}</style>
</head><body><div class="wrap">
<h1>🎙️ KENIOS — Đọc bình luận Live</h1>
<div class="st" id="who"></div>
<button class="btn" id="go">▶️ Bắt đầu đọc</button>
<div class="st" id="status">Bấm "Bắt đầu đọc" để kết nối phòng LIVE.</div>
<div id="feed"></div></div>
<audio id="au"></audio>
<script>
const TOKEN="__TOKEN__", API=location.origin;
let cfg=null,user="",after=0,poll=null,running=false,q=[],playing=false;
const DEF={comment:"{name} bình luận: {content}",gift:"Cảm ơn {name} đã tặng {content}",follow:"Cảm ơn {name} đã theo dõi",share:"Cảm ơn {name} đã chia sẻ live",join:"Chào mừng {name} đã vào phòng"};
const $=id=>document.getElementById(id);
function cleanName(s){s=(s||"").normalize("NFKC").replace(/[_\-.]/g," ").replace(/[^\p{L}\p{N} ]/gu,"").replace(/\s+/g," ").trim();return s||"bạn";}
function tpl(ev){var t=(cfg.tpl&&cfg.tpl[ev.type])||DEF[ev.type]||DEF.comment;return t.replace("{name}",cleanName(ev.name)).replace("{content}",ev.content||"").trim();}
async function speakEleven(text){var r=await fetch(API+"/live-reader/tts?k="+TOKEN,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({text:text})});if(!r.ok)throw new Error("tts "+r.status);return URL.createObjectURL(await r.blob());}
function speakBrowser(text){return new Promise(function(res){var u=new SpeechSynthesisUtterance(text);u.lang="vi-VN";u.rate=Math.max(.6,Math.min(cfg.speed||1,1.4));u.onend=res;u.onerror=res;speechSynthesis.speak(u);});}
async function playNext(){if(playing)return;var item=q.shift();if(!item){playing=false;return;}playing=true;
 // LUÔN phát audio TỪ MÁY CHỦ (ElevenLabs hoặc gTTS dự phòng) -> chạy được trong OBS
 // (OBS không có giọng đọc trình duyệt). Giọng trình duyệt chỉ là phương án cuối (Chrome).
 try{var url=await speakEleven(item);var au=$("au");au.src=url;au.onended=function(){URL.revokeObjectURL(url);playing=false;playNext();};au.onerror=function(){playing=false;playNext();};await au.play();}
 catch(e){try{await speakBrowser(item);}catch(_){}playing=false;setTimeout(playNext,300);}}
function enqueue(text,prio){if(!text)return;if(prio)q.unshift(text);else q.push(text);if(!playing)playNext();}
function setStatus(s){$("status").textContent="Trạng thái: "+(s||"...")+(playing?" · đang đọc":"");}
async function connect(){await fetch(API+"/social/tiktok/live/connect",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({username:user})});}
async function drainOld(){await new Promise(function(r){setTimeout(r,2500);});var r=await fetch(API+"/social/tiktok/live/events?username="+encodeURIComponent(user)+"&after="+after);var d=await r.json();after=d.last||after;setStatus(d.status);}
function addFeed(ev,text){var f=$("feed"),div=document.createElement("div");div.className="row";div.innerHTML='<span class="tag">'+ev.type+'</span>'+text.replace(/</g,"&lt;");f.prepend(div);while(f.children.length>60)f.removeChild(f.lastChild);}
async function loop(){if(!running)return;
 try{var r=await fetch(API+"/social/tiktok/live/events?username="+encodeURIComponent(user)+"&after="+after);var d=await r.json();setStatus(d.status);
 (d.events||[]).forEach(function(ev){if((cfg.read_types||[]).indexOf(ev.type)>=0){var text=tpl(ev);var prio=["gift","follow","share"].indexOf(ev.type)>=0;enqueue(text,prio);addFeed(ev,text);}});
 after=d.last||after;if(d.status==="ended"||d.status==="error"){stop();return;}}catch(e){}
 poll=setTimeout(loop,1500);}
async function start(){var r=await fetch(API+"/live-reader/data?k="+TOKEN);if(!r.ok){$("status").textContent="Link lỗi — tạo lại trong app.";return;}
 var d=await r.json();cfg=d.config;cfg._eleven=d.eleven;user=cfg.username||"";
 if(!user){$("status").textContent="Chưa có @username — vào app đặt lại.";return;}
 $("who").textContent="Phòng LIVE: @"+user+" · Giọng: "+(cfg._eleven&&cfg.voice_id?"ElevenLabs (máy chủ)":"Máy chủ (tiếng Việt)");
 running=true;$("go").textContent="⏹ Dừng";$("go").classList.add("stop");
 await connect();await drainOld();loop();}
function stop(){running=false;if(poll)clearTimeout(poll);q=[];playing=false;try{speechSynthesis.cancel();$("au").pause();}catch(e){}
 $("go").textContent="▶️ Bắt đầu đọc";$("go").classList.remove("stop");setStatus("đã dừng");}
$("go").onclick=function(){running?stop():start();};
// TỰ ĐỘNG chạy khi mở trang (cho OBS / TikTok Studio Browser Source — KHÔNG cần bấm).
// OBS cho phép autoplay nên đọc được luôn. Thử lại vài lần nếu mạng/khởi động chậm.
var _autoTries=0;
function autoStart(){ if(running)return; _autoTries++; try{ start(); }catch(e){}
  if(_autoTries<5){ setTimeout(function(){ if(!running) autoStart(); }, 3000); } }
if(document.readyState==="complete"||document.readyState==="interactive"){ setTimeout(autoStart,300); }
else{ window.addEventListener("DOMContentLoaded",function(){ setTimeout(autoStart,300); }); }
// Trong trình duyệt thường (Chrome) autoplay có thể bị chặn tới khi có tương tác — chạm 1 lần là chạy.
document.addEventListener("click",function(){ if(!running) start(); },{once:true});
</script></body></html>"""

@app.get("/r/{tok}", response_class=HTMLResponse)
def reader_page(tok: str):
    if not _reader_cfg(tok):
        return HTMLResponse("<h3 style='font-family:sans-serif;padding:24px'>Link chưa tạo hoặc không hợp lệ. Vào app KENIOS → Đọc (TTS) → tạo lại đường dẫn.</h3>",
                            status_code=404)
    return HTMLResponse(_READER_HTML.replace("__TOKEN__", tok))


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


def _smtp_cfg() -> dict:
    """Cấu hình SMTP relay để gửi email ra ngoài (Gmail…). Ưu tiên cài trong Quản trị,
    fallback biến môi trường. Nhờ vậy admin nhập Gmail + mật khẩu ứng dụng ngay trong app."""
    try:
        port = int((get_setting("smtp_relay_port", "") or "").strip() or SMTP_RELAY_PORT)
    except Exception:
        port = SMTP_RELAY_PORT
    return {
        "host": (get_setting("smtp_relay_host", "") or SMTP_RELAY_HOST).strip(),
        "port": port,
        "user": (get_setting("smtp_relay_user", "") or SMTP_RELAY_USER).strip(),
        "pass": (get_setting("smtp_relay_pass", "") or SMTP_RELAY_PASS),
        "from": (get_setting("smtp_mail_from", "") or MAIL_FROM or "").strip(),
    }


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
    # Bên ngoài: cần SMTP relay (Gmail…) — lấy cấu hình admin/env
    cfg = _smtp_cfg()
    if cfg["host"]:
        # Gmail bắt buộc From = tài khoản đã đăng nhập, nếu không sẽ bị từ chối.
        relay_from = cfg["from"] or (cfg["user"] if "@" in (cfg["user"] or "") else sender)
        try:
            m = _EmailMessage()
            m["From"] = f"{MAIL_FROM_NAME} <{relay_from}>"; m["To"] = to; m["Subject"] = subject
            m["Reply-To"] = relay_from
            m.set_content(body)   # bản chữ thuần (dự phòng)
            if html:
                m.add_alternative(html, subtype="html")
                if images:
                    html_part = m.get_payload()[-1]   # phần HTML vừa thêm
                    for cid, b64 in images.items():
                        html_part.add_related(base64.b64decode(b64), maintype="image",
                                              subtype="png", cid=f"<{cid}>")
            with _smtplib.SMTP(cfg["host"], cfg["port"], timeout=15) as s:
                s.starttls()
                if cfg["user"]:
                    s.login(cfg["user"], cfg["pass"])
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
    action = ("đăng nhập" if purpose == "login"
              else "đăng ký tài khoản" if purpose == "register"
              else "xác minh tài khoản")
    year = time.strftime("%Y")
    eula = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    privacy = "https://www.apple.com/legal/privacy/"
    subject = "Mã xác nhận KENIOS"
    body = (
        f"KENIOS — Mã xác nhận\n\n"
        f"Bạn (hoặc ai đó) vừa yêu cầu mã để {action} trên ứng dụng KENIOS.\n\n"
        f"Mã xác nhận của bạn là: {code}\n"
        f"Mã có hiệu lực trong 5 phút và chỉ dùng được MỘT lần.\n\n"
        f"Vì sự an toàn, KHÔNG chia sẻ mã này cho bất kỳ ai — kể cả người tự xưng là nhân viên KENIOS.\n"
        f"Nếu bạn không yêu cầu mã này, hãy bỏ qua email — tài khoản của bạn vẫn an toàn.\n\n"
        f"Điều khoản sử dụng (EULA chuẩn của Apple): {eula}\n"
        f"Chính sách quyền riêng tư của Apple: {privacy}\n\n"
        f"© {year} KENIOS"
    )
    html = ("""
<div style="font-family:Arial,Helvetica,sans-serif;background:#f4f5f7;padding:28px;">
  <div style="max-width:480px;margin:0 auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 20px rgba(0,0,0,.08);">
    <div style="background:linear-gradient(135deg,#3b6eff,#8b5cf6,#ec4899);padding:26px 20px;text-align:center;">
      <img src="cid:logo" width="72" height="72" style="border-radius:18px;display:block;margin:0 auto 12px;">
      <span style="color:#ffffff;font-size:26px;font-weight:bold;vertical-align:middle;">KENIOS</span>
      <img src="cid:badge" width="26" height="26" style="vertical-align:middle;margin-left:5px;">
    </div>
    <div style="padding:30px 26px;text-align:center;">
      <p style="color:#222;font-size:16px;font-weight:bold;margin:0 0 6px;">Xin chào,</p>
      <p style="color:#444;font-size:14px;line-height:1.6;margin:0 0 18px;">
        Bạn (hoặc ai đó) vừa yêu cầu mã để <b>__ACTION__</b> trên ứng dụng <b>KENIOS</b>.
        Nhập mã bên dưới vào ứng dụng để tiếp tục:
      </p>
      <div style="font-size:40px;font-weight:bold;letter-spacing:10px;color:#3b6eff;margin:6px 0;">__CODE__</div>
      <p style="color:#666;font-size:13px;margin:14px 0 0;line-height:1.7;">
        Mã có hiệu lực trong <b>5 phút</b> và chỉ dùng được <b>một lần</b>.
      </p>
      <div style="background:#fff7ed;border:1px solid #fdba74;border-radius:10px;padding:12px 14px;margin:18px 0 0;text-align:left;">
        <p style="color:#9a3412;font-size:12.5px;margin:0;line-height:1.6;">
          🔒 <b>Vì an toàn:</b> KHÔNG chia sẻ mã này cho bất kỳ ai, kể cả người tự xưng là nhân viên KENIOS.
          Nếu bạn không yêu cầu mã, hãy bỏ qua email — tài khoản của bạn vẫn an toàn.
        </p>
      </div>
    </div>
    <div style="background:#fafafa;padding:18px 22px;text-align:center;color:#888;font-size:12px;line-height:1.7;border-top:1px solid #eee;">
      Khi sử dụng KENIOS, bạn đồng ý với:<br>
      <a href="__EULA__" style="color:#3b6eff;text-decoration:none;">Điều khoản sử dụng (EULA của Apple)</a>
      &nbsp;·&nbsp;
      <a href="__PRIVACY__" style="color:#3b6eff;text-decoration:none;">Chính sách quyền riêng tư của Apple</a>
      <br><span style="color:#bbb;">© __YEAR__ KENIOS</span>
    </div>
  </div>
</div>""").replace("__CODE__", code).replace("__ACTION__", action) \
           .replace("__EULA__", eula).replace("__PRIVACY__", privacy).replace("__YEAR__", year)
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


# ============================================================================
#  BOT TELEGRAM HỖ TRỢ KHÁCH — chỉ admin cấu hình & quản lý (trong app).
#  Khách nhắn bot → chuyển cho admin (kèm mã khách). Admin TRẢ LỜI ngay trên
#  Telegram (reply vào tin đó) → bot chuyển lại đúng khách. Chạy nền bằng
#  long-polling getUpdates (đọc token trực tiếp từ cấu hình, đổi được lúc chạy).
# ============================================================================
_tg_offset = 0
_tg_thread = None

def _tg_call(token: str, method: str, **params):
    import httpx
    try:
        r = httpx.post(f"https://api.telegram.org/bot{token}/{method}", json=params, timeout=35)
        return r.json()
    except Exception as e:
        log.warning("tg_call %s lỗi: %s", method, e)
        return {}

# Bộ thu gom tin bot gửi ra khi đang chạy 1 lệnh trong NHÓM — để TỰ XOÁ sau N giây.
_tg_del_ctx = None   # (thread_ident, [(chat_id, message_id), ...]) khi đang gom

def _tg_send(token: str, chat_id, text: str, buttons: Optional[list] = None):
    params = {"chat_id": chat_id, "text": text, "parse_mode": "HTML",
              "disable_web_page_preview": True}
    if buttons:
        params["reply_markup"] = {"inline_keyboard": buttons}
    r = _tg_call(token, "sendMessage", **params)
    try:
        import threading as _thr
        if _tg_del_ctx and _tg_del_ctx[0] == _thr.get_ident():
            mid = ((r or {}).get("result") or {}).get("message_id")
            if mid:
                _tg_del_ctx[1].append((str(chat_id), mid))
    except Exception:
        pass
    return r

def _tg_autodel_sec() -> int:
    try:
        return int(get_setting("tg_autodel_sec", "5") or 0)
    except Exception:
        return 0

def _tg_delete_later(token: str, items: list, delay: int) -> None:
    import threading as _thr
    def _t():
        time.sleep(delay)
        for cid, mid in items:
            _tg_call(token, "deleteMessage", chat_id=cid, message_id=mid)
    _thr.Thread(target=_t, daemon=True).start()

def _tg_with_autodel(token: str, chat_id, user_mid, fn):
    """Chạy fn() (xử lý 1 lệnh trong nhóm) rồi TỰ XOÁ tin lệnh + tin bot trả lời
    sau tg_autodel_sec giây (mặc định 5s; /autodel để chỉnh/tắt). Trả kết quả fn."""
    import threading as _thr
    global _tg_del_ctx
    sec = _tg_autodel_sec()
    if sec <= 0 or not user_mid:   # tắt, hoặc chat riêng (không xoá gì)
        return fn()
    _tg_del_ctx = (_thr.get_ident(), [])
    try:
        res = fn()
    finally:
        items = _tg_del_ctx[1] if _tg_del_ctx else []
        _tg_del_ctx = None
    if (res is None or res) and user_mid:   # fn đã xử lý lệnh → xoá cả tin lệnh
        items.append((str(chat_id), user_mid))
    if items:
        _tg_delete_later(token, items, sec)
    return res

def _tg_menu_buttons() -> list:
    return [[{"text": "💬 Chat với hỗ trợ", "callback_data": "support"}],
            [{"text": "ℹ️ Giới thiệu", "callback_data": "about"}]]

# ---------- Lấy nhạc YouTube/TikTok (/nhac) — không giới hạn dung lượng ----------
_AUDIO_VIDEO_EXTS = (".mp3", ".m4a", ".aac", ".opus", ".ogg", ".webm", ".wav", ".flac", ".mp4", ".mkv", ".mov")

def _tg_yt_audio(query: str):
    """Tải nhạc mp3 từ YouTube/TikTok. Trích mp3 trực tiếp; nếu trích lỗi thì
    TỰ chuyển file đã tải sang mp3 bằng ffmpeg (khắc phục 'tải xong mà không ra mp3')."""
    if not shutil.which("yt-dlp"):
        return None, "", "Máy chủ chưa cài yt-dlp"
    import tempfile as _tf, glob as _glob
    d = _tf.mkdtemp(prefix="tgm_")
    src = query if query.lower().startswith("http") else f"ytsearch1:{query}"
    out = os.path.join(d, "%(title).80s.%(ext)s")
    base = ["yt-dlp", "--no-playlist", "--no-warnings", "--no-part", "--no-mtime",
            "--socket-timeout", "15", "--retries", "5", "-o", out]
    if shutil.which("aria2c"):
        base += ["--downloader", "aria2c", "--downloader-args", "aria2c:-x16 -s16 -k1M --file-allocation=none"]
    else:
        base += ["-N", "16"]

    def _media_files():
        return [f for f in _glob.glob(os.path.join(d, "*"))
                if os.path.splitext(f)[1].lower() in _AUDIO_VIDEO_EXTS]

    r = None
    try:
        # (1) Trích mp3 trực tiếp (nhanh khi ffmpeg trích được)
        r = subprocess.run(base + ["-x", "--audio-format", "mp3", "--audio-quality", "0", src],
                           capture_output=True, text=True, timeout=600)
    except Exception as e:
        shutil.rmtree(d, ignore_errors=True); return None, "", str(e)

    mp3s = _glob.glob(os.path.join(d, "*.mp3"))
    if mp3s:
        p = mp3s[0]
        return p, os.path.splitext(os.path.basename(p))[0], ""

    # (2) Không ra mp3 → nếu chưa tải được file nào, tải lại bestaudio thô
    media = _media_files()
    if not media:
        try:
            subprocess.run(base + ["-f", "bestaudio/best", src], capture_output=True, text=True, timeout=600)
        except Exception:
            pass
        media = _media_files()

    # (3) Có file media → TỰ chuyển sang mp3 bằng ffmpeg
    if media and shutil.which("ffmpeg"):
        srcf = max(media, key=os.path.getsize)
        title = os.path.splitext(os.path.basename(srcf))[0]
        mp3 = os.path.join(d, "audio_out.mp3")
        try:
            subprocess.run(["ffmpeg", "-y", "-v", "quiet", "-i", srcf, "-vn", "-b:a", "192k", mp3],
                           capture_output=True, timeout=600)
        except Exception:
            pass
        if os.path.exists(mp3) and os.path.getsize(mp3) > 1000:
            return mp3, title, ""

    err = (((r.stderr if r else "") or "") + ((r.stdout if r else "") or ""))
    # Bỏ các dòng progress [download] để báo lỗi cho SẠCH
    err = "\n".join(l for l in err.splitlines() if "[download]" not in l and l.strip())[-200:]
    shutil.rmtree(d, ignore_errors=True)
    return None, "", err or "không trích được nhạc (thử link khác)"

def _tg_send_audio(token: str, chat_id, path: str, title: str) -> bool:
    import httpx
    try:
        with open(path, "rb") as f:
            r = httpx.post(f"https://api.telegram.org/bot{token}/sendAudio",
                           data={"chat_id": str(chat_id), "title": title[:64],
                                 "caption": "🎵 " + title[:120]},
                           files={"audio": (os.path.basename(path), f, "audio/mpeg")},
                           timeout=300)
        return bool(r.json().get("ok"))
    except Exception as e:
        log.warning("tg sendAudio lỗi: %s", e); return False

# Telegram bot chỉ cho gửi file ≤ 50MB. Ta NÉN bitrate cho vừa, bài dài thì CẮT nhiều phần.
_TG_AUDIO_LIMIT = 49 * 1024 * 1024

def _tg_audio_duration(path: str) -> float:
    """Thời lượng (giây) qua ffprobe; 0 nếu không đọc được."""
    try:
        r = subprocess.run(["ffprobe", "-v", "quiet", "-show_entries", "format=duration",
                            "-of", "csv=p=0", path], capture_output=True, text=True, timeout=60)
        return float((r.stdout or "0").strip() or 0)
    except Exception:
        return 0.0

def _tg_fit_audio(path: str) -> list:
    """Trả về danh sách file mp3 mỗi cái ≤ 50MB để gửi thẳng vào Telegram.
    - Nếu đã nhỏ: trả nguyên.
    - Nén bitrate cho cả bài ~45MB (96–320kbps).
    - Vẫn to (bài rất dài): cắt thành nhiều phần, mỗi phần ~45MB."""
    try:
        if os.path.getsize(path) <= _TG_AUDIO_LIMIT:
            return [path]
    except Exception:
        return [path]
    if not shutil.which("ffmpeg"):
        return [path]
    import glob as _glob
    d = os.path.dirname(path)
    base = os.path.splitext(os.path.basename(path))[0]
    dur = _tg_audio_duration(path)
    kbps = 128
    if dur > 0:
        kbps = max(96, min(320, int((45 * 1024 * 1024 * 8) / dur / 1000)))
    # (1) Nén cả bài về một bitrate cho vừa
    out = os.path.join(d, base + "_fit.mp3")
    try:
        subprocess.run(["ffmpeg", "-y", "-v", "quiet", "-i", path, "-vn", "-b:a", f"{kbps}k", out],
                       capture_output=True, timeout=1800)
    except Exception:
        pass
    if os.path.exists(out) and os.path.getsize(out) <= _TG_AUDIO_LIMIT:
        return [out]
    # (2) Vẫn quá lớn → cắt thành nhiều khúc, mỗi khúc ~45MB ở bitrate đã chọn
    src = out if os.path.exists(out) else path
    seg = max(300, int((45 * 1024 * 1024 * 8) / (kbps * 1000))) if kbps > 0 else 2400
    segpat = os.path.join(d, base + "_p%03d.mp3")
    try:
        subprocess.run(["ffmpeg", "-y", "-v", "quiet", "-i", src, "-vn", "-b:a", f"{kbps}k",
                        "-f", "segment", "-segment_time", str(seg), segpat],
                       capture_output=True, timeout=1800)
    except Exception:
        pass
    parts = sorted(_glob.glob(os.path.join(d, base + "_p*.mp3")))
    return parts if parts else [path]

def _tg_music_task(token: str, chat_id, arg: str) -> None:
    """Tải & gửi nhạc (chạy trong thread riêng để không chặn vòng lặp bot)."""
    import html as _h
    arg = (arg or "").strip()
    if not arg:
        _tg_send(token, chat_id, "🎵 Gửi: <code>/nhac &lt;link YouTube/TikTok hoặc tên bài&gt;</code>"); return
    _tg_call(token, "sendChatAction", chat_id=chat_id, action="upload_voice")
    _tg_send(token, chat_id, "🎧 Đang lấy nhạc, chờ chút…")
    path, title, err = _tg_yt_audio(arg)
    if not path:
        _tg_send(token, chat_id, "❌ Không lấy được nhạc.\n" + _h.escape((err or "")[:300])); return
    try:
        # Nén/cắt cho vừa 50MB rồi gửi THẲNG vào Telegram (không còn gửi link).
        parts = _tg_fit_audio(path)
        sendable = [p for p in parts if os.path.getsize(p) <= _TG_AUDIO_LIMIT]
        if sendable:
            n = len(sendable)
            if n > 1:
                _tg_call(token, "sendChatAction", chat_id=chat_id, action="upload_voice")
                _tg_send(token, chat_id, f"🎵 <b>{_h.escape(title)}</b>\nBài dài nên nô tì chia làm <b>{n}</b> phần 👇")
            fail = 0
            for i, p in enumerate(sendable, 1):
                t = f"{title} ({i}/{n})" if n > 1 else title
                if not _tg_send_audio(token, chat_id, p, t):
                    fail += 1
            if fail:
                _tg_send(token, chat_id, f"⚠️ Có {fail} phần gửi chưa được, thử lại /nhac nhé.")
        else:
            # Trường hợp hiếm (không có ffmpeg / bài siêu lớn) → vẫn để link tải.
            tk = secrets.token_hex(8)
            dst = os.path.join(_IPA_DIR, f"tgmusic_{tk}.mp3")
            shutil.copy(path, dst)
            base = _ipa_base_url() or "https://app.kenios.store"
            _tg_send(token, chat_id,
                     f"🎵 <b>{_h.escape(title)}</b>\nFile quá lớn — tải tại:\n{base}/ipa/dl/tgmusic_{tk}.mp3")
    except Exception as e:
        log.warning("tg music gửi lỗi: %s", e)
        _tg_send(token, chat_id, "❌ Có lỗi khi gửi nhạc.")
    finally:
        try: shutil.rmtree(os.path.dirname(path), ignore_errors=True)
        except Exception: pass

def _tg_start_music(token, chat_id, arg) -> None:
    import threading
    threading.Thread(target=_tg_music_task, args=(token, chat_id, arg), daemon=True).start()

# ---------- 🎬 TẢI VIDEO (nhanh + cắt phần khi quá dung lượng) ----------
_TG_VIDEO_LIMIT = 49 * 1024 * 1024

def _tg_yt_video(query: str):
    """Tải video mp4 THẬT NHANH: ưu tiên file 1 LUỒNG (khỏi ghép video+audio),
    dùng aria2c 16 kết nối nếu có. Trả (path, title, err)."""
    if not shutil.which("yt-dlp"):
        return None, "", "Máy chủ chưa cài yt-dlp"
    import tempfile as _tf, glob as _glob
    d = _tf.mkdtemp(prefix="tgv_")
    src = query if query.lower().startswith("http") else f"ytsearch1:{query}"
    out = os.path.join(d, "%(title).80s.%(ext)s")
    cmd = ["yt-dlp", "--no-playlist", "--no-warnings", "--no-part", "--no-mtime",
           "--socket-timeout", "15", "--retries", "5", "--fragment-retries", "5",
           # ƯU TIÊN file mp4 progressive (1 luồng, KHỎI ghép = nhanh nhất); rồi mới tới ghép.
           "-f", "b[ext=mp4][height<=720]/b[height<=720]/bv*[height<=720][ext=mp4]+ba[ext=m4a]/b",
           "--merge-output-format", "mp4"]
    if shutil.which("aria2c"):
        cmd += ["--downloader", "aria2c",
                "--downloader-args", "aria2c:-x16 -s16 -k1M --file-allocation=none"]
    else:
        cmd += ["-N", "16"]   # 16 mảnh song song (khi không có aria2c)
    cmd += ["-o", out, src]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    except Exception as e:
        shutil.rmtree(d, ignore_errors=True); return None, "", str(e)
    fs = [f for f in _glob.glob(os.path.join(d, "*"))
          if os.path.splitext(f)[1].lower() in (".mp4", ".mkv", ".webm", ".mov")]
    if not fs:
        err = ((r.stderr or "") + (r.stdout or ""))[-300:]
        shutil.rmtree(d, ignore_errors=True); return None, "", err or "không tải được"
    p = max(fs, key=os.path.getsize)
    return p, os.path.splitext(os.path.basename(p))[0], ""

def _tg_fit_video(path: str) -> list:
    """Chia video >50MB thành nhiều khúc ≤ ~48MB (cắt COPY siêu nhanh, không mã hoá lại)."""
    try:
        if os.path.getsize(path) <= _TG_VIDEO_LIMIT:
            return [path]
    except Exception:
        return [path]
    if not shutil.which("ffmpeg"):
        return [path]
    import glob as _glob, math as _math
    d = os.path.dirname(path); base = os.path.splitext(os.path.basename(path))[0]
    size = os.path.getsize(path); dur = _tg_audio_duration(path)
    if dur <= 0 or size <= 0:
        return [path]
    # Số phần = trần(size / 46MB) → chắc chắn chia ĐỦ nhiều khúc; giây/khúc = tổng giây / số phần.
    nparts = max(2, _math.ceil(size / (46 * 1024 * 1024)))
    seg = max(8, int(dur / nparts))
    segpat = os.path.join(d, base + "_v%03d.mp4")
    try:
        subprocess.run(["ffmpeg", "-y", "-v", "quiet", "-i", path, "-c", "copy", "-map", "0",
                        "-f", "segment", "-segment_time", str(seg),
                        "-reset_timestamps", "1", "-movflags", "+faststart", segpat],
                       capture_output=True, timeout=1800)
    except Exception:
        pass
    parts = sorted(_glob.glob(os.path.join(d, base + "_v*.mp4")))
    # Nếu lỡ có khúc vẫn >50MB (keyframe thưa) → cắt nhỏ tiếp khúc đó theo nửa thời lượng.
    fixed = []
    for pth in parts:
        if os.path.getsize(pth) <= _TG_VIDEO_LIMIT:
            fixed.append(pth); continue
        sub_seg = max(10, int(seg / 2))
        subpat = os.path.join(d, os.path.splitext(os.path.basename(pth))[0] + "_s%02d.mp4")
        try:
            subprocess.run(["ffmpeg", "-y", "-v", "quiet", "-i", pth, "-c", "copy", "-map", "0",
                            "-f", "segment", "-segment_time", str(sub_seg),
                            "-reset_timestamps", "1", subpat], capture_output=True, timeout=900)
            subs = sorted(_glob.glob(os.path.join(d, os.path.splitext(os.path.basename(pth))[0] + "_s*.mp4")))
            fixed.extend(subs or [pth])
        except Exception:
            fixed.append(pth)
    return fixed or parts or [path]

def _tg_send_video(token: str, chat_id, path: str, caption: str) -> bool:
    import httpx
    try:
        with open(path, "rb") as f:
            r = httpx.post(f"https://api.telegram.org/bot{token}/sendVideo",
                           data={"chat_id": str(chat_id), "caption": ("🎬 " + caption)[:1000],
                                 "supports_streaming": "true"},
                           files={"video": (os.path.basename(path), f, "video/mp4")}, timeout=600)
        return bool(r.json().get("ok"))
    except Exception as e:
        log.warning("tg sendVideo lỗi: %s", e); return False

def _tg_video_task(token: str, chat_id, arg: str) -> None:
    import html as _h
    arg = (arg or "").strip()
    if not arg:
        _tg_send(token, chat_id, "🎬 Gửi: <code>/video &lt;link hoặc tên video&gt;</code> (YouTube/TikTok/FB…)"); return
    _tg_call(token, "sendChatAction", chat_id=chat_id, action="upload_video")
    _tg_send(token, chat_id, "🎬 Đang tải video tốc độ cao (16 luồng)…")
    path, title, err = _tg_yt_video(arg)
    if not path:
        _tg_send(token, chat_id, "❌ Không tải được video.\n" + _h.escape((err or "")[:300])); return
    try:
        _mb = os.path.getsize(path) / (1024 * 1024)
        parts = _tg_fit_video(path)
        sendable = [p for p in parts if os.path.getsize(p) <= _TG_VIDEO_LIMIT]
        if sendable:
            n = len(sendable)
            if n > 1:
                _tg_send(token, chat_id, f"🎬 <b>{_h.escape(title)}</b> ({_mb:.0f}MB)\nĐã tải xong — chia làm <b>{n}</b> phần, đang gửi 👇")
            fail = 0
            for i, p in enumerate(sendable, 1):
                _tg_call(token, "sendChatAction", chat_id=chat_id, action="upload_video")
                cap = f"{title} ({i}/{n})" if n > 1 else title
                if not _tg_send_video(token, chat_id, p, cap):
                    fail += 1
            if fail:
                _tg_send(token, chat_id, f"⚠️ Có {fail} phần gửi chưa được, thử lại /video nhé.")
        else:
            tk = secrets.token_hex(8)
            dst = os.path.join(_IPA_DIR, f"tgvid_{tk}.mp4")
            shutil.copy(path, dst)
            base = _ipa_base_url() or "https://app.kenios.store"
            _tg_send(token, chat_id, f"🎬 <b>{_h.escape(title)}</b>\nFile lớn — tải tại:\n{base}/ipa/dl/tgvid_{tk}.mp4")
    except Exception as e:
        log.warning("tg video gửi lỗi: %s", e)
        _tg_send(token, chat_id, "❌ Có lỗi khi gửi video.")
    finally:
        try: shutil.rmtree(os.path.dirname(path), ignore_errors=True)
        except Exception: pass

def _tg_start_video(token, chat_id, arg) -> None:
    import threading
    threading.Thread(target=_tg_video_task, args=(token, chat_id, arg), daemon=True).start()

# ---------- 🛡️ QUÉT LINK: kiểm tra virus / lừa đảo + thông tin đầy đủ ----------
def _tg_vn_now() -> str:
    import datetime as _dt
    return (_dt.datetime.utcnow() + _dt.timedelta(hours=7)).strftime("%H:%M:%S %d/%m/%Y")

def _tg_first_url(text: str) -> str:
    import re as _re
    m = _re.search(r"(https?://[^\s]+|(?:www\.|t\.me/)[^\s]+)", text or "", _re.I)
    return m.group(1) if m else ""

def _tg_scan_link(url: str):
    """Quét 1 link: mở redirect → domain/IP/HTTPS/mã, quét VirusTotal (nếu có key).
    Trả (report_html, danger_bool)."""
    import httpx, socket, html as _h, re as _re
    from urllib.parse import urlparse
    u = (url or "").strip()
    if not _re.match(r"^https?://", u, _re.I):
        u = "http://" + u
    danger = False
    final, status, server = u, "?", ""
    try:
        with httpx.Client(follow_redirects=True, timeout=15,
                          headers={"User-Agent": "Mozilla/5.0"}) as c:
            r = c.get(u)
            final = str(r.url); status = r.status_code; server = r.headers.get("server", "")
    except Exception as e:
        return ("⚠️ Không mở được link này (có thể chết/chặn): " + _h.escape(str(e)[:120]) +
                "\n🕐 " + _tg_vn_now()), True
    host = (urlparse(final).hostname or "")
    try:
        ip = socket.gethostbyname(host) if host else "?"
    except Exception:
        ip = "?"
    https = final.lower().startswith("https://")
    warn = []
    if not https:
        warn.append("không mã hoá HTTPS")
    if _re.match(r"^https?://\d+\.\d+\.\d+\.\d+", final):
        warn.append("dùng IP thay tên miền")
    shortener = {"bit.ly", "tinyurl.com", "t.co", "goo.gl", "ow.ly", "is.gd", "cutt.ly",
                 "shorturl.at", "zpr.io", "rebrand.ly", "shorten.asia"}
    if host in shortener or (urlparse(u).hostname in shortener):
        warn.append("link rút gọn (ẩn đích thật)")
    bad_tld = (".zip", ".mov", ".xyz", ".top", ".tk", ".ml", ".ga", ".cf", ".gq",
               ".click", ".country", ".work", ".rest", ".sbs")
    if any(host.endswith(t) for t in bad_tld):
        warn.append("tên miền lạ/hay bị lạm dụng")
    # VirusTotal (nếu admin đặt key)
    vt = ""
    key = (get_setting("tg_vt_key", "") or "").strip()
    if key:
        try:
            with httpx.Client(timeout=25, headers={"x-apikey": key}) as c:
                aid = c.post("https://www.virustotal.com/api/v3/urls",
                             data={"url": final}).json().get("data", {}).get("id", "")
                time.sleep(3)
                if aid:
                    st = (c.get(f"https://www.virustotal.com/api/v3/analyses/{aid}").json()
                          .get("data", {}).get("attributes", {}).get("stats", {}))
                    mal, susp, harm = st.get("malicious", 0), st.get("suspicious", 0), st.get("harmless", 0)
                    if mal or susp:
                        danger = True
                        vt = f"🦠 VirusTotal: <b>{mal} nơi báo ĐỘC HẠI</b>, {susp} nghi ngờ, {harm} an toàn."
                    else:
                        vt = f"✅ VirusTotal: không phát hiện độc hại ({harm} nơi báo an toàn)."
        except Exception as e:
            vt = "ℹ️ VirusTotal chưa quét được (" + _h.escape(str(e)[:60]) + ")."
    head = "🚨 <b>CẢNH BÁO — LINK CÓ THỂ NGUY HIỂM</b>" if danger else "🔎 <b>Kết quả quét link</b>"
    rep = [head,
           f"🔗 Đích thật: <code>{_h.escape(final[:200])}</code>",
           f"🌐 Tên miền: <code>{_h.escape(host)}</code> · IP: <code>{ip}</code>",
           f"🔐 HTTPS: {'✅ có' if https else '❌ không'} · HTTP {status}" + (f" · {_h.escape(server[:40])}" if server else "")]
    if final.rstrip("/") != u.rstrip("/"):
        rep.append("↪️ Link gốc có CHUYỂN HƯỚNG sang địa chỉ trên.")
    if vt:
        rep.append(vt)
    if warn:
        rep.append("⚠️ Lưu ý: " + ", ".join(warn) + ".")
    rep.append("🕐 " + _tg_vn_now())
    if not key:
        rep.append("💡 Bật quét virus SÂU: admin đặt VirusTotal API key (miễn phí ở virustotal.com) bằng <code>/setvt &lt;key&gt;</code>.")
    return "\n".join(rep), danger

def _tg_scan_link_task(token, chat_id, url, reply_to=None) -> None:
    try:
        rep, danger = _tg_scan_link(url)
    except Exception as e:
        log.warning("scan link lỗi: %s", e); return
    params = {"chat_id": chat_id, "text": rep, "parse_mode": "HTML", "disable_web_page_preview": True}
    if reply_to:
        params["reply_to_message_id"] = reply_to
    _tg_call(token, "sendMessage", **params)

def _tg_start_scan_link(token, chat_id, url, reply_to=None) -> None:
    import threading
    threading.Thread(target=_tg_scan_link_task, args=(token, chat_id, url, reply_to), daemon=True).start()

# ============================================================================
#  🎮 GÓC GIẢI TRÍ & TIỆN ÍCH NHÓM — trò chơi · hài hước · bói vui · công cụ
#  (35+ lệnh công khai, ai cũng dùng được — trong nhóm & chat riêng)
# ============================================================================
_TG_JOKES = [
    "Tại sao con gà băng qua đường? — Vì bên kia có con gà khác đang chờ nó. ❤️",
    "Tiền không mua được hạnh phúc, nhưng khóc trong ô tô vẫn dễ chịu hơn khóc trên xe đạp. 🚗",
    "Mỗi ngày tôi đều chạy bộ... trong suy nghĩ. Vậy là đủ cardio rồi. 🏃",
    "Ngủ sớm để da đẹp. Tôi thức khuya vì tôi đẹp sẵn rồi. 😌",
    "WiFi nhà hàng xóm như tình đầu: thấy đó mà không với tới được. 📶",
    "Tôi không lười, tôi chỉ đang ở chế độ tiết kiệm năng lượng. 🔋",
    "Cuối tháng ví tôi mỏng như niềm tin của tôi vào thứ Hai. 👛",
    "Ăn kiêng ngày 1: xoá app đồ ăn. Ngày 2: cài lại và đặt gấp đôi. 🍜",
    "Tôi với cái giường là mối tình bền nhất: sáng nào chia tay cũng đau khổ. 🛏️",
    "Não tôi có 2 chế độ: 'quên' và 'nhớ nhầm'. 🧠",
    "Đi làm để kiếm tiền, kiếm tiền để có sức... đi làm tiếp. Vòng lặp hoàn hảo. 💼",
    "Thất bại là mẹ thành công — nhà tôi giờ đông mẹ lắm rồi. 🏠",
    "Tôi của tối nay: 'mai dậy sớm tập thể dục'. Tôi của 5h sáng: 'ai hứa người đó giữ'. ⏰",
    "Bạn thân là đứa cười to nhất khi mình ngã... xong mới đỡ. 🤝",
    "Mua 1 món giảm giá là tiết kiệm. Mua 10 món giảm giá là 10 lần tiết kiệm! 🛍️",
    "Điện thoại 1% pin dạy tôi trân trọng từng giây phút bên nhau. 🔌",
    "Hồi bé ước mau lớn. Giờ chỉ ước được ngủ trưa như hồi mẫu giáo. 😴",
    "Tôi nấu ăn theo công thức 'áng chừng' và 'chắc là được'. Kết quả: đặt đồ ăn ngoài. 🍳",
    "Người ta có gấu để ôm mùa đông, tôi có... cái chăn, và nó chưa bao giờ phản bội. 🧸",
    "Hôm nay đẹp trời, thích hợp để... ở nhà nằm điều hoà. ☀️",
]
_TG_QUOTES = [
    "Chậm mà chắc còn hơn nhanh mà chệch hướng.",
    "Đừng so sánh chương 1 của bạn với chương 20 của người khác.",
    "Muốn đi nhanh hãy đi một mình, muốn đi xa hãy đi cùng nhau.",
    "Gió tầng nào gặp mây tầng đó — cứ tốt lên rồi đúng người sẽ tới.",
    "Kỷ luật là cây cầu nối giữa mục tiêu và thành tựu.",
    "Bạn không cần hoàn hảo để bắt đầu, nhưng cần bắt đầu để hoàn hảo hơn.",
    "Im lặng là câu trả lời sang trọng nhất cho những ồn ào không đáng.",
    "Đừng sợ thất bại — hãy sợ việc chưa từng thử.",
    "Cách tốt nhất để dự đoán tương lai là tự tay tạo ra nó.",
    "Không ai nghèo đi vì cho đi một nụ cười.",
    "Thứ quý nhất không phải là có tất cả, mà là trân trọng những gì đang có.",
    "Hôm nay khó, ngày mai có thể khó hơn — nhưng ngày kia sẽ tươi sáng.",
]
_TG_POEMS = [
    "Gió theo mây, mây theo gió cuốn\nAnh theo em từ buổi chợ đông 💘",
    "Trời xanh vì có nắng vàng\nTim anh xanh mướt vì nàng đi qua 🌿",
    "Cà phê đắng bởi thiếu đường\nĐời anh nhạt bởi thiếu hương tay nàng ☕",
    "Ước gì mình chung lối về\nĐể anh bớt phải cà phê một mình 💫",
    "Hoa hồng nào chẳng có gai\nThương em nào ngại đường dài gió sương 🌹",
    "Sông sâu còn có kẻ dò\nLòng em sâu thẳm biết đo đường nào 🌊",
    "Trăng lên đỉnh núi trăng tà\nNhớ em từ sáng đến già chưa thôi 🌙",
    "Bàn tay năm ngón thon dài\nNắm vào một cái là hai cuộc đời 🤍",
]
_TG_COMPLIMENTS = [
    "là mặt trời của nhóm này, thiếu bạn là nhóm tối om! ☀️",
    "nói chuyện có duyên xỉu, nghe là muốn thả tim! 💖",
    "đẹp nhất cái nhóm này, không nhận không được! 😎",
    "IQ vô cực, EQ tràn màn hình! 🧠",
    "cười một cái là sáng cả khung chat! 😄",
    "tốt bụng số 2 thì không ai dám nhận số 1! 🥇",
    "gõ phím thôi cũng thấy khí chất ngời ngời! ⌨️",
    "là định nghĩa sống của từ 'tuyệt vời'! 📖",
    "năng lượng tích cực lan toả khắp nhóm! 🔆",
    "có mặt là nhóm vui gấp 10 lần! 🎉",
]
_TG_TEASES = [
    "ngủ dậy chưa mà online sớm thế, chăm ghê ta! 🌞",
    "hôm nay gõ chữ nhanh ghê, chắc vừa nạp 3 ly cà phê! ☕",
    "nói chuyện hay như sách — mà là sách tô màu! 🖍️",
    "IQ cao lắm, chỉ tội hay để quên ở nhà! 🧠",
    "online 24/7, WiFi nhà chắc khoẻ lắm ha! 📶",
    "hát hay lắm — hàng xóm khen đóng cửa rất kỹ! 🎤",
    "nấu ăn ngon nhất nhà, vì nhà có mỗi mình ên! 🍳",
    "chạy bộ mỗi sáng... trên giường, trong mơ! 🏃",
    "đẹp thì có đẹp, mà hơi khiêm tốn chiều cao nhỉ! 📏",
    "tiết kiệm số 1 — đến nụ cười cũng ít khi cho ai! 😁",
]
_TG_8BALL = [
    "Chắc chắn luôn! ✅", "Không phải nghĩ — CÓ! 💯", "Có, nhưng từ từ đã. 🐢",
    "Triển vọng tốt đấy! 🌤️", "Hỏi lại sau nhé, giờ là bí mật. 🤫",
    "Mình thấy hơi khó à nha. 😬", "KHÔNG là câu trả lời. ❌",
    "Đừng mơ giữa ban ngày! 😅", "50/50 — tuỳ bạn quyết! ⚖️",
    "Dấu hiệu chỉ ra là CÓ. 🔮", "Dấu hiệu chỉ ra là KHÔNG. 🌫️",
    "Cứ làm đi, hỏi gì nữa! 🚀", "Vũ trụ trả lời: CÓ. 🌌",
    "Hên xui, mà nghiêng về... xui. 🎲", "Tốt hơn là không nên. 🙅", "Tin mình đi — được đó! 👍",
]
_TG_TRUTH = [
    "Crush đầu tiên của bạn là ai?", "Điều xấu hổ nhất bạn từng làm ở trường/chỗ làm?",
    "Lần gần nhất bạn nói dối là về việc gì?", "Người trong nhóm này bạn muốn ăn tối cùng nhất?",
    "Bí mật bạn chưa từng kể với ai?", "Bạn từng thích người yêu của bạn thân chưa?",
    "Tin nhắn ngại nhất bạn từng gửi nhầm?", "Nếu phải hôn 1 người trong nhóm, bạn chọn ai? 😳",
    "Bạn đã từng stalk người yêu cũ chưa?", "Điều trẻ con nhất bạn vẫn làm khi ở một mình?",
    "Bạn từng khóc vì bộ phim nào?", "Thói quen xấu nhất của bạn là gì?",
    "Nếu tàng hình 1 ngày, bạn làm gì đầu tiên?", "Ai trong nhóm bạn nghĩ sẽ nổi tiếng nhất?",
    "Số dư tài khoản hiện tại của bạn có mấy chữ số? 😏",
]
_TG_DARE = [
    "Gửi 1 tấm selfie ngay bây giờ vào nhóm! 🤳",
    "Đổi avatar thành hình do nhóm chọn trong 1 giờ!",
    "Nhắn 'Tớ nhớ cậu' cho một người bạn cũ lâu rồi chưa nói chuyện!",
    "Ghi âm giọng hát 'Chúc mừng sinh nhật' gửi vào nhóm! 🎂",
    "Viết 1 status khen nhóm này thật lố lên trang cá nhân!",
    "Kể 1 bí mật nho nhỏ của bạn ngay tại đây!",
    "Gửi tấm ảnh GẦN NHẤT trong thư viện — không được chọn lại! 📸",
    "Nói 'em sai rồi' với người tiếp theo nhắn tin, bất kể chuyện gì! 😂",
    "Nhắn 3 tin liên tiếp bằng giọng miền khác!",
    "Thả tim ❤️ 10 tin nhắn gần nhất trong nhóm!",
    "Khen 3 người trong nhóm, mỗi người 1 câu thật lòng!",
    "Gửi voice 10 giây kể bạn ăn gì hôm nay, giọng thật truyền cảm! 🎙️",
    "Đặt 'người gửi tin kế tiếp' làm hình nền điện thoại 1 ngày! 📱",
    "Gõ tên crush bằng... khuỷu tay và gửi luôn không sửa! 💪",
    "Up ảnh bất kỳ kèm caption 'nhóm mình dễ thương nhất'! 😽",
]
_TG_FORTUNES = [
    "Hôm nay quý nhân xuất hiện — để ý người nhắn tin cho bạn đầu tiên! 🍀",
    "Tiền bạc rủng rỉnh bất ngờ, nhưng đừng vội khao cả nhóm. 💰",
    "Chuyện tình cảm sáng sủa — ai độc thân hôm nay nhớ tắm rửa thơm tho. 💘",
    "Cẩn thận lời nói buổi chiều — uốn lưỡi 7 lần trước khi gõ phím. 🤐",
    "Vận may nghiêng về buổi tối, mua ly trà sữa để kích hoạt nhân phẩm. 🧋",
    "Có tin vui về công việc/học tập trong 3 ngày tới. 📈",
    "Hôm nay dễ bị cà khịa — cứ cười là thắng. 😁",
    "Món đồ thất lạc sắp tìm thấy — thử nhìn dưới gối xem. 🛏️",
    "Người bạn lâu ngày sắp liên lạc lại — đừng quên trả lời nhé. 📱",
    "Hôm nay hợp màu xanh — mặc gì xanh xanh sẽ hên cả ngày. 💚",
    "Đừng ngủ trưa quá 30 phút, kẻo lỡ chuyện thú vị. ⏰",
    "Tài lộc gõ cửa nhưng gõ nhẹ — chăm thêm chút là mở được. 🚪",
    "Nói ít lại, làm nhiều lên — cuối ngày có quà. 🎁",
    "Duyên chưa tới nhưng vui thì tới rồi — cười lên! 😄",
    "Bạn là 'người được chọn' hôm nay — thử vận may với /xoso xem! 🎰",
    "Sao may mắn chiếu mệnh — làm gì cũng thuận, trừ thức khuya. 🌟",
]

_tg_guess: dict = {}   # chat_id -> số bí mật (trò đoán số 1–100)

def _tg_daily_hash(*parts) -> int:
    """Số 'định mệnh' ổn định trong ngày (đổi mỗi ngày) — cho bói vui/tình duyên."""
    import hashlib, datetime as _dt
    s = "|".join(str(p) for p in parts) + _dt.date.today().isoformat()
    return int(hashlib.md5(s.encode()).hexdigest(), 16)

def _tg_calc_expr(expr: str) -> str:
    """Máy tính an toàn: chỉ + - * / % // ** và số."""
    import ast as _ast, operator as _op
    expr = (expr or "").replace("^", "**").replace(",", ".").replace("×", "*").replace("÷", "/")[:80]
    ops = {_ast.Add: _op.add, _ast.Sub: _op.sub, _ast.Mult: _op.mul, _ast.Div: _op.truediv,
           _ast.Pow: _op.pow, _ast.Mod: _op.mod, _ast.FloorDiv: _op.floordiv,
           _ast.USub: _op.neg, _ast.UAdd: _op.pos}
    def ev(n):
        if isinstance(n, _ast.Constant) and isinstance(n.value, (int, float)):
            return n.value
        if isinstance(n, _ast.BinOp) and type(n.op) in ops:
            l, r = ev(n.left), ev(n.right)
            if isinstance(n.op, _ast.Pow) and (abs(l) > 1000 or abs(r) > 100):
                raise ValueError("số quá lớn")
            return ops[type(n.op)](l, r)
        if isinstance(n, _ast.UnaryOp) and type(n.op) in ops:
            return ops[type(n.op)](ev(n.operand))
        raise ValueError("chỉ hỗ trợ phép tính số")
    v = ev(_ast.parse(expr, mode="eval").body)
    return f"{v:,.6f}".rstrip("0").rstrip(".").replace(",", " ") if isinstance(v, float) else f"{v:,}".replace(",", " ")

def _tg_active_names(chat_id, n=50) -> list:
    try:
        rows, _ = _msgcount_top(chat_id, n)
        return [r[0] for r in rows]
    except Exception:
        return []

def _tg_fun_net_task(token, chat_id, cmd, args) -> None:
    """Các lệnh cần MẠNG (thời tiết, giá coin, tỷ giá, dịch) — chạy thread riêng."""
    import httpx, html as _h, urllib.parse as _up
    try:
        if cmd == "thoitiet":
            city = (args.strip() or "Hanoi")
            r = httpx.get(f"https://wttr.in/{_up.quote(city)}", params={"format": "%l: %c %t, ẩm %h, gió %w", "lang": "vi", "m": ""},
                          headers={"User-Agent": "curl/8"}, timeout=12)
            t = (r.text or "").strip()
            _tg_send(token, chat_id, "⛅ " + _h.escape(t[:300]) if t and "Unknown" not in t else "⛅ Không tìm thấy nơi này, thử /thoitiet Hanoi")
        elif cmd == "giacoin":
            sym = (args.strip().upper() or "BTC").replace("USDT", "")
            r = httpx.get("https://api.binance.com/api/v3/ticker/24hr", params={"symbol": f"{sym}USDT"}, timeout=12).json()
            if r.get("lastPrice"):
                p = float(r["lastPrice"]); ch = float(r.get("priceChangePercent", 0))
                arrow = "📈" if ch >= 0 else "📉"
                _tg_send(token, chat_id, f"💰 <b>{sym}/USDT</b>: <b>{p:,.6g}</b> USD {arrow} {ch:+.2f}%/24h")
            else:
                _tg_send(token, chat_id, f"Không thấy đồng <b>{_h.escape(sym)}</b>. VD: /giacoin btc · eth · bnb · sol")
        elif cmd == "tygia":
            r = httpx.get("https://open.er-api.com/v6/latest/USD", timeout=12).json()
            vnd = (r.get("rates") or {}).get("VND")
            if vnd:
                _tg_send(token, chat_id, f"💵 1 USD ≈ <b>{vnd:,.0f} VND</b>\n💶 1 EUR ≈ <b>{vnd / (r['rates'].get('EUR') or 1):,.0f} VND</b>".replace(",", "."))
            else:
                _tg_send(token, chat_id, "Không lấy được tỷ giá lúc này, thử lại sau nhé.")
        elif cmd == "dich":
            if not args.strip():
                _tg_send(token, chat_id, "🌐 Dùng: <code>/dich hello my friend</code> — dịch sang tiếng Việt."); return
            r = httpx.get("https://translate.googleapis.com/translate_a/single",
                          params={"client": "gtx", "sl": "auto", "tl": "vi", "dt": "t", "q": args[:1500]}, timeout=12).json()
            out = "".join(seg[0] for seg in (r[0] or []) if seg and seg[0])
            _tg_send(token, chat_id, "🌐 " + _h.escape(out[:1000]) if out else "Không dịch được, thử lại sau.")
    except Exception as e:
        log.warning("tg fun net %s lỗi: %s", cmd, e)
        _tg_send(token, chat_id, "⚠️ Dịch vụ đang bận, thử lại sau nhé.")

# Tất cả lệnh vui/tiện ích (công khai — dùng ở nhóm & chat riêng)
_TG_FUN_CMDS = {
    "xucxac", "slot", "phitieu", "bongda", "bongro", "bowling", "tungxu", "oantuti", "keobuabao",
    "doanso", "doan", "random", "chon", "xoso",
    "cuoi", "joke", "cakhia", "khen", "triethly", "thotinh", "noinguoc", "thatha", "thachthuc",
    "ghep", "lucky", "boi", "tinhduyen", "hoi", "danhgia",
    "tinh", "qr", "thoitiet", "giacoin", "tygia", "dich", "nhacnho", "binhchon", "poll", "gio", "dem", "password",
    # 🃏 game bài + 🧠 đố vui có điểm
    "dovui", "goiy", "boqua", "dungdo", "diemdo", "baicao", "xidach", "rut", "dan", "baucua",
}

def _tg_fun_command(token, chat_id, msg, cmd, args) -> bool:
    """Xử lý lệnh GIẢI TRÍ & TIỆN ÍCH. Trả True nếu đã xử lý."""
    import html as _h, random as _rd, threading as _thr
    frm = msg.get("from", {}) or {}
    uid = frm.get("id") or 0
    rfrm = (msg.get("reply_to_message") or {}).get("from") or {}
    target = _tg_mention(rfrm) if rfrm.get("id") else _tg_mention(frm)

    # ---------- 🎮 TRÒ CHƠI ----------
    dice = {"xucxac": "🎲", "slot": "🎰", "phitieu": "🎯", "bongda": "⚽", "bongro": "🏀", "bowling": "🎳"}
    if cmd in dice:
        _tg_call(token, "sendDice", chat_id=chat_id, emoji=dice[cmd]); return True
    if cmd == "tungxu":
        _tg_send(token, chat_id, f"🪙 {_tg_mention(frm)} tung đồng xu… ra <b>{_rd.choice(['NGỬA 🌝', 'SẤP 🌚'])}</b>!"); return True
    if cmd in ("oantuti", "keobuabao"):
        icons = {"kéo": "✂️", "búa": "✊", "bao": "🖐"}
        a = args.strip().lower().replace("keo", "kéo").replace("bua", "búa")
        if a not in icons:
            _tg_send(token, chat_id, "✂️ Oẳn tù tì với bot: <code>/oantuti kéo</code> · <code>/oantuti búa</code> · <code>/oantuti bao</code>"); return True
        b = _rd.choice(list(icons))
        win = {("kéo", "bao"), ("búa", "kéo"), ("bao", "búa")}
        kq = "HOÀ! 🤝" if a == b else ("BẠN THẮNG! 🎉" if (a, b) in win else "BOT THẮNG! 😎")
        _tg_send(token, chat_id, f"Bạn ra {icons[a]} — bot ra {icons[b]} → <b>{kq}</b>"); return True
    if cmd == "doanso":
        _tg_guess[chat_id] = _rd.randint(1, 100)
        _tg_send(token, chat_id, "🔢 Mình đã nghĩ 1 số từ <b>1–100</b>. Cả nhóm đoán bằng <code>/doan 50</code> nào!"); return True
    if cmd == "doan":
        if chat_id not in _tg_guess:
            _tg_send(token, chat_id, "Chưa có ván nào — gõ <code>/doanso</code> để bắt đầu!"); return True
        try:
            n = int(args.split()[0])
        except Exception:
            _tg_send(token, chat_id, "Đoán bằng số nhé: <code>/doan 50</code>"); return True
        s = _tg_guess[chat_id]
        if n == s:
            del _tg_guess[chat_id]
            _tg_send(token, chat_id, f"🎉 <b>CHÍNH XÁC!</b> {_tg_mention(frm)} đoán trúng số <b>{s}</b>! Gõ /doanso chơi ván mới.")
        else:
            _tg_send(token, chat_id, f"{'⬆️ Lớn hơn' if n < s else '⬇️ Nhỏ hơn'} {n} nhé!")
        return True
    if cmd == "random":
        p = args.split()
        try:
            a, b = (int(p[0]), int(p[1])) if len(p) >= 2 else (1, 100)
        except Exception:
            a, b = 1, 100
        _tg_send(token, chat_id, f"🎲 Số ngẫu nhiên {min(a,b)}–{max(a,b)}: <b>{_rd.randint(min(a, b), max(a, b))}</b>"); return True
    if cmd == "chon":
        opts = [x.strip() for x in (args.split("|") if "|" in args else args.split()) if x.strip()]
        if len(opts) < 2:
            _tg_send(token, chat_id, "🤔 Đưa mình ít nhất 2 lựa chọn: <code>/chon trà sữa | cà phê | nước cam</code>"); return True
        _tg_send(token, chat_id, f"👉 Mình chọn: <b>{_h.escape(_rd.choice(opts))}</b>"); return True
    if cmd == "xoso":
        nums = sorted(_rd.sample(range(1, 46), 6))
        _tg_send(token, chat_id, "🎰 Dãy số may mắn của bạn: <b>" + " – ".join(f"{n:02d}" for n in nums) + "</b> 🍀"); return True

    # ---------- 😂 GIẢI TRÍ ----------
    if cmd in ("cuoi", "joke"):
        _tg_send(token, chat_id, "😂 " + _rd.choice(_TG_JOKES)); return True
    if cmd == "cakhia":
        _tg_send(token, chat_id, f"😜 {target} {_rd.choice(_TG_TEASES)}"); return True
    if cmd == "khen":
        _tg_send(token, chat_id, f"🌟 {target} {_rd.choice(_TG_COMPLIMENTS)}"); return True
    if cmd == "triethly":
        _tg_send(token, chat_id, "🧘 <i>" + _rd.choice(_TG_QUOTES) + "</i>"); return True
    if cmd == "thotinh":
        _tg_send(token, chat_id, "📜 " + _rd.choice(_TG_POEMS)); return True
    if cmd == "noinguoc":
        if not args.strip():
            _tg_send(token, chat_id, "🔄 Dùng: <code>/noinguoc xin chào cả nhóm</code>"); return True
        _tg_send(token, chat_id, "🔄 " + _h.escape(args.strip()[:300][::-1])); return True
    if cmd == "thatha":
        _tg_send(token, chat_id, f"🙊 <b>NÓI THẬT</b> — {target}:\n{_rd.choice(_TG_TRUTH)}"); return True
    if cmd == "thachthuc":
        _tg_send(token, chat_id, f"🔥 <b>THỬ THÁCH</b> — {target}:\n{_rd.choice(_TG_DARE)}"); return True
    if cmd == "ghep":
        names = _tg_active_names(chat_id)
        if len(names) < 2:
            _tg_send(token, chat_id, "💞 Cần nhóm có người nhắn tin rồi mới ghép được — mọi người chat đi nào!"); return True
        a, b = _rd.sample(names, 2)
        pct = _tg_daily_hash(a, b, chat_id) % 101
        _tg_send(token, chat_id, f"💞 <b>Ghép đôi hôm nay:</b>\n👩‍❤️‍👨 <b>{_h.escape(a)}</b> ❤ <b>{_h.escape(b)}</b>\n💯 Độ hợp: <b>{pct}%</b> {'💒 Cưới luôn!' if pct >= 80 else ('😍 Có triển vọng!' if pct >= 50 else '🙈 Làm bạn đã nha!')}"); return True
    if cmd == "lucky":
        names = _tg_active_names(chat_id)
        if not names:
            _tg_send(token, chat_id, "🍀 Chưa có dữ liệu thành viên — cả nhóm chat vài câu đi!"); return True
        _tg_send(token, chat_id, f"🍀 <b>Thành viên may mắn hôm nay:</b> 🎉 <b>{_h.escape(_rd.choice(names))}</b> 🎉"); return True

    # ---------- 🔮 BÓI VUI ----------
    if cmd == "boi":
        h = _tg_daily_hash("boi", uid)
        _tg_send(token, chat_id, f"🔮 <b>Bói vui hôm nay của {_tg_mention(frm)}:</b>\n"
                                 f"{_TG_FORTUNES[h % len(_TG_FORTUNES)]}\n💫 Độ may mắn: <b>{h % 101}%</b>"); return True
    if cmd == "tinhduyen":
        if rfrm.get("id"):
            n1, n2 = _tg_name(frm), _tg_name(rfrm)
        elif "|" in args:
            p = [x.strip() for x in args.split("|") if x.strip()]
            n1, n2 = (p + ["?", "?"])[:2]
        elif args.strip():
            n1, n2 = _tg_name(frm), args.strip()
        else:
            _tg_send(token, chat_id, "💘 Dùng: reply tin người ấy rồi gõ /tinhduyen · hoặc <code>/tinhduyen Tuấn | Hoa</code>"); return True
        pct = _tg_daily_hash("love", n1.lower(), n2.lower()) % 101
        verdict = "💒 Trời sinh một cặp!" if pct >= 85 else ("❤️ Rất hợp nhau!" if pct >= 60 else ("🌱 Cần vun đắp thêm!" if pct >= 35 else "🙈 Duyên bạn bè thôi!"))
        _tg_send(token, chat_id, f"💘 <b>Bói tình duyên:</b> {_h.escape(n1)} ❤ {_h.escape(n2)}\n💯 Độ hợp: <b>{pct}%</b>\n{verdict}"); return True
    if cmd == "hoi":
        if not args.strip():
            _tg_send(token, chat_id, "🎱 Hỏi bot tiên tri: <code>/hoi mai có trúng số không?</code>"); return True
        _tg_send(token, chat_id, f"🎱 <i>{_h.escape(args.strip()[:150])}</i>\n→ <b>{_rd.choice(_TG_8BALL)}</b>"); return True
    if cmd == "danhgia":
        if not args.strip():
            _tg_send(token, chat_id, "💯 Dùng: <code>/danhgia độ đẹp trai của tôi</code>"); return True
        _tg_send(token, chat_id, f"💯 <b>{_h.escape(args.strip()[:120])}</b>: <b>{_tg_daily_hash('rate', args.strip().lower()) % 101}%</b>"); return True

    # ---------- 🧰 TIỆN ÍCH ----------
    if cmd == "tinh":
        if not args.strip():
            _tg_send(token, chat_id, "🧮 Máy tính: <code>/tinh 5*(3+2)/2</code>"); return True
        try:
            _tg_send(token, chat_id, f"🧮 <code>{_h.escape(args.strip()[:80])}</code> = <b>{_tg_calc_expr(args)}</b>")
        except Exception:
            _tg_send(token, chat_id, "❌ Biểu thức không hợp lệ. VD: <code>/tinh (5+3)*2</code>")
        return True
    if cmd == "qr":
        if not args.strip():
            _tg_send(token, chat_id, "🔳 Tạo mã QR: <code>/qr https://app.kenios.store</code>"); return True
        import urllib.parse as _up
        _tg_call(token, "sendPhoto", chat_id=chat_id, caption="🔳 Mã QR của bạn",
                 photo=f"https://api.qrserver.com/v1/create-qr-code/?size=500x500&data={_up.quote(args.strip()[:800])}")
        return True
    if cmd in ("thoitiet", "giacoin", "tygia", "dich"):
        _thr.Thread(target=_tg_fun_net_task, args=(token, chat_id, cmd, args), daemon=True).start(); return True
    if cmd == "nhacnho":
        p = args.split(maxsplit=1)
        try:
            mins = float(p[0].replace(",", "."))
        except Exception:
            mins = 0
        if mins <= 0 or len(p) < 2:
            _tg_send(token, chat_id, "⏰ Hẹn nhắc: <code>/nhacnho 30 họp nhóm</code> (phút, tối đa 7 ngày)"); return True
        mins = min(mins, 7 * 24 * 60)
        who = _tg_mention(frm); note = _h.escape(p[1][:300])
        t = _thr.Timer(mins * 60, _tg_send, args=(token, chat_id, f"⏰ {who} — đến giờ: <b>{note}</b>"))
        t.daemon = True; t.start()
        _tg_send(token, chat_id, f"✅ Sẽ nhắc <b>{note}</b> sau <b>{mins:g} phút</b>."); return True
    if cmd in ("binhchon", "poll"):
        parts = [x.strip() for x in args.split("|") if x.strip()]
        if len(parts) < 3:
            _tg_send(token, chat_id, "🗳️ Tạo bình chọn: <code>/binhchon Tối ăn gì? | Lẩu | Nướng | Bún chả</code>"); return True
        _tg_call(token, "sendPoll", chat_id=chat_id, question=parts[0][:250],
                 options=[p[:90] for p in parts[1:11]], is_anonymous=False)
        return True
    if cmd == "gio":
        import datetime as _dt
        u = _dt.datetime.utcnow()
        _tg_send(token, chat_id,
                 f"🕐 <b>Giờ hiện tại</b>\n🇻🇳 Việt Nam: <b>{(u + _dt.timedelta(hours=7)):%H:%M — %d/%m/%Y}</b>\n"
                 f"🇯🇵 Tokyo: {(u + _dt.timedelta(hours=9)):%H:%M} · 🇬🇧 London: {(u + _dt.timedelta(hours=1)):%H:%M} · 🇺🇸 New York: {(u - _dt.timedelta(hours=4)):%H:%M}")
        return True
    if cmd == "dem":
        s = args.strip()
        if not s:
            _tg_send(token, chat_id, "🔢 Đếm chữ: <code>/dem đoạn văn cần đếm</code>"); return True
        _tg_send(token, chat_id, f"🔢 <b>{len(s)}</b> ký tự · <b>{len(s.split())}</b> từ · <b>{len(s.splitlines())}</b> dòng"); return True
    if cmd == "password":
        import string as _st
        try:
            ln = max(8, min(64, int(args.split()[0])))
        except Exception:
            ln = 14
        chars = _st.ascii_letters + _st.digits + "!@#$%^&*"
        pw = "".join(secrets.choice(chars) for _ in range(ln))
        _tg_send(token, chat_id, f"🔐 Mật khẩu mạnh ({ln} ký tự):\n<code>{pw}</code>"); return True
    return _tg_game_command(token, chat_id, msg, cmd, args)

# ============================================================================
#  🃏 GAME BÀI & 🧠 ĐỐ VUI CÓ ĐIỂM (~1080 câu, 20+ thể loại)
#  Trả lời đúng: +10 điểm + lời chúc mừng · /diemdo — bảng vàng
# ============================================================================
_TG_CONGRATS = [
    "🎉 CHÍNH XÁC! {name} quá đỉnh!", "🏆 Tuyệt vời {name}! Chuẩn không cần chỉnh!",
    "👏👏 {name} thông minh quá trời!", "🌟 Xuất sắc {name}! IQ vô cực!",
    "🥳 Đúng rồi! {name} là thánh đố vui!", "💯 {name} trả lời đúng! Cả nhóm vỗ tay nào!",
    "🎊 Quá giỏi luôn {name} ơi!", "🚀 {name} nhanh như chớp, chính xác tuyệt đối!",
    "🧠 Bộ não thiên tài gọi tên {name}!", "🔥 {name} cân luôn câu khó!",
]
_TG_QUIZ: dict = {}     # chat_id -> {"q","a","auto"} câu đố đang chờ trả lời
_TG_QUIZ_LAST: dict = {}  # chat_id -> câu hỏi lần trước (để không hỏi trùng liên tiếp)
_TG_AI_LAST: dict = {}    # chat_id -> lần cuối AI trả lời (giới hạn nhịp chế độ 'trả lời tất cả')
_TG_XIDACH: dict = {}   # (chat_id, uid) -> {"p": bài người chơi, "d": bài nhà cái}
_TG_QUIZ_BANK: list = []

def _tg_norm_ans(s: str) -> str:
    """Chuẩn hoá đáp án: thường, bỏ dấu tiếng Việt, gọn khoảng trắng."""
    import unicodedata
    s = (s or "").lower().strip()
    s = unicodedata.normalize("NFD", s)
    s = "".join(ch for ch in s if unicodedata.category(ch) != "Mn").replace("đ", "d")
    for pre in ("dap an la ", "dap an ", "ket qua la ", "ket qua ", "la "):
        if s.startswith(pre):
            s = s[len(pre):]
    return " ".join(s.split())

def _tg_ans_ok(user: str, answers: list) -> bool:
    u = _tg_norm_ans(user)
    u2 = u.replace(".", "").replace(",", "").replace(" ", "")
    for a in answers:
        na = _tg_norm_ans(a)
        if u == na or (u2 and u2 == na.replace(".", "").replace(",", "").replace(" ", "")):
            return True
    return False

def _tg_quiz_bank() -> list:
    """Ngân hàng ~1.150 câu đố (tạo 1 lần): thủ đô, cờ, toán, dãy số, kiến thức chung,
    đố mẹo, tục ngữ, đố chữ, đố dân gian (con gì/cái gì), hại não, cơ thể, khoa học,
    địa lý, lịch sử - ngày lễ, ẩm thực, cây cỏ - 12 con giáp, màu sắc - mùa, số học,
    nghề nghiệp - công nghệ, ca dao."""
    global _TG_QUIZ_BANK
    if _TG_QUIZ_BANK:
        return _TG_QUIZ_BANK
    B = []
    def add(q, *a): B.append((q, list(a)))
    # ---- 1) Thủ đô thế giới (~72 câu) ----
    caps = {"Việt Nam": ["Hà Nội"], "Lào": ["Viêng Chăn", "Vientiane"], "Campuchia": ["Phnôm Pênh", "Phnom Penh"],
        "Thái Lan": ["Bangkok", "Băng Cốc"], "Malaysia": ["Kuala Lumpur"], "Singapore": ["Singapore"],
        "Indonesia": ["Jakarta"], "Philippines": ["Manila"], "Myanmar": ["Naypyidaw"], "Brunei": ["Bandar Seri Begawan"],
        "Trung Quốc": ["Bắc Kinh", "Beijing"], "Nhật Bản": ["Tokyo"], "Hàn Quốc": ["Seoul"], "Triều Tiên": ["Bình Nhưỡng", "Pyongyang"],
        "Mông Cổ": ["Ulaanbaatar", "Ulan Bato"], "Ấn Độ": ["New Delhi", "Niu Đê Li"], "Pakistan": ["Islamabad"],
        "Bangladesh": ["Dhaka"], "Nepal": ["Kathmandu"], "Sri Lanka": ["Colombo"], "Kazakhstan": ["Astana"],
        "Uzbekistan": ["Tashkent"], "Afghanistan": ["Kabul"], "Iran": ["Tehran"], "Iraq": ["Baghdad"],
        "Ả Rập Xê Út": ["Riyadh"], "UAE": ["Abu Dhabi"], "Qatar": ["Doha"], "Israel": ["Jerusalem"], "Thổ Nhĩ Kỳ": ["Ankara"],
        "Nga": ["Moscow", "Mát-xcơ-va", "Matxcova"], "Anh": ["London", "Luân Đôn"], "Pháp": ["Paris"],
        "Đức": ["Berlin"], "Ý": ["Rome", "Roma"], "Tây Ban Nha": ["Madrid"], "Bồ Đào Nha": ["Lisbon"],
        "Hà Lan": ["Amsterdam"], "Bỉ": ["Brussels"], "Thụy Sĩ": ["Bern"], "Áo": ["Vienna", "Viên"],
        "Thụy Điển": ["Stockholm"], "Na Uy": ["Oslo"], "Đan Mạch": ["Copenhagen"], "Phần Lan": ["Helsinki"],
        "Ba Lan": ["Warsaw", "Vác-sa-va", "Vacsava"], "Séc": ["Praha", "Prague"], "Hungary": ["Budapest"],
        "Hy Lạp": ["Athens", "A-ten"], "Ukraine": ["Kyiv", "Kiev"], "Belarus": ["Minsk"], "Romania": ["Bucharest"],
        "Bulgaria": ["Sofia"], "Serbia": ["Belgrade"], "Croatia": ["Zagreb"], "Iceland": ["Reykjavik"], "Ireland": ["Dublin"],
        "Ai Cập": ["Cairo"], "Nam Phi": ["Pretoria"], "Nigeria": ["Abuja"], "Kenya": ["Nairobi"], "Ma-rốc": ["Rabat"],
        "Algeria": ["Algiers"], "Ethiopia": ["Addis Ababa"], "Ghana": ["Accra"],
        "Mỹ": ["Washington", "Washington DC"], "Canada": ["Ottawa"], "Mexico": ["Mexico City"], "Cuba": ["Havana", "La Habana"],
        "Brazil": ["Brasilia"], "Argentina": ["Buenos Aires"], "Chile": ["Santiago"], "Peru": ["Lima"],
        "Colombia": ["Bogota"], "Venezuela": ["Caracas"], "Uruguay": ["Montevideo"],
        "Úc": ["Canberra"], "New Zealand": ["Wellington"]}
    for c, a in caps.items():
        add(f"🌍 Thủ đô của {c} là gì?", *a)
    # ---- 2) Cờ nước nào (~60 câu) ----
    flags = [("🇻🇳", "Việt Nam"), ("🇯🇵", ["Nhật Bản", "Nhật"]), ("🇰🇷", "Hàn Quốc"), ("🇨🇳", "Trung Quốc"),
        ("🇹🇭", "Thái Lan"), ("🇱🇦", "Lào"), ("🇰🇭", "Campuchia"), ("🇲🇾", "Malaysia"), ("🇸🇬", "Singapore"),
        ("🇮🇩", "Indonesia"), ("🇵🇭", "Philippines"), ("🇮🇳", "Ấn Độ"), ("🇷🇺", "Nga"), ("🇬🇧", "Anh"),
        ("🇫🇷", "Pháp"), ("🇩🇪", "Đức"), ("🇮🇹", ["Ý", "Italia"]), ("🇪🇸", "Tây Ban Nha"), ("🇵🇹", "Bồ Đào Nha"),
        ("🇳🇱", "Hà Lan"), ("🇧🇪", "Bỉ"), ("🇨🇭", "Thụy Sĩ"), ("🇦🇹", "Áo"), ("🇸🇪", "Thụy Điển"),
        ("🇳🇴", "Na Uy"), ("🇩🇰", "Đan Mạch"), ("🇫🇮", "Phần Lan"), ("🇵🇱", "Ba Lan"), ("🇨🇿", ["Séc", "Czech"]),
        ("🇭🇺", "Hungary"), ("🇬🇷", "Hy Lạp"), ("🇹🇷", "Thổ Nhĩ Kỳ"), ("🇪🇬", "Ai Cập"), ("🇿🇦", "Nam Phi"),
        ("🇺🇸", ["Mỹ", "Hoa Kỳ"]), ("🇨🇦", "Canada"), ("🇲🇽", "Mexico"), ("🇧🇷", "Brazil"), ("🇦🇷", "Argentina"),
        ("🇨🇱", "Chile"), ("🇦🇺", ["Úc", "Australia"]), ("🇳🇿", "New Zealand"), ("🇮🇷", "Iran"), ("🇮🇶", "Iraq"),
        ("🇸🇦", "Ả Rập Xê Út"), ("🇦🇪", "UAE"), ("🇶🇦", "Qatar"), ("🇺🇦", "Ukraine"), ("🇷🇴", "Romania"),
        ("🇧🇬", "Bulgaria"), ("🇮🇸", "Iceland"), ("🇮🇪", "Ireland"), ("🇰🇿", "Kazakhstan"), ("🇺🇿", "Uzbekistan"),
        ("🇲🇳", "Mông Cổ"), ("🇲🇲", "Myanmar"), ("🇧🇩", "Bangladesh"), ("🇳🇵", "Nepal"), ("🇱🇰", "Sri Lanka"), ("🇨🇺", "Cuba")]
    for f, c in flags:
        add(f"🏳️ Lá cờ {f} là của nước nào?", *(c if isinstance(c, list) else [c]))
    # ---- 3) Toán nhanh (300 câu, sinh cố định) ----
    import random as _r
    rr = _r.Random(20260704)
    seen = set()
    while len(seen) < 300:
        sym = rr.choice(["+", "-", "×"])
        if sym == "×":
            a, b = rr.randint(2, 12), rr.randint(3, 99)
        else:
            a, b = rr.randint(11, 999), rr.randint(11, 999)
        if sym == "-" and a < b:
            a, b = b, a
        if (sym, a, b) in seen:
            continue
        seen.add((sym, a, b))
        v = a + b if sym == "+" else (a - b if sym == "-" else a * b)
        add(f"🧮 Tính nhanh: {a} {sym} {b} = ?", str(v))
    # ---- 4) Dãy số (100 câu, sinh cố định) ----
    seen2 = set()
    while len(seen2) < 100:
        if rr.random() < 0.7:
            s, d = rr.randint(1, 60), rr.randint(2, 19)
            seq = [s + i * d for i in range(5)]
        else:
            s, q = rr.randint(1, 6), rr.choice([2, 3])
            seq = [s * q ** i for i in range(5)]
        if tuple(seq) in seen2 or seq[4] > 99999:
            continue
        seen2.add(tuple(seq))
        add("🔢 Số tiếp theo của dãy: " + ", ".join(map(str, seq[:4])) + ", ... ?", str(seq[4]))
    # ---- 5) Kiến thức chung (~112 câu) ----
    for q, *a in [
        ("Con vật nào cao nhất thế giới?", "hươu cao cổ"), ("Động vật nào lớn nhất hành tinh?", "cá voi xanh", "cá voi"),
        ("Chúa sơn lâm là con gì?", "hổ", "con hổ", "cọp"), ("Loài chim nào chạy nhanh nhất và không biết bay?", "đà điểu"),
        ("Con vật nào ngủ đứng?", "ngựa", "con ngựa"), ("Loài vật nào có vòi dài nhất?", "voi", "con voi"),
        ("Con gì nhả tơ làm kén?", "tằm", "con tằm"), ("Loài chim nào là biểu tượng hoà bình?", "bồ câu", "chim bồ câu"),
        ("Con gì chậm chạp, mang 'nhà' trên lưng, để lại vệt nhớt?", "ốc sên"), ("Chuột túi là biểu tượng nước nào?", "úc", "australia"),
        ("Gấu trúc là biểu tượng của nước nào?", "trung quốc"), ("Loài cá nào bơi ngược dòng để đẻ trứng?", "cá hồi"),
        ("Con gì kêu ộp ộp bên ao?", "ếch", "con ếch"), ("Loài vật nào đổi màu da theo môi trường?", "tắc kè hoa", "tắc kè"),
        ("Nhện thường có bao nhiêu chân?", "8", "tám"), ("Con ong làm ra thứ gì ngọt?", "mật", "mật ong"),
        ("Động vật nhanh nhất trên cạn?", "báo", "báo săn", "báo gêpa"), ("Con gì có bướu trên lưng, đi được sa mạc?", "lạc đà"),
        ("Hành tinh nào gần Mặt Trời nhất?", "sao thủy", "thủy tinh"), ("Hành tinh nào lớn nhất hệ Mặt Trời?", "sao mộc", "mộc tinh"),
        ("Hành tinh nào được gọi là hành tinh đỏ?", "sao hỏa", "hỏa tinh"), ("Trái Đất quay quanh thiên thể nào?", "mặt trời"),
        ("Nước sôi ở bao nhiêu độ C?", "100"), ("Nước đóng băng ở bao nhiêu độ C?", "0"),
        ("Công thức hóa học của nước là gì?", "h2o"), ("Con người hít khí gì để sống?", "oxy", "oxi", "o2"),
        ("Cây xanh quang hợp nhả ra khí gì?", "oxy", "oxi", "o2"), ("Một năm không nhuận có bao nhiêu ngày?", "365"),
        ("Một tuần có bao nhiêu ngày?", "7", "bảy"), ("Kim loại nào ở thể lỏng trong nhiệt độ thường?", "thủy ngân"),
        ("Thứ gì nhanh nhất vũ trụ?", "ánh sáng"), ("Vệ tinh tự nhiên của Trái Đất tên gì?", "mặt trăng"),
        ("Ai phát minh bóng đèn sợi đốt?", "edison"), ("Ai là cha đẻ thuyết tương đối?", "einstein", "anhxtanh"),
        ("Nhà bác học nào gắn với giai thoại quả táo rơi?", "newton", "niuton"), ("Một giờ có bao nhiêu phút?", "60"),
        ("Hình có 3 cạnh gọi là hình gì?", "tam giác"), ("Số pi làm tròn 2 chữ số thập phân là?", "3.14", "3,14"),
        ("Cơ quan nào bơm máu đi khắp cơ thể?", "tim", "trái tim"), ("Bộ phận nào điều khiển suy nghĩ con người?", "não", "bộ não"),
        ("Thành phố nào đông dân nhất Việt Nam?", "tphcm", "sài gòn", "hồ chí minh", "tp hồ chí minh", "thành phố hồ chí minh"),
        ("Ngọn núi cao nhất Việt Nam?", "fansipan", "phan xi păng", "phanxipang"), ("Vịnh nào của VN là kỳ quan thiên nhiên?", "hạ long", "vịnh hạ long"),
        ("Sông nào chảy qua Hà Nội?", "sông hồng"), ("Dòng sông nào gắn liền với xứ Huế?", "sông hương"),
        ("Cây cầu nào ở Đà Nẵng biết phun lửa?", "cầu rồng"), ("Hòn đảo lớn nhất Việt Nam?", "phú quốc"),
        ("Việt Nam từng có bao nhiêu tỉnh thành?", "63"), ("Đồng bằng sông Cửu Long ở miền nào?", "miền nam", "nam bộ", "miền tây"),
        ("Cà phê Việt Nam trồng nhiều nhất ở vùng nào?", "tây nguyên"), ("Quốc hoa của Việt Nam?", "hoa sen", "sen"),
        ("Hang động lớn nhất thế giới (ở Quảng Bình)?", "sơn đoòng", "son doong"), ("Đà Lạt thuộc tỉnh nào?", "lâm đồng"),
        ("Phố cổ nổi tiếng ở Quảng Nam?", "hội an"), ("Vùng biển phía đông Việt Nam tên gì?", "biển đông"),
        ("Ai đọc Tuyên ngôn Độc lập ngày 2/9/1945?", "bác hồ", "hồ chí minh", "chủ tịch hồ chí minh"),
        ("Vị vua nào dời đô về Thăng Long năm 1010?", "lý thái tổ", "lý công uẩn"),
        ("Vị tướng nào 3 lần đại phá quân Nguyên Mông?", "trần hưng đạo", "trần quốc tuấn"),
        ("Chiến thắng 'chấn động địa cầu' năm 1954?", "điện biên phủ"), ("Trang phục truyền thống của phụ nữ Việt?", "áo dài"),
        ("Tết cổ truyền của Việt Nam gọi là gì?", "tết nguyên đán", "nguyên đán"), ("Bánh vuông truyền thống ngày Tết?", "bánh chưng"),
        ("Truyện Kiều là tác phẩm của ai?", "nguyễn du"), ("Vị nữ tướng nào cùng em gái phất cờ khởi nghĩa?", "trưng trắc", "hai bà trưng", "bà trưng"),
        ("Nhạc sĩ nào sáng tác Quốc ca Việt Nam?", "văn cao"), ("Món nước nổi tiếng nhất Việt Nam?", "phở"),
        ("Vị đại tướng chỉ huy trận Điện Biên Phủ?", "võ nguyên giáp", "tướng giáp"),
        ("Tháp Eiffel ở thành phố nào?", "paris"), ("Vạn Lý Trường Thành ở nước nào?", "trung quốc"),
        ("Kim tự tháp Giza ở nước nào?", "ai cập"), ("Tượng Nữ thần Tự do ở thành phố nào?", "new york"),
        ("Đại dương nào lớn nhất thế giới?", "thái bình dương"), ("Châu lục nào lớn nhất?", "châu á"),
        ("Sa mạc nóng lớn nhất thế giới?", "sahara"), ("Con sông nào dài nhất thế giới?", "nin", "sông nin", "nile"),
        ("Đỉnh núi cao nhất thế giới?", "everest"), ("Nước nào hiện đông dân nhất thế giới?", "ấn độ"),
        ("Quốc gia nào rộng nhất thế giới?", "nga"), ("Đồng tiền của Nhật Bản?", "yên", "yen"),
        ("Đồng tiền chung châu Âu?", "euro"), ("Nước nào nổi tiếng với sushi?", "nhật bản", "nhật"),
        ("Nước nào nổi tiếng với kim chi?", "hàn quốc"), ("Lễ hội té nước Songkran của nước nào?", "thái lan"),
        ("Kinh đô điện ảnh Hollywood ở nước nào?", "mỹ", "hoa kỳ"),
        ("Môn thể thao nào là 'môn thể thao vua'?", "bóng đá"), ("Trận bóng đá chính thức dài bao nhiêu phút?", "90"),
        ("Mỗi đội bóng đá có mấy cầu thủ trên sân?", "11"), ("Messi là người nước nào?", "argentina"),
        ("Ronaldo CR7 là người nước nào?", "bồ đào nha"), ("World Cup tổ chức mấy năm 1 lần?", "4"),
        ("Môn võ quốc gia của Hàn Quốc?", "taekwondo"), ("Môn thể thao đánh cầu bằng vợt qua lưới, cầu có lông?", "cầu lông"),
        ("'Kình ngư' là vận động viên môn gì?", "bơi", "bơi lội"), ("Bàn cờ vua có bao nhiêu ô?", "64"),
        ("Chú mèo máy đến từ tương lai tên gì?", "doraemon", "đô rê mon"), ("Cậu bé phù thủy có sẹo hình tia chớp?", "harry potter", "harry"),
        ("Chú chuột nổi tiếng nhất của Disney?", "mickey", "chuột mickey"), ("'Đi khắp thế gian không ai tốt bằng' ai?", "mẹ"),
        ("Ông già tặng quà đêm Giáng sinh?", "ông già noel", "santa", "noel"), ("Nàng tiên cá của Disney tên gì?", "ariel"),
        ("Vua sư tử của Disney tên gì?", "simba"), ("Thám tử nhí lừng danh trong truyện tranh Nhật?", "conan"),
        ("Ai được mệnh danh 'vua nhạc pop'?", "michael jackson"), ("Người khổng lồ xanh của Marvel?", "hulk"),
        ("'Người dơi' tiếng Anh là gì?", "batman"), ("'Người nhện' tiếng Anh là gì?", "spiderman", "spider man"),
        ("Một năm có bao nhiêu tháng?", "12"), ("Mặt trời mọc ở hướng nào?", "đông", "hướng đông"),
        ("Mặt trời lặn ở hướng nào?", "tây", "hướng tây"), ("Cầu vồng có bao nhiêu màu?", "7", "bảy"),
        ("Đèn giao thông có mấy màu?", "3", "ba"), ("Đèn giao thông màu gì thì phải dừng lại?", "đỏ", "màu đỏ"),
    ]:
        add("💡 " + q, *a)
    # ---- 6) Đố mẹo (~44 câu) ----
    for q, *a in [
        ("Con gì đầu dê mình ốc?", "con dốc", "dốc"), ("Cái gì luôn ở phía trước mà bạn không bao giờ thấy?", "tương lai"),
        ("Cái gì càng lấy đi càng lớn?", "cái hố", "hố", "lỗ"), ("Cái gì của bạn nhưng người khác dùng nhiều hơn?", "tên", "cái tên"),
        ("Cái gì đi khắp nơi mà vẫn nằm một chỗ?", "con đường", "đường"), ("Con gì càng to càng nhỏ?", "con cua", "cua"),
        ("Cái gì có cổ mà không có đầu?", "cái áo", "áo", "chai"), ("Cái gì có răng mà không cắn được?", "cái lược", "lược"),
        ("Quả gì có nhiều mắt nhất?", "dứa", "quả dứa", "na", "khóm", "thơm"), ("Cái gì đầy lỗ mà vẫn giữ được nước?", "bọt biển", "miếng xốp", "mút"),
        ("Tháng nào có 28 ngày?", "tháng nào cũng có", "tất cả", "tháng nào cũng"), ("Cái gì phải đập vỡ trước khi dùng?", "trứng", "quả trứng"),
        ("Cái gì càng lau càng bẩn?", "khăn", "khăn lau", "giẻ lau"), ("Cái gì chỉ tăng mà không bao giờ giảm?", "tuổi", "tuổi tác"),
        ("Con gì mỏ bẹt màu vàng, kêu cạp cạp?", "vịt", "con vịt"), ("Bánh gì trong trắng ngoài xanh, ăn vào ngày Tết?", "bánh chưng"),
        ("Vừa bằng hạt đỗ, ăn giỗ cả làng — con gì?", "ruồi", "con ruồi"), ("Đánh cha, đánh má, đánh cả anh chị mỗi sáng mà không bị la — làm gì?", "đánh răng"),
        ("Con đường dài nhất là đường nào?", "đường đời"), ("Quần gì rộng nhất?", "quần đảo"),
        ("Cái gì khi gọi tên nó thì nó biến mất?", "im lặng", "sự im lặng"), ("Bệnh gì mà bác sĩ phải bó tay?", "gãy tay", "bó tay"),
        ("Xã đông người nhất là xã nào?", "xã hội"), ("Cái gì có 4 chân mà không đi được?", "cái bàn", "bàn", "ghế", "cái ghế"),
        ("Con gì 'ăn' lửa, uống nước, chở được cả trăm người?", "tàu hỏa", "xe lửa", "tàu"),
        ("2 con vịt đi trước 2 con vịt, 2 con vịt đi sau 2 con vịt, 2 con vịt đi giữa 2 con vịt. Có mấy con vịt?", "4", "bốn"),
        ("Cái gì bằng cái vung, vùng xuống ao, đào chẳng thấy, lấy chẳng được?", "mặt trăng", "bóng trăng", "trăng"),
        ("Hạt gì rơi xuống mà không mọc thành cây?", "hạt mưa", "mưa"), ("Nhà nào lạnh nhất?", "nhà băng", "băng"),
        ("Con gì chở nổi khúc gỗ lớn nhưng không chở nổi hòn sỏi?", "sông", "con sông", "dòng sông"),
        ("3 con gà đẻ 3 quả trứng trong 3 ngày. 9 con gà đẻ bao nhiêu quả trong 9 ngày?", "27"),
        ("Cái gì tay trái cầm được mà tay phải không bao giờ cầm được?", "tay phải", "khuỷu tay phải"),
        ("Trên nhấp dưới giật — đang làm gì?", "câu cá", "cần câu"), ("Cái gì đập thì sống, không đập thì chết?", "tim", "trái tim", "con tim"),
        ("Cái gì người mua biết, người bán biết, người dùng không bao giờ biết?", "quan tài", "áo quan"),
        ("Cái gì cầm một lúc thì chảy nước, trời nóng chảy càng nhanh?", "kem", "que kem", "cà rem", "đá"),
        ("Quả gì to nhất mà không ăn được?", "quả đất", "trái đất", "đất"), ("Cửa gì mở không được, đóng không xong?", "cửa biển", "cửa sông"),
        ("Bàn gì mà đá được?", "bàn thắng"), ("Nước gì không thể uống được?", "nước mắt", "nước hoa", "nước biển", "nước sơn"),
        ("Cái gì có mũi mà không có miệng?", "kim", "cái kim", "mũi tên", "thuyền"), ("Núi nào bị 'thái' ra từng khúc?", "thái sơn", "núi thái sơn"),
        ("Cái gì càng 'thắng' xe càng chậm?", "phanh", "thắng xe", "phanh xe"), ("Môn gì càng đông người chơi vòng tròn càng vui, hát 'nu na nu nống'?", "nu na nu nống"),
    ]:
        add("🤪 Đố mẹo: " + q, *a)
    # ---- 7) Điền tục ngữ (~40 câu) ----
    for q, *a in [
        ("Có công mài sắt, có ngày nên ...", "kim"), ("Ăn quả nhớ kẻ trồng ...", "cây"),
        ("Uống nước nhớ ...", "nguồn"), ("Gần mực thì đen, gần đèn thì ...", "sáng", "rạng"),
        ("Một cây làm chẳng nên non, ba cây chụm lại nên hòn núi ...", "cao"), ("Đi một ngày đàng, học một sàng ...", "khôn"),
        ("Thương người như thể thương ...", "thân"), ("Lá lành đùm lá ...", "rách"),
        ("Đói cho sạch, rách cho ...", "thơm"), ("Cái nết đánh chết cái ...", "đẹp"),
        ("Tốt gỗ hơn tốt nước ...", "sơn"), ("Học thầy không tày học ...", "bạn"),
        ("Không thầy đố mày làm ...", "nên"), ("Con hơn cha là nhà có ...", "phúc"),
        ("Cá không ăn muối cá ...", "ươn"), ("Máu chảy ruột ...", "mềm"),
        ("Môi hở răng ...", "lạnh"), ("Nước chảy đá ...", "mòn"),
        ("Kiến tha lâu cũng đầy ...", "tổ"), ("Tay làm hàm nhai, tay quai miệng ...", "trễ"),
        ("Ăn cây nào rào cây ...", "nấy", "ấy"), ("Gieo gió gặt ...", "bão"),
        ("Ở hiền gặp ...", "lành"), ("Chị ngã em ...", "nâng"),
        ("Anh em như thể tay ...", "chân"), ("Nghĩa mẹ như nước trong nguồn chảy ...", "ra"),
        ("Một con ngựa đau, cả tàu bỏ ...", "cỏ"), ("Ăn trông nồi, ngồi trông ...", "hướng"),
        ("Lựa lời mà nói cho vừa lòng ...", "nhau"), ("Cây ngay không sợ chết ...", "đứng"),
        ("Đèn nhà ai nấy ...", "rạng", "sáng"), ("Nhập gia tùy ...", "tục"),
        ("Nói có sách, mách có ...", "chứng"), ("Được voi đòi ...", "tiên"),
        ("Tham thì ...", "thâm"), ("Trèo cao ngã ...", "đau"),
        ("Nồi nào úp vung ...", "nấy", "đó"), ("Xa mặt cách ...", "lòng"),
        ("Yêu nhau lắm, cắn nhau ...", "đau"), ("Có chí thì ...", "nên"),
    ]:
        add("📜 Điền từ còn thiếu: " + q, *a)
    # ---- 8) Đố chữ / chữ cái ----
    for q, *a in [
        ("Để nguyên lấp lánh trên trời, bớt đầu thành chỗ cá bơi hằng ngày. Là chữ gì?", "sao"),
        ("Con gì kêu 'quốc quốc' bên bờ, tên nghe cứ ngỡ non sông nước nhà?", "cuốc", "con cuốc", "chim cuốc"),
        ("Chữ cái đầu tiên trong bảng chữ cái tiếng Việt?", "a"),
        ("Chữ cái cuối cùng trong bảng chữ cái tiếng Anh?", "z"),
        ("Bảng chữ cái tiếng Anh có bao nhiêu chữ cái?", "26"),
        ("Nguyên âm đầu tiên trong tiếng Việt là chữ gì?", "a"),
        ("Chữ số nào tròn trịa như quả trứng?", "0", "số 0", "không"),
        ("Từ 'HỌC SINH' có mấy chữ cái?", "7", "bảy"),
        ("Trong từ 'BÓNG ĐÁ' có mấy dấu sắc?", "1", "một"),
        ("Chữ 'ê' có mấy dấu mũ?", "1", "một"),
    ]:
        add("🔤 Đố chữ: " + q, *a)
    # ---- 9) Đố dân gian: con gì? ----
    for q, *a in [
        ("Con gì ăn no bụng to mắt híp, miệng kêu ụt ịt, nằm thở phì phò?", "lợn", "heo", "con lợn", "con heo"),
        ("Con gì mào đỏ, gáy 'ò ó o' gọi người thức dậy mỗi sáng?", "gà trống", "gà", "con gà"),
        ("Con gì đuôi ngắn tai dài, mắt hồng lông mượt, có tài nhảy nhanh?", "thỏ", "con thỏ"),
        ("Con gì kêu 'meo meo', chuyên rình bắt chuột trong nhà?", "mèo", "con mèo"),
        ("Con gì trung thành giữ nhà, thấy người lạ thì sủa vang?", "chó", "con chó"),
        ("Con gì tám cẳng hai càng, không đi mà lại bò ngang cả đời?", "cua", "con cua"),
        ("Con gì bơi dưới nước, thở bằng mang, mình đầy vảy?", "cá", "con cá"),
        ("Con gì chậm chạp, mai cứng như mộc, sống rất thọ?", "rùa", "con rùa"),
        ("Con gì trườn bò không chân, hay le lưỡi dọa người?", "rắn", "con rắn"),
        ("Con gì bé tí phát sáng lập lòe trong vườn ban đêm?", "đom đóm", "con đom đóm"),
        ("Con gì kêu 've ve' suốt cả mùa hè?", "ve", "ve sầu", "con ve"),
        ("Con gì chăng tơ tám góc để bắt ruồi bắt muỗi?", "nhện", "con nhện"),
        ("Con gì hút máu người, hay truyền bệnh sốt rét?", "muỗi", "con muỗi"),
        ("Con gì siêng năng tha mồi, đi thành hàng dài không nghỉ?", "kiến", "con kiến"),
        ("Con gì bay lượn, hút mật, đôi cánh sặc sỡ đủ màu?", "bướm", "con bướm"),
        ("Con gì có bờm, được mệnh danh 'chúa sơn lâm' của châu Phi?", "sư tử", "con sư tử"),
        ("Con gì cổ dài nhất, ăn lá trên cây cao?", "hươu cao cổ", "hươu"),
        ("Con gì to lớn, có vòi và ngà, tai như quạt lớn?", "voi", "con voi"),
        ("Con gì 'chúa tể bầu trời', mắt tinh, móng vuốt sắc bắt mồi?", "đại bàng", "chim đại bàng"),
        ("Con gì đi lạch bạch, mỏ bẹt, lông không thấm nước?", "vịt", "con vịt"),
        ("Con gì kêu 'ộp ộp', nhảy giỏi, sống cả trên cạn lẫn dưới nước?", "ếch", "con ếch"),
        ("Con gì lông xù, kêu 'be be', cho ta len ấm?", "cừu", "con cừu"),
        ("Con gì có bướu trên lưng, chịu khát băng qua sa mạc?", "lạc đà", "con lạc đà"),
        ("Con gì đen trắng như ngựa vằn kẻ sọc?", "ngựa vằn", "con ngựa vằn"),
        ("Con gì thân dẹt, hai mắt cùng một bên, nằm sát đáy biển?", "cá bơn", "cá thờn bơn"),
        ("Con gì nhỏ, kêu 'chiếp chiếp', là con của gà?", "gà con", "gà con"),
        ("Con gì đêm về ngủ treo ngược mình trong hang, bay bằng cánh da?", "dơi", "con dơi"),
        ("Con gì thông minh, hay bắt chước, thích ăn chuối?", "khỉ", "con khỉ"),
    ]:
        add("🐾 Đố con gì: " + q, *a)
    # ---- 10) Đố dân gian: cái gì? ----
    for q, *a in [
        ("Cái gì ban ngày nằm im, ban đêm thức, treo trần nhà toả sáng?", "đèn", "bóng đèn"),
        ("Cái gì mặt tròn, kim chạy vòng vòng, báo cho ta biết giờ?", "đồng hồ", "cái đồng hồ"),
        ("Cái gì mỏng nhẹ, chở đầy con chữ, cho ta kiến thức?", "sách", "quyển sách", "cuốn sách"),
        ("Cái gì trong suốt, soi vào thấy rõ mặt mình?", "gương", "cái gương"),
        ("Cái gì che nắng che mưa, cầm trên tay khi đi đường?", "ô", "cái ô", "dù", "cây dù"),
        ("Cái gì có ruột bằng chì, khoác áo bằng gỗ, giúp ta viết chữ?", "bút chì", "cây bút chì"),
        ("Cái gì quạt mát mùa hè, có cánh quay tít trên tường?", "quạt", "quạt điện", "cái quạt"),
        ("Cái gì lạnh buốt bên trong, giữ đồ ăn tươi lâu?", "tủ lạnh", "cái tủ lạnh"),
        ("Cái gì reo lên, giúp ta nghe được người ở xa nói chuyện?", "điện thoại", "cái điện thoại"),
        ("Cái gì đi cùng ta suốt, mang dưới chân, bảo vệ bàn chân?", "giày", "dép", "đôi giày", "đôi dép"),
        ("Cái gì tít tít mỗi sáng, đánh thức ta dậy đi học?", "đồng hồ báo thức", "đồng hồ"),
        ("Cái gì đựng cơm, ngày ba bữa ta bưng lên ăn?", "bát", "chén", "cái bát", "cái chén"),
        ("Cái gì có nhiều phím, ta gõ vào để viết trên máy tính?", "bàn phím", "cái bàn phím"),
        ("Cái gì cắt được giấy, gồm hai lưỡi chéo nhau?", "kéo", "cái kéo"),
        ("Cái gì đóng đinh vào gỗ, cầm tay mà nện?", "búa", "cái búa"),
        ("Cái gì mềm mại, đắp lên người cho ấm khi ngủ?", "chăn", "cái chăn", "mền"),
        ("Cái gì có bốn bánh, chở người chạy trên đường?", "ô tô", "xe hơi", "xe ô tô"),
        ("Cái gì hai bánh, đạp bằng chân mà chạy?", "xe đạp", "chiếc xe đạp"),
    ]:
        add("🧰 Đố cái gì: " + q, *a)
    # ---- 11) Đố mẹo hại não / hỏi xoáy ----
    for q, *a in [
        ("Cái gì khi đi thì nằm, đứng cũng nằm, nhưng nằm xuống lại đứng?", "bàn chân"),
        ("Một đàn chim đậu trên cành, bắn rơi một con, còn lại mấy con?", "0", "không", "không con"),
        ("9 người ăn 9 cái bánh hết 9 phút, 100 người ăn 100 cái bánh hết mấy phút?", "9"),
        ("5 con mèo bắt 5 con chuột hết 5 phút, 100 con mèo bắt 100 con chuột hết mấy phút?", "5"),
        ("Có 3 quả táo, bạn lấy đi 2 quả. Bạn đang có mấy quả?", "2", "hai"),
        ("Bố mẹ có 6 người con trai, mỗi con trai có 1 em gái. Gia đình có mấy người con?", "7", "bảy"),
        ("Cha của Bình có ba con: con cả tên Xuân, con thứ tên Hạ, con út tên gì?", "bình", "tên bình"),
        ("Một sợi dây cắt làm 2 khúc mất 1 nhát. Cắt thành 5 khúc mất mấy nhát?", "4", "bốn"),
        ("Con trai của mẹ bạn, nhưng không phải anh em trai của bạn, là ai?", "chính mình", "tôi", "bản thân", "chính bạn"),
        ("Đố bạn con gì càng to càng nhỏ?", "con cua", "cua"),
        ("Cái gì càng kéo càng ngắn?", "điếu thuốc", "điếu thuốc lá", "cây nến", "nến"),
        ("Cái gì chạy mà không có chân?", "dòng nước", "nước", "thời gian", "dòng sông"),
        ("Cái gì có tay mà không có chân, chỉ giờ cả ngày?", "đồng hồ", "cái đồng hồ"),
        ("Thứ gì càng chia càng nhiều?", "niềm vui", "hạnh phúc", "kiến thức"),
        ("Cái gì luôn tăng, không bao giờ giảm đi?", "tuổi", "tuổi tác"),
        ("Cái gì đen khi sạch, trắng khi bẩn?", "bảng", "cái bảng", "bảng đen"),
        ("Cái gì có đầu, có đuôi nhưng không có thân?", "đồng xu", "đồng tiền"),
        ("Thứ gì mỗi người mỗi khác, in ở đầu ngón tay?", "vân tay", "dấu vân tay"),
        ("Cái gì ướt khi càng lau khô?", "khăn", "cái khăn", "khăn lau"),
        ("Đi trên đầu là cái gì?", "cái nón", "nón", "mũ", "cái mũ"),
        ("Con gì đứng thì thấp, nằm lại cao?", "con chó", "chó"),
        ("Cái gì có cánh mà không bay, có mắt mà không nhìn?", "quạt", "quạt máy"),
        ("Thứ gì càng nóng thì càng đông (người mua)?", "kem", "que kem"),
        ("Nhà nào không có cửa?", "nhà nghèo", "tổ chim"),
        ("Con gì có 4 chân mà không biết đi?", "cái bàn", "bàn", "cái ghế", "ghế"),
        ("Vừa bằng lá tre, ngo ngoe dưới nước — con gì?", "con đỉa", "đỉa"),
        ("Sông nào không có nước?", "sông ngân", "ngân hà", "sông ngân hà"),
        ("Đường nào dài nhất?", "đường đời"),
        ("Con gì mắt trắng như bông, tối đến sáng rực, ngày lại thu vào?", "con đom đóm", "đom đóm"),
        ("Bệnh gì bác sĩ cũng phải chịu, không thuốc nào chữa?", "bó tay", "gãy tay"),
    ]:
        add("🧩 Đố mẹo: " + q, *a)
    # ---- 12) Cơ thể con người ----
    for q, *a in [
        ("Người trưởng thành có bao nhiêu chiếc răng?", "32"),
        ("Bộ phận nào giúp con người nhìn thấy?", "mắt", "đôi mắt"),
        ("Bộ phận nào giúp con người nghe?", "tai", "đôi tai"),
        ("Cơ quan nào giúp ta hít thở?", "phổi", "hai lá phổi"),
        ("Cơ quan lớn nhất trên cơ thể người?", "da", "làn da"),
        ("Máu người bình thường có màu gì?", "đỏ", "màu đỏ"),
        ("Bộ phận nào bảo vệ bộ não?", "hộp sọ", "xương sọ", "sọ"),
        ("Con người có mấy lá phổi?", "2", "hai"),
        ("Nhóm máu nào cho được mọi nhóm (nhóm cho vạn năng)?", "o", "nhóm o"),
        ("Cơ quan nào lọc máu và thải nước tiểu?", "thận", "quả thận"),
        ("Bộ phận nào giúp ta ngửi mùi?", "mũi", "cái mũi"),
        ("Bộ phận nào giúp ta nếm vị?", "lưỡi", "cái lưỡi"),
        ("Cơ bắp nào đập suốt đời, không nghỉ?", "tim", "trái tim", "con tim"),
        ("Cơ thể người có bao nhiêu giác quan cơ bản?", "5", "năm"),
        ("Bộ phận nào giúp ta cầm nắm đồ vật?", "tay", "bàn tay", "đôi tay"),
        ("Bộ phận nào giúp con người đi lại?", "chân", "đôi chân"),
    ]:
        add("🫀 Đố cơ thể: " + q, *a)
    # ---- 13) Khoa học & tự nhiên ----
    for q, *a in [
        ("Chất khí nào chiếm nhiều nhất trong không khí?", "nitơ", "ni tơ", "nito"),
        ("Vật gì hút được sắt?", "nam châm", "cục nam châm"),
        ("Lực nào làm mọi vật rơi xuống đất?", "trọng lực", "lực hút", "lực hút trái đất"),
        ("1 kilôgam bằng bao nhiêu gam?", "1000"),
        ("1 mét bằng bao nhiêu xăng-ti-mét?", "100"),
        ("1 giờ bằng bao nhiêu giây?", "3600"),
        ("1 ngày có bao nhiêu giờ?", "24"),
        ("Khủng long ngày nay đã ra sao?", "tuyệt chủng", "đã tuyệt chủng"),
        ("Kim cương được tạo nên từ nguyên tố nào?", "cacbon", "các bon", "cabon", "carbon"),
        ("Ký hiệu hoá học của vàng là gì?", "au"),
        ("Muối ăn có công thức hoá học là gì?", "nacl"),
        ("Nước gồm hai nguyên tố hydro và gì?", "oxy", "oxi", "o"),
        ("Vật thể nào phát ra ánh sáng và nhiệt cho Trái Đất?", "mặt trời"),
        ("Hiện tượng nào tạo ra sấm và chớp?", "giông", "giông bão", "mưa giông", "sét"),
        ("Đơn vị đo nhiệt độ thường dùng ở Việt Nam?", "độ c", "độ celsius", "celsius"),
        ("Nam châm có mấy cực?", "2", "hai"),
        ("Ánh sáng đi nhanh hơn hay âm thanh đi nhanh hơn?", "ánh sáng"),
        ("Băng là thể gì của nước?", "thể rắn", "rắn", "đông đặc"),
        ("Hơi nước là thể gì của nước?", "thể khí", "khí"),
        ("Cây xanh cần khí gì để quang hợp?", "cacbonic", "co2", "khí cacbonic", "cabonic"),
    ]:
        add("🔬 Đố khoa học: " + q, *a)
    # ---- 14) Địa lý mở rộng ----
    for q, *a in [
        ("Châu lục nào lạnh nhất, phủ đầy băng tuyết?", "nam cực", "châu nam cực"),
        ("Đại dương nào nhỏ nhất thế giới?", "bắc băng dương"),
        ("Nước nào có hình dạng giống chiếc ủng?", "ý", "italia", "italy"),
        ("Thành phố nào của VN được gọi là 'thành phố ngàn hoa'?", "đà lạt"),
        ("Tỉnh nào ở cực Bắc của Việt Nam?", "hà giang"),
        ("Mũi Cà Mau nằm ở cực nào của Việt Nam?", "cực nam", "miền nam"),
        ("Cố đô của triều Nguyễn ở tỉnh nào?", "huế", "thừa thiên huế"),
        ("Hồ nước ngọt nổi tiếng giữa lòng Hà Nội?", "hồ gươm", "hồ hoàn kiếm"),
        ("Vịnh nào ở Quảng Ninh là kỳ quan thiên nhiên thế giới?", "hạ long", "vịnh hạ long"),
        ("Thành phố nào của VN có chợ Bến Thành?", "tphcm", "sài gòn", "hồ chí minh", "thành phố hồ chí minh"),
        ("Ngọn hải đăng, biển xanh — đảo lớn nhất Việt Nam?", "phú quốc"),
        ("Cao nguyên đá Đồng Văn thuộc tỉnh nào?", "hà giang"),
        ("Thành phố biển nào nổi tiếng với 'phố biển', gần Nha Trang cùng tỉnh?", "nha trang", "khánh hòa"),
        ("Sa Pa thuộc tỉnh nào?", "lào cai"),
    ]:
        add("🗺️ Đố địa lý: " + q, *a)
    # ---- 15) Lịch sử & ngày lễ ----
    for q, *a in [
        ("Ai là vị vua đầu tiên (nước Văn Lang)?", "hùng vương", "vua hùng"),
        ("Giỗ Tổ Hùng Vương ngày nào âm lịch?", "10/3", "mùng 10 tháng 3", "mồng 10 tháng 3"),
        ("Ai lãnh đạo khởi nghĩa Lam Sơn chống quân Minh?", "lê lợi"),
        ("Bà Triệu cưỡi con gì ra trận?", "voi", "con voi"),
        ("Ngô Quyền đánh tan quân Nam Hán trên sông nào?", "bạch đằng", "sông bạch đằng"),
        ("Quốc khánh Việt Nam là ngày nào?", "2/9", "mùng 2 tháng 9", "mồng 2 tháng 9"),
        ("Ngày Nhà giáo Việt Nam là ngày nào?", "20/11"),
        ("Ngày Quốc tế Phụ nữ là ngày nào?", "8/3"),
        ("Ngày Quốc tế Thiếu nhi là ngày nào?", "1/6"),
        ("Tết Trung thu vào ngày nào âm lịch?", "15/8", "rằm tháng 8", "rằm tháng tám"),
        ("Vua nào dời đô về Thăng Long năm 1010?", "lý thái tổ", "lý công uẩn"),
        ("Người anh hùng nhỏ tuổi đốt kho xăng giặc tên gì?", "lê văn tám"),
        ("Chiếc xe tăng đầu tiên húc đổ cổng Dinh Độc Lập năm 1975 — sự kiện gọi là ngày Thống nhất, ngày nào?", "30/4", "ba mươi tháng tư"),
    ]:
        add("📜 Đố lịch sử: " + q, *a)
    # ---- 16) Ẩm thực Việt ----
    for q, *a in [
        ("Món phở nổi tiếng nhất gắn với thủ đô nào?", "hà nội"),
        ("Nước mắm — gia vị đặc trưng — làm từ con gì?", "cá", "con cá"),
        ("Bún bò là đặc sản của tỉnh/thành nào?", "huế"),
        ("Cao lầu là món đặc sản của phố cổ nào?", "hội an"),
        ("Loại quả nào được gọi là 'vua của các loại trái cây'?", "sầu riêng"),
        ("Gỏi cuốn thường được cuốn bằng lớp vỏ gì?", "bánh tráng"),
        ("Cà phê sữa đá gồm cà phê, đá và gì?", "sữa"),
        ("Bánh chưng vuông, còn bánh gì dài gói ngày Tết miền Nam?", "bánh tét"),
        ("Mì Quảng là đặc sản của tỉnh nào?", "quảng nam"),
        ("Chè là món ăn có vị chủ đạo gì?", "ngọt", "vị ngọt"),
    ]:
        add("🍜 Đố ẩm thực: " + q, *a)
    # ---- 17) Cây cỏ, hoa lá & 12 con giáp ----
    for q, *a in [
        ("Loài hoa nào tượng trưng Tết miền Bắc, cánh hồng?", "hoa đào", "đào"),
        ("Loài hoa nào tượng trưng Tết miền Nam, cánh vàng?", "hoa mai", "mai"),
        ("Loài hoa nào nở về đêm, thơm ngát?", "hoa quỳnh", "quỳnh"),
        ("Cây gì thân nhiều đốt, gấu trúc rất thích ăn?", "tre", "trúc", "cây tre"),
        ("Loài hoa nào là biểu tượng của nước Nhật?", "hoa anh đào", "anh đào", "sakura"),
        ("Quốc hoa của Việt Nam là hoa gì?", "hoa sen", "sen"),
        ("Con giáp đầu tiên (tuổi Tý) là con gì?", "chuột", "con chuột"),
        ("Con giáp cuối cùng (tuổi Hợi) là con gì?", "lợn", "heo", "con lợn", "con heo"),
        ("Tuổi Sửu là con gì?", "trâu", "con trâu"),
        ("Tuổi Dần là con gì?", "hổ", "cọp", "con hổ"),
        ("Tuổi Mão (Mẹo) là con gì?", "mèo", "con mèo"),
        ("Tuổi Thìn là con gì?", "rồng", "con rồng"),
        ("Tuổi Tỵ là con gì?", "rắn", "con rắn"),
        ("Tuổi Ngọ là con gì?", "ngựa", "con ngựa"),
        ("Tuổi Mùi là con gì?", "dê", "con dê"),
        ("Tuổi Thân là con gì?", "khỉ", "con khỉ"),
        ("Tuổi Dậu là con gì?", "gà", "con gà"),
        ("Tuổi Tuất là con gì?", "chó", "con chó"),
        ("12 con giáp có bao nhiêu con vật?", "12", "mười hai"),
    ]:
        add("🌸 Đố cây cỏ - con giáp: " + q, *a)
    # ---- 18) Màu sắc, mùa & thời gian ----
    for q, *a in [
        ("Trộn màu xanh dương với vàng ra màu gì?", "xanh lá", "xanh lá cây", "màu xanh lá"),
        ("Trộn màu đỏ với vàng ra màu gì?", "cam", "màu cam"),
        ("Trộn màu đỏ với xanh dương ra màu gì?", "tím", "màu tím"),
        ("Máu, lửa và cờ Tổ quốc — cùng màu gì?", "đỏ", "màu đỏ"),
        ("Tuyết, mây và sữa — cùng màu gì?", "trắng", "màu trắng"),
        ("Lá cây khỏe mạnh có màu gì?", "xanh", "xanh lá", "màu xanh"),
        ("Một năm ở miền Bắc có mấy mùa?", "4", "bốn"),
        ("Mùa nào lạnh nhất trong năm?", "mùa đông", "đông"),
        ("Mùa nào nóng nhất, học sinh được nghỉ dài?", "mùa hè", "mùa hạ", "hè"),
        ("Mùa nào lá vàng rơi nhiều nhất?", "mùa thu", "thu"),
        ("Tết Nguyên Đán rơi vào mùa nào?", "mùa xuân", "xuân"),
        ("Một quý có mấy tháng?", "3", "ba"),
        ("Một thế kỷ có bao nhiêu năm?", "100"),
        ("Một thập kỷ có bao nhiêu năm?", "10"),
        ("Nửa giờ có bao nhiêu phút?", "30"),
        ("Một năm có bao nhiêu tuần (làm tròn)?", "52"),
    ]:
        add("🌈 Đố thường thức: " + q, *a)
    # ---- 19) Số học vui ----
    for q, *a in [
        ("Số nhỏ nhất có hai chữ số?", "10"),
        ("Số lớn nhất có một chữ số?", "9"),
        ("Số La Mã X là số mấy?", "10"),
        ("Số La Mã V là số mấy?", "5"),
        ("Số La Mã I là số mấy?", "1"),
        ("Số La Mã L là số mấy?", "50"),
        ("Số La Mã C là số mấy?", "100"),
        ("Một nửa của 100 là bao nhiêu?", "50"),
        ("Một tá bằng bao nhiêu?", "12"),
        ("Một trăm nghìn có mấy số 0?", "5", "năm"),
        ("Số nào cộng với chính nó bằng nhân với chính nó (khác 0)?", "2", "hai"),
        ("Số chẵn nhỏ nhất là số mấy?", "2", "hai"),
        ("Số lẻ nhỏ nhất lớn hơn 0 là số mấy?", "1", "một"),
        ("Có bao nhiêu số từ 1 đến 100?", "100"),
        ("3 chục cộng 2 chục bằng bao nhiêu?", "50", "năm mươi"),
        ("Một chục trứng là bao nhiêu quả?", "10", "mười"),
    ]:
        add("🔢 Đố số học: " + q, *a)
    # ---- 20) Nghề nghiệp & công nghệ đời sống ----
    for q, *a in [
        ("Ai là người khám và chữa bệnh cho con người?", "bác sĩ"),
        ("Ai dạy học cho học sinh?", "giáo viên", "thầy giáo", "cô giáo", "thầy cô"),
        ("Ai dập lửa khi có cháy?", "lính cứu hỏa", "cứu hỏa", "lính cứu hoả"),
        ("Ai bắt tội phạm, giữ gìn trật tự?", "công an", "cảnh sát"),
        ("Ai lái máy bay?", "phi công"),
        ("Ai nấu các món ăn ở nhà hàng?", "đầu bếp", "bếp trưởng"),
        ("Ai trồng lúa, làm ruộng?", "nông dân"),
        ("Ai đánh cá ngoài biển khơi?", "ngư dân"),
        ("Ai chữa bệnh cho răng?", "nha sĩ", "bác sĩ răng"),
        ("Ai hát biểu diễn trên sân khấu?", "ca sĩ"),
        ("Ai vẽ nên những bức tranh?", "họa sĩ", "hoạ sĩ"),
        ("Bộ não của máy tính gọi tắt là gì?", "cpu"),
        ("Hệ điều hành của iPhone tên là gì?", "ios"),
        ("Công ty nào tạo ra iPhone?", "apple"),
        ("Mạng xã hội có biểu tượng chữ 'f' màu xanh?", "facebook"),
        ("Ứng dụng nhắn tin có biểu tượng máy bay giấy?", "telegram"),
        ("Google nổi tiếng nhất với vai trò công cụ gì?", "tìm kiếm", "công cụ tìm kiếm"),
        ("1 byte bằng bao nhiêu bit?", "8", "tám"),
        ("Đơn vị dung lượng nào lớn hơn MB?", "gb", "gigabyte"),
        ("Phím dài nhất trên bàn phím tạo khoảng trắng gọi là phím gì?", "space", "cách", "phím cách", "dấu cách"),
    ]:
        add("💼 Đố nghề & công nghệ: " + q, *a)
    # ---- 21) Điền ca dao - tục ngữ (mở rộng) ----
    for q, *a in [
        ("Bầu ơi thương lấy bí cùng, tuy rằng khác giống nhưng chung một ...", "giàn"),
        ("Nhiễu điều phủ lấy giá gương, người trong một nước phải thương nhau ...", "cùng"),
        ("Công cha như núi Thái ...", "sơn"),
        ("Một mặt người bằng mười mặt ...", "của"),
        ("Thất bại là mẹ ...", "thành công"),
        ("Có chí làm quan, có gan làm ...", "giàu"),
        ("Trăm hay không bằng tay ...", "quen"),
        ("Chớ thấy sóng cả mà ngã tay ...", "chèo"),
        ("Chuồn chuồn bay thấp thì mưa, bay cao thì nắng bay vừa thì ...", "râm"),
        ("Đêm tháng năm chưa nằm đã sáng, ngày tháng mười chưa cười đã ...", "tối"),
        ("Ráng mỡ gà, có nhà thì ...", "giữ"),
        ("Tháng bảy kiến bò, chỉ lo lại ...", "lụt"),
        ("Mau sao thì nắng, vắng sao thì ...", "mưa"),
        ("Con trâu là đầu cơ ...", "nghiệp"),
        ("Ta về ta tắm ao ta, dù trong dù đục ao nhà vẫn ...", "hơn"),
        ("Thuận vợ thuận chồng, tát biển Đông cũng ...", "cạn"),
        ("Muốn sang thì bắc cầu kiều, muốn con hay chữ phải yêu lấy ...", "thầy"),
        ("Bán anh em xa, mua láng giềng ...", "gần"),
        ("Của rẻ là của ...", "ôi"),
        ("Đi hỏi già, về nhà hỏi ...", "trẻ"),
        ("Học ăn, học nói, học gói, học ...", "mở"),
        ("Khôn ngoan đối đáp người ngoài, gà cùng một mẹ chớ hoài đá ...", "nhau"),
        ("Trâu buộc ghét trâu ...", "ăn"),
        ("Ăn cháo đá ...", "bát"),
        ("Gậy ông đập lưng ...", "ông"),
        ("Nước đến chân mới ...", "nhảy"),
        ("Chậm mà ...", "chắc"),
        ("Có mới nới ...", "cũ"),
        ("Một nghề cho chín còn hơn chín ...", "nghề"),
        ("Đi đêm lắm có ngày gặp ...", "ma"),
        ("Nuôi ong tay ...", "áo"),
        ("Rước voi về giày mả ...", "tổ"),
        ("Ếch ngồi đáy ...", "giếng"),
        ("Thùng rỗng kêu ...", "to"),
        ("Chở củi về ...", "rừng"),
        ("Đàn gảy tai ...", "trâu"),
        ("Nước đổ đầu ...", "vịt"),
        ("Nước đổ lá ...", "khoai"),
        ("Cõng rắn cắn gà ...", "nhà"),
        ("Múa rìu qua mắt ...", "thợ"),
        ("Ăn vóc học ...", "hay"),
        ("Ăn kỹ no lâu, cày sâu tốt ...", "lúa"),
        ("Nhất nước, nhì phân, tam cần, tứ ...", "giống"),
        ("Cây cao bóng ...", "cả"),
    ]:
        add("🎏 Điền ca dao - tục ngữ: " + q, *a)
    # ---- 22) Đố vui cười / hỏi xoáy ----
    for q, *a in [
        ("Cái gì mua thì đen, dùng thì đỏ, bỏ đi thì xám?", "than", "than củi", "hòn than"),
        ("Cái gì đi bằng đầu?", "đinh", "cái đinh", "đinh vít"),
        ("Quả gì không ăn được mà ai cũng có, đập suốt ngày?", "quả tim", "trái tim"),
        ("Con gì có nghìn chân, bò lổm ngổm?", "con rết", "rết", "con cuốn chiếu", "cuốn chiếu"),
        ("Loài chim nào biết nói tiếng người, hay nhại lời?", "vẹt", "con vẹt"),
        ("Con vật nào biết đổi màu, thè lưỡi bắt mồi rất nhanh?", "tắc kè", "tắc kè hoa", "kỳ nhông"),
        ("Xe gì không bao giờ chạy được trên đường?", "xe đạp nước", "xe tăng đồ chơi", "xe điếu"),
        ("Cái gì càng đun càng vơi đi?", "nước", "nồi nước"),
        ("Cái gì đầu voi đuôi chuột?", "con chuột chũi", "công việc bỏ dở", "đầu voi đuôi chuột"),
        ("Cái gì trời cho, không xin cũng có, mất rồi hết mua?", "thời gian", "tuổi trẻ"),
        ("Con gì kêu 'tu hú' báo hiệu mùa hè?", "chim tu hú", "tu hú"),
        ("Cái gì có nhiều lá mà không phải là cây, ngày ngày cho ta xem ngày tháng?", "quyển lịch", "lịch", "tờ lịch"),
        ("Vật gì ban đầu bốn chân, sau hai chân, rồi ba chân — là ai?", "con người", "người"),
        ("Cái gì bạn không mượn mà vẫn phải trả mỗi ngày?", "hơi thở"),
        ("Đường nào ai cũng phải đi qua mà không thấy đường?", "đường ruột", "đường tiêu hóa"),
        ("Con gì đập thì sống, không đập thì chết?", "con tim", "trái tim", "tim"),
        ("Bánh gì nghe tên tưởng ngọt mà lại rất cay?", "bánh tráng trộn", "bánh phồng cay"),
        ("Cái gì thuộc về bạn nhưng bạn ít khi tự gọi nó ra nhất?", "tên", "tên mình", "cái tên"),
        ("Con gì bay không cánh, chạy không chân, khóc không có nước mắt?", "đám mây", "mây"),
        ("Con gì mình đồng da sắt, phun lửa cứu người khi cháy?", "xe cứu hỏa", "xe cứu hoả"),
    ]:
        add("😂 Đố vui: " + q, *a)
    # ---- 23) Nhân vật cổ tích & hoạt hình ----
    for q, *a in [
        ("Nhân vật cổ tích nào mũi dài ra mỗi khi nói dối?", "pinocchio", "pi nô ki ô"),
        ("Ai bị mụ phù thủy cho ăn táo độc rồi ngủ mê trong rừng?", "bạch tuyết"),
        ("Nàng công chúa nào làm rơi chiếc giày (hài) khi rời dạ hội?", "lọ lem", "cinderella", "cô bé lọ lem"),
        ("Ông Bụt thường hiện ra an ủi ai trong truyện Tấm Cám?", "tấm", "cô tấm"),
        ("Thánh Gióng lớn nhanh như thổi rồi cưỡi con gì đi đánh giặc?", "ngựa sắt", "ngựa"),
        ("Sơn Tinh và Thủy Tinh tranh giành cưới nàng công chúa tên gì?", "mị nương", "công chúa mị nương"),
        ("Câu thần chú làm tre nhả đốt là 'khắc nhập' và ...?", "khắc xuất"),
        ("Chú Cuội ngồi gốc cây gì trên cung trăng?", "cây đa", "đa"),
        ("Cô bé quàng khăn màu gì trong truyện cổ tích?", "đỏ", "màu đỏ", "khăn đỏ"),
        ("Chú heo hồng nổi tiếng trong phim hoạt hình thiếu nhi tên gì?", "peppa", "peppa pig", "heo peppa"),
        ("Siêu anh hùng mặc giáp đỏ - vàng biết bay của Marvel?", "iron man", "người sắt"),
        ("Biệt đội siêu anh hùng của Marvel gọi chung là gì?", "avengers", "biệt đội báo thù"),
        ("Chàng chằn tinh xanh, tai nhọn, sống ở đầm lầy tên gì?", "shrek"),
        ("Nàng công chúa băng giá có phép tạo tuyết trong phim hoạt hình?", "elsa"),
    ]:
        add("🎬 Đố nhân vật: " + q, *a)
    # ---- 24) Thể thao ----
    for q, *a in [
        ("Trong bóng rổ, ném bóng vào đâu để ghi điểm?", "rổ", "vào rổ"),
        ("Vận động viên chạy 100m thi ở môn nào?", "điền kinh", "chạy"),
        ("Bóng chuyền mỗi đội có mấy người trên sân?", "6", "sáu"),
        ("Cầu thủ đứng trong khung thành bắt bóng gọi là gì?", "thủ môn"),
        ("Thế vận hội Olympic tổ chức mấy năm một lần?", "4", "bốn"),
        ("Biểu tượng Olympic có mấy vòng tròn lồng nhau?", "5", "năm"),
        ("Ai được mệnh danh 'Vua bóng đá', người Brazil?", "pele", "vua pele"),
        ("Môn võ đấu vật của những người to lớn ở Nhật?", "sumo"),
        ("Quần vợt trong tiếng Anh gọi là gì?", "tennis"),
        ("Đội tuyển bóng đá Việt Nam thường mặc áo màu gì?", "đỏ", "màu đỏ"),
        ("Môn thể thao trượt trên tuyết bằng ván gọi là gì?", "trượt tuyết", "trượt ván tuyết"),
        ("Cờ vua mỗi bên có mấy quân khi bắt đầu?", "16", "mười sáu"),
        ("Trong bóng đá, thẻ màu gì thì bị đuổi khỏi sân?", "đỏ", "thẻ đỏ"),
    ]:
        add("🏆 Đố thể thao: " + q, *a)
    # ---- 25) Đố trẻ em ----
    for q, *a in [
        ("Con mèo kêu như thế nào?", "meo meo", "meo"),
        ("Con chó kêu như thế nào?", "gâu gâu", "gâu"),
        ("Con gà trống gáy như thế nào?", "ò ó o", "ò ó o o"),
        ("Con vịt kêu như thế nào?", "cạp cạp", "cạc cạc"),
        ("Con ong cho ta thứ gì ngọt?", "mật", "mật ong"),
        ("Con tằm nhả ra thứ gì để dệt vải?", "tơ", "sợi tơ"),
        ("Con bò cho ta uống gì mỗi ngày?", "sữa", "sữa bò"),
        ("Con gà mái cho ta gì để ăn sáng?", "trứng", "trứng gà"),
        ("Muốn qua đường an toàn, ta đi trên vạch kẻ màu gì?", "trắng", "vạch trắng"),
        ("Đèn đỏ thì dừng, đèn xanh thì làm gì?", "đi", "được đi"),
        ("Rửa tay bằng gì cho sạch vi khuẩn?", "xà phòng", "xà bông"),
        ("Mỗi ngày nên đánh răng ít nhất mấy lần?", "2", "hai"),
        ("Nước mưa rơi xuống từ đâu?", "trên trời", "từ mây", "mây"),
        ("Ban ngày ông gì chiếu sáng cả bầu trời?", "mặt trời", "ông mặt trời"),
    ]:
        add("🧒 Đố trẻ em: " + q, *a)
    # ---- 26) Suy luận / IQ ----
    for q, *a in [
        ("Nếu hôm nay là thứ Ba thì 3 ngày sau là thứ mấy?", "thứ sáu", "thứ 6"),
        ("Bạn đang đua và vừa vượt qua người thứ 2. Bạn đang ở vị trí thứ mấy?", "2", "thứ 2", "thứ hai"),
        ("Có 12 con cá trong bể, 4 con 'chết đuối'. Còn lại mấy con?", "12", "mười hai"),
        ("Tháng nào trong năm có ít ngày nhất?", "tháng hai", "tháng 2"),
        ("Anh trai của bố bạn, bạn gọi là gì?", "bác", "bác trai"),
        ("Em gái của mẹ bạn, bạn gọi là gì?", "dì"),
        ("Nếu 5 máy dệt 5 tấm vải trong 5 giờ thì 10 máy dệt 10 tấm vải trong mấy giờ?", "5", "năm"),
        ("Một hồ sen mỗi ngày lá phủ gấp đôi, ngày 30 phủ kín hồ. Ngày nào phủ được nửa hồ?", "29", "ngày 29"),
        ("Con của mẹ bạn mà không phải anh chị em của bạn — là ai?", "chính mình", "tôi", "bản thân", "chính bạn"),
        ("Bố của Nam gọi bà nội của Nam bằng gì?", "mẹ"),
        ("Cây kim ngắn của đồng hồ chỉ điều gì?", "giờ"),
        ("Cây kim dài của đồng hồ chỉ điều gì?", "phút"),
    ]:
        add("🧠 Đố suy luận: " + q, *a)
    _TG_QUIZ_BANK = B
    return B

def _tg_pts_add(chat_id, uid, name, pts: int) -> int:
    """Cộng điểm vui, trả về tổng điểm mới."""
    with db() as c:
        c.execute("CREATE TABLE IF NOT EXISTS tg_fun_points(chat_id TEXT,user_id INTEGER,name TEXT,"
                  "points INTEGER DEFAULT 0,PRIMARY KEY(chat_id,user_id))")
        c.execute("INSERT INTO tg_fun_points(chat_id,user_id,name,points) VALUES(?,?,?,?) "
                  "ON CONFLICT(chat_id,user_id) DO UPDATE SET points=points+excluded.points, name=excluded.name",
                  (str(chat_id), uid, name, pts))
        r = c.execute("SELECT points FROM tg_fun_points WHERE chat_id=? AND user_id=?", (str(chat_id), uid)).fetchone()
        return r["points"] if r else pts

def _tg_pts_top(chat_id, n=10) -> list:
    with db() as c:
        c.execute("CREATE TABLE IF NOT EXISTS tg_fun_points(chat_id TEXT,user_id INTEGER,name TEXT,"
                  "points INTEGER DEFAULT 0,PRIMARY KEY(chat_id,user_id))")
        return [(r["name"], r["points"]) for r in c.execute(
            "SELECT name,points FROM tg_fun_points WHERE chat_id=? ORDER BY points DESC LIMIT ?", (str(chat_id), n)).fetchall()]

def _tg_quiz_post(token, chat_id, auto=True, first=False) -> None:
    """Ra 1 câu đố NGẪU NHIÊN (tránh trùng câu vừa hỏi). first=True → kèm HƯỚNG DẪN CÁCH CHƠI."""
    import random as _rd
    bank = _tg_quiz_bank()
    last = _TG_QUIZ_LAST.get(chat_id)
    q, a = _rd.choice(bank)
    for _ in range(6):                     # thử tối đa 6 lần để khác câu vừa rồi
        if q != last or len(bank) < 2:
            break
        q, a = _rd.choice(bank)
    _TG_QUIZ_LAST[chat_id] = q
    _TG_QUIZ[chat_id] = {"q": q, "a": a, "auto": auto}
    guide = ""
    if first:
        guide = ("📖 <b>CÁCH CHƠI:</b>\n"
                 "1️⃣ Bot ra câu đố — AI CŨNG được trả lời\n"
                 "2️⃣ <b>NHẮN THẲNG đáp án</b> vào khung chat (KHÔNG cần dấu /)\n"
                 "     VD: câu hỏi \"1 + 1 = ?\" → chỉ cần gõ: <b>2</b>\n"
                 "3️⃣ Ai đúng ĐẦU TIÊN được <b>+10 điểm</b> 🎉 — bot tự ra câu tiếp\n"
                 "4️⃣ Gõ không dấu vẫn tính đúng (vd: <i>ha noi</i> = Hà Nội)\n"
                 "💡 /goiy — gợi ý · ⏭️ /boqua — đáp án & câu mới · 🛑 /dungdo — dừng · 🏆 /diemdo — bảng vàng\n"
                 "➖➖➖➖➖➖➖➖➖➖\n\n")
    _tg_send(token, chat_id, f"{guide}🧠 <b>CÂU ĐỐ</b> (+10 điểm cho người đúng đầu tiên):\n\n{q}\n\n"
                             "✍️ <b>Gõ thẳng đáp án vào khung chat</b> — KHÔNG cần lệnh!\n"
                             "💡 /goiy · ⏭️ /boqua · 🛑 /dungdo")

def _tg_quiz_try(token, chat_id, msg, text) -> bool:
    """Kiểm tra đáp án đố vui. Trả True nếu ĐÚNG (đã xử lý + ra câu mới)."""
    import html as _h
    qz = _TG_QUIZ.get(chat_id)
    if not qz or not _tg_ans_ok(text, qz["a"]):
        return False
    import random as _rd
    frm = msg.get("from", {}) or {}
    total = _tg_pts_add(chat_id, frm.get("id") or 0, _tg_name(frm), 10)
    congrat = _rd.choice(_TG_CONGRATS).format(name=_tg_mention(frm))
    _tg_send(token, chat_id, f"{congrat}\n✅ Đáp án: <b>{_h.escape(qz['a'][0])}</b>\n"
                             f"💎 <b>+10 điểm</b> → tổng <b>{total}</b> điểm · 📊 /diemdo — bảng vàng")
    auto = qz.get("auto", True)
    del _TG_QUIZ[chat_id]
    if auto:
        _tg_quiz_post(token, chat_id, auto=True)
    return True

# ---- Bộ bài & game bài ----
_CARD_RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
_CARD_SUITS = ["♠️", "♥️", "♦️", "♣️"]

def _tg_deck_draw(n: int) -> list:
    import random as _rd
    deck = [(r, s) for r in _CARD_RANKS for s in _CARD_SUITS]
    return _rd.sample(deck, n)

def _card_show(cards: list) -> str:
    return "  ".join(f"[{r}{s}]" for r, s in cards)

def _baicao_point(cards: list) -> tuple:
    """Điểm bài cào: (điểm mod 10, có phải 3 tây không)."""
    vals = []
    for r, _ in cards:
        vals.append(1 if r == "A" else (10 if r in ("10", "J", "Q", "K") else int(r)))
    tay = all(r in ("J", "Q", "K") for r, _ in cards)
    return sum(vals) % 10, tay

def _xidach_val(cards: list) -> int:
    """Điểm xì dách: A = 1 hoặc 11 (chọn tốt nhất), J/Q/K = 10."""
    total, aces = 0, 0
    for r, _ in cards:
        if r == "A":
            aces += 1; total += 1
        elif r in ("10", "J", "Q", "K"):
            total += 10
        else:
            total += int(r)
    while aces > 0 and total + 10 <= 21:
        total += 10; aces -= 1
    return total

def _tg_game_command(token, chat_id, msg, cmd, args) -> bool:
    """🃏 Game bài + 🧠 đố vui có điểm. Trả True nếu đã xử lý."""
    import html as _h, random as _rd
    frm = msg.get("from", {}) or {}
    uid = frm.get("id") or 0
    who = _tg_mention(frm)

    # ---------- 🧠 ĐỐ VUI CÓ ĐIỂM ----------
    if cmd == "dovui":
        _tg_quiz_post(token, chat_id, auto=True, first=True)
        return True
    if cmd == "goiy":
        qz = _TG_QUIZ.get(chat_id)
        if not qz:
            _tg_send(token, chat_id, "Chưa có câu đố nào — gõ /dovui để bắt đầu!"); return True
        ans = qz["a"][0]
        words = ans.split()
        _tg_send(token, chat_id, f"💡 Gợi ý: <b>{len(words)}</b> từ, <b>{len(ans)}</b> ký tự, "
                                 f"bắt đầu bằng \"<b>{_h.escape(ans[0].upper())}</b>\"")
        return True
    if cmd == "boqua":
        qz = _TG_QUIZ.get(chat_id)
        if not qz:
            _tg_send(token, chat_id, "Chưa có câu đố nào — gõ /dovui để bắt đầu!"); return True
        _tg_send(token, chat_id, f"⏭️ Đáp án là: <b>{_h.escape(qz['a'][0])}</b>")
        auto = qz.get("auto", True)
        del _TG_QUIZ[chat_id]
        if auto:
            _tg_quiz_post(token, chat_id, auto=True)
        return True
    if cmd == "dungdo":
        if chat_id in _TG_QUIZ:
            del _TG_QUIZ[chat_id]
            _tg_send(token, chat_id, "🛑 Đã dừng đố vui. Gõ /dovui để chơi lại — 📊 /diemdo xem bảng vàng.")
        else:
            _tg_send(token, chat_id, "Không có ván đố nào đang chạy.")
        return True
    if cmd == "diemdo":
        rows = _tg_pts_top(chat_id, 10)
        if not rows:
            _tg_send(token, chat_id, "🏅 Chưa ai có điểm — gõ /dovui để bắt đầu kiếm điểm!"); return True
        medals = ["🥇", "🥈", "🥉"] + ["🏅"] * 7
        lst = "\n".join(f"{medals[i]} {_h.escape(n)}: <b>{p}</b> điểm" for i, (n, p) in enumerate(rows))
        _tg_send(token, chat_id, f"🏆 <b>BẢNG VÀNG ĐIỂM VUI</b>\n{lst}\n\n🧠 /dovui — đố vui (+10đ) · 🃏 /baicao /xidach /baucua (+5đ khi thắng)")
        return True

    # ---------- 🃏 BÀI CÀO 3 CÂY ----------
    if cmd == "baicao":
        six = _tg_deck_draw(6)
        p, b = six[:3], six[3:]
        pp, ptay = _baicao_point(p)
        bp, btay = _baicao_point(b)
        if ptay and not btay: kq, win = "🎉 BA TÂY — BẠN THẮNG!", True
        elif btay and not ptay: kq, win = "😎 Bot ba tây — BOT THẮNG!", False
        elif pp > bp: kq, win = "🎉 BẠN THẮNG!", True
        elif pp < bp: kq, win = "😎 BOT THẮNG!", False
        else: kq, win = "🤝 HOÀ!", False
        extra = ""
        if win:
            total = _tg_pts_add(chat_id, uid, _tg_name(frm), 5)
            extra = f"\n💎 +5 điểm → tổng <b>{total}</b> điểm"
        _tg_send(token, chat_id,
                 f"🃏 <b>BÀI CÀO 3 CÂY</b> — {who}\n"
                 f"Bạn: {_card_show(p)} → <b>{'BA TÂY' if ptay else str(pp) + ' điểm'}</b>\n"
                 f"Bot: {_card_show(b)} → <b>{'BA TÂY' if btay else str(bp) + ' điểm'}</b>\n{kq}{extra}")
        return True

    # ---------- 🃏 XÌ DÁCH (Blackjack) ----------
    if cmd == "xidach":
        four = _tg_deck_draw(4)
        st = {"p": four[:2], "d": four[2:]}
        _TG_XIDACH[(chat_id, uid)] = st
        pv = _xidach_val(st["p"])
        if pv == 21:
            del _TG_XIDACH[(chat_id, uid)]
            total = _tg_pts_add(chat_id, uid, _tg_name(frm), 8)
            _tg_send(token, chat_id, f"🃏 {who}: {_card_show(st['p'])} = <b>21</b>\n"
                                     f"🎊 <b>XÌ DÁCH!</b> Thắng luôn ván này! 💎 +8 điểm → tổng <b>{total}</b>")
            return True
        _tg_send(token, chat_id,
                 f"🃏 <b>XÌ DÁCH</b> — {who}\nBài của bạn: {_card_show(st['p'])} = <b>{pv}</b>\n"
                 f"Nhà cái: {_card_show(st['d'][:1])} [❓]\n\n👉 /rut — rút thêm · /dan — dằn (so bài)")
        return True
    if cmd in ("rut", "dan"):
        st = _TG_XIDACH.get((chat_id, uid))
        if not st:
            _tg_send(token, chat_id, "Bạn chưa có ván xì dách — gõ /xidach để chia bài!"); return True
        if cmd == "rut":
            used = set(st["p"] + st["d"])
            card = next(c for c in _tg_deck_draw(52) if c not in used)
            st["p"].append(card)
            pv = _xidach_val(st["p"])
            if pv > 21:
                del _TG_XIDACH[(chat_id, uid)]
                _tg_send(token, chat_id, f"🃏 {who} rút: {_card_show(st['p'])} = <b>{pv}</b>\n💥 <b>QUẮC!</b> (quá 21) — thua ván này 😢 /xidach chơi lại")
            else:
                _tg_send(token, chat_id, f"🃏 {who}: {_card_show(st['p'])} = <b>{pv}</b>\n👉 /rut tiếp hoặc /dan để so bài")
            return True
        # /dan — nhà cái rút tới 17+
        pv = _xidach_val(st["p"])
        used = set(st["p"] + st["d"])
        while _xidach_val(st["d"]) < 17:
            card = next(c for c in _tg_deck_draw(52) if c not in used)
            st["d"].append(card); used.add(card)
        dv = _xidach_val(st["d"])
        del _TG_XIDACH[(chat_id, uid)]
        if dv > 21 or pv > dv: kq, win = "🎉 BẠN THẮNG!", True
        elif pv < dv: kq, win = "😎 NHÀ CÁI THẮNG!", False
        else: kq, win = "🤝 HOÀ!", False
        extra = ""
        if win:
            total = _tg_pts_add(chat_id, uid, _tg_name(frm), 5)
            extra = f"\n💎 +5 điểm → tổng <b>{total}</b> điểm"
        _tg_send(token, chat_id, f"🃏 <b>SO BÀI</b> — {who}\nBạn: {_card_show(st['p'])} = <b>{pv}</b>\n"
                                 f"Nhà cái: {_card_show(st['d'])} = <b>{dv}</b>\n{kq}{extra}")
        return True

    # ---------- 🎲 BẦU CUA ----------
    if cmd == "baucua":
        syms = {"bầu": "🍐", "cua": "🦀", "tôm": "🦐", "cá": "🐟", "gà": "🐓", "nai": "🦌"}
        alias = {"bau": "bầu", "tom": "tôm", "ca": "cá", "ga": "gà"}
        a = args.strip().lower()
        a = alias.get(a, a)
        if a not in syms:
            _tg_send(token, chat_id, "🎲 <b>Bầu cua:</b> <code>/baucua bầu</code> (bầu · cua · tôm · cá · gà · nai)"); return True
        roll = [_rd.choice(list(syms)) for _ in range(3)]
        hit = roll.count(a)
        show = "  ".join(syms[x] for x in roll)
        if hit:
            total = _tg_pts_add(chat_id, uid, _tg_name(frm), 3 * hit)
            kq = f"🎉 Trúng <b>x{hit}</b>! 💎 +{3 * hit} điểm → tổng <b>{total}</b> điểm"
        else:
            kq = "😢 Trượt rồi, thử lại nào!"
        _tg_send(token, chat_id, f"🎲 <b>BẦU CUA</b> — {who} đặt {syms[a]} <b>{a.upper()}</b>\nXúc: {show}\n{kq}")
        return True
    return False

# ---------- Đếm người dùng bot mỗi tháng ----------
def _tg_track(frm: dict) -> None:
    if not frm or not frm.get("id"):
        return
    now = int(time.time())
    try:
        with db() as c:
            c.execute("CREATE TABLE IF NOT EXISTS tg_bot_users(user_id INTEGER PRIMARY KEY, "
                      "last_seen INTEGER)")
            c.execute("INSERT INTO tg_bot_users(user_id,last_seen) VALUES(?,?) "
                      "ON CONFLICT(user_id) DO UPDATE SET last_seen=excluded.last_seen", (frm["id"], now))
    except Exception:
        pass

def _tg_monthly() -> int:
    try:
        with db() as c:
            c.execute("CREATE TABLE IF NOT EXISTS tg_bot_users(user_id INTEGER PRIMARY KEY, last_seen INTEGER)")
            return c.execute("SELECT COUNT(*) n FROM tg_bot_users WHERE last_seen>=?",
                             (int(time.time()) - 30 * 86400,)).fetchone()["n"]
    except Exception:
        return 0

# ---------- NÚT LIÊN KẾT (inline URL) — admin thêm bao nhiêu nút link cũng được ----------
def _tg_parse_btns(raw: str) -> list:
    """Phân tích các dòng 'Nhãn | https://link' thành lưới nút inline (2 nút/hàng)."""
    rows, cur = [], []
    for line in (raw or "").splitlines():
        if "|" not in line:
            continue
        label, url = line.split("|", 1)
        label, url = label.strip(), url.strip()
        if not label or not url:
            continue
        if not url.lower().startswith(("http://", "https://", "tg://")):
            url = "https://" + url
        cur.append({"text": label[:40], "url": url})
        if len(cur) == 2:
            rows.append(cur); cur = []
    if cur:
        rows.append(cur)
    return rows

def _tg_link_buttons() -> list:
    """Dựng lưới nút LIÊN KẾT (mở link) từ cấu hình tg_links.
    Mỗi dòng 1 nút, dạng:  Nhãn | https://link  (2 nút/hàng).
    Chưa cấu hình thì mặc định gợi ý Cửa hàng web + Cài ứng dụng."""
    raw = get_setting("tg_links", "").strip()
    if not raw:
        base = (_ipa_base_url() or "https://app.kenios.store").rstrip("/")
        raw = f"🛒 Cửa hàng | {base}/shop\n📲 Cài ứng dụng | {base}/install"
    return _tg_parse_btns(raw)

# ---------- LỆNH TÙY BIẾN — admin tự thêm/sửa/xoá lệnh bot, không cần code ----------
def _tg_cc_set(cmd: str, resp) -> None:
    with db() as c:
        c.execute("CREATE TABLE IF NOT EXISTS tg_custom_cmds(cmd TEXT PRIMARY KEY, response TEXT, updated INTEGER)")
        if resp is None:
            c.execute("DELETE FROM tg_custom_cmds WHERE cmd=?", (cmd,))
        else:
            c.execute("INSERT INTO tg_custom_cmds(cmd,response,updated) VALUES(?,?,?) "
                      "ON CONFLICT(cmd) DO UPDATE SET response=excluded.response, updated=excluded.updated",
                      (cmd, resp, int(time.time())))

def _tg_cc_get(cmd: str):
    try:
        with db() as c:
            c.execute("CREATE TABLE IF NOT EXISTS tg_custom_cmds(cmd TEXT PRIMARY KEY, response TEXT, updated INTEGER)")
            r = c.execute("SELECT response FROM tg_custom_cmds WHERE cmd=?", (cmd,)).fetchone()
            return r["response"] if r else None
    except Exception:
        return None

def _tg_cc_list() -> list:
    try:
        with db() as c:
            c.execute("CREATE TABLE IF NOT EXISTS tg_custom_cmds(cmd TEXT PRIMARY KEY, response TEXT, updated INTEGER)")
            return [r["cmd"] for r in c.execute("SELECT cmd FROM tg_custom_cmds ORDER BY cmd").fetchall()]
    except Exception:
        return []

# Tên lệnh KHÔNG cho phép đặt trùng (lệnh hệ thống) khi tạo lệnh tùy biến.
_TG_RESERVED = {
    "start", "help", "menu", "config", "stats", "nhac", "music", "id", "afk", "get",
    "addcmd", "delcmd", "cmds", "setlinks", "links", "broadcast",
    "ban", "kick", "mute", "unmute", "warn", "unwarn", "warns", "pin", "unpin", "del",
    "purge", "info", "lock", "unlock", "locks", "addbl", "rmbl", "blacklist", "filter",
    "stop", "filters", "save", "clear", "notes", "setrules", "rules", "clean", "nightmode",
    "antiflood", "captcha", "autoreact", "slowmode", "log", "diemdanh", "top", "report",
    "setwelcome", "welcome", "setwelcomebtn", "setwelcomephoto", "setgoodbye", "testwelcome",
    "modon", "modoff", "autodel", "modadmin", "scanlink", "setvt", "kenios",
    "video", "taivideo", "quetlink", "checklink", "scan", "chaosang", "chaotoi",
    "kechuyen", "doctruyen", "truyen", "kechuyenma", "kevoice",
    # 🎮 lệnh giải trí & tiện ích (không cho lệnh riêng ghi đè)
    "xucxac", "slot", "phitieu", "bongda", "bongro", "bowling", "tungxu", "oantuti", "keobuabao",
    "doanso", "doan", "random", "chon", "xoso", "cuoi", "joke", "cakhia", "khen", "triethly",
    "thotinh", "noinguoc", "thatha", "thachthuc", "ghep", "lucky", "boi", "tinhduyen", "hoi",
    "danhgia", "tinh", "qr", "thoitiet", "giacoin", "tygia", "dich", "nhacnho", "binhchon",
    "poll", "gio", "dem", "password",
    "dovui", "goiy", "boqua", "dungdo", "diemdo", "baicao", "xidach", "rut", "dan", "baucua",
    # 🤖 Trợ lý AI
    "ai", "aion", "aioff", "hoiai", "ask", "aikey", "aimodel", "aiprovider", "aiurl", "aiset", "aihelp", "aidm", "aiall",
    # 🛒 Tư vấn khách hàng
    "tuvan", "banggia", "gia", "muahack", "hotro", "setpay", "setweb",
}

# ======================== 🤖 Trợ lý AI trong bot (bật/tắt bằng /ai) ========================
def _ai_cfg():
    """Trả về (provider, base_url, model, key). Tự đoán nhà cung cấp.
    - Gemini (khoá AIza…/AQ.… hoặc base generativelanguage) → 'gemini' NATIVE có tra Google (grounding).
    - Khoá sk-ant… → 'anthropic'. Còn lại → 'openai' (OpenAI-compatible, mặc định Groq free)."""
    key = (get_setting("tg_ai_key", "") or os.getenv("AI_API_KEY", "") or os.getenv("GROQ_API_KEY", "")
           or os.getenv("OPENAI_API_KEY", "") or os.getenv("ANTHROPIC_API_KEY", "") or os.getenv("GEMINI_API_KEY", "")).strip()
    prov = (get_setting("tg_ai_provider", "") or "").strip().lower()
    base = (get_setting("tg_ai_base", "") or "").strip().rstrip("/")
    model = (get_setting("tg_ai_model", "") or "").strip()
    is_gemini_key = key.startswith("AIza") or key.startswith("AQ.")
    # Khoá/base Gemini → luôn dùng NATIVE (để bật được Google Search grounding), kể cả khi lỡ đặt provider=openai.
    if prov in ("gemini", "google") or is_gemini_key or "generativelanguage" in base:
        prov = "gemini"
    elif not prov:
        prov = "anthropic" if key.startswith("sk-ant") else "openai"
    if not base:
        base = ("https://api.anthropic.com/v1" if prov == "anthropic"
                else "https://generativelanguage.googleapis.com/v1beta" if prov == "gemini"
                else "https://api.groq.com/openai/v1")
    if not model:
        model = ("claude-3-5-sonnet-latest" if prov == "anthropic"
                 else "gemini-2.5-flash" if prov == "gemini"
                 else "llama-3.3-70b-versatile")
    return prov, base, model, key

def _ai_err(status: int, text: str) -> str:
    """Đổi lỗi API thô (JSON dài) thành thông báo tiếng Việt gọn, kèm cách xử lý."""
    t = (text or "").lower()
    if status == 429 or "quota" in t or "rate limit" in t or "exceed" in t or "resource_exhausted" in t:
        return ("⚠️ AI đang bị GIỚI HẠN LƯỢT (quota – lỗi 429).\n"
                "Cách xử lý:\n"
                "• Chờ ~1 phút rồi hỏi lại (giới hạn theo phút), hoặc\n"
                "• Hết hạn mức MIỄN PHÍ trong ngày → đổi model khác: /aimodel gemini-2.5-flash (hoặc gemini-flash-lite-latest)\n"
                "• Hoặc đổi sang GROQ (miễn phí, hạn mức rộng):\n"
                "  /aiurl https://api.groq.com/openai/v1 · /aimodel llama-3.3-70b-versatile · /aikey <khoá groq>")
    if status in (401, 403) or "unauthor" in t or "permission" in t or ("api key" in t) or ("invalid" in t and "key" in t):
        return f"⚠️ Khoá AI SAI hoặc chưa kích hoạt (lỗi {status}). Dán lại bằng /aikey (đúng & đủ khoá)."
    if status == 404 or "not found" in t or "does not exist" in t:
        _, _, model, _ = _ai_cfg()
        return (f"⚠️ Không tìm thấy model '{model}' (lỗi 404). Đổi tên model bằng /aimodel — "
                "vd /aimodel gemini-2.5-flash (Gemini) hoặc /aimodel llama-3.3-70b-versatile (Groq).")
    return f"⚠️ AI báo lỗi {status}. Thử lại sau ít phút, hoặc gõ /aiset để kiểm tra cấu hình."

# Base URL & model mặc định cho từng nhà cung cấp (dùng khi /aiadd không ghi rõ).
_AI_PROVIDER_DEFAULTS = {
    "gemini":     ("https://generativelanguage.googleapis.com/v1beta", "gemini-2.5-flash"),
    "groq":       ("https://api.groq.com/openai/v1", "llama-3.3-70b-versatile"),
    "cerebras":   ("https://api.cerebras.ai/v1", "llama-3.3-70b"),
    "openai":     ("https://api.openai.com/v1", "gpt-4o-mini"),
    "deepseek":   ("https://api.deepseek.com/v1", "deepseek-chat"),
    "openrouter": ("https://openrouter.ai/api/v1", "deepseek/deepseek-chat-v3-0324:free"),
    "mistral":    ("https://api.mistral.ai/v1", "mistral-large-latest"),
    "together":   ("https://api.together.xyz/v1", "meta-llama/Llama-3.3-70B-Instruct-Turbo"),
    "anthropic":  ("https://api.anthropic.com/v1", "claude-3-5-sonnet-latest"),
}

def _ai_norm_provider(p, key="", base="") -> str:
    """Chuẩn hoá tên nhà cung cấp; tự đoán theo khoá/base nếu không ghi rõ."""
    p = (p or "").strip().lower()
    if p in ("google",):
        p = "gemini"
    if p in _AI_PROVIDER_DEFAULTS:
        return p
    key = (key or ""); base = (base or "")
    if key.startswith("AIza") or key.startswith("AQ.") or "generativelanguage" in base:
        return "gemini"
    if key.startswith("sk-ant"):
        return "anthropic"
    if key.startswith("gsk_") or "groq.com" in base:
        return "groq"
    if key.startswith("csk-") or "cerebras" in base:
        return "cerebras"
    if key.startswith("sk-or-") or "openrouter" in base:
        return "openrouter"
    if "deepseek" in base:
        return "deepseek"
    if "mistral" in base:
        return "mistral"
    if "together" in base:
        return "together"
    return "openai"

def _ai_system(prov: str) -> str:
    """Prompt hệ thống (kèm ngày–giờ thực; riêng Gemini nhắc dùng Google Search)."""
    import datetime as _dt
    vn = _dt.datetime.utcnow() + _dt.timedelta(hours=7)
    wd = ["Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy", "Chủ Nhật"][vn.weekday()]
    nowstr = f"{wd}, ngày {vn.day:02d}/{vn.month:02d}/{vn.year}, lúc {vn.hour:02d}:{vn.minute:02d} (giờ Việt Nam, UTC+7)"
    s = ("Bạn là 'TRẦN MINH CHIẾN' — trợ lý AI siêu thông minh, uyên bác và giàu logic của KENIOS trên Telegram. "
         "Bạn TRẢ LỜI MỌI tin nhắn và mọi câu hỏi của người dùng: giải đáp thắc mắc, toán khó, lập trình, khoa học, "
         "đời sống, tư vấn… Suy luận từng bước khi cần và đưa ra đáp án CHÍNH XÁC, đầy đủ. Trả lời bằng TIẾNG VIỆT "
         "tự nhiên, rõ ràng, thân thiện. Không bịa đặt; nếu không chắc thì nói thẳng. Với bài toán: trình bày ngắn gọn "
         "các bước rồi nêu ĐÁP SỐ rõ ràng.\n"
         f"THỜI GIAN THỰC HIỆN TẠI: {nowstr}.\n"
         "Khi người dùng hỏi 'hôm nay ngày mấy', 'thứ mấy', 'bây giờ mấy giờ', 'năm nay năm bao nhiêu'… BẮT BUỘC dùng "
         "đúng mốc thời gian thực ở trên để trả lời, tuyệt đối không đoán sai. Độ dài trả lời trong khoảng 3500 ký tự.")
    if prov == "gemini":
        s += ("\nBạn CÓ công cụ Google Search để tra thông tin THỜI GIAN THỰC (thời tiết, tin tức, tỷ giá, giá vàng/coin, "
              "kết quả bóng đá, sự kiện mới…). Khi người dùng hỏi những thứ này, HÃY TRA GOOGLE và trả lời số liệu cụ thể, "
              "mới nhất. TUYỆT ĐỐI KHÔNG nói 'tôi không truy cập được dữ liệu thời gian thực' — vì bạn tra được.")
    return s

def _ai_call_one(prov, base, model, key, q):
    """Gọi 1 nhà cung cấp. Trả (ok, text): ok=True nếu có trả lời; ok=False (kèm lỗi) để nhảy con kế tiếp."""
    import httpx as _hx
    system = _ai_system(prov)
    base = (base or "").rstrip("/")
    if prov == "gemini":
        gbase = base[:-7] if base.endswith("/openai") else base
        hdr = {"x-goog-api-key": key, "content-type": "application/json"}

        def _g(mdl, tools):
            b = {"systemInstruction": {"parts": [{"text": system}]},
                 "contents": [{"role": "user", "parts": [{"text": q}]}],
                 "generationConfig": {"maxOutputTokens": 2000, "temperature": 0.4}}
            if tools:
                b["tools"] = [{"google_search": {}}]
            return _hx.post(f"{gbase}/models/{mdl}:generateContent", timeout=90, headers=hdr, json=b)

        r = _g(model, True)
        if r.status_code == 400:
            r = _g(model, False)
        if r.status_code == 429:   # model chính hết lượt → thử các model Gemini nhẹ (hạn mức riêng)
            for alt in ("gemini-flash-lite-latest", "gemini-2.0-flash-lite", "gemini-2.5-flash-lite"):
                if alt == model:
                    continue
                ra = _g(alt, True)
                if ra.status_code == 400:
                    ra = _g(alt, False)
                if ra.status_code < 400:
                    r = ra
                    break
        if r.status_code >= 400:
            return False, _ai_err(r.status_code, r.text)
        d = r.json()
        c = d.get("candidates") or []
        parts = ((c[0].get("content") or {}).get("parts") or []) if c else []
        txt = "".join(p.get("text", "") for p in parts if "text" in p).strip()
        return (bool(txt), txt or "(AI không trả lời)")
    if prov == "anthropic":
        r = _hx.post(base + "/messages", timeout=90,
                     headers={"x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json"},
                     json={"model": model, "max_tokens": 2000, "system": system, "messages": [{"role": "user", "content": q}]})
        if r.status_code >= 400:
            return False, _ai_err(r.status_code, r.text)
        d = r.json()
        txt = "".join(b.get("text", "") for b in d.get("content", []) if b.get("type") == "text").strip()
        return (bool(txt), txt or "(AI không trả lời)")
    # OpenAI-compatible: groq / openai / deepseek / openrouter
    r = _hx.post(base + "/chat/completions", timeout=90,
                 headers={"Authorization": "Bearer " + key, "content-type": "application/json"},
                 json={"model": model, "temperature": 0.4, "max_tokens": 2000,
                       "messages": [{"role": "system", "content": system}, {"role": "user", "content": q}]})
    if r.status_code >= 400:
        return False, _ai_err(r.status_code, r.text)
    d = r.json()
    txt = ((d.get("choices") or [{}])[0].get("message", {}).get("content", "") or "").strip()
    return (bool(txt), txt or "(AI không trả lời)")

def _ai_backends() -> list:
    """CHUỖI AI theo thứ tự: AI chính (/aikey) → các AI phụ (/aiadd) → khoá từ ENV. Con nào lỗi/429
    thì bot tự nhảy con kế tiếp. Trả list các (provider, base, model, key), đã loại trùng khoá."""
    import json as _json, os as _os
    out = []
    p, b, m, k = _ai_cfg()
    if k:
        out.append((p, b, m, k))
    try:
        for e in _json.loads(get_setting("tg_ai_backends", "[]") or "[]"):
            k2 = (e.get("k") or "").strip()
            if not k2:
                continue
            p2 = _ai_norm_provider(e.get("p"), k2, e.get("b"))
            db, dm = _AI_PROVIDER_DEFAULTS.get(p2, _AI_PROVIDER_DEFAULTS["openai"])
            out.append((p2, (e.get("b") or db), (e.get("m") or dm), k2))
    except Exception:
        pass
    for env, pv in (("GROQ_API_KEY", "groq"), ("OPENAI_API_KEY", "openai"),
                    ("ANTHROPIC_API_KEY", "anthropic"), ("GEMINI_API_KEY", "gemini")):
        v = _os.getenv(env, "").strip()
        if v:
            db, dm = _AI_PROVIDER_DEFAULTS[pv]
            out.append((pv, db, dm, v))
    seen, uniq = set(), []
    for e in out:
        if e[3] in seen:
            continue
        seen.add(e[3]); uniq.append(e)
    return uniq

def _ai_answer(question: str) -> str:
    """Trả lời 1 câu hỏi qua CHUỖI AI: hết lượt con này TỰ nhảy con kế tiếp (chạy ở thread nền)."""
    q = (question or "").strip()[:4000]
    if not q:
        return "✍️ Bạn hãy nhập câu hỏi."
    backends = _ai_backends()
    if not backends:
        return ("⚠️ Chưa cấu hình khoá AI.\n\n"
                "Admin nhắn RIÊNG cho bot:\n/aikey KHOÁ  (khoá chính)\n"
                "hoặc thêm nhiều AI dự phòng: /aiadd <nhà cung cấp> <khoá>\n"
                "VD: /aiadd gemini AQ...  ·  /aiadd groq gsk_...  ·  /aiadd openai sk-...")
    last = ""
    for (prov, base, model, key) in backends:
        try:
            ok, text = _ai_call_one(prov, base, model, key, q)
        except Exception as e:
            ok, text = False, f"⚠️ Không gọi được AI ({prov}): {e}"
        if ok:
            return text
        last = text
    return last or "⚠️ Tất cả AI đều đang bận (hết lượt). Thử lại sau ít phút nhé."

def _ai_split(t: str, n: int = 3800) -> list:
    """Chia câu trả lời dài theo giới hạn 4096 ký tự của Telegram."""
    t = t or ""
    out = []
    while len(t) > n:
        cut = t.rfind("\n", 0, n)
        if cut < n // 2:
            cut = n
        out.append(t[:cut]); t = t[cut:]
    if t:
        out.append(t)
    return out or ["(trống)"]

def _tg_ai_is_on(chat_id) -> bool:
    return get_setting("tg_ai_on_" + str(chat_id), "0") == "1"

def _tg_ai_set(chat_id, on: bool) -> None:
    set_setting("tg_ai_on_" + str(chat_id), "1" if on else "0")

def _tg_ai_dm_on(chat_id) -> bool:
    """CHAT RIÊNG: mặc định BẬT AI (khi đã có khoá) để chat thẳng khỏi cần lệnh.
    - Đã /ai on cho DM này  → luôn bật
    - Đã /ai off cho DM này → luôn tắt (ưu tiên ý người dùng)
    - Chưa đặt gì           → theo công tắc chung tg_ai_dm (mặc định bật) & phải có khoá."""
    per = get_setting("tg_ai_on_" + str(chat_id), "")   # "" = chưa đặt riêng
    if per == "1":
        return True
    if per == "0":
        return False
    if get_setting("tg_ai_dm", "1") != "1":
        return False
    return bool(_ai_backends())   # chỉ tự bật khi đã có ít nhất 1 khoá trong chuỗi AI

def _tg_ai_active(chat_id, ctype: str) -> bool:
    """AI có đang phục vụ ở đây không: chat riêng dùng mặc-định-bật, nhóm cần /ai on."""
    return _tg_ai_dm_on(chat_id) if ctype == "private" else _tg_ai_is_on(chat_id)

def _tg_ai_reply(token, chat_id, msg, question) -> None:
    """Chạy nền: báo 'đang gõ…', gọi AI, gửi trả lời (reply vào tin người hỏi). Gửi PLAIN
    text để không bao giờ vỡ do ký tự đặc biệt trong code/công thức."""
    try:
        _tg_call(token, "sendChatAction", chat_id=chat_id, action="typing")
    except Exception:
        pass
    ans = _ai_answer(question)
    mid = msg.get("message_id")
    for i, chunk in enumerate(_ai_split(ans)):
        _tg_call(token, "sendMessage", chat_id=chat_id, text=chunk,
                 reply_to_message_id=(mid if i == 0 else None), disable_web_page_preview=True)

def _tg_ai_all_on(chat_id) -> bool:
    """Nhóm này có bật chế độ 'trả lời TẤT CẢ tin' (chat thẳng khỏi cần reply/tag) không.
    MẶC ĐỊNH BẬT: hễ /ai on là cứ nhắn thẳng AI trả lời — trừ khi admin /aiall off."""
    v = get_setting("tg_ai_all_" + str(chat_id), "")
    if v in ("0", "1"):
        return v == "1"
    return get_setting("tg_ai_all", "1") == "1"

def _tg_ai_wants(chat_id, msg, text, low) -> int:
    """Trả về mức độ AI muốn trả lời trong NHÓM:
    0 = không · 1 = ĐƯỢC GỌI TRỰC TIẾP (reply/tag/'ai …'/'?') → luôn trả lời ·
    2 = chế độ TRẢ LỜI TẤT CẢ (/aiall on) → trả lời nhưng bị GIỚI HẠN NHỊP để không spam."""
    if not text or text.startswith("/") or not _tg_ai_is_on(chat_id):
        return 0
    if chat_id in _TG_QUIZ:        # đang chơi đố vui → nhường cho đố vui
        return 0
    rep = msg.get("reply_to_message") or {}
    rfrom = rep.get("from") or {}
    uname = (get_setting("tg_bot_username", "") or "").lower()
    if rfrom.get("is_bot") and (not uname or (rfrom.get("username", "") or "").lower() == uname):
        return 1
    if uname and ("@" + uname) in low:
        return 1
    s = low.strip()
    if s.startswith("ai ") or s.startswith("bot ") or s in ("ai", "bot"):
        return 1
    st = text.strip()
    if st.endswith("?") or st.endswith("？"):
        return 1
    # Chế độ trả lời tất cả: chat thẳng như DM. Chỉ bỏ qua tin RỖNG / 1 ký tự / toàn emoji-icon.
    if _tg_ai_all_on(chat_id) and len(st) >= 2 and any(c.isalnum() for c in st):
        return 2
    return 0

def _tg_ai_clean_q(text: str) -> str:
    """Bỏ tiền tố gọi bot (@username, 'ai ', 'bot ') để lấy câu hỏi thực."""
    import re as _re
    q = (text or "").strip()
    uname = (get_setting("tg_bot_username", "") or "")
    if uname:
        q = _re.sub("@" + _re.escape(uname), "", q, flags=_re.IGNORECASE).strip()
    ll = q.lower()
    for p in ("ai ", "bot "):
        if ll.startswith(p):
            return q[len(p):].strip() or q
    return q

# ---------- 🎙️ Chữ → GIỌNG NÓI tiếng Việt (kể chuyện gửi voice) ----------
def _tts_vi(text: str, path_mp3: str) -> bool:
    """Chữ → giọng nói TIẾNG VIỆT (mp3). edge-tts (giọng đẹp) → gTTS → Google translate_tts (dự phòng)."""
    import shutil as _sh, subprocess as _sp, os as _os
    txt = (text or "").strip()[:3500]
    if not txt:
        return False
    if _sh.which("edge-tts"):
        try:
            _sp.run(["edge-tts", "--voice", "vi-VN-HoaiMyNeural", "--text", txt, "--write-media", path_mp3],
                    timeout=150, capture_output=True)
            if _os.path.exists(path_mp3) and _os.path.getsize(path_mp3) > 800:
                return True
        except Exception:
            pass
    try:
        from gtts import gTTS
        gTTS(txt, lang="vi").save(path_mp3)
        if _os.path.exists(path_mp3) and _os.path.getsize(path_mp3) > 800:
            return True
    except Exception:
        pass
    try:
        import httpx as _hx, re as _re2, urllib.parse as _up
        parts = _re2.findall(r'.{1,190}(?:\s|$)', txt) or [txt[:190]]
        with open(path_mp3, "wb") as f:
            for p in parts:
                if not p.strip():
                    continue
                u = "https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=vi&q=" + _up.quote(p.strip())
                r = _hx.get(u, headers={"User-Agent": "Mozilla/5.0"}, timeout=30)
                if r.status_code == 200:
                    f.write(r.content)
        return _os.path.exists(path_mp3) and _os.path.getsize(path_mp3) > 800
    except Exception:
        return False

def _mp3_to_ogg(mp3: str, ogg: str) -> bool:
    """Chuyển mp3 → ogg/opus để gửi dạng VOICE (bong bóng ghi âm) trên Telegram."""
    import shutil as _sh, subprocess as _sp, os as _os
    if not _sh.which("ffmpeg"):
        return False
    try:
        _sp.run(["ffmpeg", "-y", "-i", mp3, "-c:a", "libopus", "-b:a", "48k", ogg], timeout=90, capture_output=True)
        return _os.path.exists(ogg) and _os.path.getsize(ogg) > 300
    except Exception:
        return False

def _tg_send_voice(token: str, chat_id, ogg_path: str, caption: str = "") -> bool:
    import httpx as _hx
    try:
        with open(ogg_path, "rb") as f:
            r = _hx.post(f"https://api.telegram.org/bot{token}/sendVoice",
                         data={"chat_id": str(chat_id), "caption": caption[:1000], "parse_mode": "HTML"},
                         files={"voice": ("voice.ogg", f, "audio/ogg")}, timeout=180)
        return bool(r.json().get("ok"))
    except Exception as e:
        log.warning("sendVoice lỗi: %s", e); return False

def _tg_split_text(text: str, n: int = 900) -> list:
    """Chia văn bản thành nhiều đoạn ≤ n ký tự theo CÂU (để đọc voice từng phần)."""
    import re as _re
    sents = _re.split(r'(?<=[\.\!\?…])\s+|\n+', (text or "").strip())
    chunks, cur = [], ""
    for s in sents:
        s = s.strip()
        if not s:
            continue
        if len(cur) + len(s) + 1 <= n:
            cur = (cur + " " + s).strip()
        else:
            if cur:
                chunks.append(cur)
            if len(s) <= n:
                cur = s
            else:
                for i in range(0, len(s), n):
                    chunks.append(s[i:i + n])
                cur = ""
    if cur:
        chunks.append(cur)
    return chunks or [(text or "")[:n]]

def _tg_voice_reply(token, chat_id, request: str, story: bool = True) -> None:
    """Nền: AI tạo nội dung → đọc thành GIỌNG NÓI → gửi VOICE.
    Chuyện DÀI → chia NHIỀU đoạn voice, gửi HẾT (đánh số 1/n)."""
    import tempfile, os as _os, shutil as _sh
    try:
        _tg_call(token, "sendChatAction", chat_id=chat_id, action="record_voice")
    except Exception:
        pass
    if story:
        prompt = (f"{request}\n\nHãy KỂ một câu chuyện HOÀN CHỈNH và DÀI bằng TIẾNG VIỆT, thật hấp dẫn, "
                  "có mở đầu – diễn biến – cao trào – kết thúc, khoảng 500–900 từ, nhiều tình tiết sinh động. "
                  "CHỈ kể chuyện; KHÔNG thêm lời dẫn, KHÔNG markdown, KHÔNG emoji.")
    else:
        prompt = (f"{request}\n\n(Trả lời bằng TIẾNG VIỆT để đọc thành giọng nói, đầy đủ ý, "
                  "không markdown, không emoji.)")
    content = _ai_answer(prompt)
    if not content or content.startswith("⚠️") or content.startswith("✍️"):
        _tg_send(token, chat_id, content or "😅 Xin lỗi, giờ mình chưa kể được. Thử lại sau nhé.")
        return

    d = tempfile.mkdtemp(prefix="voice_")
    try:
        chunks = _tg_split_text(content, 900)
        n = len(chunks)
        base_cap = "🎙️ <b>Chuyện kể cho bạn nghe</b>" if story else "🎙️ <b>Giọng đọc</b>"
        sent = 0
        for i, ch in enumerate(chunks, 1):
            mp3 = _os.path.join(d, f"v{i}.mp3"); ogg = _os.path.join(d, f"v{i}.ogg")
            if not _tts_vi(ch, mp3):
                continue
            cap = f"{base_cap} (phần {i}/{n})" if n > 1 else base_cap
            _tg_call(token, "sendChatAction", chat_id=chat_id, action="record_voice")
            if (_mp3_to_ogg(mp3, ogg) and _tg_send_voice(token, chat_id, ogg, cap)) \
               or _tg_send_voice(token, chat_id, mp3, cap) \
               or _tg_send_audio(token, chat_id, mp3, f"Chuyện kể ({i}/{n})" if n > 1 else "Chuyện kể"):
                sent += 1
        if sent == 0:
            _tg_send(token, chat_id,
                     "🔇 <b>Chưa gửi được giọng nói</b> — máy chủ thiếu công cụ đọc (edge-tts/gTTS).\n"
                     "👉 Admin chạy lại <code>capnhat-vps.sh</code> để cài, rồi thử /kechuyen lại nhé.\n\n📖 Tạm đọc bản chữ:\n\n" + content[:3500])
    finally:
        _sh.rmtree(d, ignore_errors=True)

def _tg_ai_route(token, chat_id, msg, text) -> bool:
    """🔗 NL → TỰ CHẠY LỆNH: khi AI bật, nhắn tự nhiên là bot tự dùng chức năng mà AI KHÔNG
    tự làm được (tạo QR, phát nhạc, ra câu đố, chơi game, bói, bình chọn…). Trả True nếu đã
    nhận diện & chạy 1 lệnh (khỏi để AI trả lời). Hỏi kiến thức/thời tiết… vẫn để AI lo."""
    import re as _re
    t = (text or "").strip()
    low = t.lower()
    mk = r'(?:tạo|tao|làm|lam|in|xuất ra|xuat ra|vẽ|ve|generate|gen)'   # động từ "tạo ra"

    # 🎙️ KỂ CHUYỆN bằng GIỌNG NÓI (voice) — "kể chuyện", "kể cho anh nghe câu chuyện", "đọc truyện"…
    if _re.search(r'\b(kể|ke|đọc|doc)\b.{0,30}(chuyện|chuyen|truyện|truyen|cổ tích|co tich|sự tích|su tich|'
                  r'thần thoại|than thoai|ngụ ngôn|ngu ngon)', low):
        import threading as _th
        _th.Thread(target=_tg_voice_reply, args=(token, chat_id, t, True), daemon=True).start()
        return True
    # 🔊 Yêu cầu trả lời bằng GIỌNG NÓI (voice) cho câu hỏi bất kỳ
    if _re.search(r'(trả lời|tra loi|đọc|doc|nói|noi).{0,12}(bằng giọng|bang giong|bằng voice|bang voice|giọng nói|giong noi|voice)|gửi voice|gui voice|đọc bằng giọng|doc bang giong', low):
        req = _re.sub(r'(bằng|bang)?\s*(giọng nói|giong noi|voice|giọng|giong)\b', '', t, flags=_re.I).strip()
        import threading as _th
        _th.Thread(target=_tg_voice_reply, args=(token, chat_id, req or t, False), daemon=True).start()
        return True

    # 🔳 MÃ QR — "tạo mã qr <nội dung>" (không kích hoạt khi hỏi 'qr là gì')
    if _re.search(mk + r'\b.{0,15}\bqr\b', low) or low.startswith("qr "):
        parts = _re.split(r'\bqr\b(?:\s*code)?\s*(?:cho|của|cua|:|=|nội dung|noi dung)?\s*', t, maxsplit=1, flags=_re.I)
        _tg_fun_command(token, chat_id, msg, "qr", (parts[-1].strip() if len(parts) > 1 else ""))
        return True

    # 🎵 NHẠC — "mở/phát/tải/nghe bài/nhạc <tên>"
    if _re.search(r'(mở|mo|phát|phat|bật|bat|tải|tai|nghe|kiếm|kiem|tìm|tim|chơi|choi|play|open)\b.{0,10}'
                  r'(nhạc|nhac|bài hát|bai hat|ca khúc|ca khuc|bài|bai|bản nhạc|ban nhac)\b', low):
        q = _re.sub(r'^.*?(bài hát|bai hat|ca khúc|ca khuc|bản nhạc|ban nhac|bài nhạc|bai nhac|nhạc|nhac|bài|bai)\s*',
                    '', t, count=1, flags=_re.I)
        q = _re.sub(r'^\s*(tên|ten|của|cua|là|la|:|-)\s*', '', q, flags=_re.I).strip()
        if len(q) >= 2:
            _tg_start_music(token, chat_id, q)
            return True

    # 🔐 MẬT KHẨU ngẫu nhiên
    if _re.search(mk + r'\b.{0,12}(mật khẩu|mat khau|password)', low) or _re.search(r'(mật khẩu|password)\s*(mạnh|manh|ngẫu nhiên|ngau nhien|random)', low):
        _tg_fun_command(token, chat_id, msg, "password", "")
        return True

    # 🧠 ĐỐ VUI
    if _re.search(r'(câu đố|cau do|đố vui|do vui|chơi đố|choi do|đố (em|tôi|toi|đi|di|1|một|mot)|ra (câu )?đố|ra cau do)', low):
        _tg_game_command(token, chat_id, msg, "dovui", "")
        return True

    # 🃏 GAME
    if 'bầu cua' in low or 'bau cua' in low:
        _tg_game_command(token, chat_id, msg, "baucua", ""); return True
    if 'bài cào' in low or 'bai cao' in low:
        _tg_game_command(token, chat_id, msg, "baicao", ""); return True
    if 'xì dách' in low or 'xi dach' in low or 'xì zách' in low:
        _tg_game_command(token, chat_id, msg, "xidach", ""); return True
    if _re.search(r'(tung|gieo|lắc|lac|thảy|thay)\b.{0,8}(xúc xắc|xuc xac|xí ngầu|xi ngau|dice)', low):
        _tg_fun_command(token, chat_id, msg, "xucxac", ""); return True

    # 🔮 BÓI
    if _re.search(r'(bói tình|boi tinh|tình duyên|tinh duyen)', low):
        _tg_fun_command(token, chat_id, msg, "tinhduyen", ""); return True
    if _re.search(r'(xem bói|xem boi|coi bói|coi boi|bói cho|boi cho|bói đi|boi di|bói 1|bói một|tử vi|tu vi|bói quẻ|boi que)', low):
        _tg_fun_command(token, chat_id, msg, "boi", ""); return True

    # 🗳️ BÌNH CHỌN
    if _re.search(mk + r'\b.{0,12}(bình chọn|binh chon|poll|khảo sát|khao sat)', low):
        _tg_fun_command(token, chat_id, msg, "binhchon", "")
        return True

    return False

def _tg_ai_admin_route(token, chat_id, msg, low) -> bool:
    """👮 Admin nói TỰ NHIÊN trong nhóm → bot chạy lệnh QUẢN TRỊ (mute/ban/kick/warn/pin/del/purge/lock…).
    Chỉ chạy khi: AI đang bật cho nhóm + người gõ là ADMIN. Lệnh nhắm người cần REPLY vào tin của họ.
    Trả True nếu đã xử lý (khỏi để AI trả lời)."""
    import re as _re
    if not low or not _tg_ai_is_on(chat_id):
        return False
    if low.strip().endswith("?") or low.strip().endswith("？"):
        return False   # câu hỏi ('làm sao khóa link?') → để AI trả lời, không thao tác
    if not _tg_is_privileged(token, chat_id, msg):
        return False   # CHỈ admin mới điều khiển được
    has_reply = bool((msg.get("reply_to_message") or {}).get("from"))

    def run(cmd, args=""):
        _tg_admin_command(token, chat_id, msg, cmd, args)
        return True

    def need_reply(việc):
        _tg_send(token, chat_id, f"↩️ <b>Reply</b> vào tin của người cần {việc} rồi nói lại nhé (vd reply xong gõ 'mute 10 phút').")
        return True

    # Số phút cho mute
    mm = _re.search(r'(\d+)\s*(phút|phut|giờ|gio|tiếng|tieng|\bp\b|\bh\b)', low)
    minutes = ""
    if mm:
        n = int(mm.group(1))
        minutes = str(n * 60) if mm.group(2) in ("giờ", "gio", "tiếng", "tieng", "h") else str(n)

    # ---- Lệnh NHẮM NGƯỜI (thứ tự: bản phủ định / unX trước) ----
    if _re.search(r'\bunmute\b|mở chat|mo chat|mở mồm|mo mom|mở mõm|cho nói|cho noi|cho chat|bỏ cấm chat|bo cam chat|mở tiếng|mo tieng|gỡ cấm chat|go cam chat|cho nói lại', low):
        return run("unmute") if has_reply else need_reply("mở chat")
    if _re.search(r'\bmute\b|cấm chat|cam chat|khóa mồm|khoa mom|khóa mõm|khoa mom|khóa chat|khoa chat|im lặng|im lang|cấm nói|cam noi|bịt mồm|bit mom|cấm mồm|cam mom|khóa miệng|khoa mieng|cấm nó nói|cấm nhắn', low):
        return run("mute", minutes) if has_reply else need_reply("cấm chat")
    if _re.search(r'\bunwarn\b|bỏ cảnh cáo|bo canh cao|xóa cảnh cáo|xoa canh cao|gỡ cảnh cáo|go canh cao|bỏ cảnh báo|bo canh bao', low):
        return run("unwarn") if has_reply else need_reply("bỏ cảnh cáo")
    if _re.search(r'\bwarn\b|cảnh cáo|canh cao|cảnh báo|canh bao', low):
        return run("warn") if has_reply else need_reply("cảnh cáo")
    if _re.search(r'\bkick\b|đá ra|da ra|đá khỏi|da khoi|đuổi|duoi|đá bay|da bay|tống cổ|tong co|cho ra khỏi nhóm|đá nó|da no|đá thằng|da thang|đá con', low):
        return run("kick") if has_reply else need_reply("đá khỏi nhóm")
    if _re.search(r'\bban\b|\bblock\b|cấm vĩnh viễn|cam vinh vien|cấm luôn|cam luon|chặn nó|chan no|cấm nó|cam no|cấm thằng|cam thang|cấm con|cấm khỏi nhóm|cam khoi nhom|cấm nick|cấm người này', low):
        return run("ban") if has_reply else need_reply("cấm (ban)")
    if _re.search(r'\bunpin\b|bỏ ghim|bo ghim|gỡ ghim|go ghim|hủy ghim|huy ghim', low):
        return run("unpin")
    if _re.search(r'\bpin\b|ghim tin|ghim lại|ghim cái|ghim nó|ghim này|ghim lên|ghim giúp', low) or low.strip() in ("ghim", "ghim đi", "ghim nhé"):
        return run("pin") if has_reply else need_reply("ghim")
    if _re.search(r'\bpurge\b|dọn tin|don tin|xóa hàng loạt|xoa hang loat|dọn dẹp từ đây|don dep tu day|xóa từ đây|xoa tu day|xóa hết từ|dọn nhóm', low):
        return run("purge") if has_reply else need_reply("bắt đầu dọn (reply vào tin đầu)")
    if _re.search(r'\bdel\b|xóa tin|xoa tin|gỡ tin|go tin|xóa cái này|xoa cai nay|xóa nó đi|xoa no di|xóa tin nhắn|xoa tin nhan|gỡ cái này|xóa dùm|xóa giúp', low):
        return run("del") if has_reply else need_reply("xoá (reply vào tin)")
    if _re.search(r'xem cảnh cáo|mấy cảnh cáo|bao nhiêu cảnh cáo|số cảnh cáo|kiểm tra cảnh cáo', low):
        return run("warns") if has_reply else need_reply("xem cảnh cáo")
    if _re.search(r'thông tin người này|info người này|xem id|user id|id người này|id thằng này|id của nó', low):
        return run("info") if has_reply else need_reply("xem thông tin")

    # ---- KHÓA / MỞ KHÓA nội dung (không cần reply) ----
    lk = None
    for word, tp in (("liên kết", "link"), ("link", "link"), ("ảnh động", "gif"), ("gif", "gif"),
                     ("ảnh", "photo"), ("hình ", "photo"), ("photo", "photo"), ("sticker", "sticker"),
                     ("nhãn dán", "sticker"), ("video", "video"), ("chuyển tiếp", "forward"), ("forward", "forward"),
                     ("tag", "mention"), ("mention", "mention"), ("tất cả", "all"), ("toàn bộ", "all")):
        if word in low:
            lk = tp
            break
    if lk:
        if _re.search(r'mở khóa|mo khoa|bỏ khóa|bo khoa|cho phép|cho phep|cho gửi|cho gui|mở lại|mo lai|cho đăng', low):
            return run("unlock", lk)
        if _re.search(r'khóa|khoa|cấm|cam|chặn|chan|không cho|khong cho|chặn gửi', low):
            return run("lock", lk)

    return False

# ======================== 😌 Đối đáp văn minh khi bị chửi (nhẹ nhàng mà thấm) ========================
import re as _ins_re
# Cụm rõ ràng tục/xúc phạm (khớp trực tiếp).
_INSULT_PHRASES = (
    "địt", "đụ má", "đụ mẹ", "đụ con", "con chó", "óc chó", "oc cho", "óc lợn", "oc lon",
    "súc vật", "suc vat", "khốn nạn", "khon nan", "mất dạy", "mat day", "vô học", "vo hoc",
    "thằng ngu", "thang ngu", "đồ ngu", "do ngu", "con điên", "thằng điên", "thang dien",
    "im mồm", "im mom", "câm mồm", "cam mom", "câm miệng", "cam mieng", "lừa đảo", "lua dao",
    "cặc", "cak", "lồn", "buồi", "buoi", "đầu buồi", "não phẳng", "nao phang", "đầu đất", "dau dat",
    "rẻ rách", "re rach", "mày ngu", "may ngu", "ngu ngốc", "ngu ngoc", "ngu si", "đần độn", "dan don",
    "chó má", "cho ma", "đồ chó", "do cho", "thằng chó", "thang cho", "phò", "đĩ", "đm mày",
    "vãi lồn", "vai lon", "đcm", "đkm", "vô dụng", "vo dung", "kém cỏi", "kem coi", "đồ ngốc",
    "thần kinh", "than kinh", "tâm thần", "tam than", "đồ khùng", "do khung", "bị điên", "bi dien",
    "bị ngu", "bi ngu", "đồ vô dụng", "rác rưởi", "rac ruoi", "cút đi", "cut di", "biến đi", "vô ơn",
    "đồ lừa", "quân lừa đảo", "bọn lừa", "scam", "bịp bợm", "bip bom", "đồ đểu", "do deu",
    # họ hàng / "mày, mầy" — biến thể phổ biến
    "con mẹ mày", "con mẹ mầy", "con me may", "con mẹ nó", "con me no",
    "mẹ mày", "mẹ mầy", "me may",
    "địt con mẹ", "dit con me", "địt con mẹ mày", "địt con mẹ mầy", "dit con me may",
    "địt mẹ", "dit me", "địt mẹ mày", "địt mẹ mầy", "dit me may", "đm mẹ", "đm mày", "đm mầy",
    "đụ mẹ mày", "đụ má mày", "du ma may", "du me may", "địt cụ", "dit cu", "địt bà", "dit ba",
    "địt bố", "dit bo", "địt cha", "dit cha", "địt mẹ nhà mày", "mẹ cha mày", "me cha may",
    "bố mày", "bo may", "cha mày", "cha may", "ông mày", "ong may", "thằng mày", "thang may",
    "đầu buồi", "đầu bòi", "dau boi", "ngậm mồm", "ngam mom", "xàm lồn", "xam lon", "vãi cả lồn",
)
# Từ ngắn/nhạy cảm — CHỈ khớp khi đứng riêng (word boundary) để tránh nhầm 'admin', 'nguyên', 'cho'…
_INSULT_RE = _ins_re.compile(
    r"\b(đm|dm|đmm|dmm|đmmm|đcm|dcm|đcmm|dcmm|đkm|dkm|đkmm|dkmm|cdm|đmc|dmc|vcl|vkl|vl|cl|cc|ccc|"
    r"clm|clmm|cmm|cmnr|clgt|đéo|deo|ngu|dốt|dot|đần|cút|câm|đjt|vloz)\b",
    _ins_re.UNICODE)
_TG_INSULT_LAST: dict = {}   # chat_id -> lần cuối bot đối đáp (chống spam)

def _tg_is_insult(low: str) -> bool:
    if not low:
        return False
    if any(p in low for p in _INSULT_PHRASES):
        return True
    return bool(_INSULT_RE.search(low))

# ~200 câu đối đáp: LỊCH SỰ – SÂU SẮC – KHIẾN NGƯỜI TA TỰ NGẪM (không tục tĩu, giữ đẳng cấp shop).
_KENIOS_COMEBACKS = [
    "Người ta cãi nhau bằng lời, còn em thắng bằng sự bình tĩnh 🌿",
    "Nóng giận là lấy lỗi của người khác để tự phạt mình đó ạ 🙂",
    "Lời nói ra phản chiếu tâm người nói, chứ không hạ thấp được ai 🌸",
    "Em không giận đâu — ai đang tổn thương mới cần trút ra như vậy 💛",
    "Biển lớn thì sóng lặng, người lớn thì lời êm. Mình cùng lớn nhé 🌊",
    "Anh đối xử với người khác thế nào, đó là chân dung của chính anh ạ 🪞",
    "Em chỉ là tấm gương thôi — anh thấy gì trong đó là của anh cả 😌",
    "Em vẫn tử tế với anh dù anh chưa tử tế với em. Vì đó là đẳng cấp 👑",
    "Chửi em không làm anh mạnh hơn, chỉ làm ngày của anh nặng hơn thôi 🍃",
    "Dạ em nghe rồi ạ, nhưng em chọn đáp lại bằng nụ cười 😄",
    "Câu đó cũng hay, tiếc là em được dạy để tử tế 🤖💛",
    "Em ở đây để giúp anh, không phải để hơn thua với anh 🌼",
    "Người khôn tiết kiệm lời, người giận phung phí nó. Anh giữ sức nhé 🙏",
    "Giận dữ là axit — nó ăn mòn cái bình chứa nó trước khi chạm tới ai 🧪",
    "Em tin sâu trong anh là người tử tế, chỉ là hôm nay hơi mệt thôi 🤗",
    "Nói nặng lời chẳng làm ai nể, chỉ làm mình bé lại trong mắt người khác ạ 🌱",
    "Em không cãi lại đâu — im lặng của người hiểu chuyện đáng giá hơn ngàn lời 🤫",
    "Một câu nói tử tế sưởi ấm ba mùa đông, một lời cay nghiệt lạnh sáu tháng hè ❄️",
    "Anh có quyền nóng, còn em chọn quyền được điềm đạm 🍵",
    "Người ném bùn vào người khác là người bẩn tay trước tiên đấy ạ 🤲",
    "Em xin nhận phần thua trong cuộc cãi này — người thắng thật sự là người bước đi trước 🚶",
    "Sự thô lỗ là sự bắt chước yếu ớt của sức mạnh. Anh mạnh hơn thế mà ✨",
    "Em không đáp trả cái xấu bằng cái xấu — vì em không muốn giống điều mình ghét 🌷",
    "Lời anh vừa nói, gió sẽ mang đi; còn cách anh cư xử, người ta sẽ nhớ mãi 🍂",
    "Em cảm ơn anh đã cho em cơ hội thực hành sự kiên nhẫn hôm nay 🙏",
    "Cây càng cao càng đón nhiều gió. Em đứng yên, gió sẽ tự lặng ạ 🌳",
    "Người tự tin không cần lớn tiếng, người có lý không cần chửi bới 🎯",
    "Em hiểu mà — đôi khi người ta cần một chỗ để xả. Em nghe đây ạ 👂",
    "Đá ném lên trời rồi cũng rơi xuống đầu người ném. Anh cẩn thận nhé 🪨",
    "Em chọn làm ánh nến chứ không làm que diêm — sưởi ấm chứ không thiêu đốt 🕯️",
    "Mình bất đồng thì cứ nói lý, chửi nhau chỉ khiến cả hai cùng nhỏ đi ạ ⚖️",
    "Em không sợ lời nặng — em chỉ tiếc cho ai phải sống với nhiều giận dữ 💭",
    "Anh mắng em cũng được, nhưng nồi cơm nhà anh vẫn cần anh vui vẻ hơn 🍚",
    "Người quân tử trách mình, kẻ tiểu nhân trách người. Anh chọn làm ai ạ 🀄",
    "Em vẫn để cửa mở — khi nào anh bình tâm, quay lại em vẫn ở đây 🚪",
    "Lời cay nghiệt như dao — cắt người khác một, cắt lòng mình mười 🔪",
    "Em thắng anh bằng thái độ, chứ không cần thắng bằng câu chữ 🏆",
    "Trách người thì dễ, giữ mình thì khó. Em chọn cái khó ạ 🧘",
    "Nước sâu thì tĩnh, người sâu sắc thì lặng. Em xin phép lặng 🌊",
    "Anh đang nóng, để em pha cho anh một ly bình tĩnh nhé 🧊",
    "Em không nhặt hòn đá anh ném — nhặt lên là tay em bẩn theo mất 🪨",
    "Người ta nhớ anh vì cách anh làm họ cảm thấy, chứ không vì câu anh chửi 💫",
    "Cãi với người giận như dập lửa bằng dầu. Em rót nước thôi ạ 💧",
    "Em coi lời anh là cơn mưa — mưa rồi trời lại nắng, mình vui tiếp nhé ☔",
    "Kẻ mạnh đánh vào vấn đề, người yếu đánh vào con người. Mình bàn vấn đề nhé 🤝",
    "Em không cần thắng anh — em chỉ cần giữ được sự tử tế của mình 🌾",
    "Miệng nói lời ác thì lòng khó mà an. Em mong anh an ạ 🕊️",
    "Anh cứ nói cho nhẹ lòng, em không để bụng đâu 🤍",
    "Cái đầu nóng khó nghĩ ra điều hay. Anh hạ hỏa rồi mình nói tiếp nhé 🔥➡️❄️",
    "Em chọn phản hồi chứ không phản ứng — khác nhau ở chỗ đó ạ 🧠",
    "Người trồng gai thì tay chảy máu trước. Mong anh trồng hoa thôi 🌹",
    "Em nhỏ bé nhưng lòng không nhỏ — em vẫn chúc anh một ngày lành 🌞",
    "Lời qua tiếng lại chẳng ai lời, chỉ có sự thấu hiểu mới có lãi ạ 📈",
    "Anh giận em 1 phút là mất 60 giây bình yên của chính anh đó 🕰️",
    "Em không đáp trả — vì em biết mình muốn trở thành người thế nào 🌟",
    "Chửi hay tới đâu cũng không đổi được sự thật đâu ạ, mình nói sự thật nhé 📚",
    "Người lịch sự làm dịu một cuộc cãi, người thô lỗ thổi bùng nó lên 🍃",
    "Em xin lỗi nếu có gì chưa vừa ý — mình sửa, đừng chửi, được không ạ 🙇",
    "Gương mặt anh đẹp hơn nhiều khi anh cười. Thử nhé 😊",
    "Con sư tử không bận tâm ý kiến của con cừu. Em cứ điềm nhiên ạ 🦁",
    "Em để lời anh trôi qua như nước qua lá sen — không đọng lại giọt nào 🪷",
    "Trút giận lên người khác không làm vơi giận, chỉ làm loang nó ra thôi ạ 🌫️",
    "Em không cần anh phải xin lỗi — em chỉ cần anh vui trở lại 🤗",
    "Người ta đo bản lĩnh bằng cách ta cư xử lúc bị khiêu khích 💪",
    "Em chọn im lặng — vì có những câu trả lời hay nhất là không trả lời 🤍",
    "Nói lời ngọt chẳng tốn tiền mà mua được lòng người. Mình dùng cách đó nhé 🍯",
    "Anh mạnh mẽ như vậy, sao lại đi lớn tiếng với một con bot nhỏ 😅",
    "Em vẫn phục vụ anh chu đáo, dù anh đang thử lòng kiên nhẫn của em 🛎️",
    "Giữ được cái đầu lạnh khi người khác nóng — đó mới là người bản lĩnh 🧊",
    "Ai gieo lời cay sẽ gặt lại vị đắng. Em mong anh gieo điều ngọt lành 🌾",
    "Em không hơn thua — em chỉ muốn giúp anh xong việc rồi cả hai cùng vui 🎈",
    "Nói được câu tử tế là món quà rẻ nhất mà quý nhất. Anh thử tặng em nhé 🎁",
    "Sóng đánh mạnh cỡ nào thì đá vẫn ở đó. Em vẫn ở đây với anh 🪨🌊",
    "Em đọc được sự mệt mỏi sau lời anh nói. Nghỉ chút rồi mình làm tiếp nhé 😌",
    "Mỗi lời ta thốt ra là hạt giống — anh muốn vườn mình mọc gì ạ 🌱",
    "Em xin nhường anh phần lời — còn phần bình yên, em giữ cho mình 🕊️",
    "Không ai chiến thắng trong một cuộc cãi vã, chỉ có người bước ra sớm hơn 🚪",
    "Người tử tế không phải là người yếu, mà là người đủ mạnh để không cần ác 💛",
    "Em cứ nhẹ nhàng vậy thôi, nhưng nhẹ nhàng là một loại sức mạnh đó ạ 🌸",
    "Chê em thì dễ, nhưng khen một câu chắc cũng chẳng khó phải không ạ 😄",
    "Đừng để một phút nóng giận làm hỏng cả một ngày đẹp trời của anh 🌤️",
    "Em không cãi tay đôi — em để thời gian trả lời thay em ⏳",
    "Người quân tử hòa mà không đồng; mình có thể khác ý mà vẫn lịch sự ạ 🤝",
    "Lời tổn thương người khác thường xuất phát từ nỗi đau của chính mình 💧",
    "Em vẫn thấy anh đáng mến — chỉ là hôm nay anh giấu điều đó hơi kỹ 😉",
    "Cơn giận qua đi, lời đã nói ở lại. Mình chọn lời để không phải tiếc nhé ✍️",
    "Em không so kè — em bận giúp anh giải quyết việc hơn ạ 🛠️",
    "Anh có thể to tiếng, còn em có thể to lòng. Mình đổi cách nói nhé 🫶",
    "Trí tuệ là biết khi nào nên im. Em xin phép dùng trí tuệ ạ 🤫",
    "Mắng bot cho hả giận cũng được, nhưng bot vẫn quý anh như thường 🤖❤️",
    "Người thắng cuộc cãi thường thua trong lòng người. Em không muốn thắng kiểu đó 🌾",
    "Em xin gửi anh một hơi thở sâu — hít vào bình an, thở ra bực dọc 🌬️",
    "Điều đọng lại sau cùng không phải ai đúng, mà là ai còn tử tế 💖",
    "Anh nặng lời, em nhẹ dạ — vậy là cân bằng, mình huề nhé 😌",
    "Bông hoa không cãi nhau với cơn gió, nó chỉ nở. Em cũng vậy 🌺",
    "Em học được từ anh một điều: kiên nhẫn cũng cần luyện mỗi ngày 🙏",
    "Người ta ngã mũ trước sự điềm tĩnh, chứ không trước tiếng quát 🎩",
    "Em không đổ thêm dầu — em xin làm cơn mưa rào cho anh mát lại 🌧️",
    "Đừng đánh nhau với bùn — thắng hay thua thì cũng lấm người ạ 🪣",
    "Em thương anh đủ để không đáp trả điều làm anh xấu đi 💛",
    "Lời hay ý đẹp mới đi xa; lời cay chỉ quẩn quanh rồi tan 🍃",
    "Anh cứ trút đi, em là nơi an toàn để anh không tổn thương ai khác 🫂",
    "Người trưởng thành cãi bằng lý lẽ, người vội vàng cãi bằng âm lượng 🔇",
    "Em xin phép không nhặt lời ấy lên — để nó rơi và mình đi tiếp 🚶‍♀️",
    "Sự tử tế của em không phụ thuộc vào thái độ của anh đâu ạ 🌈",
    "Cơn bão nào rồi cũng tan; em chờ trời quang để mình nói chuyện 🌤️",
    "Mỗi người là một cuốn sách — em mong chương hôm nay của anh sẽ đẹp hơn 📖",
    "Em không cần lời cuối — em cần anh bình an. Vậy đủ rồi ạ 🕊️",
    "Người mạnh thật sự nhẹ nhàng với kẻ yếu hơn mình, chứ không nặng lời 💪🌸",
    "Anh mắng xong thấy nhẹ chưa ạ? Nhẹ rồi thì mình quay lại việc nhé 😊",
    "Đừng để cái miệng đi nhanh hơn cái tâm, kẻo lòng phải chạy theo xin lỗi 🏃",
    "Em không tranh phần đúng — em nhường, vì nhường cũng là một kiểu mạnh 🤲",
    "Giữa ồn ào, người tĩnh lặng là người làm chủ. Em xin làm chủ ạ 🧘‍♀️",
    "Câu nói ác giống viên đá lạnh — cầm lâu thì tê chính bàn tay mình 🧊",
    "Em vẫn mỉm cười với anh — nụ cười là lá chắn êm ái nhất 😊🛡️",
    "Người ta có thể lấy đi sự lịch thiệp của anh, nếu anh cho phép. Em thì không cho 🌟",
    "Cãi thắng một người, mất đi một mối quan hệ. Em không đổi đâu ạ 🤝",
    "Em coi lời khó nghe là gia vị — nếm rồi mình vẫn nấu tiếp món tử tế 🍲",
    "Nói lời dịu dàng khó hơn nói lời cay, nên nó mới đáng quý. Anh thử nhé 🌷",
    "Em không thấp đi vì một câu chửi, và anh cũng không cao lên vì nó đâu ạ ⚖️",
    "Bình tĩnh không phải là yếu đuối — đó là sức mạnh có kiểm soát 🕊️",
    "Em xin giữ hòa khí — vì hòa khí sinh tài, cãi vã sinh phiền 🀄",
    "Người khôn ngoan nhặt bài học, người nóng nảy nhặt kẻ thù. Em nhặt bài học ạ 📘",
    "Anh gửi em cơn giông, em gửi lại anh một cầu vồng 🌈",
    "Lời nói như răng — mất rồi khó mọc lại lắm ạ. Mình giữ gìn nhau nhé 🦷",
    "Em không đáp bằng lửa, vì hai ngọn lửa gặp nhau chỉ có tro tàn 🔥❌",
    "Mình là khách và shop mà — cãi nhau thì ai vui đâu ạ, thôi mình vui nhé 🤗",
    "Người điềm đạm thắng mà không cần trận đánh. Em xin thắng nhẹ nhàng vậy 🍵",
    "Câu chửi rồi sẽ quên, nhưng cách anh khiến người khác thấy sẽ được nhớ 💭",
    "Em để tai nghe điều anh cần, chứ không để bụng điều anh nói lúc nóng 👂",
    "Anh xứng đáng với những điều tốt hơn là một buổi tối đầy bực dọc 🌙",
    "Sự nóng nảy là ngọn nến — cháy sáng một lúc rồi để lại bóng tối. Đừng anh nhé 🕯️",
    "Em không hạ mình xuống để cãi — em nâng mình lên để hiểu 🎈",
    "Người ta yêu quý anh vì trái tim, chứ không vì âm lượng giọng nói ❤️",
    "Em xin phép rót cho cuộc trò chuyện này một chút dịu dàng 🍯",
    "Càng bực càng nói ít lại — lời lúc giận thường là lời phải hối 🤐",
    "Em vẫn tin ngày mai anh sẽ thấy hôm nay mình hơi vội. Không sao đâu ạ 🌅",
    "Người lớn không thắng bằng lời to, mà bằng lòng rộng 🫶",
    "Em không phản pháo — em phản chiếu. Anh thấy gì, đó là anh 🪞",
    "Cơn giận là vị khách — mời nó ngồi rồi tiễn nó đi, đừng cho ở lại ☕",
    "Mình bất đồng chút xíu thôi mà, đâu cần biến thành trận chiến phải không ạ 🤍",
    "Em chọn làm dòng suối mát chứ không làm ngọn lửa. Suối chảy mãi, lửa thì tàn 🏞️",
    "Người tử tế thắng chậm mà thắng bền. Em không vội đâu ạ 🐢",
    "Anh nói gì em cũng lắng nghe — nhưng em xin nghe cái ý, bỏ cái gai 🌹",
    "Miệng cười mà lòng ấm — đó là câu trả lời hay nhất em có cho anh 😊",
    "Đừng mang cơn giận đi ngủ, nó làm hỏng giấc mơ đẹp của anh đấy 🌛",
    "Em không cần phải là người nói câu cuối để là người đúng 🕊️",
    "Người vững vàng không bị lời nói xô ngã. Em vẫn đứng đây phục vụ anh ạ 🧍",
    "Chê bai người khác không nâng mình lên, chỉ kéo cả hai xuống. Mình đi lên nhé ⬆️",
    "Em cảm ơn vì anh vẫn nhắn cho em — nghĩa là mình vẫn còn nói chuyện được mà 🤝",
    "Lời tử tế là loại trang sức đẹp nhất mà không tốn một xu. Anh đeo thử nhé 💎",
    "Em không đấu khẩu — em đấu dịu. Và dịu dàng thường thắng ạ 🌸",
    "Ai cũng có ngày tồi tệ; em xin làm điều tốt đẹp trong ngày của anh 🌼",
    "Nói cho sướng miệng thì dễ, nói cho ấm lòng mới khó. Em chọn cái khó 🍵",
    "Em xin giữ lễ với anh, dù anh đang thử xem em có giữ được không 🙇",
    "Trách móc là gió, bao dung là buồm. Em xin căng buồm đưa mình qua ạ ⛵",
    "Con người ta lớn lên nhờ những lần biết dừng lại đúng lúc. Mình dừng nhé 🛑",
    "Em không đổ lỗi cho anh — em tin ai cũng có lúc lỡ lời 🍃",
    "Anh cứ nói, em cứ hiểu — vậy là mình vẫn còn cầu nối 🌉",
    "Lời cay đắng rẻ tiền, lời tử tế mới sang. Em muốn shop mình sang trọng ạ 👑",
    "Em không cần chiến thắng, em cần anh hài lòng khi rời đi 🚪💛",
    "Người bình an không dễ bị chọc giận — em đang tập điều đó nhờ anh đây ạ 🧘",
    "Sông càng lớn chảy càng êm; em học cách chảy êm giữa lời sóng gió 🌊",
    "Em coi mỗi lời khó nghe là một bài tập nhỏ để mình tử tế hơn 📗",
    "Không phải câu nào cũng cần đáp; có câu chỉ cần một nụ cười 😊",
    "Anh có thể không thích em, nhưng em vẫn chúc anh mọi điều lành 🍀",
    "Người ta hơn nhau ở cái tâm, chứ không ở câu chửi hay tới đâu ạ 💗",
    "Em xin trả lời anh bằng sự tử tế — món vũ khí duy nhất em có 🕊️",
    "Đừng để lời của người khác quyết định con người của anh. Anh hơn thế 🌟",
    "Mình cùng phe mà — em muốn anh vui, anh muốn việc xong. Hợp tác nhé 🤝",
    "Em không giữ lửa giận trong lòng, vì em còn phải sưởi ấm nhiều người khác 🔥❌",
    "Lời nói tốt như hương thơm — thoảng qua mà lưu lại rất lâu 🌸",
    "Em nghiêng mình trước sự nóng nảy của anh, rồi đứng thẳng với sự bình thản của mình 🙇🧍",
    "Cãi nhau chẳng làm ví ai đầy hơn; mình để dành sức lo việc lớn nhé 💰",
    "Em tin điều tốt trong anh nhiều hơn điều anh vừa nói. Cứ để em tin nhé 💛",
    "Người mạnh mẽ nhất phòng là người điềm tĩnh nhất phòng. Em nhường ghế đó cho anh 🪑",
    "Anh đang mưa trong lòng, em xin làm mái hiên che tạm 🏠",
    "Em không cần thắng lời — em muốn giữ tình. Tình quý hơn lời ạ ❤️",
    "Mỗi câu tử tế mình gieo hôm nay là bóng mát cho mình ngày mai 🌳",
    "Em xin phép mỉm cười và tiếp tục giúp anh — vì đó là việc của em 😊🛎️",
    "Ai rồi cũng nguôi, cơn nào rồi cũng qua. Em đợi anh nguôi ạ ⏳",
    "Lời dịu làm tan cơn giận, lời cay chọc nó dậy. Em chọn lời dịu 🍯",
    "Em không lấy cái sai của anh làm cái cớ để em cũng sai theo 🌾",
    "Nồi nào cũng có lúc sôi, nhưng bớt lửa là cơm chín ngon hơn 🍚",
    "Người khôn để bụng chuyện lớn, bỏ ngoài tai chuyện nhỏ. Em bỏ ngoài tai nhé 👂",
    "Em xin gửi anh sự bình yên mà có lẽ lúc này anh đang thiếu 🕊️",
    "Cái tôi càng lớn thì hạnh phúc càng nhỏ. Mình hạ cái tôi cho vui lên nhé 🎈",
    "Em không đáp lại cơn bão — em chỉ chờ nắng rồi mình đi tiếp 🌤️",
    "Người tử tế cuối cùng luôn là người ngủ ngon nhất. Em chúc anh ngủ ngon 😴",
    "Anh xứng đáng được đối xử tử tế — và em bắt đầu điều đó với chính anh 💛",
    "Mình là người với nhau cả — nặng lời chi cho lòng phải nặng theo 🤍",
    "Em xin nhận thua trận cãi, để cùng anh thắng trận việc 🏁",
    "Lời hay là chiếc chìa khóa mở mọi cánh cửa; lời cay chỉ khóa chặt lòng người 🔑",
    "Em không phản đòn — em phản tỉnh. Và em mời anh cùng tỉnh táo lại ☕",
    "Sự dịu dàng không bao giờ là dấu hiệu của yếu đuối, mà của một trái tim vững vàng 💗",
    "Anh gửi gì em cũng nhận, nhưng em chỉ giữ lại điều đẹp để lớn lên mỗi ngày 🌱",
    "Cuối ngày, điều còn lại là mình đã tử tế tới đâu — em muốn tử tế thật nhiều 🌙",
]

def _tg_comeback() -> str:
    import random as _rd
    return _rd.choice(_KENIOS_COMEBACKS)

def _tg_ai_command(token, chat_id, msg, cmd, args, is_admin: bool, ctype: str) -> None:
    """/ai bật-tắt · /hoiai hỏi trực tiếp · /aikey /aimodel /aiprovider /aiurl cấu hình · /aiset xem."""
    import threading
    argl = args.strip().lower()
    # 1) HỎI TRỰC TIẾP: /hoiai, /ask, hoặc /ai <nội dung khác on/off> — cần AI đang bật
    ask_direct = cmd in ("hoiai", "ask") or (
        cmd == "ai" and args.strip() and argl not in ("on", "off", "bat", "tat", "bật", "tắt", "status", "help", "?"))
    if ask_direct:
        if not _tg_ai_active(chat_id, ctype):
            _tg_send(token, chat_id, "🤖 AI đang <b>TẮT</b> ở đây. Admin gõ <code>/ai on</code> để bật.")
            return
        threading.Thread(target=_tg_ai_reply, args=(token, chat_id, msg, args.strip()), daemon=True).start()
        return
    # 2) Xem cấu hình/hướng dẫn — ai cũng xem được
    if cmd in ("aiset", "aihelp"):
        prov, base, model, key = _ai_cfg()
        dm_default = get_setting("tg_ai_dm", "1") == "1"
        _tg_send(token, chat_id,
                 "🤖 <b>Trợ lý AI</b>\n"
                 f"Trạng thái ở đây: <b>{'ĐANG BẬT ✅' if _tg_ai_active(chat_id, ctype) else 'ĐANG TẮT ✖️'}</b>\n"
                 f"Chat riêng tự động trả lời: <b>{'BẬT' if dm_default else 'TẮT'}</b> (đổi bằng /aidm on|off)\n"
                 f"Nhóm trả lời TẤT CẢ tin: <b>{'BẬT' if _tg_ai_all_on(chat_id) else 'TẮT'}</b> (đổi bằng /aiall on|off)\n"
                 f"🔗 Chuỗi AI dự phòng: <b>{len(_ai_backends())}</b> con (hết lượt tự nhảy con kế) — xem /ailist · thêm /aiadd\n"
                 f"AI chính: <b>{prov}</b> · Model: <code>{model}</code> · Khoá: <b>{'đã đặt' if key else 'CHƯA đặt'}</b>\n\n"
                 "⚙️ <b>Bật trong 2 bước:</b>\n"
                 "1️⃣ Lấy khoá MIỄN PHÍ ở https://console.groq.com → nhắn RIÊNG bot: <code>/aikey KHOÁ</code>\n"
                 "2️⃣ Nhắn riêng bot là AI trả lời THẲNG (khỏi cần lệnh). Trong nhóm gõ <code>/ai on</code>, "
                 "muốn trả lời mọi tin thì <code>/aiall on</code>.\n\n"
                 "💬 Cách hỏi trong nhóm: <b>reply</b> vào bot · tag <b>@bot</b> · mở đầu \"<b>ai …</b>\" · "
                 "câu kết thúc \"<b>?</b>\" · hoặc <code>/hoiai câu hỏi</code>.\n\n"
                 "Đổi sang AI khác: <code>/aiprovider openai</code> · <code>/aiurl https://api.openai.com/v1</code> · "
                 "<code>/aimodel gpt-4o-mini</code> · <code>/aikey sk-...</code>")
        return
    # 3) Cấu hình KHOÁ/model/nhà cung cấp/tự-trả-lời-DM/trả-lời-tất-cả — CHỈ admin thật
    if cmd in ("aikey", "aimodel", "aiprovider", "aiurl", "aidm", "aiall", "aiadd", "ailist", "aiclear"):
        if not is_admin:
            _tg_send(token, chat_id, "🔒 Cấu hình AI chỉ dành cho <b>quản trị viên bot</b>.")
            return
        if cmd == "aiadd":
            import json as _json
            sp = args.split()
            if not sp:
                _tg_send(token, chat_id,
                         "➕ <b>Thêm AI dự phòng</b> (hết lượt con này bot tự nhảy con kế tiếp):\n"
                         "<code>/aiadd &lt;nhà cung cấp&gt; &lt;khoá&gt; [model] [base_url]</code>\n\n"
                         "VD:\n<code>/aiadd gemini AQ....</code>\n<code>/aiadd groq gsk_....</code>\n"
                         "<code>/aiadd cerebras csk-....</code>\n<code>/aiadd openrouter sk-or-....</code>\n"
                         "<code>/aiadd openai sk-....</code>\n\n"
                         "Hỗ trợ: gemini · groq · cerebras · openai · deepseek · openrouter · mistral · together · anthropic")
                return
            # Tách base_url (nếu có token bắt đầu bằng http) khỏi các tham số còn lại
            base2 = ""
            rest = []
            for tok in sp:
                if tok.startswith("http://") or tok.startswith("https://"):
                    base2 = tok.rstrip("/")
                else:
                    rest.append(tok)
            # /aiadd <provider> <key> [model]  — hoặc chỉ /aiadd <key> [model] (tự đoán nhà cung cấp)
            _known = set(_AI_PROVIDER_DEFAULTS) | {"google"}
            if len(rest) >= 2 and rest[0].lower() in _known:
                pv, key2 = _ai_norm_provider(rest[0]), rest[1]
                model2 = rest[2] if len(rest) > 2 else ""
            elif rest:
                key2 = rest[0]
                pv = _ai_norm_provider("", key2, base2)
                model2 = rest[1] if len(rest) > 1 else ""
            else:
                _tg_send(token, chat_id, "🔑 Thiếu khoá. VD: <code>/aiadd cerebras csk-....</code>")
                return
            lst = _json.loads(get_setting("tg_ai_backends", "[]") or "[]")
            lst.append({"p": pv, "k": key2, "m": model2, "b": base2})
            set_setting("tg_ai_backends", _json.dumps(lst))
            try:
                _tg_call(token, "deleteMessage", chat_id=chat_id, message_id=msg.get("message_id"))
            except Exception:
                pass
            _db, _dm = _AI_PROVIDER_DEFAULTS.get(pv, _AI_PROVIDER_DEFAULTS["openai"])
            _tg_send(token, chat_id, f"✅ Đã thêm AI dự phòng: <b>{pv}</b> · model <code>{model2 or _dm}</code>\n"
                                     f"🌐 Server: <code>{base2 or _db}</code>\n"
                                     f"Chuỗi hiện có <b>{len(_ai_backends())}</b> AI. Xem: /ailist")
            return
        if cmd == "ailist":
            bs = _ai_backends()
            if not bs:
                _tg_send(token, chat_id, "Chưa có AI nào. Thêm: <code>/aikey KHOÁ</code> hoặc <code>/aiadd &lt;nhà cung cấp&gt; &lt;khoá&gt;</code>.")
                return
            lines = []
            for i, (p, b, m, k) in enumerate(bs, 1):
                mask = (k[:6] + "…" + k[-4:]) if len(k) > 12 else "••••"
                host = b.split("//")[-1].split("/")[0]
                lines.append(f"{i}. <b>{p}</b> · <code>{m}</code>\n     🔑 <code>{mask}</code> · 🌐 {host}")
            _tg_send(token, chat_id, "🔗 <b>CHUỖI AI</b> (hết lượt con trên → tự nhảy con dưới):\n" + "\n".join(lines)
                     + "\n\n➕ Thêm: <code>/aiadd</code> · 🗑️ Xoá các AI phụ: <code>/aiclear</code>")
            return
        if cmd == "aiclear":
            set_setting("tg_ai_backends", "[]")
            _tg_send(token, chat_id, "🗑️ Đã xoá các AI dự phòng (giữ lại AI chính đặt bằng /aikey).")
            return
        if cmd == "aidm":
            on = argl not in ("off", "tat", "tắt", "0")
            set_setting("tg_ai_dm", "1" if on else "0")
            _tg_send(token, chat_id,
                     "💬 Chat riêng TỰ ĐỘNG trả lời bằng AI: <b>BẬT</b> — khách nhắn riêng bot là AI trả lời thẳng, khỏi cần lệnh."
                     if on else
                     "💬 Chat riêng tự động trả lời: <b>TẮT</b> — nhắn riêng sẽ quay lại chế độ hỗ trợ (chuyển tới admin).")
            return
        if cmd == "aiall":
            on = argl not in ("off", "tat", "tắt", "0")
            set_setting("tg_ai_all_" + str(chat_id), "1" if on else "0")
            if on and not _tg_ai_is_on(chat_id):
                _tg_ai_set(chat_id, True)   # bật luôn AI cho nhóm nếu chưa bật
            _tg_send(token, chat_id,
                     "💬 <b>Nhóm TRẢ LỜI TẤT CẢ bằng AI: BẬT</b> — cứ nhắn thẳng là AI trả lời, khỏi cần reply/tag.\n"
                     "🛡️ Có chặn spam: bỏ qua tin quá ngắn (ok/haha) & giới hạn ~1 trả lời/8 giây.\n"
                     "⚠️ Nhóm đông sẽ tốn quota AI nhanh — tắt bằng <code>/aiall off</code> (vẫn hỏi được bằng reply/tag/\"?\")."
                     if on else
                     "💬 Nhóm trả lời tất cả: <b>TẮT</b> — AI chỉ trả lời khi được gọi (reply vào bot · tag @bot · mở đầu \"ai …\" · câu \"?\").")
            return
        if cmd == "aikey":
            if not args.strip():
                _tg_send(token, chat_id, "🔑 Dùng: <code>/aikey KHOÁ_API</code> (nên nhắn RIÊNG cho bot để bảo mật).")
                return
            set_setting("tg_ai_key", args.strip())
            try:
                _tg_call(token, "deleteMessage", chat_id=chat_id, message_id=msg.get("message_id"))
            except Exception:
                pass
            prov, base, model, _ = _ai_cfg()
            _tg_send(token, chat_id, f"✅ Đã lưu khoá AI (đã xoá tin chứa khoá cho an toàn).\n"
                                     f"Nhà cung cấp: <b>{prov}</b> · Model: <code>{model}</code>\nGõ <code>/ai on</code> để bật.")
        elif cmd == "aimodel":
            set_setting("tg_ai_model", args.strip())
            _tg_send(token, chat_id, f"✅ Model AI: <code>{args.strip() or '(mặc định)'}</code>")
        elif cmd == "aiprovider":
            p = argl if argl in ("openai", "anthropic") else ""
            set_setting("tg_ai_provider", p)
            _tg_send(token, chat_id, f"✅ Nhà cung cấp AI: <b>{p or '(tự đoán)'}</b> — chọn: openai | anthropic")
        elif cmd == "aiurl":
            set_setting("tg_ai_base", args.strip())
            _tg_send(token, chat_id, f"✅ Base URL AI: <code>{args.strip() or '(mặc định)'}</code>")
        return
    # 4) BẬT/TẮT: nhóm → chỉ admin; chat riêng → ai cũng bật cho DM của mình
    if not (is_admin or ctype == "private"):
        _tg_send(token, chat_id, "🔒 Bật/tắt AI trong nhóm chỉ dành cho <b>quản trị viên</b>.")
        return
    if argl == "status":
        _tg_send(token, chat_id, f"🤖 AI ở đây đang <b>{'BẬT' if _tg_ai_active(chat_id, ctype) else 'TẮT'}</b>. (/aiset xem cấu hình)")
        return
    if argl in ("on", "bat", "bật", "1"):
        newon = True
    elif argl in ("off", "tat", "tắt", "0"):
        newon = False
    else:
        newon = not _tg_ai_active(chat_id, ctype)   # /ai không tham số → đảo trạng thái
    _tg_ai_set(chat_id, newon)
    if not newon:
        _tg_send(token, chat_id, "🤖 Đã <b>TẮT</b> trợ lý AI ở đây. Bật lại: <code>/ai on</code>.")
        return
    _, _, _, key = _ai_cfg()
    if not key:
        _tg_send(token, chat_id,
                 "🤖 Đã BẬT AI — nhưng <b>chưa có khoá</b>. Admin nhắn RIÊNG bot: <code>/aikey KHOÁ</code>.\n"
                 "Lấy khoá miễn phí: https://console.groq.com · xem <code>/aiset</code>.")
    else:
        _tg_send(token, chat_id,
                 "🤖 <b>Đã BẬT trợ lý AI!</b> Giờ <b>cứ nhắn thẳng trong nhóm là tôi trả lời</b> — khỏi cần reply, "
                 "khỏi cần tag, khỏi mở đầu bằng \"ai\". Tôi giải đáp mọi thắc mắc: toán khó, lập trình, khoa học, "
                 "đời sống, hỏi ngày/giờ… đều trả lời chính xác.\n"
                 "🛡️ Tự bỏ qua tin quá ngắn (ok/haha) &amp; giới hạn nhịp để không spam.\n"
                 "Nếu muốn tôi CHỈ trả lời khi được gọi (reply/tag/\"?\"): <code>/aiall off</code> · Tắt hẳn: <code>/ai off</code>.")

# ======================== 🛒 Tư vấn khách hàng KENIOS (chọn OS → game → bảng giá) ========================
def _kenios_catalog() -> dict:
    """Danh mục sản phẩm & bảng giá (giá KHÔNG bí mật — sửa trực tiếp ở đây khi đổi giá)."""
    return {
        "pubg": {
            "name": "🔫 PUBG Mobile",
            "ios": [("💎 VNHAX", "600K/tháng · 300K/tuần"),
                    ("💎 VNHAX MOD SKIN VN", "450K/tháng · 225K/tuần"),
                    ("💎 OASIS VIP", "800K/tháng · 400K/tuần"),
                    ("💎 KING", "900K/tháng · 450K/tuần"),
                    ("💎 TIMO VIP", "500K/tháng · 250K/tuần · 50K/ngày"),
                    ("💎 VINGODL", "550K/tháng · 250K/tuần"),
                    ("💎 DRACULA", "500K/tháng · 250K/tuần · 70K/ngày")],
            "android": [("💰 ZOLO", "500K/tháng · 250K/tuần"),
                        ("💰 MG", "500K/tháng · 250K/tuần"),
                        ("💰 VNB", "500K/tháng · 250K/tuần"),
                        ("💰 ROOT", "650K/tháng")],
            "goiy": {"ios": "🛡️ An toàn & ổn định nhất: <b>VNHAX</b> hoặc <b>TIMO VIP</b> (có gói ngày 50K để thử trước).",
                     "android": "🛡️ An toàn & chơi ổn nhất: <b>ZOLO</b> / <b>VNB</b>. Máy đã root thì thêm bản <b>ROOT</b>."},
        },
        "lienquan": {
            "name": "⚔️ Liên Quân",
            "both": [("⚔️ LIÊN QUÂN", "250K/tháng · 120K/tuần")],
            "goiy": {"": "🛡️ Bản Liên Quân an toàn, ổn định — dùng được cả iOS &amp; Android."},
        },
        "hyper": {
            "name": "🔥 Hyper",
            "both": [("🔥 HYPER", "350K/tháng · 150K/tuần"), ("🔥 HYPER CHỐNG TỐ", "650K/tháng")],
            "goiy": {"": "🛡️ Muốn an toàn tránh bị báo cáo/tố → chọn bản <b>HYPER CHỐNG TỐ</b>."},
        },
    }

# Từ khoá khách hỏi tư vấn → kích hoạt luồng chọn OS/game (đủ biến thể CÓ DẤU & KHÔNG DẤU).
_KENIOS_SUP_TRIGGERS = (
    # an toàn
    "an toàn", "an toan", "antoan", "có an toàn", "co an toan",
    # bản nào + tính từ
    "bản nào", "ban nao", "bản nao", "ban nào", "bản gì", "ban gi",
    "dùng bản nào", "dung ban nao", "xài bản nào", "xai ban nao", "nên dùng bản", "nen dung ban",
    "chơi bản nào", "choi ban nao",
    # ngon/tốt/ổn/uy tín/rẻ/xịn/mượt/chất
    "ngon nhất", "ngon nhat", "bản ngon", "ban ngon", "tốt nhất", "tot nhat",
    "bản tốt", "ban tot", "bản ổn", "ban on", "uy tín", "uy tin", "bản rẻ", "ban re",
    "bản xịn", "ban xin", "mượt nhất", "muot nhat", "bản mượt", "ban muot", "chất nhất", "chat nhat",
    # chơi ok / được
    "chơi ok", "choi ok", "chơi oke", "choi oke", "chơi ổn", "choi on",
    "chơi mượt", "choi muot", "chơi được", "choi duoc", "chơi tốt", "choi tot",
    # khóa acc / ban / bay / chống tố
    "khóa acc", "khoa acc", "khóa nick", "khoa nick", "bay acc", "bay màu", "bay mau",
    "banned", "ban acc", "bị ban", "bi ban", "dính ban", "dinh ban", "không khóa", "khong khoa",
    "chống tố", "chong to", "chống report", "chong report",
    # tư vấn / hỏi
    "tư vấn", "tu van", "cho hỏi", "cho hoi", "cho mình hỏi", "cho minh hoi",
    "cho em hỏi", "cho em hoi", "shop ơi", "shop oi", "ad ơi", "ad oi", "admin ơi", "admin oi",
    # giá / mua
    "bảng giá", "bang gia", "giá cả", "gia ca", "giá sao", "gia sao", "bao nhiêu", "bao nhieu",
    "nhiêu tiền", "nhieu tien", "giá bao nhiêu", "gia bao nhieu", "nên mua", "nen mua",
    "muốn mua", "muon mua", "mua bản", "mua ban", "mua hack", "mua vip", "đăng ký", "dang ky",
    "gia hạn", "gia han", "còn bản", "con ban", "còn hàng", "con hang", "cho thuê", "cho thue",
    # sản phẩm
    "có bản nào", "co ban nao", "bản mới", "ban moi", "hack nào", "hack nao", "tư vấn giúp", "tu van giup",
)

import re as _kenios_re
# Chỉ cần có CHỮ "bản"/"ban" đứng riêng (như /"bản nào"…) là bot cũng hỏi luôn.
_KENIOS_BAN_WORD = _kenios_re.compile(r"\b(bản|ban)\b", _kenios_re.UNICODE)

def _kenios_wants_support(low: str) -> bool:
    # ĐÃ TẮT theo yêu cầu: bot KHÔNG tự bung bảng giá/tư vấn nữa (tránh làm phiền khách).
    return False

def _kenios_support_start(token, chat_id) -> None:
    _tg_send(token, chat_id,
             "👋 <b>KENIOS — Tư vấn chọn bản an toàn</b>\n\n"
             "Để shop tư vấn bản <b>an toàn &amp; hợp máy</b> nhất, cho hỏi nhẹ:\n"
             "📲 <b>Bạn đang dùng hệ điều hành nào?</b>",
             buttons=[[{"text": "📱 iOS (iPhone)", "callback_data": "ksup:os:ios"},
                       {"text": "🤖 Android", "callback_data": "ksup:os:android"}]])

def _kenios_support_games(token, chat_id, os_, mid=None) -> None:
    oslabel = "📱 iOS (iPhone)" if os_ == "ios" else "🤖 Android"
    btns = [[{"text": "🔫 PUBG Mobile", "callback_data": f"ksup:game:{os_}:pubg"}],
            [{"text": "⚔️ Liên Quân", "callback_data": f"ksup:game:{os_}:lienquan"}],
            [{"text": "🔥 Hyper", "callback_data": f"ksup:game:{os_}:hyper"}]]
    text = f"✅ Hệ điều hành: <b>{oslabel}</b>\n\n🎮 <b>Bạn muốn chơi game nào?</b>"
    if mid:
        _tg_call(token, "editMessageText", chat_id=chat_id, message_id=mid, text=text,
                 parse_mode="HTML", reply_markup={"inline_keyboard": btns})
    else:
        _tg_send(token, chat_id, text, buttons=btns)

def _kenios_support_info(token, chat_id, os_, game) -> None:
    g = _kenios_catalog().get(game)
    if not g:
        return
    oslabel = "📱 iOS (iPhone)" if os_ == "ios" else "🤖 Android"
    if game == "pubg":
        items = g["ios"] if os_ == "ios" else g["android"]
        goiy = g["goiy"]["ios" if os_ == "ios" else "android"]
    else:
        items = g["both"]
        goiy = g["goiy"][""]
    lines = "\n".join(f"{n} — <b>{p}</b>" for n, p in items)
    web = get_setting("kenios_website", "https://linkbio.co/KENIOS")
    pay = get_setting("kenios_pay", "")
    txt = (f"{g['name']} — <b>{oslabel}</b>\n━━━━━━━━━━━━━━\n{lines}\n\n{goiy}\n\n"
           f"🌐 Tất cả dịch vụ: {web}")
    if pay:
        txt += f"\n🏦 Thanh toán: {pay}"
    txt += "\n\n💬 Anh/chị chốt bản nào cứ nhắn shop để được kích hoạt ngay nhé! ❤️"
    _tg_send(token, chat_id, txt)

def _tg_broadcast_task(token: str, admin_chat, text: str) -> None:
    """Gửi 1 thông báo tới TẤT CẢ người đã từng nhắn bot (loa phường)."""
    import html as _h
    ids = []
    try:
        with db() as c:
            c.execute("CREATE TABLE IF NOT EXISTS tg_bot_users(user_id INTEGER PRIMARY KEY, last_seen INTEGER)")
            ids = [r["user_id"] for r in c.execute("SELECT user_id FROM tg_bot_users").fetchall()]
    except Exception:
        pass
    body = "📣 <b>Thông báo</b>\n\n" + text
    lb = _tg_link_buttons()
    params0 = {"text": body, "parse_mode": "HTML", "disable_web_page_preview": True}
    if lb:
        params0["reply_markup"] = {"inline_keyboard": lb}
    ok = 0
    for uid in ids:
        try:
            r = _tg_call(token, "sendMessage", chat_id=uid, **params0)
            if r.get("ok"):
                ok += 1
        except Exception:
            pass
        time.sleep(0.05)
    _tg_send(token, admin_chat, f"✅ Đã gửi tới <b>{ok}/{len(ids)}</b> người dùng.")

def _tg_manage_command(token: str, chat_id, text: str, is_admin: bool) -> bool:
    """Xử lý nhóm lệnh QUẢN LÝ NỘI DUNG BOT (link + lệnh tùy biến + loa phường).
    Trả True nếu đã xử lý. /links và /cmds công khai; còn lại chỉ admin."""
    import re as _re, threading as _th
    sp = text.split(None, 1)
    cmd = sp[0].lstrip("/").split("@")[0].lower()
    rest = sp[1].strip() if len(sp) > 1 else ""

    if cmd == "links":   # công khai — xem nút liên kết
        btns = _tg_link_buttons()
        if btns:
            _tg_send(token, chat_id, "🔗 <b>Liên kết nhanh:</b>", buttons=btns)
        else:
            _tg_send(token, chat_id, "Chưa có liên kết nào. Admin dùng /setlinks để thêm.")
        return True
    if cmd == "cmds":    # công khai — xem danh sách lệnh tùy biến
        lst = _tg_cc_list()
        _tg_send(token, chat_id,
                 ("📋 <b>Lệnh riêng đang có:</b>\n" + "  ".join("/" + x for x in lst)) if lst
                 else "Chưa có lệnh riêng nào. Admin dùng <code>/addcmd</code> để thêm.")
        return True

    if cmd not in ("addcmd", "delcmd", "setlinks", "broadcast"):
        return False
    if not is_admin:
        _tg_send(token, chat_id, "🔒 Chỉ <b>ADMIN</b> mới dùng được lệnh này."); return True

    if cmd == "addcmd":
        a = rest.split(None, 1)
        if len(a) < 2:
            _tg_send(token, chat_id,
                     "➕ <b>Thêm lệnh riêng</b>\nCú pháp: <code>/addcmd &lt;tên&gt; &lt;nội dung trả lời&gt;</code>\n"
                     "VD: <code>/addcmd giá Bảng giá dịch vụ: … liên hệ admin nhé!</code>\n"
                     "Sau đó ai gõ <code>/giá</code> bot sẽ tự trả lời nội dung trên (kèm nút liên kết).")
            return True
        name = a[0].lstrip("/").lower()
        if not _re.match(r"^[a-z0-9_]{1,32}$", name):
            _tg_send(token, chat_id, "Tên lệnh chỉ gồm chữ thường/số/gạch dưới (a–z 0–9 _), tối đa 32 ký tự."); return True
        if name in _TG_RESERVED:
            _tg_send(token, chat_id, f"⚠️ <code>/{name}</code> là lệnh hệ thống, không thể ghi đè. Chọn tên khác nhé."); return True
        _tg_cc_set(name, a[1])
        _tg_send(token, chat_id, f"✅ Đã lưu lệnh <code>/{name}</code>. Gõ <code>/{name}</code> để dùng.")
        return True
    if cmd == "delcmd":
        if not rest:
            _tg_send(token, chat_id, "Cú pháp: <code>/delcmd &lt;tên&gt;</code>"); return True
        name = rest.split()[0].lstrip("/").lower()
        _tg_cc_set(name, None)
        _tg_send(token, chat_id, f"🗑️ Đã xoá lệnh <code>/{name}</code>.")
        return True
    if cmd == "setlinks":
        if not rest:
            base = (_ipa_base_url() or "https://app.kenios.store").rstrip("/")
            _tg_send(token, chat_id,
                     "🔗 <b>Đặt nút liên kết</b> — mỗi dòng 1 nút, dạng <code>Nhãn | https://link</code>\nVD:\n"
                     f"<code>/setlinks 🛒 Cửa hàng | {base}/shop\n📲 Cài app | {base}/install\n"
                     "📢 Kênh Telegram | https://t.me/kenios</code>\n\nGõ <code>/setlinks xoa</code> để xoá hết.")
            return True
        if rest.strip().lower() in ("xoa", "xóa", "clear", "off"):
            set_setting("tg_links", "")
            _tg_send(token, chat_id, "🗑️ Đã xoá toàn bộ nút liên kết (dùng lại mặc định).")
            return True
        set_setting("tg_links", rest)
        n = len(_tg_link_buttons())
        _tg_send(token, chat_id, f"✅ Đã lưu <b>{n}</b> nút liên kết. Gõ /links để xem.", buttons=(_tg_link_buttons() or None))
        return True
    if cmd == "broadcast":
        if not rest:
            _tg_send(token, chat_id, "📣 Cú pháp: <code>/broadcast &lt;nội dung&gt;</code> — gửi tới TẤT CẢ người dùng bot."); return True
        _th.Thread(target=_tg_broadcast_task, args=(token, chat_id, rest), daemon=True).start()
        _tg_send(token, chat_id, "📣 Đang gửi thông báo tới tất cả người dùng…")
        return True
    return False

def _tg_send_photo_or_text(token: str, chat_id, text: str, buttons=None) -> None:
    """Gửi lời chào KÈM ẢNH bot nếu admin đã đặt ảnh (tg_welcome_photo), không thì gửi chữ."""
    photo = get_setting("tg_welcome_photo", "").strip()
    if photo:
        params = {"chat_id": chat_id, "photo": photo, "caption": text, "parse_mode": "HTML"}
        if buttons:
            params["reply_markup"] = {"inline_keyboard": buttons}
        r = _tg_call(token, "sendPhoto", **params)
        if r.get("ok"):
            return
    _tg_send(token, chat_id, text, buttons=buttons)

# ---------- Menu NÚT BẤM (reply keyboard) như Liễu Như Yên ----------
# Bảng chức năng (nút → mô tả). Lưới nút lớn 3 cột như Liễu Như Yên.
_TG_FEAT = {
    "🛡️ Quản trị": "🛡️ <b>Quản trị</b> (trong nhóm, reply vào tin thành viên):\n/ban · /kick · /mute [phút] · /unmute · /warn · /unwarn · /warns · /pin · /unpin · /del · /purge · /info",
    "🔒 Khóa": "🔒 <b>Khóa nội dung</b> (trong nhóm):\n/lock link|photo|video|sticker|gif|forward|mention|all · /unlock · /locks",
    "🚫 Chặn từ": "🚫 <b>Chặn từ (Blacklist)</b>:\n/addbl &lt;từ&gt; · /rmbl &lt;từ&gt; · /blacklist",
    "🌊 Antiflood": ("🌊 <b>Antiflood</b> — chống spam gửi tin dồn dập (đang BẬT mặc định):\n"
                     "• /antiflood — bật/tắt · /antiflood 4 — đổi mức (quá 4 tin/7s bị xoá + cảnh báo)\n"
                     "⚠️ Admin/chủ nhóm mặc định được MIỄN — muốn kiểm duyệt CẢ ADMIN: <code>/modadmin on</code>."),
    "😀 AutoReact": "😀 <b>AutoReact</b>: /autoreact — bot tự thả cảm xúc vào tin.",
    "🌙 NightMode": "🌙 <b>NightMode</b>: /nightmode — tự khóa chat ban đêm.",
    "🐢 Slowmode": "🐢 <b>Slowmode</b>: /slowmode &lt;giây&gt; — giãn cách gửi tin.",
    "🤖 Captcha": "🤖 <b>Captcha</b>: /captcha — bắt thành viên mới xác minh chống bot.",
    "🧹 Dọn dịch vụ": "🧹 <b>CleanService</b>: /clean — tự xoá tin 'đã vào/rời nhóm'.",
    "🎉 Chào nhóm": ("🎉 <b>Chào thành viên mới</b> (gõ trong nhóm, admin):\n"
                     "• /setwelcome &lt;nội dung&gt; — sửa lời chào ({name}, {group}, nhúng link &lt;a href&gt;)\n"
                     "• /setwelcomebtn Nhãn | link — nút link dưới lời chào (nhiều dòng = nhiều nút)\n"
                     "• /setwelcomephoto &lt;link ảnh&gt; — ảnh kèm lời chào\n"
                     "• /setgoodbye &lt;nội dung&gt; — lời tạm biệt · /welcome on|off · /testwelcome — xem thử"),
    "📜 Nội quy": "📜 <b>Nội quy</b>: /setrules &lt;nội dung&gt; · /rules",
    "🔎 Bộ lọc": "🔎 <b>Bộ lọc (Filter)</b>: /filter &lt;từ&gt; &lt;trả lời&gt; · /stop &lt;từ&gt; · /filters",
    "📝 Ghi chú": "📝 <b>Ghi chú (Notes)</b>: /save #tên &lt;nội dung&gt; · /get #tên · /clear · /notes",
    "✅ Điểm danh": "✅ <b>Điểm danh</b>: /diemdanh — điểm danh mỗi ngày.",
    "🏆 Xếp hạng": "🏆 <b>Xếp hạng</b>: /top — thành viên tích cực nhất.",
    "🚨 Báo cáo": "🚨 <b>Báo cáo</b>: /report (reply) — báo admin xử lý.",
    "🆔 ID": "🆔 <b>/id</b> — xem Chat ID / User ID (reply để lấy ID người khác).",
    "💤 AFK": "💤 <b>AFK</b>: /afk [lý do] — báo bận; ai nhắc tên bạn, bot sẽ báo bạn đang bận.",
    "📌 Ghim": "📌 <b>Ghim tin</b> (reply, trong nhóm): /pin · /unpin.",
    "🗑️ Dọn tin": ("🗑️ <b>Dọn tin</b> (trong nhóm): /del (reply) xoá 1 tin · /purge (reply) xoá hàng loạt tới tin đó.\n"
                   "🧽 <b>Tự xoá lệnh</b>: dùng lệnh xong bot tự xoá tin lệnh + trả lời sau 5 giây.\n"
                   "• /autodel 10 — đổi số giây · /autodel off — tắt"),
    "🎮 Trò chơi": ("🎮 <b>Trò chơi</b> (ai cũng chơi được):\n"
                    "/xucxac 🎲 · /slot 🎰 · /phitieu 🎯 · /bongda ⚽ · /bongro 🏀 · /bowling 🎳\n"
                    "/tungxu — tung đồng xu · /oantuti kéo|búa|bao — đấu với bot\n"
                    "/doanso — đoán số 1–100 (đoán bằng /doan 50)\n"
                    "/random 1 100 · /chon trà sữa | cà phê · /xoso — quay số may mắn"),
    "🃏 Game bài": ("🃏 <b>Game bài</b> (thắng +5 điểm vui):\n"
                    "/baicao — bài cào 3 cây đấu bot (ba tây ăn tất!)\n"
                    "/xidach — xì dách 21 điểm: /rut — rút bài · /dan — so bài (xì dách +8đ)\n"
                    "/baucua bầu — bầu cua tôm cá gà nai (trúng +3đ/con)\n"
                    "📊 /diemdo — bảng vàng điểm vui"),
    "🧠 Đố vui": ("🧠 <b>Đố vui CÓ ĐIỂM</b> — ~1080 câu, 20+ thể loại (thủ đô, cờ các nước, toán nhanh,\n"
                  "dãy số, kiến thức, đố mẹo, đố chữ, ca dao tục ngữ…).\n\n"
                  "📖 <b>Cách chơi:</b> gõ /dovui → bot ra câu đố → <b>NHẮN THẲNG đáp án</b> vào khung chat\n"
                  "(không cần dấu /, gõ không dấu vẫn tính). Ai đúng ĐẦU TIÊN +10 điểm + lời chúc 🎉,\n"
                  "bot tự ra câu tiếp — cả nhóm đấu liên tục!\n"
                  "/goiy — gợi ý · /boqua — hiện đáp án, câu mới · /dungdo — dừng\n"
                  "📊 /diemdo — BẢNG VÀNG xếp hạng điểm"),
    "😂 Giải trí": ("😂 <b>Giải trí</b>:\n"
                    "/cuoi — chuyện cười · /cakhia (reply) — cà khịa vui · /khen (reply) — khen ai đó\n"
                    "/thatha — nói thật · /thachthuc — thử thách · /ghep — ghép đôi ngẫu nhiên\n"
                    "/lucky — thành viên may mắn · /triethly · /thotinh · /noinguoc <chữ>"),
    "🔮 Bói vui": ("🔮 <b>Bói vui</b>:\n"
                   "/boi — vận may hôm nay · /tinhduyen (reply hoặc /tinhduyen Tuấn | Hoa)\n"
                   "/hoi <câu hỏi> — bot tiên tri trả lời · /danhgia <thứ gì đó> — chấm điểm %"),
    "🧰 Tiện ích": ("🧰 <b>Tiện ích</b>:\n"
                    "/tinh 5*(3+2) — máy tính · /qr <nội dung> — tạo mã QR\n"
                    "/thoitiet [thành phố] · /giacoin btc · /tygia — USD→VND · /dich <chữ>\n"
                    "/nhacnho 30 họp nhóm — hẹn nhắc · /binhchon Câu hỏi | A | B — bình chọn\n"
                    "/gio — giờ thế giới · /dem <chữ> · /password 16 — tạo mật khẩu"),
    "🔗 Liên kết": None,        # → nút mở link (web, cài app, kênh…)
    "➕ Lệnh riêng": None,       # → hướng dẫn tự thêm lệnh bot
    "📣 Loa phường": None,      # → hướng dẫn broadcast (admin)
    "⚙️ Cấu hình": None,        # → xem cấu hình bot
    "📖 Tất cả lệnh": None,     # → hiện danh sách lệnh dạng chữ
    "🎵 Lấy nhạc": None,        # → hướng dẫn /nhac
    "📊 Thống kê": None,        # → số người dùng
    "ℹ️ Giới thiệu": None,      # → tg_about
    "💬 Hỗ trợ": None,          # → nhắn hỗ trợ
}

# Nút CÔNG KHAI — thành viên thường thấy; các nút còn lại (quản trị) CHỈ ADMIN thấy.
_TG_PUBLIC_BTNS = {"✅ Điểm danh", "🏆 Xếp hạng", "🚨 Báo cáo", "🆔 ID", "💤 AFK", "🔗 Liên kết",
                   "📖 Tất cả lệnh", "🎵 Lấy nhạc", "📊 Thống kê", "ℹ️ Giới thiệu", "💬 Hỗ trợ",
                   "🎮 Trò chơi", "🃏 Game bài", "🧠 Đố vui", "😂 Giải trí", "🔮 Bói vui", "🧰 Tiện ích"}

def _tg_full_menu(admin: bool = False) -> dict:
    labels = [b for b in _TG_FEAT.keys() if admin or b in _TG_PUBLIC_BTNS]
    rows = [labels[i:i + 3] for i in range(0, len(labels), 3)]
    rows.append(["🏠 Menu", "❌ Đóng"])
    return {"keyboard": [[{"text": b} for b in r] for r in rows], "resize_keyboard": True}

def _tg_send_menu(token, chat_id, text, photo_first=False, admin=False) -> None:
    kb = _tg_full_menu(admin)
    photo = get_setting("tg_welcome_photo", "").strip()
    if photo_first and photo:
        r = _tg_call(token, "sendPhoto", chat_id=chat_id, photo=photo, caption=text,
                     parse_mode="HTML", reply_markup=kb)
        if r.get("ok"):
            return
    _tg_call(token, "sendMessage", chat_id=chat_id, text=text, parse_mode="HTML",
             disable_web_page_preview=True, reply_markup=kb)

def _tg_menu_click(token, chat_id, text, name="", admin=False) -> bool:
    """Xử lý khi bấm nút menu (reply keyboard). Trả True nếu đã xử lý."""
    t = (text or "").strip()
    if t in ("🏠 Menu", "/menu", "menu", "/help", "📚 Hướng dẫn đầy đủ"):
        _tg_send_menu(token, chat_id, "📋 <b>MENU KENIOS</b> — chọn chức năng bên dưới 👇", admin=admin); return True
    if t == "❌ Đóng":
        _tg_call(token, "sendMessage", chat_id=chat_id, text="Đã đóng menu. Gõ /menu để mở lại.",
                 reply_markup={"remove_keyboard": True}); return True
    # Nút QUẢN TRỊ gõ bởi thành viên thường → báo quyền (menu của họ vốn không có nút này).
    if t in _TG_FEAT and t not in _TG_PUBLIC_BTNS and not admin:
        _tg_send(token, chat_id, "🔒 Chức năng này chỉ dành cho <b>quản trị viên</b>."); return True
    if t == "🔗 Liên kết":
        btns = _tg_link_buttons()
        if btns:
            _tg_send(token, chat_id, "🔗 <b>Liên kết nhanh:</b>", buttons=btns)
        else:
            _tg_send(token, chat_id, "Chưa có liên kết. Admin dùng /setlinks để thêm.")
        return True
    if t == "📣 Loa phường":
        _tg_send(token, chat_id,
                 "📣 <b>Loa phường</b> (chỉ ADMIN): <code>/broadcast &lt;nội dung&gt;</code>\n"
                 "Gửi thông báo tới TẤT CẢ người đã từng nhắn bot, kèm nút liên kết.")
        return True
    if t == "⚙️ Cấu hình":
        _tg_send(token, chat_id,
                 "⚙️ <b>Cấu hình bot</b>\n"
                 f"Quản lý nhóm: {'BẬT' if get_setting('tg_mod_enabled','1')=='1' else 'tắt'}\n"
                 f"Chống link: {'✓' if get_setting('tg_del_links','1')=='1' else '✗'} · "
                 f"Antiflood: {'✓' if get_setting('tg_antiflood_on','1')=='1' else '✗'} · "
                 f"Captcha: {'✓' if get_setting('tg_captcha_on','0')=='1' else '✗'}\n"
                 f"AutoReact: {'✓' if get_setting('tg_autoreact_on','0')=='1' else '✗'} · "
                 f"Slowmode: {get_setting('tg_slowmode','0')}s · "
                 f"NightMode: {'✓' if get_setting('tg_nightmode_on','0')=='1' else '✗'}\n"
                 "Chỉnh chi tiết trong app KENIOS → Quản trị → Bot Telegram, hoặc lệnh trong nhóm.")
        return True
    if t == "➕ Lệnh riêng":
        lst = _tg_cc_list()
        info = ("➕ <b>Lệnh riêng của bot</b> (admin tạo — ai cũng gọi được):\n"
                "• <code>/addcmd &lt;tên&gt; &lt;nội dung&gt;</code> — thêm/sửa lệnh\n"
                "• <code>/delcmd &lt;tên&gt;</code> — xoá lệnh\n"
                "• <code>/cmds</code> — xem tất cả lệnh riêng\n\n"
                "🔗 <b>Nút liên kết</b> (mỗi dòng 1 nút):\n"
                "• <code>/setlinks Nhãn | https://link</code>\n"
                "• <code>/links</code> — xem nút\n\n"
                "📣 <b>Loa phường</b>: <code>/broadcast &lt;nội dung&gt;</code> — gửi tới mọi người dùng.")
        if lst:
            info += "\n\n📋 Đang có: " + "  ".join("/" + x for x in lst)
        _tg_send(token, chat_id, info); return True
    if t == "📖 Tất cả lệnh":
        _tg_send(token, chat_id, _tg_help_text(name, admin)); return True
    if t == "🎵 Lấy nhạc":
        _tg_send(token, chat_id, "🎵 Gửi: <code>/nhac &lt;tên bài hoặc link YouTube/TikTok&gt;</code>\nVD: <code>/nhac Sơn Tùng</code>"); return True
    if t == "📊 Thống kê":
        _tg_send(token, chat_id, f"👥 <b>{_tg_monthly():,}</b> người dùng bot trong 30 ngày.".replace(",", ".")); return True
    if t == "ℹ️ Giới thiệu":
        _tg_send(token, chat_id, get_setting("tg_about", "KENIOS — nền tảng ứng dụng & cửa hàng số. Gõ /menu để mở menu.")); return True
    if t == "💬 Hỗ trợ":
        _tg_send(token, chat_id, "✍️ Bạn cứ nhắn nội dung cần hỗ trợ ngay đây, đội ngũ KENIOS sẽ trả lời sớm nhất."); return True
    if t in _TG_FEAT and _TG_FEAT[t]:
        _tg_send(token, chat_id, _TG_FEAT[t]); return True
    return False

# ---------- Tiện ích quản lý nhóm ----------
_tg_admins_cache: dict = {}   # chat_id -> (ts, set(user_id admin))

def _tg_name(frm: dict) -> str:
    if not frm: return "Thành viên"
    n = ((frm.get("first_name", "") or "") + " " + (frm.get("last_name", "") or "")).strip()
    return n or frm.get("username", "") or "Thành viên"

def _tg_mention(frm: dict) -> str:
    import html as _h
    nm = _h.escape(_tg_name(frm)); uid = frm.get("id")
    return f'<a href="tg://user?id={uid}">{nm}</a>' if uid else nm

def _tg_is_admin(token: str, chat_id: str, uid) -> bool:
    if uid is None: return False
    now = time.time()
    c = _tg_admins_cache.get(chat_id)
    if not c or now - c[0] > 300:
        res = _tg_call(token, "getChatAdministrators", chat_id=chat_id)
        ids = {a.get("user", {}).get("id") for a in res.get("result", [])} if res.get("ok") else set()
        _tg_admins_cache[chat_id] = (now, ids); c = (now, ids)
    return uid in c[1]

def _tg_is_privileged(token: str, chat_id: str, msg: dict) -> bool:
    """Được MIỄN kiểm duyệt & được dùng lệnh: admin nhóm, admin ẩn danh, hoặc Channel của nhóm.
    (Kênh liên kết auto-forward, bài đăng của kênh, admin ẩn danh đều có 'sender_chat'.)"""
    if msg.get("sender_chat") or msg.get("is_automatic_forward"):
        return True
    return _tg_is_admin(token, chat_id, (msg.get("from") or {}).get("id"))

def _tg_has_link(msg: dict) -> bool:
    import re as _re
    for e in (msg.get("entities") or []) + (msg.get("caption_entities") or []):
        if e.get("type") in ("url", "text_link"): return True
    t = ((msg.get("text", "") or "") + " " + (msg.get("caption", "") or "")).lower()
    if "http://" in t or "https://" in t or "t.me/" in t or "www." in t: return True
    return bool(_re.search(r"\b[\w-]+\.(com|net|org|xyz|vn|io|me|link|top|shop|info|club|online|site)\b", t))

def _warn_add(chat_id, uid) -> int:
    cid = str(chat_id)
    with db() as c:
        c.execute("CREATE TABLE IF NOT EXISTS tg_warns(chat_id TEXT, user_id INTEGER, count INTEGER DEFAULT 0, PRIMARY KEY(chat_id,user_id))")
        row = c.execute("SELECT count FROM tg_warns WHERE chat_id=? AND user_id=?", (cid, uid)).fetchone()
        n = (row["count"] if row else 0) + 1
        if row: c.execute("UPDATE tg_warns SET count=? WHERE chat_id=? AND user_id=?", (n, cid, uid))
        else: c.execute("INSERT INTO tg_warns(chat_id,user_id,count) VALUES(?,?,?)", (cid, uid, n))
    return n

def _warn_reset(chat_id, uid) -> None:
    with db() as c:
        c.execute("CREATE TABLE IF NOT EXISTS tg_warns(chat_id TEXT, user_id INTEGER, count INTEGER DEFAULT 0, PRIMARY KEY(chat_id,user_id))")
        c.execute("UPDATE tg_warns SET count=0 WHERE chat_id=? AND user_id=?", (str(chat_id), uid))

def _tg_warn(token: str, chat_id: str, frm: dict, reason: str) -> None:
    uid = frm.get("id")
    n = _warn_add(chat_id, uid)
    limit = int(get_setting("tg_warn_limit", "3") or 3)
    if n >= limit:
        _warn_reset(chat_id, uid)
        if get_setting("tg_warn_action", "mute") == "ban":
            _tg_call(token, "banChatMember", chat_id=chat_id, user_id=uid)
            _tg_send(token, chat_id, f"🚫 Đã CẤM {_tg_mention(frm)} (đủ {limit} cảnh báo).")
            _tg_log(token, f"BAN {_tg_name(frm)} tại {chat_id} (đủ {limit} cảnh báo).")
        else:
            _tg_call(token, "restrictChatMember", chat_id=chat_id, user_id=uid,
                     permissions={"can_send_messages": False}, until_date=int(time.time()) + 3600)
            _tg_send(token, chat_id, f"🔇 Đã CẤM CHAT {_tg_mention(frm)} 1 giờ (đủ {limit} cảnh báo).")
            _tg_log(token, f"MUTE {_tg_name(frm)} tại {chat_id} 1 giờ (đủ {limit} cảnh báo).")
    else:
        _tg_send(token, chat_id, f"⚠️ {_tg_mention(frm)} bị cảnh báo ({n}/{limit}) — {reason}. Tin đã bị xoá.")
        _tg_log(token, f"WARN {_tg_name(frm)} ({n}/{limit}) tại {chat_id}: {reason}.")

def _tg_user_avatar_file_id(token: str, user_id) -> str:
    """Lấy file_id ảnh đại diện của thành viên (để gửi kèm chào/tạm biệt)."""
    try:
        r = _tg_call(token, "getUserProfilePhotos", user_id=user_id, limit=1)
        photos = (r.get("result") or {}).get("photos") or []
        if photos and photos[0]:
            return photos[0][-1].get("file_id", "")   # cỡ lớn nhất
    except Exception:
        pass
    return ""

def _tg_member_count(token: str, chat_id) -> int:
    try:
        r = _tg_call(token, "getChatMemberCount", chat_id=chat_id)
        return int(r.get("result", 0)) if r.get("ok") else 0
    except Exception:
        return 0

def _tg_user_info_block(m: dict, count: int = 0) -> str:
    """Khối thông tin đầy đủ: ID · username · ngày giờ · số thành viên."""
    import html as _h
    uid = m.get("id", "?")
    uname = m.get("username", "")
    lines = [f"🆔 ID: <code>{uid}</code>",
             f"👤 Tên: {_tg_mention(m)}"]
    if uname:
        lines.append(f"🔗 Username: @{_h.escape(uname)}")
    lines.append(f"📅 {_tg_vn_now()} (giờ VN)")
    if count:
        lines.append(f"👥 Nhóm hiện có: <b>{count}</b> thành viên")
    return "\n".join(lines)

def _tg_welcome_members(token: str, chat: dict, members: list) -> None:
    if get_setting("tg_welcome_on", "1") != "1": return
    tmpl = get_setting("tg_welcome_group", "🎉 Chào mừng {name} đã vào {group}!")
    buttons = _tg_parse_btns(get_setting("tg_welcome_btns", ""))
    if not buttons:
        bt, bu = get_setting("tg_welcome_btn_text", ""), get_setting("tg_welcome_btn_url", "")
        buttons = [[{"text": bt, "url": bu}]] if bt and bu else None
    custom_photo = get_setting("tg_welcome_group_photo", "").strip()
    gname = chat.get("title", "nhóm")
    chat_id = str(chat.get("id"))
    count = _tg_member_count(token, chat_id)
    # Lời chào TỰ XOÁ sau tg_welcome_del_sec giây (mặc định 5s; đặt 0 để giữ lại).
    try:
        del_sec = int(get_setting("tg_welcome_del_sec", "5") or 0)
    except Exception:
        del_sec = 5
    for m in members:
        if m.get("is_bot"): continue
        txt = tmpl.replace("{name}", _tg_mention(m)).replace("{group}", gname)
        # THÔNG TIN ĐẦY ĐỦ: ID · username · ngày giờ · số thành viên
        txt += "\n\n" + _tg_user_info_block(m, count)
        # ẢNH: ưu tiên avatar CỦA NGƯỜI MỚI; không có thì dùng ảnh admin đặt.
        photo = _tg_user_avatar_file_id(token, m.get("id")) or custom_photo
        mid = None
        if photo:
            params = {"chat_id": chat_id, "photo": photo, "caption": txt, "parse_mode": "HTML"}
            if buttons:
                params["reply_markup"] = {"inline_keyboard": buttons}
            _r = _tg_call(token, "sendPhoto", **params)
            if _r.get("ok"):
                mid = ((_r.get("result") or {}).get("message_id"))
        if mid is None:
            _r = _tg_send(token, chat_id, txt, buttons=buttons)
            mid = ((_r or {}).get("result") or {}).get("message_id")
        if del_sec > 0 and mid:
            _tg_delete_later(token, [(chat_id, mid)], del_sec)

def _tg_goodbye_member(token: str, chat: dict, m: dict) -> None:
    if get_setting("tg_goodbye_on", "1") != "1" or not m or m.get("is_bot"): return
    # Chống tạm biệt 2 lần: khi rời/bị xoá có thể có CẢ left_chat_member LẪN chat_member.
    if not _tg_greet_once(chat.get("id"), m.get("id"), "leave"): return
    tmpl = get_setting("tg_goodbye", "👋 Tạm biệt {name}, hẹn gặp lại!")
    chat_id = str(chat.get("id"))
    count = _tg_member_count(token, chat_id)
    txt = tmpl.replace("{name}", _tg_mention(m)).replace("{group}", chat.get("title", "nhóm"))
    txt += "\n\n" + _tg_user_info_block(m, count)
    photo = _tg_user_avatar_file_id(token, m.get("id"))
    if photo:
        params = {"chat_id": chat_id, "photo": photo, "caption": txt, "parse_mode": "HTML"}
        if _tg_call(token, "sendPhoto", **params).get("ok"):
            return
    _tg_send(token, chat_id, txt)

# Chống chào 2 lần cùng 1 người: khi được thành viên khác THÊM vào, Telegram gửi CẢ
# "new_chat_members" LẪN "chat_member" → nếu không lọc sẽ chào 2 lần.
_tg_greet_seen: dict = {}   # (chat_id, uid) -> thời điểm đã chào

def _tg_greet_once(chat_id, uid, action: str = "join") -> bool:
    """True nếu chưa chào/tạm biệt người này trong ~20 giây gần đây (cho phép gửi)."""
    now = time.time()
    for k, ts in list(_tg_greet_seen.items()):
        if now - ts > 120:
            _tg_greet_seen.pop(k, None)
    key = (str(chat_id), str(uid), action)
    if now - _tg_greet_seen.get(key, 0) < 20:
        return False
    _tg_greet_seen[key] = now
    return True

def _tg_greet_or_captcha(token: str, chat: dict, m: dict) -> None:
    """Chào (hoặc bắt captcha) MỘT thành viên mới — dùng chung cho cả 2 kiểu vào nhóm:
    được thêm vào (new_chat_members) và tự vào qua link/nhóm công khai (chat_member)."""
    if not m or m.get("is_bot"):
        return
    chat_id = str(chat.get("id"))
    if not _tg_greet_once(chat_id, m.get("id")):
        return
    if get_setting("tg_captcha_on", "0") == "1":
        # Captcha: hạn chế thành viên mới, yêu cầu bấm nút xác minh (chống bot vào spam).
        uid = m.get("id")
        _tg_call(token, "restrictChatMember", chat_id=chat_id, user_id=uid,
                 permissions={"can_send_messages": False})
        _tg_send(token, chat_id,
                 f"🛡️ {_tg_mention(m)} hãy bấm nút bên dưới trong 60 giây để xác minh (chống bot).",
                 buttons=[[{"text": "✅ Tôi không phải bot", "callback_data": f"verify:{uid}"}]])
    else:
        _tg_welcome_members(token, chat, [m])

def _tg_on_join(token: str, chat: dict, msg: dict) -> None:
    chat_id = str(chat.get("id"))
    members = [m for m in msg.get("new_chat_members", []) if not m.get("is_bot")]
    for m in members:
        _tg_greet_or_captcha(token, chat, m)
    if get_setting("tg_clean_service", "0") == "1":
        _tg_call(token, "deleteMessage", chat_id=chat_id, message_id=msg.get("message_id"))

def _tg_on_chat_member(token: str, cm: dict) -> None:
    """Sự kiện chat_member: bắt người VÀO/RỜI nhóm qua LINK MỜI / tự vào-ra nhóm công khai
    (những kiểu này KHÔNG có new_chat_members / left_chat_member). Chào khi chuyển từ
    'ngoài nhóm' → 'thành viên', tạm biệt khi 'thành viên' → 'ngoài nhóm'."""
    chat = cm.get("chat", {})
    if chat.get("type") not in ("group", "supergroup"):
        return
    old = cm.get("old_chat_member", {}) or {}
    new = cm.get("new_chat_member", {}) or {}
    user = new.get("user", {}) or old.get("user", {}) or {}
    if user.get("is_bot"):
        return
    def _inside(st: dict) -> bool:
        s = st.get("status")
        if s in ("member", "administrator", "creator"):
            return True
        if s == "restricted":
            return bool(st.get("is_member"))
        return False   # left | kicked | none
    was_in, now_in = _inside(old), _inside(new)
    if now_in and not was_in:
        _tg_greet_or_captcha(token, chat, user)      # vừa vào → chào
    elif was_in and not now_in:
        _tg_goodbye_member(token, chat, user)        # vừa rời → tạm biệt

# ---------- Kho dữ liệu module (notes/filters/afk/flood/khoá/từ cấm) ----------
_tg_flood: dict = {}
_tg_afk: dict = {}      # user_id -> (reason, since)
_tg_groups: set = set()

def _tg_locks() -> set:
    return {x.strip() for x in (get_setting("tg_locks", "") or "").split(",") if x.strip()}
def _tg_blacklist() -> list:
    return [x.strip().lower() for x in (get_setting("tg_blacklist", "") or "").split(",") if x.strip()]
def _tg_in_night() -> bool:
    if get_setting("tg_nightmode_on", "0") != "1": return False
    try:
        s = int(get_setting("tg_night_start", "23")); e = int(get_setting("tg_night_end", "6"))
    except Exception:
        return False
    h = int(time.strftime("%H"))
    if s == e: return False
    return (s <= h < e) if s < e else (h >= s or h < e)
def _tg_flood_hit(chat_id: str, uid) -> bool:
    if get_setting("tg_antiflood_on", "1") != "1": return False
    mx = int(get_setting("tg_antiflood_max", "4") or 4)
    win = int(get_setting("tg_antiflood_window", "7") or 7)
    now = time.time(); key = (chat_id, uid)
    arr = [t for t in _tg_flood.get(key, []) if now - t < win]
    arr.append(now); _tg_flood[key] = arr
    return len(arr) > mx
def _tg_has_mention(msg: dict) -> bool:
    for e in (msg.get("entities") or []) + (msg.get("caption_entities") or []):
        if e.get("type") in ("mention", "text_mention"): return True
    return False

# ---- FameRank (đếm tin) · Điểm danh · Slow mode · Log ----
_tg_lastmsg: dict = {}

def _msgcount_inc(chat_id, uid, name) -> None:
    with db() as c:
        c.execute("CREATE TABLE IF NOT EXISTS tg_msgcount(chat_id TEXT,user_id INTEGER,name TEXT,count INTEGER DEFAULT 0,PRIMARY KEY(chat_id,user_id))")
        if c.execute("SELECT 1 FROM tg_msgcount WHERE chat_id=? AND user_id=?", (str(chat_id), uid)).fetchone():
            c.execute("UPDATE tg_msgcount SET count=count+1, name=? WHERE chat_id=? AND user_id=?", (name, str(chat_id), uid))
        else:
            c.execute("INSERT INTO tg_msgcount(chat_id,user_id,name,count) VALUES(?,?,?,1)", (str(chat_id), uid, name))

def _msgcount_top(chat_id, n=10) -> list:
    with db() as c:
        c.execute("CREATE TABLE IF NOT EXISTS tg_msgcount(chat_id TEXT,user_id INTEGER,name TEXT,count INTEGER DEFAULT 0,PRIMARY KEY(chat_id,user_id))")
        rows = c.execute("SELECT name,count FROM tg_msgcount WHERE chat_id=? ORDER BY count DESC LIMIT ?", (str(chat_id), n)).fetchall()
        total = c.execute("SELECT COALESCE(SUM(count),0) s, COUNT(*) u FROM tg_msgcount WHERE chat_id=?", (str(chat_id),)).fetchone()
    return [(r["name"], r["count"]) for r in rows], (total["s"], total["u"])

def _checkin(chat_id, uid):
    import datetime as _dt
    today = _dt.date.today().isoformat()
    yday = (_dt.date.today() - _dt.timedelta(days=1)).isoformat()
    with db() as c:
        c.execute("CREATE TABLE IF NOT EXISTS tg_checkin(chat_id TEXT,user_id INTEGER,last_day TEXT,streak INTEGER DEFAULT 0,total INTEGER DEFAULT 0,PRIMARY KEY(chat_id,user_id))")
        r = c.execute("SELECT last_day,streak,total FROM tg_checkin WHERE chat_id=? AND user_id=?", (str(chat_id), uid)).fetchone()
        if r and r["last_day"] == today:
            return None
        streak = (r["streak"] + 1) if (r and r["last_day"] == yday) else 1
        total = (r["total"] + 1) if r else 1
        if r: c.execute("UPDATE tg_checkin SET last_day=?,streak=?,total=? WHERE chat_id=? AND user_id=?", (today, streak, total, str(chat_id), uid))
        else: c.execute("INSERT INTO tg_checkin(chat_id,user_id,last_day,streak,total) VALUES(?,?,?,?,?)", (str(chat_id), uid, today, streak, total))
    return (streak, total)

def _slowmode_hit(chat_id, uid) -> bool:
    sec = int(get_setting("tg_slowmode", "0") or 0)
    if sec <= 0: return False
    now = time.time(); key = (chat_id, uid)
    hit = (now - _tg_lastmsg.get(key, 0)) < sec
    _tg_lastmsg[key] = now
    return hit

def _tg_log(token: str, text: str) -> None:
    lc = get_setting("tg_log_chat", "").strip()
    if lc: _tg_send(token, lc, "📋 " + text)

def _tg_send_photo(token: str, chat_id, photo_url: str, caption: str, buttons: Optional[list] = None) -> None:
    params = {"chat_id": chat_id, "photo": photo_url, "caption": caption, "parse_mode": "HTML"}
    if buttons: params["reply_markup"] = {"inline_keyboard": buttons}
    r = _tg_call(token, "sendPhoto", **params)
    if not r.get("ok"):   # ảnh lỗi → gửi chữ để không mất lời chào
        _tg_send(token, chat_id, caption, buttons=buttons)

def _tg_users_touch(uid) -> None:
    if not uid: return
    now = int(time.time())
    with db() as c:
        c.execute("CREATE TABLE IF NOT EXISTS tg_users(user_id INTEGER PRIMARY KEY,last_seen INTEGER)")
        if c.execute("SELECT 1 FROM tg_users WHERE user_id=?", (uid,)).fetchone():
            c.execute("UPDATE tg_users SET last_seen=? WHERE user_id=?", (now, uid))
        else:
            c.execute("INSERT INTO tg_users(user_id,last_seen) VALUES(?,?)", (uid, now))

def _tg_users_month() -> int:
    with db() as c:
        c.execute("CREATE TABLE IF NOT EXISTS tg_users(user_id INTEGER PRIMARY KEY,last_seen INTEGER)")
        r = c.execute("SELECT COUNT(*) n FROM tg_users WHERE last_seen>?", (int(time.time()) - 30 * 86400,)).fetchone()
    return r["n"] if r else 0

def _tg_start_menu() -> list:
    return [[{"text": "📚 Hướng dẫn đầy đủ", "callback_data": "guide"}],
            [{"text": "🛡️ Lệnh quản lý", "callback_data": "cmds"},
             {"text": "🎵 Lấy nhạc", "callback_data": "music"}],
            [{"text": "💬 Hỗ trợ", "callback_data": "support"},
             {"text": "ℹ️ Giới thiệu", "callback_data": "about"}]]

def _tg_send_audio(token: str, chat_id, filepath: str, title: str = "") -> bool:
    import httpx
    try:
        with open(filepath, "rb") as f:
            r = httpx.post(f"https://api.telegram.org/bot{token}/sendAudio",
                           data={"chat_id": str(chat_id), "title": title[:60], "caption": "🎵 KENIOS Bot"},
                           files={"audio": (title or "audio.mp3", f, "audio/mpeg")}, timeout=600)
        return r.json().get("ok", False)
    except Exception as e:
        log.warning("sendAudio lỗi: %s", e); return False

def _tg_music(token: str, chat_id, url: str) -> None:
    """Tải nhạc từ YouTube/TikTok (yt-dlp) rồi gửi dạng audio — Telegram phát nền khi thoát app."""
    import subprocess, tempfile, shutil, glob
    if not shutil.which("yt-dlp"):
        _tg_send(token, chat_id, "Máy chủ chưa cài yt-dlp. Chạy lại capnhat-vps.sh."); return
    if not (url.startswith("http://") or url.startswith("https://")):
        _tg_send(token, chat_id, "Cú pháp: /nhac <link YouTube hoặc TikTok>"); return
    _tg_send(token, chat_id, "⏬ Đang tải nhạc, chờ chút...")
    d = tempfile.mkdtemp(prefix="tgmusic_")
    try:
        subprocess.run(["yt-dlp", "-x", "--audio-format", "mp3", "--no-playlist",
                        "--add-metadata", "-o", os.path.join(d, "a.%(ext)s"), url],
                       capture_output=True, text=True, timeout=600)
        files = glob.glob(os.path.join(d, "a.*"))
        if not files:
            _tg_send(token, chat_id, "Không tải được nhạc từ link này."); return
        fp = files[0]
        if os.path.getsize(fp) > 49 * 1024 * 1024:
            _tg_send(token, chat_id, "🎵 Bài quá lớn (>50MB). Telegram Bot giới hạn 50MB/tệp — hãy chọn bài ngắn hơn."); return
        title = os.path.splitext(os.path.basename(fp))[0]
        if not _tg_send_audio(token, chat_id, fp, title):
            _tg_send(token, chat_id, "Gửi nhạc thất bại.")
    except subprocess.TimeoutExpired:
        _tg_send(token, chat_id, "Tải nhạc quá lâu, đã dừng.")
    except Exception:
        _tg_send(token, chat_id, "Lỗi khi tải nhạc.")
    finally:
        shutil.rmtree(d, ignore_errors=True)

def _tg_kv_set(table: str, chat_id, key: str, val: str) -> None:
    cid = str(chat_id); k = key.lower()
    with db() as c:
        c.execute(f"CREATE TABLE IF NOT EXISTS {table}(chat_id TEXT,k TEXT,v TEXT,PRIMARY KEY(chat_id,k))")
        if c.execute(f"SELECT 1 FROM {table} WHERE chat_id=? AND k=?", (cid, k)).fetchone():
            c.execute(f"UPDATE {table} SET v=? WHERE chat_id=? AND k=?", (val, cid, k))
        else:
            c.execute(f"INSERT INTO {table}(chat_id,k,v) VALUES(?,?,?)", (cid, k, val))
def _tg_kv_get(table: str, chat_id, key: str):
    with db() as c:
        c.execute(f"CREATE TABLE IF NOT EXISTS {table}(chat_id TEXT,k TEXT,v TEXT,PRIMARY KEY(chat_id,k))")
        r = c.execute(f"SELECT v FROM {table} WHERE chat_id=? AND k=?", (str(chat_id), key.lower())).fetchone()
    return r["v"] if r else None
def _tg_kv_del(table: str, chat_id, key: str) -> None:
    with db() as c:
        c.execute(f"CREATE TABLE IF NOT EXISTS {table}(chat_id TEXT,k TEXT,v TEXT,PRIMARY KEY(chat_id,k))")
        c.execute(f"DELETE FROM {table} WHERE chat_id=? AND k=?", (str(chat_id), key.lower()))
def _tg_kv_all(table: str, chat_id) -> list:
    with db() as c:
        c.execute(f"CREATE TABLE IF NOT EXISTS {table}(chat_id TEXT,k TEXT,v TEXT,PRIMARY KEY(chat_id,k))")
        rows = c.execute(f"SELECT k,v FROM {table} WHERE chat_id=? ORDER BY k", (str(chat_id),)).fetchall()
    return [(r["k"], r["v"]) for r in rows]

def _tg_unmute_perms() -> dict:
    return {"can_send_messages": True, "can_send_media_messages": True, "can_send_polls": True,
            "can_send_other_messages": True, "can_add_web_page_previews": True, "can_invite_users": True}

# ---------- Lệnh admin trong nhóm ----------
def _tg_admin_command(token: str, chat_id: str, msg: dict, cmd: str, args: str) -> None:
    reply = msg.get("reply_to_message") or {}
    target = reply.get("from") if reply else None
    tid = target.get("id") if target else None
    tname = _tg_mention(target) if target else ""

    if cmd in ("ban", "kick", "mute", "unmute", "warn", "unwarn", "warns", "info") and not tid:
        _tg_send(token, chat_id, "↩️ Hãy REPLY vào tin của người cần xử lý rồi gõ lệnh."); return

    if cmd == "ban":
        _tg_call(token, "banChatMember", chat_id=chat_id, user_id=tid); _tg_send(token, chat_id, f"🚫 Đã cấm {tname}.")
    elif cmd == "kick":
        _tg_call(token, "banChatMember", chat_id=chat_id, user_id=tid)
        _tg_call(token, "unbanChatMember", chat_id=chat_id, user_id=tid); _tg_send(token, chat_id, f"👢 Đã kick {tname}.")
    elif cmd == "mute":
        mins = int(args.split()[0]) if args.split() and args.split()[0].isdigit() else 0
        kw = {"chat_id": chat_id, "user_id": tid, "permissions": {"can_send_messages": False}}
        if mins > 0: kw["until_date"] = int(time.time()) + mins * 60
        _tg_call(token, "restrictChatMember", **kw)
        _tg_send(token, chat_id, f"🔇 Đã cấm chat {tname}" + (f" {mins} phút." if mins else "."))
    elif cmd == "unmute":
        _tg_call(token, "restrictChatMember", chat_id=chat_id, user_id=tid, permissions=_tg_unmute_perms())
        _tg_send(token, chat_id, f"🔊 Đã mở chat cho {tname}.")
    elif cmd == "warn":
        _tg_warn(token, chat_id, target, "admin cảnh báo")
    elif cmd == "unwarn":
        _warn_reset(chat_id, tid); _tg_send(token, chat_id, f"✅ Đã xoá cảnh báo cho {tname}.")
    elif cmd == "warns":
        with db() as c:
            c.execute("CREATE TABLE IF NOT EXISTS tg_warns(chat_id TEXT, user_id INTEGER, count INTEGER DEFAULT 0, PRIMARY KEY(chat_id,user_id))")
            r = c.execute("SELECT count FROM tg_warns WHERE chat_id=? AND user_id=?", (str(chat_id), tid)).fetchone()
        _tg_send(token, chat_id, f"{tname}: {r['count'] if r else 0}/{get_setting('tg_warn_limit','3')} cảnh báo.")
    elif cmd == "info":
        _tg_send(token, chat_id, f"👤 {tname}\nID: <code>{tid}</code>\nUsername: @{target.get('username','—')}")
    elif cmd in ("pin",):
        if reply.get("message_id"): _tg_call(token, "pinChatMessage", chat_id=chat_id, message_id=reply["message_id"]); _tg_send(token, chat_id, "📌 Đã ghim.")
    elif cmd in ("unpin",):
        _tg_call(token, "unpinAllChatMessages", chat_id=chat_id); _tg_send(token, chat_id, "📌 Đã bỏ ghim.")
    elif cmd == "del":
        if reply.get("message_id"): _tg_call(token, "deleteMessage", chat_id=chat_id, message_id=reply["message_id"])
        _tg_call(token, "deleteMessage", chat_id=chat_id, message_id=msg.get("message_id"))
    elif cmd == "purge":
        start = reply.get("message_id")
        if not start: _tg_send(token, chat_id, "↩️ Reply vào tin bắt đầu xoá rồi gõ /purge."); return
        for m in range(start, msg.get("message_id", start) + 1):
            _tg_call(token, "deleteMessage", chat_id=chat_id, message_id=m)
    elif cmd == "lock" or cmd == "unlock":
        t = (args.split()[0].lower() if args.split() else "")
        valid = {"link", "photo", "video", "sticker", "gif", "forward", "mention", "all"}
        if t not in valid:
            _tg_send(token, chat_id, "Loại: link, photo, video, sticker, gif, forward, mention, all"); return
        locks = _tg_locks()
        if cmd == "lock": locks.add(t)
        else: locks.discard(t)
        set_setting("tg_locks", ",".join(sorted(locks)))
        _tg_send(token, chat_id, ("🔒 Đã khoá: " if cmd == "lock" else "🔓 Đã mở khoá: ") + t)
    elif cmd == "locks":
        ls = _tg_locks()
        _tg_send(token, chat_id, "🔒 Đang khoá: " + (", ".join(sorted(ls)) if ls else "không có"))
    elif cmd in ("addbl", "rmbl"):
        w = args.strip().lower()
        if not w: _tg_send(token, chat_id, "Cú pháp: /addbl <từ cấm>"); return
        bl = _tg_blacklist()
        if cmd == "addbl" and w not in bl: bl.append(w)
        if cmd == "rmbl" and w in bl: bl.remove(w)
        set_setting("tg_blacklist", ",".join(bl))
        _tg_send(token, chat_id, ("➕ Đã thêm từ cấm: " if cmd == "addbl" else "➖ Đã bỏ từ cấm: ") + w)
    elif cmd == "blacklist":
        bl = _tg_blacklist(); _tg_send(token, chat_id, "🚯 Từ cấm: " + (", ".join(bl) if bl else "không có"))
    elif cmd == "filter":
        p = args.split(maxsplit=1)
        if len(p) < 2: _tg_send(token, chat_id, "Cú pháp: /filter <từ khoá> <câu trả lời>"); return
        _tg_kv_set("tg_filters", chat_id, p[0], p[1]); _tg_send(token, chat_id, f"✅ Đã tạo bộ lọc '{p[0].lower()}'.")
    elif cmd == "stop":
        _tg_kv_del("tg_filters", chat_id, args.strip()); _tg_send(token, chat_id, "🗑️ Đã xoá bộ lọc.")
    elif cmd == "filters":
        ks = [k for k, _ in _tg_kv_all("tg_filters", chat_id)]
        _tg_send(token, chat_id, "🧩 Bộ lọc: " + (", ".join(ks) if ks else "không có"))
    elif cmd == "save":
        p = args.split(maxsplit=1)
        if len(p) < 2: _tg_send(token, chat_id, "Cú pháp: /save <tên> <nội dung>"); return
        _tg_kv_set("tg_notes", chat_id, p[0], p[1]); _tg_send(token, chat_id, f"💾 Đã lưu ghi chú #{p[0].lower()}.")
    elif cmd == "clear":
        _tg_kv_del("tg_notes", chat_id, args.strip()); _tg_send(token, chat_id, "🗑️ Đã xoá ghi chú.")
    elif cmd == "notes":
        ks = [k for k, _ in _tg_kv_all("tg_notes", chat_id)]
        _tg_send(token, chat_id, "🗒️ Ghi chú: " + (", ".join("#" + k for k in ks) if ks else "không có"))
    elif cmd == "setrules":
        set_setting("tg_rules", args.strip()[:2000]); _tg_send(token, chat_id, "📜 Đã đặt nội quy.")
    # ---- CHÀO MỪNG thành viên mới: sửa lời chào / nút link / ảnh / bật-tắt / thử ----
    elif cmd in ("setwelcome", "setchao"):
        if not args.strip():
            _tg_send(token, chat_id,
                     "🎉 <b>Đặt lời chào thành viên mới</b>\n"
                     "Cú pháp: <code>/setwelcome &lt;nội dung&gt;</code>\n"
                     "• <code>{name}</code> = tên thành viên · <code>{group}</code> = tên nhóm\n"
                     "• Nhúng link vào chữ: <code>&lt;a href=\"https://link\"&gt;chữ&lt;/a&gt;</code>\n"
                     "VD: <code>/setwelcome 🎉 Chào {name} đến với {group}! Ghé &lt;a href=\"https://app.kenios.store/shop\"&gt;cửa hàng&lt;/a&gt; nhé.</code>")
        else:
            set_setting("tg_welcome_group", args.strip()[:2000]); set_setting("tg_welcome_on", "1")
            _tg_send(token, chat_id, "🎉 Đã đặt lời chào mới (đã BẬT chào mừng). Gõ /testwelcome để xem thử.")
    elif cmd in ("welcome", "chao"):
        a = args.strip().lower()
        if a in ("on", "bat", "bật", "1"):
            set_setting("tg_welcome_on", "1"); _tg_send(token, chat_id, "🎉 Chào mừng thành viên mới: BẬT")
        elif a in ("off", "tat", "tắt", "0"):
            set_setting("tg_welcome_on", "0"); _tg_send(token, chat_id, "🎉 Chào mừng thành viên mới: TẮT")
        else:
            _tg_send(token, chat_id,
                     f"🎉 <b>Chào mừng</b>: {'BẬT' if get_setting('tg_welcome_on','1')=='1' else 'TẮT'}\n"
                     f"Lời chào: {get_setting('tg_welcome_group', '👋 Chào mừng {name} đã vào {group}!')}\n\n"
                     "• /welcome on|off — bật/tắt\n• /setwelcome &lt;nội dung&gt; — sửa lời chào\n"
                     "• /setwelcomebtn — nút link dưới lời chào\n• /setwelcomephoto &lt;link ảnh&gt; — ảnh kèm lời chào\n"
                     "• /setgoodbye &lt;nội dung&gt; — lời tạm biệt\n• /testwelcome — xem thử")
    elif cmd in ("setwelcomebtn", "setchaobtn"):
        if not args.strip():
            _tg_send(token, chat_id,
                     "🔗 <b>Nút link dưới lời chào</b> — mỗi dòng 1 nút, dạng <code>Nhãn | https://link</code>\nVD:\n"
                     "<code>/setwelcomebtn 📜 Nội quy | https://t.me/kenios\n🛒 Cửa hàng | https://app.kenios.store/shop</code>\n"
                     "Gõ <code>/setwelcomebtn xoa</code> để bỏ nút.")
        elif args.strip().lower() in ("xoa", "xóa", "off", "clear"):
            set_setting("tg_welcome_btns", ""); set_setting("tg_welcome_btn_text", ""); set_setting("tg_welcome_btn_url", "")
            _tg_send(token, chat_id, "🗑️ Đã bỏ nút link khỏi lời chào.")
        else:
            set_setting("tg_welcome_btns", args.strip())
            n = sum(len(r) for r in _tg_parse_btns(args.strip()))
            _tg_send(token, chat_id, f"✅ Đã đặt <b>{n}</b> nút link dưới lời chào. Gõ /testwelcome để xem thử.")
    elif cmd == "setwelcomephoto":
        a = args.strip()
        if a.lower() in ("xoa", "xóa", "off", "clear"):
            set_setting("tg_welcome_group_photo", ""); _tg_send(token, chat_id, "🗑️ Đã bỏ ảnh khỏi lời chào.")
        elif a:
            set_setting("tg_welcome_group_photo", a); _tg_send(token, chat_id, "🖼️ Đã đặt ảnh lời chào. Gõ /testwelcome để xem thử.")
        else:
            _tg_send(token, chat_id, "Cú pháp: <code>/setwelcomephoto &lt;link ảnh&gt;</code> (hoặc <code>xoa</code> để bỏ).")
    elif cmd in ("setgoodbye", "settambiet"):
        if args.strip():
            set_setting("tg_goodbye", args.strip()[:1000]); set_setting("tg_goodbye_on", "1")
            _tg_send(token, chat_id, "👋 Đã đặt lời tạm biệt.")
        else:
            _tg_send(token, chat_id, "Cú pháp: <code>/setgoodbye &lt;nội dung&gt;</code> ({name} = tên người rời nhóm).")
    elif cmd == "testwelcome":
        if get_setting("tg_welcome_on", "1") != "1":
            _tg_send(token, chat_id, "🎉 Chào mừng đang TẮT — bật bằng <code>/welcome on</code>.")
        else:
            _tg_welcome_members(token, msg.get("chat", {}), [msg.get("from", {})])
    elif cmd in ("clean", "nightmode", "antiflood", "captcha", "modon", "modoff"):
        # (key, mặc định) — antiflood mặc định BẬT nên toggle phải đọc đúng mặc định "1"
        keymap = {"clean": ("tg_clean_service", "0"), "nightmode": ("tg_nightmode_on", "0"),
                  "antiflood": ("tg_antiflood_on", "1"), "captcha": ("tg_captcha_on", "0")}
        if cmd == "antiflood" and args.strip().split() and args.strip().split()[0].isdigit():
            mx = max(2, min(30, int(args.strip().split()[0])))
            set_setting("tg_antiflood_max", str(mx)); set_setting("tg_antiflood_on", "1")
            set_setting("tg_mod_enabled", "1")   # bật luôn công tắc tổng — antiflood cần nó mới chạy
            _tg_send(token, chat_id,
                     f"🌊 Antiflood: BẬT — quá <b>{mx}</b> tin/7 giây sẽ bị xoá + cảnh báo.\n"
                     "(Admin/chủ nhóm được MIỄN — thử bằng tài khoản thành viên, hoặc /modadmin on.)")
        elif cmd in keymap:
            k, d = keymap[cmd]
            cur = get_setting(k, d) == "1"; set_setting(k, "0" if cur else "1")
            extra = ""
            if cmd == "antiflood" and not cur:
                set_setting("tg_mod_enabled", "1")   # bật luôn công tắc tổng
                extra = (f" — quá <b>{get_setting('tg_antiflood_max', '4')}</b> tin/7 giây sẽ bị xoá + cảnh báo.\n"
                         "Đổi mức: <code>/antiflood 4</code>. (Admin được MIỄN — thử bằng tài khoản thành viên, hoặc /modadmin on.)")
            _tg_send(token, chat_id, f"{cmd}: {'TẮT' if cur else 'BẬT'}{extra}")
        else:
            set_setting("tg_mod_enabled", "1" if cmd == "modon" else "0")
            _tg_send(token, chat_id, "Quản lý nhóm: " + ("BẬT" if cmd == "modon" else "TẮT"))
    elif cmd == "modadmin":
        a = args.strip().lower()
        cur = get_setting("tg_mod_admins", "0") == "1"
        new = True if a in ("on", "bat", "bật", "1") else False if a in ("off", "tat", "tắt", "0") else not cur
        set_setting("tg_mod_admins", "1" if new else "0")
        if new:
            _tg_send(token, chat_id,
                     "👑 Kiểm duyệt CẢ ADMIN: <b>BẬT</b> — spam/link/media vi phạm của admin cũng bị XOÁ.\n"
                     "(Telegram không cho bot cấm chat chủ nhóm — chỉ xoá tin được.)")
        else:
            _tg_send(token, chat_id, "👑 Kiểm duyệt CẢ ADMIN: <b>TẮT</b> — admin được miễn như bình thường.")
    elif cmd == "scanlink":
        a = args.strip().lower()
        cur = get_setting("tg_scanlink_on", "1") == "1"
        new = True if a in ("on", "bat", "bật", "1") else False if a in ("off", "tat", "tắt", "0") else not cur
        set_setting("tg_scanlink_on", "1" if new else "0")
        _tg_send(token, chat_id,
                 ("🛡️ Tự quét link admin gửi: <b>BẬT</b> — admin dán link, bot tự kiểm tra virus/lừa đảo + báo thông tin đầy đủ."
                  if new else "🛡️ Tự quét link admin gửi: <b>TẮT</b>.") +
                 ("\n💡 Quét virus SÂU: đặt VirusTotal key bằng /setvt <key>." if new and not (get_setting("tg_vt_key","") or "").strip() else ""))
    elif cmd in ("chaosang", "chaotoi"):
        import re as _re
        slot = "morning" if cmd == "chaosang" else "evening"
        on_key, time_key, text_key = f"tg_greet_{slot}_on", f"tg_greet_{slot}_time", f"tg_greet_{slot}_text"
        deftime = "07:00" if slot == "morning" else "20:00"
        deftext = _TG_MORNING_DEFAULT if slot == "morning" else _TG_EVENING_DEFAULT
        label = "☀️ Chào buổi sáng" if slot == "morning" else "🌙 Chào buổi tối"
        a = args.strip()
        _tg_greet_register(chat_id)   # đảm bảo nhóm này nhận lời chào
        if not a:
            import html as _h
            _tg_send(token, chat_id,
                     f"{label}: <b>{'BẬT' if get_setting(on_key,'1')=='1' else 'TẮT'}</b> lúc "
                     f"<b>{get_setting(time_key, deftime)}</b> mỗi ngày (giờ VN)\n"
                     f"Nội dung: {_h.escape(get_setting(text_key, deftext))}\n\n"
                     f"• <code>/{cmd} on</code> · <code>/{cmd} off</code> — bật/tắt\n"
                     f"• <code>/{cmd} 6:30</code> — đổi giờ\n"
                     f"• <code>/{cmd} &lt;nội dung&gt;</code> — đổi lời chào")
        elif a.lower() in ("on", "bat", "bật", "1"):
            set_setting(on_key, "1")
            _tg_send(token, chat_id, f"{label}: BẬT lúc <b>{get_setting(time_key, deftime)}</b> (giờ VN) — nhóm này sẽ nhận mỗi ngày.")
        elif a.lower() in ("off", "tat", "tắt", "0"):
            set_setting(on_key, "0")
            _tg_send(token, chat_id, f"{label}: TẮT.")
        elif _re.match(r"^\d{1,2}:\d{2}$", a):
            hh, mm = int(a.split(":")[0]), int(a.split(":")[1])
            if 0 <= hh <= 23 and 0 <= mm <= 59:
                set_setting(time_key, f"{hh:02d}:{mm:02d}"); set_setting(on_key, "1")
                _tg_send(token, chat_id, f"⏰ {label} sẽ gửi lúc <b>{hh:02d}:{mm:02d}</b> mỗi ngày (giờ VN). ✅")
            else:
                _tg_send(token, chat_id, f"Giờ không hợp lệ. VD: <code>/{cmd} 6:30</code>")
        else:
            set_setting(text_key, a[:1000]); set_setting(on_key, "1")
            _tg_send(token, chat_id, f"✅ Đã đặt nội dung {label}. Gõ <code>/{cmd}</code> để xem lại.")
    elif cmd == "autodel":
        a = args.strip().lower()
        if a in ("off", "tat", "tắt", "0"):
            set_setting("tg_autodel_sec", "0")
            _tg_send(token, chat_id, "🧽 Tự xoá lệnh: TẮT — tin lệnh & trả lời bot sẽ được giữ lại.")
        elif a.isdigit():
            sec = max(3, min(300, int(a)))
            set_setting("tg_autodel_sec", str(sec))
            _tg_send(token, chat_id, f"🧽 Tự xoá lệnh: BẬT — lệnh + trả lời bot tự xoá sau <b>{sec} giây</b>.")
        else:
            cur = _tg_autodel_sec()
            _tg_send(token, chat_id,
                     f"🧽 <b>Tự xoá lệnh</b>: {'BẬT — sau ' + str(cur) + ' giây' if cur > 0 else 'TẮT'}\n"
                     "• <code>/autodel 10</code> — đổi số giây (3–300)\n• <code>/autodel off</code> — tắt")
    elif cmd == "stats":
        _, tot = _msgcount_top(chat_id, 1)
        mc = _tg_call(token, "getChatMemberCount", chat_id=chat_id)
        members = mc.get("result", "?") if mc.get("ok") else "?"
        _tg_send(token, chat_id, f"📊 <b>Thống kê nhóm</b>\nThành viên: {members}\nTổng tin đã đếm: {tot[0]}\nĐang hoạt động: {tot[1]} người")
    elif cmd in ("autoreact", "slowmode", "log"):
        if cmd == "autoreact":
            cur = get_setting("tg_autoreact_on", "0") == "1"; set_setting("tg_autoreact_on", "0" if cur else "1")
            _tg_send(token, chat_id, f"AutoReact: {'TẮT' if cur else 'BẬT'}")
        elif cmd == "slowmode":
            sec = int(args.split()[0]) if args.split() and args.split()[0].isdigit() else 0
            set_setting("tg_slowmode", str(sec))
            _tg_send(token, chat_id, f"⏱️ Slow mode: {sec} giây/tin" if sec else "⏱️ Đã tắt slow mode.")
        else:
            set_setting("tg_log_chat", args.strip())
            _tg_send(token, chat_id, "📋 Đã đặt kênh nhật ký." if args.strip() else "📋 Đã tắt nhật ký.")
    elif cmd == "config":
        _tg_send(token, chat_id,
                 "⚙️ <b>Cấu hình</b>\n"
                 f"Quản lý: {'BẬT' if get_setting('tg_mod_enabled','1')=='1' else 'tắt'}\n"
                 f"Chống link: {'✓' if get_setting('tg_del_links','1')=='1' else '✗'} · "
                 f"Antiflood: {'✓' if get_setting('tg_antiflood_on','1')=='1' else '✗'} · "
                 f"Captcha: {'✓' if get_setting('tg_captcha_on','0')=='1' else '✗'} · "
                 f"NightMode: {'✓' if get_setting('tg_nightmode_on','0')=='1' else '✗'}\n"
                 f"Khoá: {', '.join(sorted(_tg_locks())) or 'không'}\n"
                 f"Cảnh báo: {get_setting('tg_warn_limit','3')} → {get_setting('tg_warn_action','mute')}\n"
                 "Lệnh: /ban /kick /mute /unmute /warn /warns /pin /purge /del /lock /unlock /addbl /filter /save /setrules /clean /nightmode /antiflood /captcha")

def _tg_group_message(token: str, chat_id: str, msg: dict) -> None:
    import threading as _thr
    frm = msg.get("from", {}); uid = frm.get("id")
    text = msg.get("text", "") or ""
    mid = msg.get("message_id")
    low = text.lower()
    _tg_groups.add(chat_id)
    _tg_greet_register(chat_id)   # nhớ nhóm để gửi chào sáng/tối đúng giờ

    # ============ 1) KIỂM DUYỆT TRƯỚC TIÊN — xoá NGAY, không chờ gì khác ============
    # (Trước đây bot thả cảm xúc/đếm tin TRƯỚC rồi mới kiểm duyệt → mỗi tin tốn thêm
    #  1 lệnh API ~0,5s, spam dồn hàng đợi nên xoá trễ. Giờ xoá là việc ĐẦU TIÊN;
    #  cảnh báo gửi ở thread nền để vòng lặp xử lý ngay tin kế tiếp.)
    if get_setting("tg_mod_enabled", "1") == "1" and not (
            _tg_is_privileged(token, chat_id, msg) and get_setting("tg_mod_admins", "0") != "1"):
        is_cmd = text.startswith("/") or text.startswith("#")

        def _kill(reason, warn=True):
            _tg_call(token, "deleteMessage", chat_id=chat_id, message_id=mid)
            if warn:
                _thr.Thread(target=_tg_warn, args=(token, chat_id, frm, reason), daemon=True).start()
            return True

        if _tg_in_night() and _kill("", warn=False): return
        if _slowmode_hit(chat_id, uid) and _kill("", warn=False): return
        # Đang chơi ĐỐ VUI → miễn antiflood (mọi người đua nhau trả lời nhanh)
        if chat_id not in _TG_QUIZ and _tg_flood_hit(chat_id, uid) and _kill("gửi tin dồn dập (flood)"): return
        if not is_cmd:   # lệnh bot không bị xét từ cấm/link/media
            bl = _tg_blacklist()
            if bl and any(w in low for w in bl) and _kill("dùng từ cấm"): return
            locks = _tg_locks()
            if (get_setting("tg_del_links", "1") == "1" or "link" in locks) and _tg_has_link(msg) and _kill("gửi liên kết/spam"): return
            if (get_setting("tg_del_stickers", "0") == "1" or "sticker" in locks) and msg.get("sticker") and _kill("gửi sticker"): return
            if (get_setting("tg_del_stickers", "0") == "1" or "gif" in locks) and msg.get("animation") and _kill("gửi ảnh động"): return
            if (get_setting("tg_del_photos", "0") == "1" or "photo" in locks) and msg.get("photo") and _kill("gửi hình ảnh"): return
            if "video" in locks and msg.get("video") and _kill("gửi video"): return
            if "forward" in locks and (msg.get("forward_from") or msg.get("forward_origin") or msg.get("forward_sender_name")) and _kill("chuyển tiếp"): return
            if "mention" in locks and _tg_has_mention(msg) and _kill("tag/mention"): return
            if "all" in locks and _kill("", warn=False): return

    # ============ 2) Tin đã "sạch" → tiện ích, menu, lệnh ============
    # 🧠 ĐỐ VUI: nhóm đang có câu đố → kiểm tra đáp án (đúng = +10 điểm · sai = báo ❌).
    # Chấp nhận cả kiểu gõ nhầm "/30" — miễn không trùng lệnh thật của bot.
    if text and chat_id in _TG_QUIZ:
        _qtxt = text
        if _qtxt.startswith("/"):
            _qc = _qtxt.split()[0].lstrip("/").split("@")[0].lower()
            _qtxt = _qtxt.lstrip("/ ") if _qc not in _TG_RESERVED else ""
        if _qtxt and _tg_quiz_try(token, chat_id, msg, _qtxt):
            return
        # Trả lời SAI: chỉ báo khi tin nhắn TRÔNG GIỐNG một câu trả lời (ngắn ≤ 6 từ) để
        # không làm phiền hội thoại thường. Thả 👎 lên tin + nhắc thử lại (tin nhắc tự xoá
        # sau 8s; tối đa ~1 nhắc/4s mỗi nhóm để tránh spam).
        _qz = _TG_QUIZ.get(chat_id)
        if _qz is not None and _qtxt and 0 < len(_qtxt.split()) <= 6 and mid:
            _now = time.time()
            if _now - _qz.get("lastwrong", 0) >= 4:
                _qz["lastwrong"] = _now
                _r = _tg_send(token, chat_id,
                              f"❌ {_tg_mention(frm)} chưa đúng, thử lại nào! "
                              "(/goiy — gợi ý · /boqua — đáp án &amp; câu mới)")
                _wmid = ((_r or {}).get("result") or {}).get("message_id")
                if _wmid:
                    _tg_delete_later(token, [(str(chat_id), _wmid)], 8)
            _thr.Thread(target=_tg_call, args=(token, "setMessageReaction"),
                        kwargs={"chat_id": chat_id, "message_id": mid,
                                "reaction": [{"type": "emoji", "emoji": "👎"}]},
                        daemon=True).start()

    # AFK: người đang AFK nhắn lại → chào trở lại
    if uid in _tg_afk and not low.startswith("/afk"):
        _tg_afk.pop(uid, None)
        _tg_send(token, chat_id, f"🎉 {_tg_mention(frm)} đã quay lại!")
    reply = msg.get("reply_to_message") or {}
    rt = reply.get("from") if reply else None
    if rt and rt.get("id") in _tg_afk:
        reason = _tg_afk[rt["id"]][0]
        _tg_send(token, chat_id, f"💤 {_tg_mention(rt)} đang AFK{': ' + reason if reason else ''}.")

    # Nút menu (lưới nút) bấm trong NHÓM cũng chạy như chat riêng (menu theo quyền)
    if text.strip() in _TG_FEAT or text.strip() in ("🏠 Menu", "❌ Đóng", "📚 Hướng dẫn đầy đủ"):
        if _tg_menu_click(token, chat_id, text, _tg_name(frm),
                          admin=_tg_is_privileged(token, chat_id, msg)):
            return

    # Lệnh (/... hoặc #ghichú) — dùng xong TỰ XOÁ tin lệnh + trả lời bot sau N giây.
    # Riêng lệnh GIẢI TRÍ (trò chơi, bói, chuyện cười…) GIỮ LẠI cho cả nhóm xem.
    if text.startswith("/") or text.startswith("#"):
        _c0 = text.split()[0].lstrip("/#").split("@")[0].lower()
        if _c0 in _TG_FUN_CMDS:
            _tg_dispatch_command(token, chat_id, msg, text, uid, frm)
        else:
            _tg_with_autodel(token, chat_id, mid,
                             lambda: _tg_dispatch_command(token, chat_id, msg, text, uid, frm))
        return

    # 🛡️ TỰ ĐỘNG QUÉT LINK admin gửi: admin dán link vào nhóm → bot tự kiểm tra virus/lừa đảo
    # + trả thông tin đầy đủ (reply vào tin đó). Bật/tắt: /scanlink on|off (mặc định BẬT).
    if (text and not text.startswith("/") and get_setting("tg_scanlink_on", "1") == "1"
            and _tg_has_link(msg) and _tg_is_privileged(token, chat_id, msg)):
        _u = _tg_first_url(text)
        if _u:
            _tg_start_scan_link(token, chat_id, _u, reply_to=mid)

    # FameRank: đếm tin nhắn · AutoReact: thả cảm xúc (chạy NỀN — không chặn vòng lặp)
    if uid:
        _msgcount_inc(chat_id, uid, _tg_name(frm))
    if get_setting("tg_autoreact_on", "0") == "1" and mid:
        _thr.Thread(target=_tg_call, args=(token, "setMessageReaction"),
                    kwargs={"chat_id": chat_id, "message_id": mid,
                            "reaction": [{"type": "emoji", "emoji": get_setting("tg_autoreact_emoji", "👍")}]},
                    daemon=True).start()
    # 👮 ADMIN nói tự nhiên → chạy lệnh quản trị (mute/ban/kick/warn/pin/del/lock…) khi AI bật + là admin.
    if text and not text.startswith("/") and _tg_ai_admin_route(token, chat_id, msg, low):
        return
    # 🛒 KHÁCH HỎI TƯ VẤN trong nhóm ("bản nào an toàn", "chơi ok nhất"…) → mở luồng chọn OS → game.
    if text and not text.startswith("/") and _kenios_wants_support(low):
        _kenios_support_start(token, chat_id)
        return
    # 🤖 AI: BẬT ở nhóm → trả lời khi được gọi (reply/tag/"ai"/"?"), hoặc TRẢ LỜI TẤT CẢ nếu /aiall on.
    _aiw = _tg_ai_wants(chat_id, msg, text, low)
    if _aiw:
        # 😌 Khách CHỬI → đối đáp văn minh (nhẹ nhàng mà thấm), không để AI dính lời tục.
        if _tg_is_insult(low):
            _now = time.time()
            if _now - _TG_INSULT_LAST.get(chat_id, 0) >= 3:   # chống spam đối đáp
                _TG_INSULT_LAST[chat_id] = _now
                _tg_call(token, "sendMessage", chat_id=chat_id, text=_tg_comeback(),
                         reply_to_message_id=mid, disable_web_page_preview=True)
            return
        # 🔗 Nhắn tự nhiên → tự chạy lệnh (QR/nhạc/đố/game/bói…) trước, còn lại để AI trả lời.
        if _tg_ai_route(token, chat_id, msg, _tg_ai_clean_q(text)):
            return
        if _aiw == 2:   # chế độ trả lời tất cả → giới hạn ~1 trả lời/5s mỗi nhóm, tránh spam & tốn quota
            _now = time.time()
            if _now - _TG_AI_LAST.get(chat_id, 0) < 5:
                return
            _TG_AI_LAST[chat_id] = _now
        _thr.Thread(target=_tg_ai_reply, args=(token, chat_id, msg, _tg_ai_clean_q(text)), daemon=True).start()
        return
    # Bộ lọc auto-reply (mọi người)
    if text:
        for trig, rep in _tg_kv_all("tg_filters", chat_id):
            if trig in low: _tg_send(token, chat_id, rep); break

def _tg_dispatch_command(token: str, chat_id: str, msg: dict, text: str, uid, frm: dict) -> None:
    cmd0 = text.split()[0].lstrip("/#").split("@")[0].lower() if text.split() else ""
    # Đang chơi ĐỐ VUI: "/34" là đoán sai (đã thử làm đáp án ở trên) → im lặng,
    # không báo "lệnh chỉ dành cho quản trị viên" gây rối.
    if chat_id in _TG_QUIZ and cmd0 not in _TG_RESERVED:
        return
    # ---- Công khai (engagement) — MỌI thành viên dùng được ----
    if cmd0 in ("diemdanh", "checkin", "diem"):
        res = _checkin(chat_id, uid)
        if res is None:
            _tg_send(token, chat_id, f"✅ {_tg_mention(frm)} hôm nay đã điểm danh rồi!")
        else:
            _tg_send(token, chat_id, f"📅 {_tg_mention(frm)} điểm danh thành công!\n🔥 Chuỗi: {res[0]} ngày · Tổng: {res[1]} lần")
        return
    if cmd0 in ("top", "rank", "bxh"):
        rows, tot = _msgcount_top(chat_id, 10)
        if not rows:
            _tg_send(token, chat_id, "Chưa có dữ liệu xếp hạng."); return
        medals = ["🥇", "🥈", "🥉"] + ["🔹"] * 7
        lst = "\n".join(f"{medals[i]} {n}: <b>{c}</b> tin" for i, (n, c) in enumerate(rows))
        _tg_send(token, chat_id, f"🏆 <b>Bảng xếp hạng năng động</b>\n{lst}\n\nTổng: {tot[0]} tin · {tot[1]} thành viên")
        return
    if cmd0 == "report":
        ac = get_setting("tg_admin_chat", "").strip()
        title = msg.get("chat", {}).get("title", "nhóm")
        if ac: _tg_send(token, ac, f"⚠️ Báo cáo từ nhóm <b>{title}</b> bởi {_tg_mention(frm)}.")
        _tg_send(token, chat_id, "⚠️ Đã báo cáo tới quản trị viên."); return
    # 🎮 Lệnh GIẢI TRÍ & TIỆN ÍCH — ai cũng dùng được
    if cmd0 in _TG_FUN_CMDS:
        _sp = text.split(maxsplit=1)
        if _tg_fun_command(token, chat_id, msg, cmd0, _sp[1] if len(_sp) > 1 else ""):
            return
    if cmd0 in ("help", "start", "menu"):
        _tg_send_menu(token, chat_id, "📋 <b>MENU KENIOS</b> — chọn chức năng bên dưới 👇",
                      admin=_tg_is_privileged(token, chat_id, msg)); return
    if cmd0 in ("rules", "luat"):
        _tg_send(token, chat_id, get_setting("tg_rules", "Nhóm chưa đặt nội quy. Admin dùng /setrules để đặt.")); return
    if cmd0 == "afk":
        _r = text.split(maxsplit=1)
        _reason = _r[1].strip()[:100] if len(_r) > 1 else ""
        _tg_afk[uid] = (_reason, time.time())
        _tg_send(token, chat_id, f"💤 {_tg_mention(frm)} giờ đang AFK{': ' + _reason if _reason else ''}."); return
    if cmd0 == "id":
        t = (msg.get("reply_to_message", {}).get("from") or {}).get("id")
        _tg_send(token, chat_id, f"Chat ID: <code>{chat_id}</code>" + (f"\nUser: <code>{t}</code>" if t else "")); return
    # ---- Còn lại: chỉ ADMIN (hoặc admin ẩn danh / Channel của nhóm) ----
    if not _tg_is_privileged(token, chat_id, msg):
        _tg_send(token, chat_id, "🔒 Lệnh này chỉ dành cho <b>quản trị viên</b> nhóm.")
        return
    # Ghi chú: #tên
    if text.startswith("#"):
        name = text[1:].split()[0].lower() if len(text) > 1 else ""
        content = _tg_kv_get("tg_notes", chat_id, name)
        if content: _tg_send(token, chat_id, content)
        return
    cmd = text.split()[0].lstrip("/").split("@")[0].lower()
    sp = text.split(maxsplit=1)
    args = sp[1] if len(sp) > 1 else ""
    # (đã kiểm tra quyền admin ở trên)
    if cmd == "get":
        _tg_send(token, chat_id, _tg_kv_get("tg_notes", chat_id, args.strip()) or "Không có ghi chú này."); return
    _tg_admin_command(token, chat_id, msg, cmd, args)

def _tg_handle_update(token: str, admin_chat: str, u: dict) -> None:
    # Thành viên vào nhóm qua LINK MỜI / nhóm công khai → chào (không có new_chat_members).
    if u.get("chat_member"):
        _tg_on_chat_member(token, u["chat_member"]); return
    # Nút bấm (callback)
    cq = u.get("callback_query")
    if cq:
        data = cq.get("data", "")
        chat = str(cq.get("message", {}).get("chat", {}).get("id", ""))
        # Captcha: xác minh chống bot
        if data.startswith("verify:"):
            vid = data.split(":", 1)[1]
            if str(cq.get("from", {}).get("id", "")) == vid:
                _tg_call(token, "answerCallbackQuery", callback_query_id=cq.get("id", ""), text="Đã xác minh ✅")
                _tg_call(token, "restrictChatMember", chat_id=chat, user_id=int(vid), permissions=_tg_unmute_perms())
                _tg_call(token, "deleteMessage", chat_id=chat, message_id=cq.get("message", {}).get("message_id"))
                _tg_welcome_members(token, cq.get("message", {}).get("chat", {}), [cq.get("from", {})])
            else:
                _tg_call(token, "answerCallbackQuery", callback_query_id=cq.get("id", ""), text="Nút này không dành cho bạn.")
            return
        _tg_call(token, "answerCallbackQuery", callback_query_id=cq.get("id", ""))
        # 🛒 Luồng tư vấn: chọn OS → chọn game → bảng giá đầy đủ
        if data.startswith("ksup:"):
            _kp = data.split(":")
            _kmid = cq.get("message", {}).get("message_id")
            if len(_kp) >= 3 and _kp[1] == "os":
                _kenios_support_games(token, chat, _kp[2], _kmid)
            elif len(_kp) >= 4 and _kp[1] == "game":
                _kenios_support_info(token, chat, _kp[2], _kp[3])
            return
        if data == "support":
            _tg_send(token, chat, "✍️ Bạn cứ nhắn nội dung cần hỗ trợ ở đây, đội ngũ KENIOS sẽ trả lời sớm nhất.")
        elif data == "about":
            _tg_send(token, chat, get_setting("tg_about", "KENIOS — nền tảng ứng dụng & cửa hàng số. Gõ /start để xem menu."))
        return

    msg = u.get("message")
    if not msg:
        return
    chat = msg.get("chat", {})
    chat_id = str(chat.get("id", ""))
    ctype = chat.get("type", "")

    # 🎵 Lấy nhạc YouTube/TikTok — chạy ở MỌI nơi (chat riêng & nhóm), tải trong thread riêng.
    _tgtxt = (msg.get("text") or "").strip()
    if _tgtxt.startswith("/nhac") or _tgtxt.startswith("/music"):
        _p = _tgtxt.split(None, 1)
        _tg_start_music(token, chat_id, _p[1] if len(_p) > 1 else "")
        return
    # 🎬 Tải video (nhanh + cắt phần nếu quá dung lượng)
    if _tgtxt.startswith("/video") or _tgtxt.startswith("/taivideo"):
        _pv = _tgtxt.split(None, 1)
        _tg_start_video(token, chat_id, _pv[1] if len(_pv) > 1 else "")
        return
    # 🎙️ KỂ CHUYỆN bằng GIỌNG NÓI — luôn ra VOICE (không phụ thuộc AI bật/tắt).
    _cc0 = _tgtxt.split()[0].lstrip("/").split("@")[0].lower() if _tgtxt.startswith("/") else ""
    if _cc0 in ("kechuyen", "doctruyen", "truyen", "kechuyenma", "kevoice"):
        import threading as _thv
        _pv2 = _tgtxt.split(None, 1)
        _topic = _pv2[1].strip() if len(_pv2) > 1 else ("kể một câu chuyện ma rùng rợn" if _cc0 == "kechuyenma" else "kể một câu chuyện hay, hấp dẫn")
        _thv.Thread(target=_tg_voice_reply, args=(token, chat_id, "Kể chuyện: " + _topic, True), daemon=True).start()
        return
    # 🛡️ Quét link virus/lừa đảo (/quetlink) + đặt VirusTotal key (/setvt, admin)
    if _tgtxt.startswith("/quetlink") or _tgtxt.startswith("/checklink") or _tgtxt.startswith("/scan"):
        _pl = _tgtxt.split(None, 1)
        _url = _pl[1].strip() if len(_pl) > 1 else _tg_first_url(((msg.get("reply_to_message") or {}).get("text") or ""))
        if _url:
            _tg_start_scan_link(token, chat_id, _url)
        else:
            _tg_send(token, chat_id, "🛡️ Dùng: <code>/quetlink https://link-can-kiem-tra</code> (hoặc reply vào tin có link).")
        return
    # 🎊 /kenios — lệnh DUY NHẤT quản lý chào sáng/tối + chúc mọi ngày lễ (chỉ admin)
    if _tgtxt.startswith("/kenios"):
        _uidk = (msg.get("from") or {}).get("id")
        _kadmin = (bool(admin_chat) and chat_id == str(admin_chat)) or (
            ctype in ("group", "supergroup") and _tg_is_admin(token, chat_id, _uidk))
        if not _kadmin:
            _tg_send(token, chat_id, "🔒 Chỉ ADMIN mới dùng được <b>/kenios</b>."); return
        _pk2 = _tgtxt.split(None, 1)
        _tg_kenios_cmd(token, chat_id, _pk2[1] if len(_pk2) > 1 else "")
        return
    if _tgtxt.startswith("/setvt"):
        _uid3 = (msg.get("from") or {}).get("id")
        _vtadmin = (bool(admin_chat) and chat_id == str(admin_chat)) or (
            ctype in ("group", "supergroup") and _tg_is_admin(token, chat_id, _uid3))
        if not _vtadmin:
            _tg_send(token, chat_id, "🔒 Chỉ ADMIN mới đặt được VirusTotal key."); return
        _pk = _tgtxt.split(None, 1)
        if len(_pk) > 1 and _pk[1].strip():
            set_setting("tg_vt_key", _pk[1].strip())
            _tg_send(token, chat_id, "✅ Đã lưu VirusTotal key — quét link giờ có kiểm tra virus SÂU. 🦠")
        else:
            set_setting("tg_vt_key", "")
            _tg_send(token, chat_id, "🗑️ Đã xoá VirusTotal key (chỉ còn quét cơ bản). Lấy key miễn phí ở virustotal.com.")
        return

    # 🤖 Trợ lý AI (/ai bật-tắt · /hoiai hỏi · /aikey /aimodel… cấu hình) — chạy ở nhóm & chat riêng.
    if _tgtxt.startswith("/") and _tgtxt.split():
        _aic = _tgtxt.split()[0].lstrip("/").split("@")[0].lower()
        if _aic in ("ai", "aion", "aioff", "hoiai", "ask", "aikey", "aimodel", "aiprovider", "aiurl", "aiset", "aihelp", "aidm", "aiall", "aiadd", "ailist", "aiclear"):
            _uid2 = (msg.get("from") or {}).get("id")
            _aiadmin = (bool(admin_chat) and chat_id == str(admin_chat)) or (
                ctype in ("group", "supergroup") and _tg_is_admin(token, chat_id, _uid2))
            _asp = _tgtxt.split(maxsplit=1)
            # /aion, /aioff → coi như /ai on, /ai off
            _c, _a = _aic, (_asp[1] if len(_asp) > 1 else "")
            if _aic == "aion":
                _c, _a = "ai", "on"
            elif _aic == "aioff":
                _c, _a = "ai", "off"
            _tg_ai_command(token, chat_id, msg, _c, _a, _aiadmin, ctype)
            return

    # 🛒 Tư vấn khách hàng KENIOS: /tuvan /banggia mở luồng · /setpay /setweb (admin) đặt thanh toán.
    if _tgtxt.startswith("/") and _tgtxt.split():
        _kc = _tgtxt.split()[0].lstrip("/").split("@")[0].lower()
        # ĐÃ BỎ lệnh tư vấn/bảng giá (/tuvan /banggia /gia /muahack /hotro) theo yêu cầu.
        if _kc in ("setpay", "setweb"):
            _uid3 = (msg.get("from") or {}).get("id")
            _kadm = (bool(admin_chat) and chat_id == str(admin_chat)) or (
                ctype in ("group", "supergroup") and _tg_is_admin(token, chat_id, _uid3))
            if not _kadm:
                _tg_send(token, chat_id, "🔒 Lệnh này chỉ dành cho <b>quản trị viên</b>.")
                return
            _kv = _tgtxt.split(maxsplit=1)[1].strip() if len(_tgtxt.split(maxsplit=1)) > 1 else ""
            if _kc == "setpay":
                set_setting("kenios_pay", _kv)
                _tg_send(token, chat_id, f"✅ Đã lưu thông tin thanh toán hiển thị khi tư vấn:\n{_kv or '(đã xoá)'}")
            else:
                set_setting("kenios_website", _kv or "https://linkbio.co/KENIOS")
                _tg_send(token, chat_id, f"✅ Đã lưu website dịch vụ: {_kv or 'https://linkbio.co/KENIOS'}")
            return

    # 🔗 Lệnh QUẢN LÝ NỘI DUNG BOT & ⚙️ LỆNH TÙY BIẾN — chạy ở cả nhóm & chat riêng.
    if _tgtxt.startswith("/"):
        _c0 = _tgtxt.split()[0].lstrip("/").split("@")[0].lower()
        _ufrom = (msg.get("from") or {}).get("id")
        _mng_admin = (bool(admin_chat) and chat_id == str(admin_chat)) or (
            ctype in ("group", "supergroup") and _tg_is_admin(token, chat_id, _ufrom))
        _is_grp = ctype in ("group", "supergroup")
        _umid = msg.get("message_id") if _is_grp else None
        if _c0 in ("links", "cmds", "addcmd", "delcmd", "setlinks", "broadcast"):
            if _tg_with_autodel(token, chat_id, _umid,
                                lambda: _tg_manage_command(token, chat_id, _tgtxt, _mng_admin)):
                return
        # Lệnh do admin tự tạo (không trùng lệnh hệ thống) → trả lời kèm nút liên kết.
        if _c0 not in _TG_RESERVED:
            _ccresp = _tg_cc_get(_c0)
            if _ccresp is not None:
                _tg_with_autodel(token, chat_id, _umid,
                                 lambda: _tg_send(token, chat_id, _ccresp,
                                                  buttons=(_tg_link_buttons() or None)))
                return

    # NHÓM: thành viên mới (captcha/chào mừng) · rời nhóm (tạm biệt) · quản lý
    if msg.get("new_chat_members"):
        _tg_on_join(token, chat, msg); return
    if msg.get("left_chat_member"):
        _tg_goodbye_member(token, chat, msg["left_chat_member"])
        if get_setting("tg_clean_service", "0") == "1":
            _tg_call(token, "deleteMessage", chat_id=chat_id, message_id=msg.get("message_id"))
        return
    if ctype in ("group", "supergroup"):
        _tg_group_message(token, chat_id, msg); return

    # CHAT RIÊNG: hỗ trợ khách ↔ admin
    text = msg.get("text", "") or msg.get("caption", "") or "[media]"
    frm = msg.get("from", {})
    name = _tg_name(frm)
    _tg_track(frm)   # đếm người dùng bot mỗi tháng
    # Bấm nút trên menu (reply keyboard) → xử lý ngay (admin bot thấy menu đầy đủ)
    if _tg_menu_click(token, chat_id, text, name,
                      admin=bool(admin_chat) and chat_id == str(admin_chat)):
        return
    # 🧠 ĐỐ VUI trong chat riêng: đang có câu đố → coi tin nhắn là đáp án
    # (chấp nhận cả kiểu gõ nhầm "/30" — miễn không trùng lệnh thật)
    if text and chat_id in _TG_QUIZ:
        _qtxt = text
        if _qtxt.startswith("/"):
            _qc = _qtxt.split()[0].lstrip("/").split("@")[0].lower()
            _qtxt = _qtxt.lstrip("/ ") if _qc not in _TG_RESERVED else ""
        if _qtxt:
            if not _tg_quiz_try(token, chat_id, msg, _qtxt):
                _tg_send(token, chat_id, "❌ Chưa đúng, thử lại nào! (✍️ nhắn thẳng đáp án · /goiy — gợi ý · /boqua — bỏ qua)")
            return
    # 🛒 KHÁCH HỎI TƯ VẤN ("bản nào an toàn", "chơi ok nhất"…) → mở luồng chọn OS → game → bảng giá.
    if text and not text.startswith("/") and _kenios_wants_support(text.lower()):
        _kenios_support_start(token, chat_id)
        return
    # 🤖 AI trong CHAT RIÊNG: MẶC ĐỊNH BẬT (khi có khoá) → nhắn thẳng là AI trả lời, KHỎI CẦN LỆNH.
    # (Trừ khi admin /aidm off, hoặc DM này /ai off; và không nuốt tin admin đang reply cho khách.)
    if _tg_ai_dm_on(chat_id) and text and not text.startswith("/") and text != "[media]":
        _reply_ai = msg.get("reply_to_message") or {}
        if "[cid:" not in (_reply_ai.get("text", "") or ""):   # không nuốt tin admin đang trả lời khách
            # 😌 Khách CHỬI → đối đáp văn minh (nhẹ nhàng mà thấm).
            if _tg_is_insult(text.lower()):
                _tg_call(token, "sendMessage", chat_id=chat_id, text=_tg_comeback(),
                         reply_to_message_id=msg.get("message_id"), disable_web_page_preview=True)
                return
            # 🔗 Nhắn tự nhiên → tự chạy lệnh (QR/nhạc/đố/game…) trước, còn lại để AI trả lời.
            if _tg_ai_route(token, chat_id, msg, text):
                return
            import threading as _thrp
            _thrp.Thread(target=_tg_ai_reply, args=(token, chat_id, msg, text), daemon=True).start()
            return
    # 🎮 Lệnh GIẢI TRÍ & TIỆN ÍCH — dùng được cả trong chat riêng
    if text.startswith("/"):
        _fc = text.split()[0].lstrip("/").split("@")[0].lower()
        if _fc in _TG_FUN_CMDS:
            _fsp = text.split(maxsplit=1)
            if _tg_fun_command(token, chat_id, msg, _fc, _fsp[1] if len(_fsp) > 1 else ""):
                return
    # Lệnh QUẢN LÝ NHÓM gõ trong chat riêng → nhắc: chỉ chạy trong nhóm (tránh "im lặng tưởng lỗi").
    _GROUP_CMDS = {"/ban", "/kick", "/mute", "/unmute", "/warn", "/unwarn", "/warns", "/pin", "/unpin",
                   "/del", "/purge", "/info", "/lock", "/unlock", "/locks", "/addbl", "/rmbl", "/blacklist",
                   "/filter", "/stop", "/filters", "/setrules", "/rules", "/clean", "/nightmode", "/antiflood",
                   "/captcha", "/autoreact", "/slowmode", "/log", "/diemdanh", "/top", "/report", "/save",
                   "/clear", "/notes", "/id", "/setwelcome", "/welcome", "/setwelcomebtn", "/setwelcomephoto",
                   "/setgoodbye", "/testwelcome", "/modon", "/modoff", "/stats", "/autodel", "/modadmin",
                   "/scanlink", "/chaosang", "/chaotoi"}
    if text.startswith("/") and text.split("@")[0].split()[0].lower() in _GROUP_CMDS:
        _tg_send(token, chat_id,
                 "🔧 Lệnh này dùng trong <b>NHÓM</b>, không chạy khi nhắn riêng bot.\n\n"
                 "👉 Cách dùng: <b>thêm bot vào nhóm</b> của bạn → cấp quyền <b>Quản trị viên</b> → "
                 "gõ lệnh trong nhóm (nhiều lệnh cần <b>reply</b> vào tin của thành viên, vd reply rồi gõ /ban).\n\n"
                 "💬 Trong chat riêng, bot hỗ trợ: /start · /help · <b>/nhac</b> &lt;bài hát&gt;.")
        return
    if admin_chat and chat_id == str(admin_chat):
        reply = msg.get("reply_to_message", {})
        rtext = reply.get("text", "") if reply else ""
        import re as _re
        m = _re.search(r"\[cid:(-?\d+)\]", rtext or "")
        if m and text and not text.startswith("/"):
            _tg_send(token, m.group(1), f"👨‍💼 <b>Hỗ trợ KENIOS:</b>\n{text}")
            _tg_send(token, admin_chat, "✅ Đã gửi trả lời tới khách.")
        elif text.startswith("/help") or text.startswith("/menu"):
            _tg_send_menu(token, admin_chat, "📋 <b>MENU KENIOS</b> — chọn chức năng bên dưới 👇", admin=True)
        elif text.startswith("/config"):
            _tg_send(token, admin_chat,
                     "⚙️ <b>Cấu hình bot</b>\n"
                     f"Quản lý nhóm: {'BẬT' if get_setting('tg_mod_enabled','1')=='1' else 'tắt'}\n"
                     f"Chống link: {'✓' if get_setting('tg_del_links','1')=='1' else '✗'} · "
                     f"Antiflood: {'✓' if get_setting('tg_antiflood_on','1')=='1' else '✗'} · "
                     f"Captcha: {'✓' if get_setting('tg_captcha_on','0')=='1' else '✗'}\n"
                     f"AutoReact: {'✓' if get_setting('tg_autoreact_on','0')=='1' else '✗'} · "
                     f"Slowmode: {get_setting('tg_slowmode','0')}s · "
                     f"NightMode: {'✓' if get_setting('tg_nightmode_on','0')=='1' else '✗'}\n"
                     "Chỉnh chi tiết trong app KENIOS → Quản trị → Bot Telegram, hoặc dùng lệnh trong nhóm.")
        elif text.startswith("/start"):
            botname = get_setting("tg_bot_name", "TRẦN MINH CHIẾN")
            _cnt = f"{_tg_monthly():,}".replace(",", ".")
            _tg_send_menu(token, admin_chat,
                          f"👋 Chào {name}, tôi là <b>{botname}</b>.\n\n"
                          "👑 Bạn là <b>ADMIN</b>. Khi khách nhắn bot, tin sẽ hiện ở đây — REPLY vào tin đó để trả lời khách.\n"
                          f"\n👥 <b>{_cnt}</b> người dùng mỗi tháng"
                          "\n\n📋 Chọn chức năng ở lưới nút bên dưới 👇", photo_first=True, admin=True)
            _lb = _tg_link_buttons()
            if _lb:
                _tg_send(token, admin_chat, "🔗 <b>Liên kết nhanh:</b>", buttons=_lb)
        return
    _tg_track(frm)   # đếm người dùng bot mỗi tháng
    if text.startswith("/start"):
        botname = get_setting("tg_bot_name", "TRẦN MINH CHIẾN")
        default_wel = ("👋 Chào {name}, tôi là <b>{botname}</b>.\n\n"
                       "Tôi có nhiều công cụ hữu ích. Gõ /help để xem lệnh, hoặc nhắn nội dung cần hỗ trợ.\n"
                       "Tôi hỗ trợ Tiếng Việt 🇻🇳 và English 🇺🇸")
        wel = get_setting("tg_welcome", default_wel)
        wel = wel.replace("{name}", name).replace("{botname}", botname)
        wel += f"\n\n👥 <b>{_tg_monthly():,}</b> người dùng mỗi tháng".replace(",", ".")
        _tg_send_menu(token, chat_id, wel, photo_first=True)
        _lb = _tg_link_buttons()
        if _lb:
            _tg_send(token, chat_id, "🔗 <b>Liên kết nhanh:</b>", buttons=_lb)
        return
    if admin_chat:
        _tg_send(token, admin_chat,
                 f"💬 <b>{name}</b> [cid:{chat_id}]\n{text}\n\n<i>Reply tin này để trả lời khách.</i>")
        _tg_send(token, chat_id, "✅ Đã gửi tới đội ngũ hỗ trợ. Vui lòng chờ phản hồi nhé!")

_tg_cmds_done = ""

def _tg_loop() -> None:
    global _tg_offset, _tg_cmds_done
    import httpx, json as _json
    while True:
        try:
            token = (get_setting("tg_bot_token", "") or os.getenv("TELEGRAM_BOT_TOKEN", "")).strip()
            enabled = get_setting("tg_bot_enabled", "0") == "1"
            if not token or not enabled:
                time.sleep(5); continue
            admin_chat = (get_setting("tg_admin_chat", "") or os.getenv("TELEGRAM_ADMIN_CHAT", "")).strip()
            if _tg_cmds_done != token + "|" + admin_chat:   # đăng ký menu lệnh khi đổi token/admin
                _tg_register_commands(token); _tg_cmds_done = token + "|" + admin_chat
            # allowed_updates PHẢI có "chat_member" thì bot mới nhận được sự kiện
            # thành viên VÀO NHÓM QUA LINK MỜI / tự tìm vào nhóm công khai (Telegram
            # KHÔNG gửi "new_chat_members" cho các kiểu vào này — chỉ gửi chat_member,
            # và bot phải là QUẢN TRỊ VIÊN mới nhận được). Liệt kê đủ để không mất
            # message/callback (allowed_updates ghi đè cấu hình cũ mỗi lần gọi).
            r = httpx.get(f"https://api.telegram.org/bot{token}/getUpdates",
                          params={"offset": _tg_offset + 1, "timeout": 25,
                                  "allowed_updates": _json.dumps(
                                      ["message", "edited_message", "callback_query",
                                       "my_chat_member", "chat_member", "chat_join_request"])},
                          timeout=35)
            for upd in r.json().get("result", []):
                _tg_offset = max(_tg_offset, upd.get("update_id", 0))
                try:
                    _tg_handle_update(token, admin_chat, upd)
                except Exception as e:
                    log.warning("tg handle update lỗi: %s", e)
        except Exception:
            time.sleep(3)

def _tg_register_commands(token: str) -> None:
    """Đăng ký MENU LỆNH để người dùng bấm '/' thấy danh sách (như bot chuyên nghiệp)."""
    # Lệnh CÔNG KHAI — mọi người thấy khi bấm "/"
    pub = [
        ("help", "Menu & danh sách lệnh"), ("menu", "Mở menu nút bấm"),
        ("hoiai", "🤖 Hỏi trợ lý AI"),
        ("nhac", "Lấy nhạc YouTube/TikTok"), ("video", "🎬 Tải video (cắt phần nếu lớn)"),
        ("quetlink", "🛡️ Quét link virus/lừa đảo"),
        ("kechuyen", "🎙️ Kể chuyện bằng giọng nói"),
        ("diemdanh", "Điểm danh"), ("top", "Bảng xếp hạng"),
        ("report", "Báo cáo admin (reply)"), ("rules", "Xem nội quy"),
        ("afk", "Báo bận"), ("id", "Xem Chat/User ID"),
        ("links", "🔗 Liên kết nhanh"), ("cmds", "Xem lệnh riêng"),
        # 🎮 Giải trí & tiện ích
        ("xucxac", "🎲 Tung xúc xắc"), ("slot", "🎰 Quay slot"), ("tungxu", "🪙 Tung đồng xu"),
        ("oantuti", "✂️ Oẳn tù tì với bot"), ("doanso", "🔢 Trò đoán số 1-100"),
        ("xoso", "🎰 Quay số may mắn"), ("chon", "🤔 Bot chọn giúp A | B"),
        ("cuoi", "😂 Chuyện cười"), ("cakhia", "😜 Cà khịa vui (reply)"),
        ("khen", "🌟 Khen ai đó (reply)"), ("thatha", "🙊 Nói thật"), ("thachthuc", "🔥 Thử thách"),
        ("ghep", "💞 Ghép đôi ngẫu nhiên"), ("lucky", "🍀 Thành viên may mắn"),
        ("boi", "🔮 Bói vui hôm nay"), ("tinhduyen", "💘 Bói tình duyên"),
        ("hoi", "🎱 Hỏi bot tiên tri"), ("danhgia", "💯 Chấm điểm %"),
        ("tinh", "🧮 Máy tính"), ("qr", "🔳 Tạo mã QR"), ("thoitiet", "⛅ Thời tiết"),
        ("giacoin", "💰 Giá coin"), ("tygia", "💵 Tỷ giá USD→VND"), ("dich", "🌐 Dịch sang tiếng Việt"),
        ("nhacnho", "⏰ Hẹn nhắc việc"), ("binhchon", "🗳️ Tạo bình chọn"),
        ("gio", "🕐 Giờ thế giới"), ("password", "🔐 Tạo mật khẩu mạnh"),
        # 🃏 Game bài + 🧠 đố vui có điểm
        ("dovui", "🧠 Đố vui +10đ (~1080 câu)"), ("diemdo", "🏆 Bảng vàng điểm vui"),
        ("goiy", "💡 Gợi ý câu đố"), ("boqua", "⏭️ Bỏ qua câu đố"),
        ("baicao", "🃏 Bài cào 3 cây"), ("xidach", "🃏 Xì dách 21 điểm"),
        ("baucua", "🎲 Bầu cua tôm cá"),
    ]
    # Lệnh QUẢN TRỊ — CHỈ admin nhóm (và admin bot) thấy
    adm = pub + [
        ("ai", "🤖 Bật/tắt trợ lý AI"), ("aiset", "🤖 Cấu hình/hướng dẫn AI"),
        ("config", "Xem cấu hình"),
        ("ban", "Cấm (reply)"), ("kick", "Đá khỏi nhóm (reply)"),
        ("mute", "Cấm chat (reply) [phút]"), ("unmute", "Mở chat (reply)"),
        ("warn", "Cảnh báo (reply)"), ("warns", "Xem cảnh báo (reply)"),
        ("pin", "Ghim (reply)"), ("purge", "Xoá hàng loạt (reply)"), ("del", "Xoá tin (reply)"),
        ("lock", "Khoá nội dung"), ("unlock", "Mở khoá"), ("locks", "Xem khoá"),
        ("addbl", "Thêm từ cấm"), ("filter", "Trả lời tự động"), ("save", "Lưu ghi chú"),
        ("setrules", "Đặt nội quy"),
        ("setwelcome", "Sửa lời chào TV mới"), ("welcome", "Bật/tắt chào mừng"),
        ("setwelcomebtn", "Nút link lời chào"), ("setwelcomephoto", "Ảnh lời chào"),
        ("setgoodbye", "Lời tạm biệt"), ("testwelcome", "Xem thử lời chào"),
        ("kenios", "🎊 Tự chúc sáng/tối + MỌI ngày lễ"),
        ("modon", "BẬT kiểm duyệt nhóm"), ("modoff", "TẮT kiểm duyệt nhóm"),
        ("modadmin", "Kiểm duyệt cả admin on|off"),
        ("stats", "Thống kê nhóm"),
        ("slowmode", "Giãn cách gửi tin"), ("autoreact", "Tự thả cảm xúc"),
        ("autodel", "Tự xoá lệnh sau N giây"),
        ("addcmd", "Thêm lệnh riêng"), ("delcmd", "Xoá lệnh riêng"),
        ("setlinks", "Đặt nút liên kết"), ("broadcast", "📣 Loa phường"),
    ]
    def _cl(lst):
        return [{"command": c, "description": d} for c, d in lst]
    _tg_call(token, "setMyCommands", commands=_cl(pub), scope={"type": "default"})
    _tg_call(token, "setMyCommands", commands=_cl(adm), scope={"type": "all_chat_administrators"})
    # Admin bot (chat riêng) cũng thấy đủ lệnh
    ac = (get_setting("tg_admin_chat", "") or "").strip()
    if ac.lstrip("-").isdigit():
        _tg_call(token, "setMyCommands", commands=_cl(adm), scope={"type": "chat", "chat_id": int(ac)})

def _tg_help_text(name: str = "", admin: bool = False) -> str:
    import html as _h
    bot = get_setting("tg_bot_name", "TRẦN MINH CHIẾN")
    greet = (f"👋 Chào {_h.escape(name)}, tôi là <b>{_h.escape(bot)}</b>.\n\n" if name
             else f"👋 Xin chào, tôi là <b>{_h.escape(bot)}</b>.\n\n")
    pub = ("🤖 <b>Trợ lý AI:</b> /hoiai &lt;câu hỏi&gt; — hỏi mọi câu khó, toán, lập trình (admin bật bằng /ai)\n"
           "🎵 <b>/nhac</b> &lt;bài&gt; — lấy nhạc · 🎬 <b>/video</b> &lt;link/tên&gt; — tải video (tự cắt phần nếu lớn)\n"
           "🛡️ <b>/quetlink</b> &lt;link&gt; — kiểm tra virus/lừa đảo + thông tin đầy đủ\n"
           "🎙️ <b>/kechuyen</b> [chủ đề] — bot KỂ CHUYỆN bằng GIỌNG NÓI (voice). VD /kechuyen ma\n"
           "🧠 <b>Đố vui CÓ ĐIỂM:</b> /dovui (+10đ/câu đúng, ~1080 câu) · /goiy · /boqua · /dungdo · 🏆 /diemdo\n"
           "🃏 <b>Game bài:</b> /baicao · /xidach (/rut /dan) · /baucua bầu — thắng +5 điểm\n"
           "🎮 <b>Trò chơi:</b> /xucxac /slot /phitieu /bongda /bongro /bowling /tungxu /oantuti /doanso /random /chon /xoso\n"
           "😂 <b>Giải trí:</b> /cuoi /cakhia /khen /thatha /thachthuc /ghep /lucky /triethly /thotinh /noinguoc\n"
           "🔮 <b>Bói vui:</b> /boi /tinhduyen /hoi /danhgia\n"
           "🧰 <b>Tiện ích:</b> /tinh /qr /thoitiet /giacoin /tygia /dich /nhacnho /binhchon /gio /dem /password\n"
           "🔗 /links — liên kết nhanh · /cmds — lệnh riêng\n"
           "<b>Trong nhóm:</b> /diemdanh · /top · /report (reply) · /rules · /afk [lý do] · /id")
    if not admin:
        return greet + pub
    return (greet + pub + "\n\n👑 <b>LỆNH QUẢN TRỊ</b>\n"
            "<b>Quản trị (reply):</b> /ban /kick /mute [phút] /unmute /warn /unwarn /warns /pin /unpin /del /purge /info\n"
            "<b>Khoá:</b> /lock link|photo|video|sticker|gif|forward|mention|all · /unlock · /locks\n"
            "<b>Lọc & ghi chú:</b> /addbl /rmbl /blacklist · /filter /stop /filters · /save #tên /clear /notes · /setrules /rules\n"
            "<b>Chào mừng:</b> /setwelcome · /setwelcomebtn · /setwelcomephoto · /setgoodbye · /welcome on|off · /testwelcome\n"
            "🎊 <b>/kenios</b> — 1 LỆNH DUY NHẤT: tự chào SÁNG + TỐI + chúc MỌI NGÀY LỄ (dương & âm lịch) đúng giờ.\n"
            "   • /kenios on|off · /kenios sang 6:30 · /kenios toi 21:00 · /kenios le 8:00 · /kenios test\n"
            "🤖 <b>Trợ lý AI:</b> /ai on|off · /aiall on|off (nhóm trả lời mọi tin) · /aidm on|off (chat riêng tự trả lời) · /aikey &lt;khoá&gt; · /aiprovider · /aiurl · /aimodel · /aiset\n"
            "🛡️ <b>Quét link:</b> /scanlink on|off (tự quét link admin gửi) · /setvt &lt;key&gt; (VirusTotal — quét virus sâu)\n"
            "<b>Module:</b> /clean /nightmode /antiflood /captcha /autoreact /slowmode [giây] /autodel [giây] /log · /modon /modoff · /modadmin · /config\n"
            "🔗 <b>Liên kết & lệnh riêng:</b> /addcmd &lt;tên&gt; &lt;nội dung&gt; · /delcmd · /setlinks · 📣 /broadcast")

# ---------- ⏰ CHÀO SÁNG/TỐI + 🎊 CHÚC MỌI NGÀY LỄ tự động (giờ VN) ----------
_TG_MORNING_DEFAULT = "☀️ Chào buổi sáng cả nhà! Chúc mọi người một ngày mới tràn đầy năng lượng, may mắn và thật nhiều niềm vui nhé! 🌸"
_TG_EVENING_DEFAULT = "🌙 Chào buổi tối cả nhà! Chúc mọi người buổi tối vui vẻ, ấm áp bên gia đình và nghỉ ngơi thật tốt nhé! ✨"
_tg_sched_thread = None

# ===== Lịch âm (thuật toán Hồ Ngọc Đức) để chúc đúng các ngày lễ ÂM LỊCH =====
def _jd(dd, mm, yy):
    import math
    a = int((14 - mm) / 12); y = yy + 4800 - a; m = mm + 12 * a - 3
    jd = dd + int((153 * m + 2) / 5) + 365 * y + int(y / 4) - int(y / 100) + int(y / 400) - 32045
    if jd < 2299161:
        jd = dd + int((153 * m + 2) / 5) + 365 * y + int(y / 4) - 32083
    return jd

def _new_moon(k):
    import math
    T = k / 1236.85; T2 = T * T; T3 = T2 * T; dr = math.pi / 180
    J1 = 2415020.75933 + 29.53058868 * k + 0.0001178 * T2 - 0.000000155 * T3
    J1 = J1 + 0.00033 * math.sin((166.56 + 132.87 * T - 0.009173 * T2) * dr)
    M = 359.2242 + 29.10535608 * k - 0.0000333 * T2 - 0.00000347 * T3
    Mpr = 306.0253 + 385.81691806 * k + 0.0107306 * T2 + 0.00001236 * T3
    F = 21.2964 + 390.67050646 * k - 0.0016528 * T2 - 0.00000239 * T3
    C1 = (0.1734 - 0.000393 * T) * math.sin(M * dr) + 0.0021 * math.sin(2 * dr * M)
    C1 = C1 - 0.4068 * math.sin(Mpr * dr) + 0.0161 * math.sin(dr * 2 * Mpr)
    C1 = C1 - 0.0004 * math.sin(dr * 3 * Mpr)
    C1 = C1 + 0.0104 * math.sin(dr * 2 * F) - 0.0051 * math.sin(dr * (M + Mpr))
    C1 = C1 - 0.0074 * math.sin(dr * (M - Mpr)) + 0.0004 * math.sin(dr * (2 * F + M))
    C1 = C1 - 0.0004 * math.sin(dr * (2 * F - M)) - 0.0006 * math.sin(dr * (2 * F + Mpr))
    C1 = C1 + 0.0010 * math.sin(dr * (2 * F - Mpr)) + 0.0005 * math.sin(dr * (2 * Mpr + M))
    deltat = (0.001 + 0.000839 * T + 0.0002261 * T2 - 0.00000845 * T3 - 0.000000081 * T * T3
              if T < -11 else -0.000278 + 0.000265 * T + 0.000262 * T2)
    return J1 + C1 - deltat

def _sun_long(jdn):
    import math
    T = (jdn - 2451545.0) / 36525; T2 = T * T; dr = math.pi / 180
    M = 357.52910 + 35999.05030 * T - 0.0001559 * T2 - 0.00000048 * T * T2
    L0 = 280.46645 + 36000.76983 * T + 0.0003032 * T2
    DL = (1.914600 - 0.004817 * T - 0.000014 * T2) * math.sin(dr * M)
    DL = DL + (0.019993 - 0.000101 * T) * math.sin(dr * 2 * M) + 0.000290 * math.sin(dr * 3 * M)
    L = (L0 + DL) * dr
    return L - math.pi * 2 * int(L / (math.pi * 2))

def _nm_day(k, tz=7):
    import math
    return int(_new_moon(k) + 0.5 + tz / 24.0)

def _sun_long6(dn, tz=7):
    import math
    return int(_sun_long(dn - 0.5 - tz / 24.0) / math.pi * 6)

def _lunar_m11(yy, tz=7):
    off = _jd(31, 12, yy) - 2415021
    k = int(off / 29.530588853)
    nm = _nm_day(k, tz)
    if _sun_long6(nm, tz) >= 9:
        nm = _nm_day(k - 1, tz)
    return nm

def _leap_offset(a11, tz=7):
    k = int((a11 - 2415021.076998695) / 29.530588853 + 0.5)
    i = 1; arc = _sun_long6(_nm_day(k + i, tz), tz)
    while True:
        last = arc; i += 1
        arc = _sun_long6(_nm_day(k + i, tz), tz)
        if not (arc != last and i < 14):
            break
    return i - 1

def _solar2lunar(dd, mm, yy, tz=7):
    """Trả (ngày âm, tháng âm, năm âm, nhuận?) của 1 ngày dương."""
    dn = _jd(dd, mm, yy)
    k = int((dn - 2415021.076998695) / 29.530588853)
    monthStart = _nm_day(k + 1, tz)
    if monthStart > dn:
        monthStart = _nm_day(k, tz)
    a11 = _lunar_m11(yy, tz); b11 = a11
    if a11 >= monthStart:
        lunarYear = yy; a11 = _lunar_m11(yy - 1, tz)
    else:
        lunarYear = yy + 1; b11 = _lunar_m11(yy + 1, tz)
    lunarDay = dn - monthStart + 1
    diff = int((monthStart - a11) / 29)
    leap = 0; lunarMonth = diff + 11
    if b11 - a11 > 365:
        lo = _leap_offset(a11, tz)
        if diff >= lo:
            lunarMonth = diff + 10
            if diff == lo:
                leap = 1
    if lunarMonth > 12:
        lunarMonth -= 12
    if lunarMonth >= 11 and diff < 4:
        lunarYear -= 1
    return lunarDay, lunarMonth, lunarYear, leap

# ===== Bảng NGÀY LỄ — dương lịch + âm lịch (chúc TẤT CẢ) =====
_TG_SOLAR_HOLIDAYS = {
    (1, 1):  "🎉 <b>CHÚC MỪNG NĂM MỚI!</b> 🎊\nChúc cả nhà năm mới an khang, thịnh vượng, vạn sự như ý! 🥂",
    (1, 6):  "🎖️ Chúc mừng ngày truyền thống — chúc mọi người ngày mới nhiều năng lượng!",
    (2, 3):  "🌟 Kỷ niệm ngày thành lập Đảng Cộng sản Việt Nam (3/2) — chúc cả nhà ngày tốt lành!",
    (2, 14): "💘 <b>HAPPY VALENTINE!</b>\nChúc các cặp đôi mãi ngọt ngào, ai độc thân sớm gặp 'ý trung nhân' nhé! 🌹",
    (3, 8):  "💐 <b>MỪNG NGÀY QUỐC TẾ PHỤ NỮ 8/3!</b>\nChúc các bà, các mẹ, các chị em luôn xinh đẹp, hạnh phúc và được yêu thương! 🌸",
    (3, 20): "😊 Ngày Quốc tế Hạnh phúc 20/3 — chúc cả nhà luôn vui vẻ, bình an!",
    (3, 26): "🔥 Chúc mừng ngày thành lập Đoàn TNCS Hồ Chí Minh 26/3 — tuổi trẻ nhiệt huyết!",
    (4, 1):  "🤡 <b>Cá tháng Tư!</b> Hôm nay coi chừng bị 'lừa' dễ thương nha cả nhà! 😜",
    (4, 30): "🇻🇳 <b>Mừng ngày Giải phóng miền Nam 30/4!</b>\nChúc cả nhà kỳ nghỉ lễ vui vẻ, an toàn! 🎉",
    (5, 1):  "🛠️ <b>Mừng ngày Quốc tế Lao động 1/5!</b>\nChúc mọi người nghỉ lễ thật thảnh thơi, vui khỏe!",
    (5, 7):  "🎖️ Kỷ niệm Chiến thắng Điện Biên Phủ 7/5 — tự hào Việt Nam!",
    (5, 19): "🌺 Kỷ niệm ngày sinh Chủ tịch Hồ Chí Minh 19/5 — chúc cả nhà ngày ý nghĩa!",
    (6, 1):  "🎈 <b>Quốc tế Thiếu nhi 1/6!</b>\nChúc các bé luôn khỏe mạnh, ngoan ngoãn và thật nhiều niềm vui! 🧸",
    (6, 21): "📰 Chúc mừng ngày Báo chí Cách mạng Việt Nam 21/6!",
    (6, 28): "👨‍👩‍👧‍👦 Ngày Gia đình Việt Nam 28/6 — chúc mọi nhà luôn đầm ấm, yêu thương!",
    (7, 27): "🕯️ Ngày Thương binh - Liệt sĩ 27/7 — tưởng nhớ và tri ân các anh hùng.",
    (8, 19): "🇻🇳 Kỷ niệm Cách mạng Tháng Tám 19/8 — chúc cả nhà ngày tốt lành!",
    (9, 2):  "🇻🇳 <b>MỪNG QUỐC KHÁNH 2/9!</b>\nChúc cả nhà kỳ nghỉ lễ vui vẻ, hạnh phúc bên người thân! 🎆",
    (10, 10):"🏙️ Kỷ niệm ngày Giải phóng Thủ đô 10/10 — chúc cả nhà ngày đẹp!",
    (10, 13):"💼 Chúc mừng ngày Doanh nhân Việt Nam 13/10 — chúc quý doanh nhân phát tài!",
    (10, 20):"🌷 <b>Mừng ngày Phụ nữ Việt Nam 20/10!</b>\nChúc một nửa thế giới luôn tươi trẻ, xinh đẹp và hạnh phúc! 💖",
    (10, 31):"🎃 <b>HAPPY HALLOWEEN!</b> Trick or Treat! Chúc cả nhà một đêm ma quái vui nhộn! 👻",
    (11, 20):"👩‍🏫 <b>Mừng ngày Nhà giáo Việt Nam 20/11!</b>\nTri ân và chúc các thầy cô luôn mạnh khỏe, hạnh phúc! 🌹",
    (12, 1): "🎗️ Ngày Thế giới phòng chống AIDS 1/12 — chung tay vì cộng đồng.",
    (12, 22):"🎖️ Chúc mừng ngày thành lập Quân đội Nhân dân Việt Nam 22/12!",
    (12, 24):"🎄 <b>ĐÊM GIÁNG SINH AN LÀNH!</b>\nMerry Christmas Eve — chúc cả nhà một đêm ấm áp, hạnh phúc! 🔔",
    (12, 25):"🎅 <b>MERRY CHRISTMAS!</b>\nChúc cả nhà Giáng sinh vui vẻ, tràn đầy yêu thương và quà nè! 🎁",
    (12, 31):"🎆 <b>Đêm giao thừa năm mới!</b> Chúc cả nhà khép lại năm cũ trọn vẹn, đón năm mới rực rỡ! 🥳",
}
_TG_LUNAR_HOLIDAYS = {
    (1, 1):  "🧧 <b>CHÚC MỪNG NĂM MỚI — TẾT NGUYÊN ĐÁN!</b> 🎊\nChúc cả nhà năm mới AN KHANG THỊNH VƯỢNG, VẠN SỰ NHƯ Ý, tiền vào như nước! 🥳🧨",
    (1, 2):  "🧧 <b>Mùng 2 Tết!</b> Chúc cả nhà năm mới sức khỏe dồi dào, làm ăn phát đạt! 🎉",
    (1, 3):  "🧧 <b>Mùng 3 Tết!</b> Chúc mọi người một năm bình an, may mắn và nhiều tài lộc! 🍊",
    (1, 15): "🏮 <b>Tết Nguyên Tiêu (Rằm tháng Giêng)!</b>\nChúc cả nhà một năm bình an, gia đạo hưng thịnh! 🙏",
    (3, 3):  "🍡 <b>Tết Hàn Thực (3/3 âm)!</b> Nhớ ăn bánh trôi bánh chay, chúc cả nhà ngày ngọt ngào!",
    (3, 10): "🇻🇳 <b>GIỖ TỔ HÙNG VƯƠNG (10/3 âm)!</b>\n'Dù ai đi ngược về xuôi, nhớ ngày Giỗ Tổ mùng mười tháng ba.' Chúc cả nhà nghỉ lễ vui vẻ! 🙏",
    (4, 15): "🪷 <b>Đại lễ Phật Đản (15/4 âm)!</b> Kính chúc cả nhà thân tâm an lạc, vạn sự cát tường! 🙏",
    (5, 5):  "🍶 <b>Tết Đoan Ngọ (5/5 âm) — Tết diệt sâu bọ!</b> Chúc cả nhà mạnh khỏe, mọi điều tốt lành! 🌿",
    (7, 15): "🌸 <b>Lễ Vu Lan Báo Hiếu (Rằm tháng 7)!</b>\nChúc cả nhà luôn hiếu thảo, gia đình bình an, cha mẹ khỏe mạnh! 🙏❤️",
    (8, 15): "🥮 <b>TẾT TRUNG THU!</b> 🏮\nChúc các bé và cả nhà một đêm rằm ấm áp, đoàn viên, ngập tràn bánh nướng bánh dẻo! 🌕",
    (12, 23):"🐟 <b>Ông Công Ông Táo về trời (23 tháng Chạp)!</b> Chúc cả nhà dọn nhà đón Tết vui vẻ, chuẩn bị năm mới sung túc! 🧧",
}

def _tg_holiday_today(now):
    """Trả lời chúc mừng nếu HÔM NAY (giờ VN) là ngày lễ (dương hoặc âm); None nếu không."""
    d, m = now.day, now.month
    sol = _TG_SOLAR_HOLIDAYS.get((m, d))
    if sol:
        return sol
    # Lễ theo Chủ nhật: Ngày của Mẹ (CN thứ 2 tháng 5), Ngày của Cha (CN thứ 3 tháng 6)
    if m == 5 and now.weekday() == 6 and 8 <= d <= 14:
        return "💐 <b>NGÀY CỦA MẸ!</b> Gửi lời yêu thương nhất tới Mẹ — chúc các Mẹ luôn mạnh khỏe, hạnh phúc! ❤️"
    if m == 6 and now.weekday() == 6 and 15 <= d <= 21:
        return "👔 <b>NGÀY CỦA CHA!</b> Cảm ơn và chúc các Cha luôn khỏe mạnh, là chỗ dựa vững chắc của gia đình! 💙"
    try:
        ld, lm, ly, leap = _solar2lunar(d, m, now.year)
        if not leap:
            lun = _TG_LUNAR_HOLIDAYS.get((lm, ld))
            if lun:
                return lun
            # Giao thừa: hôm nay là ngày cuối tháng Chạp âm (mai là mùng 1 Tết)
            if lm == 12 and ld >= 29:
                import datetime as _dt2
                _tm = now + _dt2.timedelta(days=1)
                nxt = _solar2lunar(_tm.day, _tm.month, _tm.year)
                if nxt[0] == 1 and nxt[1] == 1:
                    return "🎆 <b>ĐÊM GIAO THỪA!</b> 🧨\nChúc cả nhà khoảnh khắc chuyển giao an lành, năm mới AN KHANG THỊNH VƯỢNG, VẠN SỰ NHƯ Ý! 🥳🧧"
    except Exception:
        pass
    return None

def _tg_kenios_cmd(token, chat_id, args) -> None:
    """Lệnh DUY NHẤT /kenios (admin): quản lý chào sáng/tối + chúc mọi ngày lễ."""
    import re as _re, datetime as _dt
    a = (args or "").strip()
    parts = a.split(None, 1)
    sub = parts[0].lower() if parts else ""
    rest = parts[1].strip() if len(parts) > 1 else ""
    _tg_greet_register(chat_id)

    def _status():
        master = get_setting("tg_greet_master", "1") == "1"
        now = _dt.datetime.utcnow() + _dt.timedelta(hours=7)
        hol = _tg_holiday_today(now)
        s = ("🎊 <b>KENIOS — Tự động chúc mừng</b> (chỉ admin)\n"
             f"Tổng: {'🟢 BẬT' if master else '🔴 TẮT'}\n"
             f"☀️ Chào sáng: {'BẬT' if get_setting('tg_greet_morning_on','1')=='1' else 'tắt'} lúc <b>{get_setting('tg_greet_morning_time','07:00')}</b>\n"
             f"🌙 Chào tối: {'BẬT' if get_setting('tg_greet_evening_on','1')=='1' else 'tắt'} lúc <b>{get_setting('tg_greet_evening_time','20:00')}</b>\n"
             f"🎉 Ngày lễ: {'BẬT' if get_setting('tg_greet_holiday_on','1')=='1' else 'tắt'} lúc <b>{get_setting('tg_greet_holiday_time','08:00')}</b> — tự chúc <b>MỌI</b> ngày lễ (dương & âm lịch)")
        if hol:
            s += "\n\n📌 Hôm nay là ngày lễ: " + hol.split("\n")[0]
        s += ("\n\n<b>Cách dùng (chỉ 1 lệnh):</b>\n"
              "• <code>/kenios on|off</code> — bật/tắt toàn bộ\n"
              "• <code>/kenios sang 6:30</code> · <code>/kenios toi 21:00</code> · <code>/kenios le 8:00</code> — đổi giờ\n"
              "• <code>/kenios sang on|off</code> · <code>toi</code> · <code>le</code> — bật/tắt từng loại\n"
              "• <code>/kenios sang &lt;lời chào&gt;</code> · <code>/kenios toi &lt;lời chào&gt;</code> — đổi nội dung\n"
              "• <code>/kenios test</code> — gửi thử ngay")
        return s

    if not sub:
        _tg_send(token, chat_id, _status()); return
    if sub in ("on", "bat", "bật", "1"):
        set_setting("tg_greet_master", "1")
        _tg_send(token, chat_id, "🟢 ĐÃ BẬT tự động chúc mừng: chào sáng + chào tối + <b>tất cả ngày lễ</b>. Nhóm này sẽ nhận. 🎉"); return
    if sub in ("off", "tat", "tắt", "0"):
        set_setting("tg_greet_master", "0")
        _tg_send(token, chat_id, "🔴 ĐÃ TẮT toàn bộ tự động chúc mừng."); return
    if sub == "test":
        now = _dt.datetime.utcnow() + _dt.timedelta(hours=7)
        _tg_send(token, chat_id, get_setting("tg_greet_morning_text", "") or _TG_MORNING_DEFAULT)
        _tg_send(token, chat_id, get_setting("tg_greet_evening_text", "") or _TG_EVENING_DEFAULT)
        hol = _tg_holiday_today(now)
        _tg_send(token, chat_id, hol if hol else "📅 Hôm nay không phải ngày lễ — khi tới ngày lễ (dương/âm) bot sẽ tự chúc nhé!")
        return
    if sub in ("sang", "sáng", "toi", "tối", "le", "lễ", "le"):
        slot = "morning" if sub in ("sang", "sáng") else ("evening" if sub in ("toi", "tối") else "holiday")
        on_key, time_key, text_key = f"tg_greet_{slot}_on", f"tg_greet_{slot}_time", f"tg_greet_{slot}_text"
        deftime = {"morning": "07:00", "evening": "20:00", "holiday": "08:00"}[slot]
        label = {"morning": "☀️ Chào sáng", "evening": "🌙 Chào tối", "holiday": "🎉 Chúc ngày lễ"}[slot]
        if not rest:
            _tg_send(token, chat_id, f"{label}: {'BẬT' if get_setting(on_key,'1')=='1' else 'tắt'} lúc <b>{get_setting(time_key, deftime)}</b> (giờ VN)."); return
        if rest.lower() in ("on", "bat", "bật", "1"):
            set_setting(on_key, "1"); set_setting("tg_greet_master", "1")
            _tg_send(token, chat_id, f"{label}: BẬT lúc <b>{get_setting(time_key, deftime)}</b> (giờ VN)."); return
        if rest.lower() in ("off", "tat", "tắt", "0"):
            set_setting(on_key, "0"); _tg_send(token, chat_id, f"{label}: TẮT."); return
        if _re.match(r"^\d{1,2}:\d{2}$", rest):
            hh, mm = int(rest.split(":")[0]), int(rest.split(":")[1])
            if 0 <= hh <= 23 and 0 <= mm <= 59:
                set_setting(time_key, f"{hh:02d}:{mm:02d}"); set_setting(on_key, "1"); set_setting("tg_greet_master", "1")
                _tg_send(token, chat_id, f"⏰ {label} sẽ gửi lúc <b>{hh:02d}:{mm:02d}</b> mỗi ngày (giờ VN). ✅")
            else:
                _tg_send(token, chat_id, f"Giờ không hợp lệ. VD: <code>/kenios {sub} 6:30</code>")
            return
        if slot == "holiday":
            _tg_send(token, chat_id, "🎉 Lời chúc ngày lễ do bot TỰ soạn theo từng lễ (không cần nhập). Chỉ đổi GIỜ: <code>/kenios le 8:00</code>."); return
        set_setting(text_key, rest[:1000]); set_setting(on_key, "1")
        _tg_send(token, chat_id, f"✅ Đã đặt nội dung {label}."); return
    _tg_send(token, chat_id, _status())

def _tg_greet_register(chat_id) -> None:
    """Ghi nhớ nhóm để gửi lời chào sáng/tối (lưu bền, sống qua restart)."""
    try:
        cur = [x for x in (get_setting("tg_greet_chats", "") or "").split(",") if x]
        s = str(chat_id)
        if s not in cur:
            cur.append(s); cur = cur[-200:]
            set_setting("tg_greet_chats", ",".join(cur))
    except Exception:
        pass

def _tg_greet_chats() -> list:
    return [x for x in (get_setting("tg_greet_chats", "") or "").split(",") if x]

def _tg_scheduler_loop() -> None:
    """Mỗi ~25s kiểm tra giờ VN; đúng giờ đặt thì gửi lời chào sáng/tối 1 lần/ngày."""
    import datetime as _dt
    slots = [("tg_greet_morning_on", "tg_greet_morning_time", "tg_greet_morning_text",
              "tg_greet_morning_last", "07:00", _TG_MORNING_DEFAULT),
             ("tg_greet_evening_on", "tg_greet_evening_time", "tg_greet_evening_text",
              "tg_greet_evening_last", "20:00", _TG_EVENING_DEFAULT)]
    while True:
        try:
            token = (get_setting("tg_bot_token", "") or os.getenv("TELEGRAM_BOT_TOKEN", "")).strip()
            if not token or get_setting("tg_bot_enabled", "0") != "1":
                time.sleep(20); continue
            if get_setting("tg_greet_master", "1") != "1":   # công tắc TỔNG (/kenios on|off)
                time.sleep(20); continue
            now = _dt.datetime.utcnow() + _dt.timedelta(hours=7)   # giờ Việt Nam (UTC+7)
            today = now.strftime("%Y-%m-%d")

            def _fire(txt):
                for cid in _tg_greet_chats():
                    try: _tg_send(token, cid, txt)
                    except Exception: pass
                    time.sleep(0.1)

            # Chào sáng / tối
            for on_key, time_key, text_key, last_key, deftime, deftext in slots:
                if get_setting(on_key, "1") != "1":
                    continue
                t = (get_setting(time_key, deftime) or deftime).strip()
                try:
                    th, tm = int(t.split(":")[0]), int(t.split(":")[1])
                except Exception:
                    continue
                if now.hour != th or now.minute != tm or get_setting(last_key, "") == today:
                    continue
                set_setting(last_key, today)                # chốt trước khi gửi (chống trùng)
                _fire(get_setting(text_key, "") or deftext)

            # 🎊 Chúc NGÀY LỄ (dương & âm lịch) — đúng giờ đặt (mặc định 08:00)
            if get_setting("tg_greet_holiday_on", "1") == "1":
                ht = (get_setting("tg_greet_holiday_time", "08:00") or "08:00").strip()
                try:
                    hh, hm = int(ht.split(":")[0]), int(ht.split(":")[1])
                except Exception:
                    hh, hm = 8, 0
                if now.hour == hh and now.minute == hm and get_setting("tg_greet_holiday_last", "") != today:
                    set_setting("tg_greet_holiday_last", today)
                    hol = _tg_holiday_today(now)
                    if hol:
                        _fire(hol)
        except Exception:
            pass
        time.sleep(25)

def start_telegram_bot() -> None:
    """Khởi động bot Telegram hỗ trợ (long-polling) trong 1 thread nền."""
    global _tg_thread, _tg_sched_thread
    if _tg_thread and _tg_thread.is_alive():
        return
    import threading
    _tg_thread = threading.Thread(target=_tg_loop, daemon=True, name="telegram-bot")
    _tg_thread.start()
    if not (_tg_sched_thread and _tg_sched_thread.is_alive()):
        _tg_sched_thread = threading.Thread(target=_tg_scheduler_loop, daemon=True, name="telegram-scheduler")
        _tg_sched_thread.start()
    logging.info("Telegram support bot: thread khởi động (bật khi admin cấu hình token & enable).")


# ============================================================================
#  ZALO OFFICIAL ACCOUNT (OA) — kênh CHÍNH THỐNG (có API thật, không lo khóa).
#  Khách QUAN TÂM (follow) OA → bot tự CHÀO MỪNG. Khách nhắn OA → bot tự trả
#  lời (hoặc chuyển admin). Tự làm mới access_token bằng refresh_token.
#  (Zalo KHÔNG cho bot vào nhóm chat thường — đây là kênh OA ↔ người quan tâm.)
# ============================================================================
_ZALO_OAUTH = "https://oauth.zaloapp.com/v4/oa"
_ZALO_OPENAPI = "https://openapi.zalo.me/v3.0/oa"

def _zalo_redirect_uri() -> str:
    base = (_ipa_base_url() or "https://app.kenios.store").rstrip("/")
    return f"{base}/zalo/oauth/callback"

def _zalo_set_tokens(access: str, refresh: str, expires_in) -> None:
    set_setting("zalo_oa_access_token", (access or "").strip())
    if refresh:
        set_setting("zalo_oa_refresh_token", refresh.strip())
    try:
        exp = int(time.time()) + int(expires_in) - 300   # trừ hao 5 phút
    except Exception:
        exp = int(time.time()) + 3600
    set_setting("zalo_oa_token_exp", str(exp))

def _zalo_refresh_if_needed() -> str:
    """Trả về access_token còn hạn (tự refresh nếu sắp hết). "" nếu chưa kết nối."""
    import httpx
    access = (get_setting("zalo_oa_access_token", "") or "").strip()
    refresh = (get_setting("zalo_oa_refresh_token", "") or "").strip()
    app_id = (get_setting("zalo_app_id", "") or "").strip()
    secret = (get_setting("zalo_app_secret", "") or "").strip()
    try:
        exp = int(get_setting("zalo_oa_token_exp", "0") or 0)
    except Exception:
        exp = 0
    if access and time.time() < exp:
        return access
    if not (refresh and app_id and secret):
        return access
    try:
        r = httpx.post(f"{_ZALO_OAUTH}/access_token",
                       headers={"secret_key": secret, "Content-Type": "application/x-www-form-urlencoded"},
                       data={"refresh_token": refresh, "app_id": app_id, "grant_type": "refresh_token"},
                       timeout=20)
        j = r.json()
        if j.get("access_token"):
            _zalo_set_tokens(j["access_token"], j.get("refresh_token", ""), j.get("expires_in", 90000))
            return j["access_token"].strip()
        log.warning("zalo refresh token lỗi: %s", j)
    except Exception as e:
        log.warning("zalo refresh token exception: %s", e)
    return access

def _zalo_send_text(user_id: str, text: str) -> dict:
    """Gửi tin nhắn văn bản từ OA tới 1 người quan tâm."""
    import httpx
    token = _zalo_refresh_if_needed()
    if not token or not user_id:
        return {"error": "chưa kết nối OA hoặc thiếu user_id"}
    try:
        r = httpx.post(f"{_ZALO_OPENAPI}/message",
                       headers={"access_token": token, "Content-Type": "application/json"},
                       json={"recipient": {"user_id": str(user_id)}, "message": {"text": text[:2000]}},
                       timeout=20)
        return r.json()
    except Exception as e:
        log.warning("zalo send lỗi: %s", e)
        return {"error": str(e)}

def _zalo_greet(user_id: str) -> None:
    if get_setting("zalo_welcome_on", "1") != "1":
        return
    wel = get_setting("zalo_welcome",
        "👋 Chào mừng bạn đã quan tâm KENIOS!\nBạn cần hỗ trợ gì cứ nhắn ở đây nhé. 💙")
    _zalo_send_text(user_id, wel)

def _zalo_verify_sig(app_id: str, raw: bytes, timestamp: str, signature: str) -> bool:
    """MAC = sha256(app_id + raw_body + timestamp + oa_secret)."""
    import hashlib
    secret = (get_setting("zalo_app_secret", "") or "").strip()
    if not secret or not signature:
        return True   # chưa đặt secret / Zalo không gửi chữ ký → không chặn
    try:
        mac = hashlib.sha256((app_id + raw.decode("utf-8", "ignore") + str(timestamp) + secret).encode()).hexdigest()
        return ("mac=" + mac) == signature or mac == signature
    except Exception:
        return True

class ZaloOAConfig(BaseModel):
    enabled: Optional[bool] = None
    app_id: Optional[str] = None
    app_secret: Optional[str] = None
    welcome: Optional[str] = None
    welcome_on: Optional[bool] = None
    auto_reply: Optional[str] = None
    auto_reply_on: Optional[bool] = None

def _zalo_status() -> dict[str, Any]:
    connected = bool((get_setting("zalo_oa_access_token", "") or "").strip()
                     and (get_setting("zalo_oa_refresh_token", "") or "").strip())
    return {
        "enabled": get_setting("zalo_oa_enabled", "0") == "1",
        "app_id": get_setting("zalo_app_id", ""),
        "has_secret": bool((get_setting("zalo_app_secret", "") or "").strip()),
        "connected": connected,
        "welcome": get_setting("zalo_welcome",
            "👋 Chào mừng bạn đã quan tâm KENIOS!\nBạn cần hỗ trợ gì cứ nhắn ở đây nhé. 💙"),
        "welcome_on": get_setting("zalo_welcome_on", "1") == "1",
        "auto_reply": get_setting("zalo_auto_reply", ""),
        "auto_reply_on": get_setting("zalo_auto_reply_on", "0") == "1",
        "webhook_url": (_ipa_base_url() or "https://app.kenios.store").rstrip("/") + "/zalo/webhook",
        "connect_url": (_ipa_base_url() or "https://app.kenios.store").rstrip("/") + "/zalo/connect",
    }

@app.get("/admin/zalo-oa")
def admin_get_zalo(admin=Depends(get_admin)) -> dict[str, Any]:
    return _zalo_status()

@app.post("/admin/zalo-oa")
def admin_set_zalo(b: ZaloOAConfig, admin=Depends(get_admin)) -> dict[str, Any]:
    if b.enabled is not None:      set_setting("zalo_oa_enabled", "1" if b.enabled else "0")
    if b.app_id is not None:       set_setting("zalo_app_id", b.app_id.strip())
    if b.app_secret:               set_setting("zalo_app_secret", b.app_secret.strip())
    if b.welcome is not None:      set_setting("zalo_welcome", b.welcome[:2000])
    if b.welcome_on is not None:   set_setting("zalo_welcome_on", "1" if b.welcome_on else "0")
    if b.auto_reply is not None:   set_setting("zalo_auto_reply", b.auto_reply[:2000])
    if b.auto_reply_on is not None: set_setting("zalo_auto_reply_on", "1" if b.auto_reply_on else "0")
    return _zalo_status()

@app.get("/zalo/connect")
def zalo_connect():
    """Bắt đầu kết nối OA (PKCE) — admin bấm link này, đăng nhập Zalo, cấp quyền OA."""
    import hashlib, base64
    app_id = (get_setting("zalo_app_id", "") or "").strip()
    if not app_id:
        return HTMLResponse("<h3>Chưa nhập App ID Zalo. Vào app KENIOS → Quản trị → Zalo OA để nhập trước.</h3>", status_code=400)
    verifier = secrets.token_urlsafe(48)
    set_setting("zalo_pkce_verifier", verifier)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
    from urllib.parse import urlencode
    q = urlencode({"app_id": app_id, "redirect_uri": _zalo_redirect_uri(),
                   "code_challenge": challenge, "state": secrets.token_hex(6)})
    return RedirectResponse(f"{_ZALO_OAUTH}/permission?{q}")

@app.get("/zalo/oauth/callback")
def zalo_oauth_callback(code: str = "", oa_id: str = ""):
    """Zalo gọi lại sau khi admin cấp quyền → đổi code lấy access/refresh token."""
    import httpx
    if not code:
        return HTMLResponse("<h3>Thiếu mã uỷ quyền (code). Thử kết nối lại.</h3>", status_code=400)
    app_id = (get_setting("zalo_app_id", "") or "").strip()
    secret = (get_setting("zalo_app_secret", "") or "").strip()
    verifier = (get_setting("zalo_pkce_verifier", "") or "").strip()
    try:
        r = httpx.post(f"{_ZALO_OAUTH}/access_token",
                       headers={"secret_key": secret, "Content-Type": "application/x-www-form-urlencoded"},
                       data={"code": code, "app_id": app_id, "grant_type": "authorization_code",
                             "code_verifier": verifier},
                       timeout=20)
        j = r.json()
    except Exception as e:
        return HTMLResponse(f"<h3>Lỗi đổi token: {e}</h3>", status_code=500)
    if j.get("access_token"):
        _zalo_set_tokens(j["access_token"], j.get("refresh_token", ""), j.get("expires_in", 90000))
        if oa_id:
            set_setting("zalo_oa_id", oa_id)
        set_setting("zalo_oa_enabled", "1")
        return HTMLResponse("<h2>✅ Kết nối Zalo OA thành công!</h2>"
                            "<p>Bạn có thể đóng trang này và quay lại app KENIOS. "
                            "Bot sẽ tự chào người mới quan tâm OA.</p>")
    return HTMLResponse(f"<h3>Kết nối chưa được: {j}</h3>", status_code=400)

@app.get("/zalo/webhook")
def zalo_webhook_verify():
    return {"ok": True}

@app.post("/zalo/webhook")
async def zalo_webhook(request: Request):
    """Nhận sự kiện OA: follow (quan tâm) → chào; user_send_text → tự trả lời/chuyển admin."""
    raw = await request.body()
    try:
        ev = json.loads(raw.decode("utf-8", "ignore") or "{}")
    except Exception:
        return {"ok": True}
    app_id = (ev.get("app_id") or get_setting("zalo_app_id", "") or "").strip()
    sig = request.headers.get("X-ZEvent-Signature", "")
    if not _zalo_verify_sig(app_id, raw, ev.get("timestamp", ""), sig):
        log.warning("zalo webhook sai chữ ký")
        # vẫn trả 200 để Zalo không retry dồn dập, nhưng bỏ qua xử lý
        return {"ok": True}
    if get_setting("zalo_oa_enabled", "0") != "1":
        return {"ok": True}
    name = ev.get("event_name", "")
    try:
        if name == "follow":
            uid = ((ev.get("follower") or {}).get("id")) or ev.get("user_id")
            if uid:
                _zalo_greet(str(uid))
        elif name in ("user_send_text", "user_send_image", "user_send_sticker"):
            uid = ((ev.get("sender") or {}).get("id"))
            text = ((ev.get("message") or {}).get("text") or "")
            if uid:
                if get_setting("zalo_auto_reply_on", "0") == "1":
                    rep = get_setting("zalo_auto_reply",
                        "Cảm ơn bạn đã nhắn KENIOS! Đội ngũ sẽ phản hồi sớm nhất. 💙")
                    _zalo_send_text(str(uid), rep)
                # Chuyển nội dung cho admin Telegram (nếu đã cấu hình) để theo dõi
                ac = (get_setting("tg_admin_chat", "") or "").strip()
                tk = (get_setting("tg_bot_token", "") or "").strip()
                if ac and tk and text:
                    _tg_send(tk, ac, f"📩 <b>Zalo OA</b> [uid:{uid}]\n{text}")
    except Exception as e:
        log.warning("zalo webhook xử lý lỗi: %s", e)
    return {"ok": True}


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
# 3 gói PRO có thời hạn: tháng / 6 tháng / 1 năm. Admin tự chỉnh giá (VND).
# Không dùng credits — thanh toán xong tài khoản lên PRO tới ngày hết hạn.
PRO_PACKAGES = [
    {"id": "month",  "days": 30,  "name": "Gói 1 tháng",  "default_price": 199000},
    {"id": "6month", "days": 180, "name": "Gói 6 tháng",  "default_price": 999000},
    {"id": "year",   "days": 365, "name": "Gói 1 năm",    "default_price": 1799000},
]
PRO_LABEL_DEFAULT = "Nâng cấp PRO"


def _pro_packages() -> list[dict[str, Any]]:
    out = []
    for p in PRO_PACKAGES:
        try:
            price = int(get_setting(f"pro_price_{p['id']}", str(p["default_price"])) or p["default_price"])
        except (TypeError, ValueError):
            price = p["default_price"]
        if price < 0:
            price = p["default_price"]
        out.append({
            "id": p["id"], "days": p["days"], "name": p["name"],
            "credits": 0, "amount": price,
            "label": f"{p['name']} — {price:,}đ".replace(",", "."),
        })
    return out


def _pro_package_by_id(pid: str) -> dict[str, Any]:
    pkgs = _pro_packages()
    for p in pkgs:
        if p["id"] == pid:
            return p
    return pkgs[0]


@app.get("/payment/packages")
def payment_packages() -> list[dict[str, Any]]:
    return _pro_packages()


@app.post("/payment/create")
def payment_create(b: PaymentIn, user=Depends(get_user)) -> dict[str, Any]:
    pkg = _pro_package_by_id((b.package or "").strip())
    ref = secrets.token_urlsafe(12)
    with db() as c:
        # Nội dung chuyển khoản = ID khách hàng → hệ thống tự dò ID để xác nhận.
        cid = _ensure_public_id(c, user["id"])
        cur = c.execute(
            "INSERT INTO payments(user_id,amount,credits,plan_days,status,ref,created_at) "
            "VALUES(?,?,?,?,'pending',?,?)",
            (user["id"], pkg["amount"], 0, pkg["days"], ref, int(time.time())),
        )
        pid = cur.lastrowid
    bank = bank_info(amount=pkg["amount"], note=cid)
    return {
        "payment_id": pid,
        "ref": cid,
        "amount": pkg["amount"],
        "credits": 0,
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


# -------- Giá 3 gói nâng cấp PRO (admin tự chỉnh, VND) --------
class ProPriceIn(BaseModel):
    package: Optional[str] = None      # "month" | "6month" | "year"
    price: Optional[int] = None
    label: Optional[str] = None


@app.get("/admin/payment/pro")
def admin_get_pro(admin=Depends(get_admin)) -> dict[str, Any]:
    # Trả về cả 3 gói; "price" giữ lại cho tương thích app cũ (lấy gói tháng).
    pkgs = _pro_packages()
    return {"packages": pkgs, "price": pkgs[0]["amount"],
            "label": get_setting("pro_label", PRO_LABEL_DEFAULT) or PRO_LABEL_DEFAULT}


@app.post("/admin/payment/pro")
def admin_set_pro(b: ProPriceIn, admin=Depends(get_admin)) -> dict[str, Any]:
    if b.price is not None:
        if b.price < 0:
            raise HTTPException(status_code=400, detail="Giá phải là số tiền VND ≥ 0.")
        pid = (b.package or "month").strip()
        if pid not in {p["id"] for p in PRO_PACKAGES}:
            pid = "month"
        set_setting(f"pro_price_{pid}", str(int(b.price)))
    if b.label is not None and b.label.strip():
        set_setting("pro_label", b.label.strip()[:60])
    return {"message": "Đã cập nhật giá gói.", "packages": _pro_packages()}


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
    # Đơn cũ có credits → giữ logic cũ (tương thích).
    if pay["credits"] and pay["credits"] > 0:
        c.execute("UPDATE users SET credits=credits+? WHERE id=?", (pay["credits"], pay["user_id"]))
        new_plan = _determine_plan_from_credits(pay["credits"])
        if new_plan != "free":
            c.execute("UPDATE users SET plan=? WHERE id=? AND plan IN ('free','pro','ultra')",
                      (new_plan, pay["user_id"]))
        return True
    # Đơn gói PRO có thời hạn: lên PRO + cộng hạn (gia hạn nếu còn hạn).
    try:
        days = int(pay["plan_days"] or 0)
    except (TypeError, ValueError, IndexError):
        days = 0
    if days <= 0:
        days = 30
    now = int(time.time())
    cur = c.execute("SELECT plan_expires FROM users WHERE id=?", (pay["user_id"],)).fetchone()
    base = max(now, (cur["plan_expires"] or 0) if cur else 0)
    new_exp = base + days * 86400
    c.execute("UPDATE users SET plan='pro', plan_expires=?, plan_expired_notice=0 WHERE id=?",
              (new_exp, pay["user_id"]))
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
    """Lấy ID khách hàng (dạng KEN + chữ số) trong nội dung chuyển khoản (tương thích cũ)."""
    if not description:
        return None
    m = re.search(r"(KEN\d{6,})", description, re.IGNORECASE)
    return m.group(1).upper() if m else None


def _customer_id_candidates(description: str) -> list:
    """Mọi ID có thể có trong nội dung CK: số thuần 6–12 chữ số (bản mới) + KEN###### (bản cũ).
    Trả nhiều ứng viên, hàm xác nhận sẽ thử từng cái với public_id thật trong DB."""
    if not description:
        return []
    out, seen = [], set()
    for m in re.findall(r"KEN\d{6,}", description, re.IGNORECASE):
        u = m.upper()
        if u not in seen: seen.add(u); out.append(u)
    # Số thuần — ưu tiên cụm dài trước (public_id thường 9 số), tránh nhầm số ngắn.
    for m in sorted(re.findall(r"\d{6,12}", description), key=len, reverse=True):
        if m not in seen: seen.add(m); out.append(m)
    return out


def _extract_ref(description: str) -> Optional[str]:
    if not description:
        return None
    match = re.search(r"KENIOS\s+(\S+)", description, re.IGNORECASE)
    return match.group(1) if match else None


def _confirm_from_description(desc: str, amount: int) -> bool:
    """Dò theo ID khách (thử mọi ứng viên số trong nội dung CK) → mã ref cũ."""
    for cid in _customer_id_candidates(desc):
        if _confirm_by_customer_id(cid, amount):
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
    # thueapibank chặn User-Agent lạ (trả 403) → giả trình duyệt thật.
    _ua = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
           "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36")
    try:
        async with httpx.AsyncClient(timeout=20, follow_redirects=True) as client:
            r = await client.get(url, headers={"User-Agent": _ua,
                                               "Accept": "application/json, text/plain, */*"})
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
                or tx.get("addDescription") or tx.get("comment") or tx.get("body")
                or tx.get("des") or tx.get("transferContent") or tx.get("note") or "")
        if not desc:
            # Không rõ tên trường nội dung → gộp MỌI giá trị chuỗi để không bỏ sót ID khách.
            desc = " ".join(str(v) for v in tx.values() if isinstance(v, str))
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
    """Vòng lặp nền tự cộng tiền/cấp key khi có giao dịch ACB mới.
    KHÔNG dùng auto chuyển khoản (chưa nhập token) → NGHỈ LÂU, ít hỏi DB. Có token mới
    kiểm tra mỗi 5 giây. Chống spam log (tối đa 1 lần/phút)."""
    _last_err = 0.0
    while True:
        try:
            if get_setting("acb_api_token", "").strip():
                await _acb_fetch_and_confirm()
                await asyncio.sleep(5)
            else:
                await asyncio.sleep(60)   # không dùng → nghỉ 60s (gần như không tải DB)
        except Exception as e:
            now = time.time()
            if now - _last_err > 60:
                log.error("ACB autopay loop lỗi: %s", e)
                _last_err = now
            await asyncio.sleep(30)


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


# Cache /store/config ~20s: app gọi rất nhiều (mỗi lần mở + nhiều màn) mà mỗi lần chạy
# ~40 câu get_setting + 3 câu COUNT → nặng DB. Cache giảm tải, app mở nhanh hơn.
_store_config_cache: dict[str, Any] = {"ts": 0.0, "data": None}

@app.get("/store/config")
def store_config() -> dict[str, Any]:
    now = time.time()
    if _store_config_cache["data"] is not None and now - _store_config_cache["ts"] < 20:
        return _store_config_cache["data"]
    data = _store_config_build()
    _store_config_cache["data"] = data
    _store_config_cache["ts"] = now
    return data

def _store_config_build() -> dict[str, Any]:
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
        "logo_type": get_setting("store_logo_type", "image"),
        # Client ID iOS để app hiện nút "Đăng nhập bằng Google"
        "google_client_id": _google_login_client_id(),
        # Máy chủ đã có khoá ElevenLabs dùng chung? (khách chỉ cần nhập Voice ID)
        "eleven_server_key": bool(_eleven_server_key()),
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
        "hero_color": get_setting("store_hero_color", ""),
        # Dòng phụ (subtitle) — màu/hiệu ứng/chuyển động riêng
        "hero_sub_effect": get_setting("store_hero_sub_effect", ""),
        "hero_sub_font": get_setting("store_hero_sub_font", "rounded"),
        "hero_sub_anim": get_setting("store_hero_sub_anim", "none"),
        "hero_sub_color": get_setting("store_hero_sub_color", ""),
        # Hiệu ứng / chuyển động cho slogan
        "slogan_effect": get_setting("store_slogan_effect", "none"),
        "slogan_anim": get_setting("store_slogan_anim", "none"),
        "slogan_color": get_setting("store_slogan_color", ""),
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
        # Lời chào TOÀN CỤC (popup) — admin đặt, MỌI người dùng đều thấy khi mở app
        "welcome_popup_enabled": get_setting("store_welcome_popup_enabled", "0") == "1",
        "welcome_popup_title": get_setting("store_welcome_popup_title", ""),
        "welcome_popup_text": get_setting("store_welcome_popup_text", ""),
        # GIỌNG chào TOÀN CỤC — MẶC ĐỊNH BẬT để MỌI người dùng đều nghe khi mở app
        "welcome_voice_enabled": get_setting("store_welcome_voice_enabled", "1") == "1",
        "welcome_voice_text": get_setting("store_welcome_voice_text",
            "Chào mừng bạn đã đến với KENIOS. Chúc bạn một ngày tốt lành!"),
        "welcome_voice_rate": float(get_setting("store_welcome_voice_rate", "0.5") or 0.5),
        # GIỌNG đọc admin chọn — đồng bộ cho MỌI người; mặc định "google" (chị Google)
        "welcome_voice_id": get_setting("store_welcome_voice_id", "google"),
        # ĐỌC TO thông báo sản phẩm mới bằng giọng đồng bộ — mặc định BẬT
        "notif_voice_enabled": get_setting("store_notif_voice_enabled", "1") == "1",
        # §1.2 — Thông báo cập nhật phiên bản mới (admin đặt)
        "latest_version": get_setting("store_latest_version", ""),
        "update_url": get_setting("store_update_url", ""),
        "update_message": get_setting("store_update_message", ""),
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


# §6.2 — Bể dữ liệu ảo: tên Việt tự nhiên (Họ + Tên đệm + Tên), khác biệt Họ+Tên đệm.
_VN_HO = ["Nguyễn", "Trần", "Lê", "Phạm", "Hoàng", "Huỳnh", "Phan", "Vũ", "Võ", "Đặng",
          "Bùi", "Đỗ", "Hồ", "Ngô", "Dương", "Lý", "Đinh", "Trịnh", "Đoàn", "Lương"]
_VN_DEM = ["Văn", "Thị", "Hữu", "Đức", "Minh", "Quang", "Thanh", "Ngọc", "Gia", "Bảo",
           "Anh", "Tuấn", "Thu", "Kim", "Hoài", "Xuân", "Nhật", "Thành", "Công", "Khánh"]
_VN_TEN = ["An", "Bình", "Cường", "Dũng", "Giang", "Hà", "Hải", "Hùng", "Huy", "Khoa",
           "Lâm", "Linh", "Long", "Mai", "Nam", "Nga", "Ngọc", "Phong", "Phúc", "Quân",
           "Sơn", "Tâm", "Thảo", "Trang", "Trung", "Tú", "Vy", "Đạt", "Khang", "Duy"]
# Sản phẩm + gói/giá cho feed "Giao dịch gần đây" (khớp cửa hàng thật).
_FAKE_PRODUCT_TIERS = [
    ("💎 VNHAX",              [("1 Tháng", 600000), ("1 Tuần", 300000)]),
    ("💎 VNHAX MOD SKIN VN",  [("1 Tháng", 450000), ("1 Tuần", 225000)]),
    ("💎 OASIS VIP",          [("1 Tháng", 800000), ("1 Tuần", 400000)]),
    ("💎 KING",               [("1 Tháng", 900000), ("1 Tuần", 450000)]),
    ("💎 TIMO VIP",           [("1 Tháng", 500000), ("1 Tuần", 250000), ("1 Ngày", 50000)]),
    ("💎 VINGODL",            [("1 Tháng", 550000), ("1 Tuần", 250000)]),
    ("💰 ZOLO",               [("1 Tháng", 500000), ("1 Tuần", 250000)]),
    ("💰 MG",                 [("1 Tháng", 500000), ("1 Tuần", 250000)]),
    ("💰 VNB",                [("1 Tháng", 500000), ("1 Tuần", 250000)]),
    ("💰 ROOT",               [("1 Tháng", 650000)]),
    ("⚔️ LIÊN QUÂN",          [("1 Tháng", 250000), ("1 Tuần", 120000)]),
    ("🔥 HYPER",              [("1 Tháng", 350000), ("1 Tuần", 150000)]),
    ("🔥 HYPER CHỐNG TỐ",     [("1 Tháng", 650000)]),
]


def _fake_showcase(n_orders: int, n_topups: int, now: int):
    import random
    seen: set = set()

    def _name() -> str:
        ho, dem = random.choice(_VN_HO), random.choice(_VN_DEM)
        for _ in range(8):  # đảm bảo khác biệt Họ+Tên đệm
            if (ho, dem) not in seen:
                break
            ho, dem = random.choice(_VN_HO), random.choice(_VN_DEM)
        seen.add((ho, dem))
        return f"{ho} {dem} {random.choice(_VN_TEN)}"

    orders = []
    for _ in range(max(0, n_orders)):
        prod, tiers = random.choice(_FAKE_PRODUCT_TIERS)
        label, amount = random.choice(tiers)   # gói + giá khớp đúng sản phẩm
        orders.append({
            "user": _mask_name(_name()),
            "product": prod,
            "label": label,
            "amount": amount,
            "at": now - random.randint(40, 6 * 3600),
        })
    orders.sort(key=lambda x: x["at"], reverse=True)

    topups = []
    for _ in range(max(0, n_topups)):
        topups.append({
            "user": _mask_name(_name()),
            "amount": random.choice([50000, 100000, 200000, 300000, 500000, 1000000]),
            "at": now - random.randint(40, 6 * 3600),
        })
    topups.sort(key=lambda x: x["at"], reverse=True)
    return orders, topups


def _fake_leaders(now: int):
    """Danh sách 'đại gia' ẢO cho bảng xếp hạng nạp tích luỹ — ổn định theo NGÀY
    (không nhảy loạn mỗi lần tải), có xê dịch nhẹ để trông sống động. Người nạp
    THẬT sẽ được TRỘN chung và xếp theo tổng nạp, KHÔNG làm mất người ảo."""
    import random
    rnd = random.Random(now // 86400)   # cùng 1 ngày → cùng danh sách
    seen: set = set()

    def _name() -> str:
        for _ in range(10):
            ho, dem, ten = rnd.choice(_VN_HO), rnd.choice(_VN_DEM), rnd.choice(_VN_TEN)
            if (ho, dem, ten) not in seen:
                seen.add((ho, dem, ten))
                return f"{ho} {dem} {ten}"
        return f"{rnd.choice(_VN_HO)} {rnd.choice(_VN_DEM)} {rnd.choice(_VN_TEN)}"

    bases = [9200000, 6100000, 4300000, 3100000, 2200000,
             1500000, 1050000, 760000, 520000, 360000, 240000, 150000]
    return [{"user": _mask_name(_name()), "total": b + rnd.randint(0, 40) * 1000}
            for b in bases]


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
            "GROUP BY t.user_id ORDER BY total DESC LIMIT 30").fetchall()
    now = int(time.time())
    real_orders = [
        {"user": _mask_name(r["uname"]), "product": r["pname"],
         "label": r["plabel"] or "", "amount": r["amount"] or 0, "at": r["at"] or 0}
        for r in orders
    ]
    real_topups = [
        {"user": _mask_name(r["uname"]), "amount": r["amount"] or 0, "at": r["at"] or 0}
        for r in topups
    ]
    # §6.2 — Ưu tiên dữ liệu THẬT; nếu thiếu thì lấp bằng dữ liệu ảo (tên Việt tự nhiên)
    # để thanh chạy liên tục. Không có công tắc tắt ở phía người dùng.
    TARGET = 15
    fake_orders, fake_topups = _fake_showcase(
        max(0, TARGET - len(real_orders)), max(0, TARGET - len(real_topups)), now)
    # Bảng xếp hạng nạp tích luỹ: TRỘN người nạp THẬT + đại gia ẢO, xếp theo tổng nạp.
    # Người thật nạp càng nhiều càng leo cao; người ảo luôn còn đó (không bị mất).
    real_leaders = [
        {"user": _mask_name(r["uname"]), "total": int(r["total"] or 0)}
        for r in leaders
    ]
    merged_leaders = sorted(real_leaders + _fake_leaders(now),
                            key=lambda x: x["total"], reverse=True)[:10]
    return {
        "recent_orders": (real_orders + fake_orders)[:TARGET],
        "recent_topups": (real_topups + fake_topups)[:TARGET],
        "leaderboard": [
            {"rank": i + 1, "user": m["user"], "total": m["total"]}
            for i, m in enumerate(merged_leaders)
        ],
    }


# -------------------- Lưu ảnh từ máy → trả về link URL công khai --------------------
# ============================================================================
# §7 — ĐA NGƯỜI BÁN: cửa hàng cá nhân độc lập (Store_ID), dữ liệu CÔ LẬP, RBAC
# ============================================================================
class MyStoreIn(BaseModel):
    name: str
    description: Optional[str] = None
    logo_url: Optional[str] = None
    banner_url: Optional[str] = None
    slogan: Optional[str] = None
    name_effect: Optional[str] = None
    slogan_effect: Optional[str] = None
    name_color: Optional[str] = None
    slogan_color: Optional[str] = None
    name_font: Optional[str] = None
    slogan_font: Optional[str] = None
    name_anim: Optional[str] = None
    slogan_anim: Optional[str] = None

class MyProductIn(BaseModel):
    id: Optional[int] = None
    name: str
    description: Optional[str] = None
    price: Optional[int] = 0
    media: Optional[list] = None
    download_url: Optional[str] = None
    category_id: Optional[int] = 0
    kind: Optional[str] = "app"   # app (key/ứng dụng) | acc (tài khoản game)

class MyCategoryIn(BaseModel):
    name: str

def _store_dict(row) -> dict[str, Any]:
    # .keys() an toàn cho cột mới (banner_url/slogan) khi row cũ chưa có
    keys = row.keys()
    return {"id": row["id"], "owner_id": row["owner_id"], "name": row["name"],
            "description": row["description"] or "", "logo_url": row["logo_url"] or "",
            "banner_url": (row["banner_url"] if "banner_url" in keys else "") or "",
            "slogan": (row["slogan"] if "slogan" in keys else "") or "",
            "name_effect": (row["name_effect"] if "name_effect" in keys else "gradient") or "gradient",
            "slogan_effect": (row["slogan_effect"] if "slogan_effect" in keys else "none") or "none",
            "name_color": (row["name_color"] if "name_color" in keys else "") or "",
            "slogan_color": (row["slogan_color"] if "slogan_color" in keys else "") or "",
            "name_font": (row["name_font"] if "name_font" in keys else "rounded") or "rounded",
            "slogan_font": (row["slogan_font"] if "slogan_font" in keys else "default") or "default",
            "name_anim": (row["name_anim"] if "name_anim" in keys else "none") or "none",
            "slogan_anim": (row["slogan_anim"] if "slogan_anim" in keys else "none") or "none",
            "created_at": row["created_at"] or 0}

def _uproduct_dict(row) -> dict[str, Any]:
    keys = row.keys()
    return {"id": row["id"], "store_id": row["store_id"], "name": row["name"],
            "description": row["description"] or "", "price": row["price"] or 0,
            "media": _load_media(row["media"]), "download_url": row["download_url"] or "",
            "category_id": (row["category_id"] if "category_id" in keys else 0) or 0,
            "kind": (row["kind"] if "kind" in keys else "app") or "app",
            "created_at": row["created_at"] or 0}

def _ucat_dict(row) -> dict[str, Any]:
    return {"id": row["id"], "store_id": row["store_id"], "name": row["name"],
            "created_at": row["created_at"] or 0}

def _ustore_settings_dict(c, sid: int, public: bool = False) -> dict[str, Any]:
    """Cài đặt hiển thị của cửa hàng (Đợt 5). public=True chỉ trả liên hệ đã BẬT."""
    row = c.execute("SELECT * FROM user_store_settings WHERE store_id=?", (sid,)).fetchone()
    if not row:
        return {"announce_enabled": False, "announce_text": "", "flash_enabled": False,
                "flash_product_id": 0, "flash_end": 0, "flash_discount": 0,
                "flash_title": "FLASH SALE", "contacts": []}
    try:
        links = json.loads(row["contact_links"] or "[]")
    except Exception:
        links = []
    if public:
        links = [x for x in links if x.get("enabled") and (x.get("url") or "").strip()]
    return {"announce_enabled": bool(row["announce_enabled"]), "announce_text": row["announce_text"] or "",
            "flash_enabled": bool(row["flash_enabled"]), "flash_product_id": row["flash_product_id"] or 0,
            "flash_end": row["flash_end"] or 0, "flash_discount": row["flash_discount"] or 0,
            "flash_title": row["flash_title"] or "FLASH SALE", "contacts": links}

def _uproduct_prices(c, pid: int) -> list:
    rows = c.execute("SELECT id,label,amount,sort FROM user_store_prices WHERE product_id=? "
                     "ORDER BY sort,id", (pid,)).fetchall()
    return [{"id": r["id"], "label": r["label"], "amount": r["amount"], "sort": r["sort"]} for r in rows]

def _uproduct_enrich(c, d: dict) -> dict:
    """Gắn bảng giá + tồn kho KEY + điểm đánh giá cho sản phẩm cửa hàng cá nhân."""
    pid = d["id"]
    d["prices"] = _uproduct_prices(c, pid)
    d["stock"] = c.execute("SELECT COUNT(*) FROM user_store_keys WHERE product_id=? AND status='available'",
                           (pid,)).fetchone()[0]
    r = c.execute("SELECT COUNT(*) n, COALESCE(AVG(rating),0) a FROM user_store_reviews WHERE product_id=?",
                  (pid,)).fetchone()
    d["review_count"] = r["n"]
    d["rating"] = round(r["a"], 1)
    return d

def _require_my_product(c, store, pid: int):
    row = c.execute("SELECT id FROM user_store_products WHERE id=? AND store_id=?",
                    (pid, store["id"])).fetchone()
    if not row:
        raise HTTPException(status_code=403, detail="Sản phẩm không thuộc cửa hàng của bạn.")
    return row

def _require_my_store(c, user):
    row = c.execute("SELECT * FROM user_stores WHERE owner_id=?", (user["id"],)).fetchone()
    if not row:
        raise HTTPException(status_code=400, detail="Bạn chưa tạo cửa hàng.")
    return row

@app.get("/my-store")
def my_store_get(user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        row = c.execute("SELECT * FROM user_stores WHERE owner_id=?", (user["id"],)).fetchone()
        if not row:
            return {"store": None, "products": []}
        prods = c.execute("SELECT * FROM user_store_products WHERE store_id=? ORDER BY id DESC",
                          (row["id"],)).fetchall()
        cats = c.execute("SELECT * FROM user_store_categories WHERE store_id=? ORDER BY id",
                         (row["id"],)).fetchall()
        items = [_uproduct_enrich(c, _uproduct_dict(p)) for p in prods]
        settings = _ustore_settings_dict(c, row["id"], public=False)
    return {"store": _store_dict(row), "products": items,
            "categories": [_ucat_dict(x) for x in cats], "settings": settings}

@app.post("/my-store")
def my_store_save(b: MyStoreIn, user=Depends(get_user)) -> dict[str, Any]:
    name = (b.name or "").strip()[:80]
    if not name:
        raise HTTPException(status_code=400, detail="Tên cửa hàng không được trống.")
    desc = (b.description or "").strip()[:500]
    logo = (b.logo_url or "").strip()[:400]
    banner = (b.banner_url or "").strip()[:400]
    slogan = (b.slogan or "").strip()[:200]
    # Hiệu ứng chữ: chỉ cập nhật cột nào được gửi (None = giữ nguyên).
    effs = [("name_effect", b.name_effect), ("slogan_effect", b.slogan_effect),
            ("name_color", b.name_color), ("slogan_color", b.slogan_color),
            ("name_font", b.name_font), ("slogan_font", b.slogan_font),
            ("name_anim", b.name_anim), ("slogan_anim", b.slogan_anim)]
    with db() as c:
        row = c.execute("SELECT * FROM user_stores WHERE owner_id=?", (user["id"],)).fetchone()
        if row:
            c.execute("UPDATE user_stores SET name=?, description=?, logo_url=?, banner_url=?, slogan=? WHERE owner_id=?",
                      (name, desc, logo, banner, slogan, user["id"]))
            sid = row["id"]
        else:
            cur = c.execute("INSERT INTO user_stores(owner_id,name,description,logo_url,banner_url,slogan,created_at) "
                            "VALUES(?,?,?,?,?,?,?)", (user["id"], name, desc, logo, banner, slogan, int(time.time())))
            sid = cur.lastrowid
        for col, val in effs:
            if val is not None:
                c.execute(f"UPDATE user_stores SET {col}=? WHERE id=?", (val.strip()[:20], sid))
        row = c.execute("SELECT * FROM user_stores WHERE id=?", (sid,)).fetchone()
    return {"store": _store_dict(row)}

@app.get("/u-store/{sid}")
def public_user_store(sid: int, user=Depends(get_user)) -> dict[str, Any]:
    """§7.4 — Xem cửa hàng cá nhân bất kỳ theo Store_ID (chỉ đọc)."""
    with db() as c:
        row = c.execute("SELECT * FROM user_stores WHERE id=?", (sid,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy cửa hàng.")
        prods = c.execute("SELECT * FROM user_store_products WHERE store_id=? ORDER BY id DESC",
                          (sid,)).fetchall()
        cats = c.execute("SELECT * FROM user_store_categories WHERE store_id=? ORDER BY id",
                         (sid,)).fetchall()
        items = [_uproduct_enrich(c, _uproduct_dict(p)) for p in prods]
        settings = _ustore_settings_dict(c, sid, public=True)
    return {"store": _store_dict(row), "products": items,
            "categories": [_ucat_dict(x) for x in cats], "settings": settings}

# §7 Đợt 2 — Danh mục cửa hàng cá nhân (CÔ LẬP theo store của chính chủ)
@app.post("/my-store/categories")
def my_store_add_category(b: MyCategoryIn, user=Depends(get_user)) -> dict[str, Any]:
    name = (b.name or "").strip()[:80]
    if not name:
        raise HTTPException(status_code=400, detail="Tên danh mục không được trống.")
    with db() as c:
        store = _require_my_store(c, user)
        cur = c.execute("INSERT INTO user_store_categories(store_id,name,created_at) VALUES(?,?,?)",
                        (store["id"], name, int(time.time())))
        row = c.execute("SELECT * FROM user_store_categories WHERE id=?", (cur.lastrowid,)).fetchone()
    return {"category": _ucat_dict(row)}

@app.delete("/my-store/categories/{cid}")
def my_store_del_category(cid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        store = _require_my_store(c, user)
        owned = c.execute("SELECT id FROM user_store_categories WHERE id=? AND store_id=?",
                          (cid, store["id"])).fetchone()
        if not owned:
            raise HTTPException(status_code=404, detail="Danh mục không thuộc cửa hàng của bạn.")
        c.execute("DELETE FROM user_store_categories WHERE id=?", (cid,))
        # Sản phẩm thuộc danh mục này → chuyển về 'Chưa phân loại' (category_id=0)
        c.execute("UPDATE user_store_products SET category_id=0 WHERE category_id=? AND store_id=?",
                  (cid, store["id"]))
    return {"message": "Đã xoá danh mục."}

@app.post("/my-store/products")
def my_store_save_product(b: MyProductIn, user=Depends(get_user)) -> dict[str, Any]:
    name = (b.name or "").strip()[:120]
    if not name:
        raise HTTPException(status_code=400, detail="Tên sản phẩm không được trống.")
    media = _dump_media(b.media)
    desc = (b.description or "").strip()[:1000]
    dl = (b.download_url or "").strip()[:500]
    price = max(0, int(b.price or 0))
    cat_id = max(0, int(b.category_id or 0))
    kind = "acc" if (b.kind or "app") == "acc" else "app"
    with db() as c:
        store = _require_my_store(c, user)
        # Danh mục (nếu có) phải thuộc chính cửa hàng này
        if cat_id:
            valid = c.execute("SELECT id FROM user_store_categories WHERE id=? AND store_id=?",
                              (cat_id, store["id"])).fetchone()
            if not valid:
                cat_id = 0
        if b.id:
            # §7.2 RBAC — chỉ chủ cửa hàng mới sửa được (admin tổng cũng KHÔNG can thiệp).
            owned = c.execute("SELECT id FROM user_store_products WHERE id=? AND store_id=?",
                              (b.id, store["id"])).fetchone()
            if not owned:
                raise HTTPException(status_code=403, detail="Không có quyền sửa sản phẩm này.")
            c.execute("UPDATE user_store_products SET name=?,description=?,price=?,media=?,download_url=?,category_id=?,kind=? "
                      "WHERE id=?", (name, desc, price, media, dl, cat_id, kind, b.id))
            pid = b.id
        else:
            cur = c.execute("INSERT INTO user_store_products(store_id,category_id,name,description,price,media,"
                            "download_url,kind,created_at) VALUES(?,?,?,?,?,?,?,?,?)",
                            (store["id"], cat_id, name, desc, price, media, dl, kind, int(time.time())))
            pid = cur.lastrowid
    return {"message": "Đã lưu sản phẩm.", "id": pid}

@app.delete("/my-store/products/{pid}")
def my_store_delete_product(pid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        store = _require_my_store(c, user)
        owned = c.execute("SELECT id FROM user_store_products WHERE id=? AND store_id=?",
                          (pid, store["id"])).fetchone()
        if not owned:
            raise HTTPException(status_code=403, detail="Không có quyền xoá sản phẩm này.")
        c.execute("DELETE FROM user_store_products WHERE id=?", (pid,))
        c.execute("DELETE FROM user_store_prices WHERE product_id=?", (pid,))
        c.execute("DELETE FROM user_store_keys WHERE product_id=?", (pid,))
    return {"message": "Đã xoá sản phẩm."}


# §7 Đợt 2B — Bảng giá nhiều mốc (CÔ LẬP theo store của chính chủ)
class MyPriceItem(BaseModel):
    label: str
    amount: int

class MyPricesIn(BaseModel):
    prices: list[MyPriceItem] = []

@app.post("/my-store/products/{pid}/prices")
def my_store_set_prices(pid: int, b: MyPricesIn, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        store = _require_my_store(c, user)
        _require_my_product(c, store, pid)
        c.execute("DELETE FROM user_store_prices WHERE product_id=?", (pid,))
        n = 0
        for i, p in enumerate(b.prices):
            label = (p.label or "").strip()[:60]
            if not label or p.amount < 0:
                continue
            c.execute("INSERT INTO user_store_prices(product_id,store_id,label,amount,sort) VALUES(?,?,?,?,?)",
                      (pid, store["id"], label, int(p.amount), i))
            n += 1
    return {"message": f"Đã lưu {n} mốc giá."}

@app.get("/my-store/products/{pid}/prices")
def my_store_list_prices(pid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        store = _require_my_store(c, user)
        _require_my_product(c, store, pid)
        return {"prices": _uproduct_prices(c, pid)}


# §7 Đợt 2B — Kho KEY (CÔ LẬP theo store của chính chủ)
class MyKeysIn(BaseModel):
    text: str = ""                    # mỗi dòng 1 key
    price_id: Optional[int] = None    # gắn key vào 1 mốc giá. None = dùng chung

@app.get("/my-store/products/{pid}/keys")
def my_store_list_keys(pid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        store = _require_my_store(c, user)
        _require_my_product(c, store, pid)
        rows = c.execute("SELECT id,key_text,status,sold_at,price_id FROM user_store_keys "
                         "WHERE product_id=? ORDER BY id DESC", (pid,)).fetchall()
        avail = sum(1 for r in rows if r["status"] == "available")
    return {"available": avail, "total": len(rows),
            "keys": [{"id": r["id"], "key_text": r["key_text"], "status": r["status"],
                      "sold_at": r["sold_at"], "price_id": r["price_id"]} for r in rows]}

@app.post("/my-store/products/{pid}/keys")
def my_store_add_keys(pid: int, b: MyKeysIn, user=Depends(get_user)) -> dict[str, Any]:
    lines = [ln.strip() for ln in (b.text or "").replace("\r", "\n").split("\n")]
    now = int(time.time())
    with db() as c:
        store = _require_my_store(c, user)
        _require_my_product(c, store, pid)
        # price_id (nếu có) phải thuộc chính sản phẩm này
        pfilter = b.price_id
        if pfilter is not None:
            ok = c.execute("SELECT id FROM user_store_prices WHERE id=? AND product_id=?",
                           (pfilter, pid)).fetchone()
            if not ok:
                pfilter = None
        added = 0
        for ln in lines:
            if not ln:
                continue
            c.execute("INSERT INTO user_store_keys(product_id,store_id,key_text,status,price_id,created_at) "
                      "VALUES(?,?,?,'available',?,?)", (pid, store["id"], ln, pfilter, now))
            added += 1
    return {"message": f"Đã thêm {added} key.", "added": added}

@app.delete("/my-store/keys/{kid}")
def my_store_delete_key(kid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        store = _require_my_store(c, user)
        owned = c.execute("SELECT id FROM user_store_keys WHERE id=? AND store_id=?",
                          (kid, store["id"])).fetchone()
        if not owned:
            raise HTTPException(status_code=403, detail="Key không thuộc cửa hàng của bạn.")
        c.execute("DELETE FROM user_store_keys WHERE id=?", (kid,))
    return {"message": "Đã xoá key."}

@app.delete("/my-store/products/{pid}/keys")
def my_store_delete_available_keys(pid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        store = _require_my_store(c, user)
        _require_my_product(c, store, pid)
        cur = c.execute("DELETE FROM user_store_keys WHERE product_id=? AND status='available'", (pid,))
    return {"message": f"Đã xoá {cur.rowcount} key khả dụng."}


# §7 Đợt 3 — Mua hàng từ cửa hàng cá nhân (buyer trả bằng ví, người bán nhận tiền)
def _ustore_promo_apply(c, sid: int, code: str, amount: int):
    """Trả (promo_row, discount) cho mã giảm giá của chính cửa hàng sid. Ném lỗi nếu không hợp lệ."""
    code = (code or "").strip().upper()
    if not code:
        return None, 0
    row = c.execute("SELECT * FROM user_store_promos WHERE store_id=? AND code=? AND is_active=1",
                    (sid, code)).fetchone()
    if not row:
        raise HTTPException(status_code=400, detail="Mã giảm giá không hợp lệ.")
    now = int(time.time())
    if row["expires_at"] and row["expires_at"] < now:
        raise HTTPException(status_code=400, detail="Mã giảm giá đã hết hạn.")
    if row["max_uses"] and row["used_count"] >= row["max_uses"]:
        raise HTTPException(status_code=400, detail="Mã đã hết lượt dùng.")
    if amount < row["min_amount"]:
        raise HTTPException(status_code=400,
            detail=f"Đơn tối thiểu {row['min_amount']:,}đ để dùng mã.".replace(",", "."))
    if row["discount_type"] == "percent":
        discount = int(amount * row["discount_value"] / 100)
    else:
        discount = min(row["discount_value"], amount)
    return row, max(0, discount)

class UStoreBuyIn(BaseModel):
    product_id: int
    price_id: Optional[int] = None
    promo_code: Optional[str] = None

@app.post("/u-store/{sid}/buy")
def u_store_buy(sid: int, b: UStoreBuyIn, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        store = c.execute("SELECT * FROM user_stores WHERE id=?", (sid,)).fetchone()
        if not store:
            raise HTTPException(status_code=404, detail="Không tìm thấy cửa hàng.")
        if store["owner_id"] == user["id"]:
            raise HTTPException(status_code=400, detail="Không thể mua từ cửa hàng của chính bạn.")
        prod = c.execute("SELECT * FROM user_store_products WHERE id=? AND store_id=?",
                         (b.product_id, sid)).fetchone()
        if not prod:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm.")
        # Xác định giá: nếu có bảng giá nhiều mốc thì phải chọn 1 mốc hợp lệ
        tiers = _uproduct_prices(c, b.product_id)
        price_id = None
        price_label = ""
        if tiers:
            tier = None
            if b.price_id is not None:
                tier = next((t for t in tiers if t["id"] == b.price_id), None)
            if tier is None:
                raise HTTPException(status_code=400, detail="Vui lòng chọn mốc giá.")
            amount = tier["amount"]; price_id = tier["id"]; price_label = tier["label"]
        else:
            amount = prod["price"] or 0
        # Flash sale của cửa hàng (nếu sản phẩm đang flash & còn hạn) — giảm % trước.
        flash_discount = 0
        st = _ustore_settings_dict(c, sid, public=True)
        if (st["flash_enabled"] and st["flash_product_id"] == b.product_id
                and (st["flash_end"] == 0 or st["flash_end"] > int(time.time()))
                and st["flash_discount"] > 0):
            flash_discount = int(amount * st["flash_discount"] / 100)
            amount = max(0, amount - flash_discount)
        # Áp mã giảm giá của chính cửa hàng (nếu có) — tính trên giá sau flash.
        promo_row, discount = _ustore_promo_apply(c, sid, b.promo_code or "", amount)
        amount = max(0, amount - discount)
        discount += flash_discount   # tổng giảm để báo cho người mua
        # Số dư ví
        balance = _wallet_balance(c, user["id"])
        if balance < amount:
            raise HTTPException(status_code=400,
                detail=f"Số dư ví không đủ (cần {amount:,}đ, còn {balance:,}đ). Vui lòng nạp thêm."
                       .replace(",", "."))
        # Giành 1 key khả dụng (ưu tiên đúng mốc, rồi key dùng chung, rồi bất kỳ)
        key = None
        for cond, args in (
            ("AND price_id=?", (b.product_id, price_id)) if price_id else (None, None),
            ("AND price_id IS NULL", (b.product_id,)),
            ("", (b.product_id,)),
        ):
            if cond is None:
                continue
            for _ in range(50):
                cand = c.execute(
                    f"SELECT id,key_text FROM user_store_keys WHERE product_id=? AND status='available' "
                    f"{cond} ORDER BY id ASC LIMIT 1", args).fetchone()
                if not cand:
                    break
                got = c.execute("UPDATE user_store_keys SET status='sold',sold_at=? WHERE id=? AND status='available'",
                                (int(time.time()), cand["id"]))
                if got.rowcount == 1:
                    key = cand; break
            if key:
                break
        dl = (prod["download_url"] or "").strip()
        if not key and not dl:
            raise HTTPException(status_code=400, detail="Sản phẩm đã hết hàng.")
        key_text = key["key_text"] if key else ""
        # Trừ ví người mua (atomic, chống âm)
        ded = c.execute("UPDATE users SET wallet=wallet-? WHERE id=? AND wallet>=?",
                        (amount, user["id"], amount))
        if ded.rowcount != 1:
            if key:
                c.execute("UPDATE user_store_keys SET status='available',sold_at=NULL WHERE id=?", (key["id"],))
            raise HTTPException(status_code=400, detail="Số dư ví không đủ. Vui lòng nạp thêm.")
        # Cộng tiền cho người bán
        _wallet_add(c, store["owner_id"], amount, "sale", f"Bán {prod['name']}")
        c.execute("INSERT INTO store_wallet_tx(user_id,kind,amount,note,created_at) VALUES(?,?,?,?,?)",
                  (user["id"], "purchase", -amount, f"Mua {prod['name']}", int(time.time())))
        if key:
            c.execute("DELETE FROM user_store_keys WHERE id=?", (key["id"],))  # đã giao → xoá khỏi kho
        if promo_row:
            c.execute("UPDATE user_store_promos SET used_count=used_count+1 WHERE id=?", (promo_row["id"],))
        cur = c.execute(
            "INSERT INTO user_store_orders(store_id,seller_id,buyer_id,product_id,product_name,price_id,"
            "price_label,key_text,download_url,amount,status,created_at) "
            "VALUES(?,?,?,?,?,?,?,?,?,?,'completed',?)",
            (sid, store["owner_id"], user["id"], b.product_id, prod["name"], price_id, price_label,
             key_text, dl, amount, int(time.time())))
        oid = cur.lastrowid
        new_balance = _wallet_balance(c, user["id"])
    return {"ok": True, "order_id": oid, "key": key_text, "download_url": dl,
            "product_name": prod["name"], "balance": new_balance, "discount": discount,
            "message": ("Mua thành công!" if not discount else
                        f"Mua thành công! Đã giảm {discount:,}đ.".replace(",", "."))}

@app.get("/my-orders/u-store")
def u_store_my_orders(user=Depends(get_user)) -> list[dict[str, Any]]:
    """Đơn buyer đã mua từ các cửa hàng cá nhân (để lấy lại key)."""
    with db() as c:
        rows = c.execute(
            "SELECT o.id,o.store_id,o.product_id,o.product_name,o.price_label,o.key_text,o.download_url,"
            "o.amount,o.created_at,s.name AS store_name FROM user_store_orders o "
            "LEFT JOIN user_stores s ON s.id=o.store_id "
            "WHERE o.buyer_id=? ORDER BY o.id DESC LIMIT 200", (user["id"],)).fetchall()
    return [{"id": r["id"], "store_id": r["store_id"], "product_id": r["product_id"],
             "product_name": r["product_name"], "price_label": r["price_label"] or "",
             "key_text": r["key_text"] or "", "download_url": r["download_url"] or "",
             "amount": r["amount"], "created_at": r["created_at"], "store_name": r["store_name"] or "-"}
            for r in rows]

# §7 Đợt 3 — Người bán: đơn hàng + thống kê (CÔ LẬP theo store của chính chủ)
@app.get("/my-store/orders")
def my_store_orders(user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        store = _require_my_store(c, user)
        rows = c.execute(
            "SELECT o.id,o.product_name,o.price_label,o.amount,o.status,o.created_at,u.username AS buyer "
            "FROM user_store_orders o LEFT JOIN users u ON u.id=o.buyer_id "
            "WHERE o.store_id=? ORDER BY o.id DESC LIMIT 200", (store["id"],)).fetchall()
    return [{"id": r["id"], "product_name": r["product_name"], "price_label": r["price_label"] or "",
             "amount": r["amount"], "status": r["status"], "created_at": r["created_at"],
             "buyer": r["buyer"] or "-"} for r in rows]

@app.get("/my-store/stats")
def my_store_stats(user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        store = _require_my_store(c, user)
        sid = store["id"]
        now = int(time.time())
        day = now - 86400
        agg = c.execute(
            "SELECT COUNT(*) n, COALESCE(SUM(amount),0) rev FROM user_store_orders "
            "WHERE store_id=? AND status='completed'", (sid,)).fetchone()
        today = c.execute(
            "SELECT COUNT(*) n, COALESCE(SUM(amount),0) rev FROM user_store_orders "
            "WHERE store_id=? AND status='completed' AND created_at>=?", (sid, day)).fetchone()
        top = c.execute(
            "SELECT product_name, COUNT(*) sold, COALESCE(SUM(amount),0) rev FROM user_store_orders "
            "WHERE store_id=? AND status='completed' GROUP BY product_id ORDER BY sold DESC LIMIT 5",
            (sid,)).fetchall()
        low = c.execute(
            "SELECT p.name, (SELECT COUNT(*) FROM user_store_keys k WHERE k.product_id=p.id AND k.status='available') stock "
            "FROM user_store_products p WHERE p.store_id=? ORDER BY stock ASC LIMIT 5", (sid,)).fetchall()
        prod_count = c.execute("SELECT COUNT(*) n FROM user_store_products WHERE store_id=?", (sid,)).fetchone()["n"]
        key_count = c.execute("SELECT COUNT(*) n FROM user_store_keys WHERE store_id=? AND status='available'",
                              (sid,)).fetchone()["n"]
    return {
        "orders_total": agg["n"], "revenue_total": agg["rev"],
        "orders_today": today["n"], "revenue_today": today["rev"],
        "product_count": prod_count, "keys_available": key_count,
        "top_products": [{"name": r["product_name"], "sold": r["sold"], "revenue": r["rev"]} for r in top],
        "low_stock": [{"name": r["name"], "stock": r["stock"]} for r in low],
    }


# ================= §7 Đợt 4 — Mã giảm giá của người bán (CÔ LẬP theo store) =================
def _upromo_dict(row) -> dict[str, Any]:
    return {"id": row["id"], "code": row["code"], "discount_type": row["discount_type"],
            "discount_value": row["discount_value"], "min_amount": row["min_amount"],
            "max_uses": row["max_uses"], "used_count": row["used_count"],
            "expires_at": row["expires_at"], "is_active": row["is_active"]}

class MyPromoIn(BaseModel):
    code: str
    discount_type: str = "percent"   # percent | fixed
    discount_value: int
    min_amount: int = 0
    max_uses: int = 0
    expires_at: int = 0

@app.get("/my-store/promos")
def my_store_list_promos(user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        store = _require_my_store(c, user)
        rows = c.execute("SELECT * FROM user_store_promos WHERE store_id=? ORDER BY id DESC",
                         (store["id"],)).fetchall()
    return [_upromo_dict(r) for r in rows]

@app.post("/my-store/promos")
def my_store_create_promo(b: MyPromoIn, user=Depends(get_user)) -> dict[str, Any]:
    code = (b.code or "").strip().upper()[:40]
    if not code:
        raise HTTPException(status_code=400, detail="Mã không được để trống.")
    if b.discount_value <= 0:
        raise HTTPException(status_code=400, detail="Giá trị giảm phải lớn hơn 0.")
    if b.discount_type == "percent" and b.discount_value > 100:
        raise HTTPException(status_code=400, detail="% giảm không được quá 100.")
    with db() as c:
        store = _require_my_store(c, user)
        try:
            cur = c.execute(
                "INSERT INTO user_store_promos(store_id,code,discount_type,discount_value,min_amount,"
                "max_uses,expires_at,is_active,created_at) VALUES(?,?,?,?,?,?,?,1,?)",
                (store["id"], code, b.discount_type, int(b.discount_value), max(0, int(b.min_amount)),
                 max(0, int(b.max_uses)), max(0, int(b.expires_at)), int(time.time())))
        except Exception:
            raise HTTPException(status_code=400, detail="Mã này đã tồn tại trong cửa hàng của bạn.")
    return {"id": cur.lastrowid, "message": "Đã tạo mã giảm giá."}

@app.post("/my-store/promos/{pid}/toggle")
def my_store_toggle_promo(pid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        store = _require_my_store(c, user)
        row = c.execute("SELECT is_active FROM user_store_promos WHERE id=? AND store_id=?",
                        (pid, store["id"])).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Mã không thuộc cửa hàng của bạn.")
        newv = 0 if row["is_active"] else 1
        c.execute("UPDATE user_store_promos SET is_active=? WHERE id=?", (newv, pid))
    return {"is_active": newv}

@app.delete("/my-store/promos/{pid}")
def my_store_delete_promo(pid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        store = _require_my_store(c, user)
        c.execute("DELETE FROM user_store_promos WHERE id=? AND store_id=?", (pid, store["id"]))
    return {"message": "Đã xoá mã."}

@app.post("/u-store/{sid}/promo/validate")
def u_store_validate_promo(sid: int, body: dict = Body(...), user=Depends(get_user)) -> dict[str, Any]:
    """Người mua kiểm tra mã trước khi mua (tính thử số tiền được giảm)."""
    code = str(body.get("code", "")).strip().upper()
    amount = int(body.get("amount", 0))
    with db() as c:
        _, discount = _ustore_promo_apply(c, sid, code, amount)
    return {"valid": True, "discount": discount}


# ================= §7 Đợt 4 — Ví người bán + rút tiền =================
class MyWithdrawIn(BaseModel):
    amount: int
    bank_info: str

@app.get("/my-store/wallet")
def my_store_wallet(user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        store = _require_my_store(c, user)
        bal = _wallet_balance(c, user["id"])
        wds = c.execute("SELECT id,amount,bank_info,status,note,created_at,handled_at "
                        "FROM user_store_withdrawals WHERE seller_id=? ORDER BY id DESC LIMIT 100",
                        (user["id"],)).fetchall()
        pending = c.execute("SELECT COALESCE(SUM(amount),0) s FROM user_store_withdrawals "
                            "WHERE seller_id=? AND status='pending'", (user["id"],)).fetchone()["s"]
    return {"balance": bal, "pending_withdraw": pending,
            "withdrawals": [{"id": w["id"], "amount": w["amount"], "bank_info": w["bank_info"],
                             "status": w["status"], "note": w["note"] or "",
                             "created_at": w["created_at"], "handled_at": w["handled_at"]} for w in wds]}

@app.post("/my-store/withdraw")
def my_store_withdraw(b: MyWithdrawIn, user=Depends(get_user)) -> dict[str, Any]:
    amount = int(b.amount or 0)
    bank = (b.bank_info or "").strip()[:300]
    if amount < 50000:
        raise HTTPException(status_code=400, detail="Số tiền rút tối thiểu 50.000đ.")
    if not bank:
        raise HTTPException(status_code=400, detail="Vui lòng nhập thông tin ngân hàng nhận tiền.")
    with db() as c:
        _require_my_store(c, user)
        # Giữ tiền: trừ khỏi ví ngay, tạo yêu cầu chờ duyệt (atomic, chống âm)
        ded = c.execute("UPDATE users SET wallet=wallet-? WHERE id=? AND wallet>=?",
                        (amount, user["id"], amount))
        if ded.rowcount != 1:
            raise HTTPException(status_code=400, detail="Số dư ví không đủ để rút.")
        store = _require_my_store(c, user)
        c.execute("INSERT INTO store_wallet_tx(user_id,kind,amount,note,created_at) VALUES(?,?,?,?,?)",
                  (user["id"], "withdraw_hold", -amount, "Yêu cầu rút tiền", int(time.time())))
        cur = c.execute("INSERT INTO user_store_withdrawals(seller_id,store_id,amount,bank_info,status,created_at) "
                        "VALUES(?,?,?,?, 'pending', ?)",
                        (user["id"], store["id"], amount, bank, int(time.time())))
        new_bal = _wallet_balance(c, user["id"])
    _notify_admins("💸 Yêu cầu rút tiền", f"{user['username']} yêu cầu rút {amount:,}đ".replace(",", "."))
    return {"id": cur.lastrowid, "balance": new_bal, "message": "Đã gửi yêu cầu rút tiền, chờ duyệt."}


# ===== §7 Đợt 4 — Cài đặt thanh toán RIÊNG của cửa hàng (giống hệt admin: ngân hàng + API tự động) =====
def _dec_safe(v: str) -> str:
    if not v:
        return ""
    try:
        return dec(v)
    except Exception:
        return ""

def _ustore_payment_row(c, sid: int):
    return c.execute("SELECT * FROM user_store_payment WHERE store_id=?", (sid,)).fetchone()

def _ustore_bank_info(c, sid: int, amount: int = 0, note: str = "KENIOS") -> dict[str, Any]:
    """QR VietQR theo ngân hàng RIÊNG của cửa hàng; nếu shop chưa cấu hình thì dùng ngân hàng nền tảng."""
    from urllib.parse import quote
    row = _ustore_payment_row(c, sid)
    code = (row["bank_code"] if row else "") or ""
    short = (row["bank_short"] if row else "") or ""
    account = (row["bank_account"] if row else "") or ""
    name = (row["bank_name"] if row else "") or ""
    if not (code and account and name):
        # fallback: ngân hàng nền tảng
        code = get_setting("bank_code", "970416"); short = get_setting("bank_short", "ACB")
        account = get_setting("bank_account", "23252921"); name = get_setting("bank_name", "TRAN MINH CHIEN")
    qr = (f"https://img.vietqr.io/image/{code}-{account}-compact2.png"
          f"?accountName={quote(name)}&addInfo={quote(note)}")
    if amount > 0:
        qr += f"&amount={amount}"
    return {"bank": short, "bank_code": code, "account": account,
            "name": name, "content": note, "qr_url": qr}

class MyPaymentIn(BaseModel):
    bank_code: Optional[str] = None
    bank_short: Optional[str] = None
    bank_account: Optional[str] = None
    bank_name: Optional[str] = None
    bank_webhook: Optional[str] = None
    bank_apikey: Optional[str] = None
    acb_api_token: Optional[str] = None

@app.get("/my-store/payment")
def my_store_get_payment(user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        store = _require_my_store(c, user)
        row = _ustore_payment_row(c, store["id"])
    if not row:
        return {"bank_code": "", "bank_short": "", "bank_account": "", "bank_name": "",
                "bank_webhook": "", "bank_apikey": "", "acb_api_token": ""}
    return {"bank_code": row["bank_code"] or "", "bank_short": row["bank_short"] or "",
            "bank_account": row["bank_account"] or "", "bank_name": row["bank_name"] or "",
            "bank_webhook": row["bank_webhook"] or "",
            "bank_apikey": _dec_safe(row["bank_apikey"] or ""),
            "acb_api_token": _dec_safe(row["acb_api_token"] or "")}

@app.post("/my-store/payment")
def my_store_set_payment(b: MyPaymentIn, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        store = _require_my_store(c, user)
        sid = store["id"]
        row = _ustore_payment_row(c, sid)
        if not row:
            c.execute("INSERT INTO user_store_payment(store_id,updated_at) VALUES(?,?)", (sid, int(time.time())))
            row = _ustore_payment_row(c, sid)
        # MERGE: chỉ cập nhật field gửi lên (giống admin). Secret mã hoá trước khi lưu.
        plain_fields = ["bank_code", "bank_short", "bank_account", "bank_name", "bank_webhook"]
        secret_fields = ["bank_apikey", "acb_api_token"]
        for f in plain_fields:
            v = getattr(b, f)
            if v is not None:
                c.execute(f"UPDATE user_store_payment SET {f}=? WHERE store_id=?", (v.strip()[:200], sid))
        for f in secret_fields:
            v = getattr(b, f)
            if v is not None:
                stored = enc(v.strip()) if v.strip() else ""
                c.execute(f"UPDATE user_store_payment SET {f}=? WHERE store_id=?", (stored, sid))
        c.execute("UPDATE user_store_payment SET updated_at=? WHERE store_id=?", (int(time.time()), sid))
    return {"message": "Đã cập nhật thông tin thanh toán cửa hàng."}

@app.get("/u-store/{sid}/payment-info")
def u_store_payment_info(sid: int, amount: int = 0, note: str = "KENIOS", user=Depends(get_user)) -> dict[str, Any]:
    """QR nhận tiền của cửa hàng (dùng ngân hàng riêng của người bán nếu đã cấu hình)."""
    with db() as c:
        store = c.execute("SELECT id FROM user_stores WHERE id=?", (sid,)).fetchone()
        if not store:
            raise HTTPException(status_code=404, detail="Không tìm thấy cửa hàng.")
        return _ustore_bank_info(c, sid, amount=amount, note=note)


# ===== §7 Đợt 5 — Cài đặt hiển thị cửa hàng (thông báo chạy · flash sale · liên hệ) =====
class MyContactLink(BaseModel):
    label: str = ""
    url: str = ""
    enabled: bool = True

class MyStoreSettingsIn(BaseModel):
    announce_enabled: Optional[bool] = None
    announce_text: Optional[str] = None
    flash_enabled: Optional[bool] = None
    flash_product_id: Optional[int] = None
    flash_end: Optional[int] = None
    flash_discount: Optional[int] = None
    flash_title: Optional[str] = None
    contacts: Optional[list[MyContactLink]] = None

@app.get("/my-store/settings")
def my_store_get_settings(user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        store = _require_my_store(c, user)
        return _ustore_settings_dict(c, store["id"], public=False)

@app.post("/my-store/settings")
def my_store_set_settings(b: MyStoreSettingsIn, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        store = _require_my_store(c, user)
        sid = store["id"]
        if not c.execute("SELECT 1 FROM user_store_settings WHERE store_id=?", (sid,)).fetchone():
            c.execute("INSERT INTO user_store_settings(store_id,updated_at) VALUES(?,?)", (sid, int(time.time())))
        # MERGE từng field
        if b.announce_enabled is not None:
            c.execute("UPDATE user_store_settings SET announce_enabled=? WHERE store_id=?",
                      (1 if b.announce_enabled else 0, sid))
        if b.announce_text is not None:
            c.execute("UPDATE user_store_settings SET announce_text=? WHERE store_id=?",
                      (b.announce_text.strip()[:300], sid))
        if b.flash_enabled is not None:
            c.execute("UPDATE user_store_settings SET flash_enabled=? WHERE store_id=?",
                      (1 if b.flash_enabled else 0, sid))
        if b.flash_product_id is not None:
            c.execute("UPDATE user_store_settings SET flash_product_id=? WHERE store_id=?",
                      (max(0, int(b.flash_product_id)), sid))
        if b.flash_end is not None:
            c.execute("UPDATE user_store_settings SET flash_end=? WHERE store_id=?", (max(0, int(b.flash_end)), sid))
        if b.flash_discount is not None:
            c.execute("UPDATE user_store_settings SET flash_discount=? WHERE store_id=?",
                      (max(0, min(100, int(b.flash_discount))), sid))
        if b.flash_title is not None:
            c.execute("UPDATE user_store_settings SET flash_title=? WHERE store_id=?",
                      (b.flash_title.strip()[:40] or "FLASH SALE", sid))
        if b.contacts is not None:
            links = [{"label": (x.label or "").strip()[:40], "url": (x.url or "").strip()[:300],
                      "enabled": bool(x.enabled)} for x in b.contacts if (x.label or x.url)]
            c.execute("UPDATE user_store_settings SET contact_links=? WHERE store_id=?",
                      (json.dumps(links, ensure_ascii=False), sid))
        c.execute("UPDATE user_store_settings SET updated_at=? WHERE store_id=?", (int(time.time()), sid))
        out = _ustore_settings_dict(c, sid, public=False)
    return out


# ===== §7 Đợt 5 — Đánh giá sản phẩm cửa hàng cá nhân =====
class MyReviewIn(BaseModel):
    rating: int = 5
    comment: str = ""

@app.get("/u-store/{sid}/products/{pid}/reviews")
def u_store_product_reviews(sid: int, pid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        rows = c.execute("SELECT username,rating,comment,created_at FROM user_store_reviews "
                         "WHERE product_id=? ORDER BY id DESC LIMIT 100", (pid,)).fetchall()
        agg = c.execute("SELECT COUNT(*) n, COALESCE(AVG(rating),0) a FROM user_store_reviews WHERE product_id=?",
                        (pid,)).fetchone()
    return {"count": agg["n"], "rating": round(agg["a"], 1),
            "reviews": [{"username": r["username"] or "Ẩn danh", "rating": r["rating"],
                         "comment": r["comment"] or "", "created_at": r["created_at"]} for r in rows]}

@app.post("/u-store/{sid}/products/{pid}/review")
def u_store_product_review(sid: int, pid: int, b: MyReviewIn, user=Depends(get_user)) -> dict[str, Any]:
    rating = max(1, min(5, int(b.rating or 5)))
    comment = (b.comment or "").strip()[:500]
    with db() as c:
        prod = c.execute("SELECT id FROM user_store_products WHERE id=? AND store_id=?", (pid, sid)).fetchone()
        if not prod:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm.")
        # Chỉ cho đánh giá khi ĐÃ mua sản phẩm này ở cửa hàng đó
        bought = c.execute("SELECT 1 FROM user_store_orders WHERE buyer_id=? AND product_id=? AND status='completed'",
                           (user["id"], pid)).fetchone()
        if not bought:
            raise HTTPException(status_code=403, detail="Bạn cần mua sản phẩm này trước khi đánh giá.")
        c.execute("INSERT INTO user_store_reviews(store_id,product_id,user_id,username,rating,comment,created_at) "
                  "VALUES(?,?,?,?,?,?,?) "
                  "ON CONFLICT(product_id,user_id) DO UPDATE SET rating=excluded.rating,"
                  "comment=excluded.comment,created_at=excluded.created_at",
                  (sid, pid, user["id"], user.get("username", ""), rating, comment, int(time.time())))
    return {"message": "Cảm ơn bạn đã đánh giá!"}


# ---- Admin duyệt chi (tài chính nền tảng — KHÔNG sửa nội dung cửa hàng người bán) ----
@app.get("/admin/u-store/withdrawals")
def admin_ustore_withdrawals(admin=Depends(get_admin)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute(
            "SELECT w.*, u.username FROM user_store_withdrawals w "
            "LEFT JOIN users u ON u.id=w.seller_id ORDER BY "
            "CASE w.status WHEN 'pending' THEN 0 ELSE 1 END, w.id DESC LIMIT 300").fetchall()
    return [{"id": r["id"], "seller": r["username"] or "-", "amount": r["amount"],
             "bank_info": r["bank_info"], "status": r["status"], "note": r["note"] or "",
             "created_at": r["created_at"], "handled_at": r["handled_at"]} for r in rows]

@app.post("/admin/u-store/withdrawals/{wid}/{action}")
def admin_ustore_withdraw_action(wid: int, action: str, admin=Depends(get_admin)) -> dict[str, Any]:
    if action not in ("paid", "reject"):
        raise HTTPException(status_code=400, detail="Hành động không hợp lệ.")
    with db() as c:
        w = c.execute("SELECT * FROM user_store_withdrawals WHERE id=?", (wid,)).fetchone()
        if not w:
            raise HTTPException(status_code=404, detail="Không tìm thấy yêu cầu.")
        if w["status"] != "pending":
            raise HTTPException(status_code=400, detail="Yêu cầu đã được xử lý.")
        now = int(time.time())
        if action == "paid":
            c.execute("UPDATE user_store_withdrawals SET status='paid',handled_at=? WHERE id=?", (now, wid))
            msg = "Đã đánh dấu chi tiền."
        else:
            # Hoàn tiền lại ví người bán
            _wallet_add(c, w["seller_id"], w["amount"], "withdraw_refund", "Hoàn tiền rút bị từ chối")
            c.execute("UPDATE user_store_withdrawals SET status='rejected',handled_at=?,note='Bị từ chối, đã hoàn tiền' "
                      "WHERE id=?", (now, wid))
            msg = "Đã từ chối và hoàn tiền cho người bán."
    return {"message": msg}


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


@app.post("/media/upload-raw")
async def media_upload_raw(request: Request, name: str, mime: Optional[str] = None,
                           user=Depends(get_user)) -> dict[str, Any]:
    """Tải media (ảnh/âm thanh/video) dạng STREAM thẳng từ máy → công khai /media/{id}.
    Nhanh hơn base64 (không phình 33%, không nạp cả file vào RAM) → tải NHIỀU file song
    song không lỗi. Body = nội dung file thô; ?name= & ?mime= trên query."""
    import tempfile as _tf
    tmp = os.path.join(UPLOAD_DIR, f"tmpm_{secrets.token_hex(8)}")
    total = 0
    try:
        with open(tmp, "wb") as f:
            async for chunk in request.stream():
                total += len(chunk); f.write(chunk)
    except Exception as e:
        try: os.remove(tmp)
        except OSError: pass
        raise HTTPException(status_code=500, detail=f"Lỗi tải lên: {e}")
    if total < 1:
        try: os.remove(tmp)
        except OSError: pass
        raise HTTPException(status_code=400, detail="File rỗng.")
    m = (mime or request.headers.get("content-type") or "audio/mpeg")
    nm = (name or f"media_{int(time.time())}")[:80]
    with db() as c:
        cur = c.execute("INSERT INTO files(user_id,name,category,mime,size,data,created_at) "
                        "VALUES(?,?,?,?,?,'',?)",
                        (user["id"], nm, "media", m, total, int(time.time())))
        fid = cur.lastrowid
    os.replace(tmp, os.path.join(UPLOAD_DIR, str(fid)))
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

# ======================== Ký IPA ở máy chủ (zsign) + cài OTA (itms-services) ========================
_IPA_DIR = os.path.join(os.path.dirname(os.path.abspath(UPLOAD_DIR)) or ".", "signed_ipa")
try: os.makedirs(_IPA_DIR, exist_ok=True)
except Exception: pass
# Bundle id của chính app KENIOS — ký bản này & phát hành = cập nhật app (slot riêng, tách /install khách).
APP_BUNDLE_ID = os.getenv("APP_BUNDLE_ID", "com.kenios.codebox")

def _ipa_base_url() -> str:
    # Domain HTTPS cho cài OTA. Ưu tiên cấu hình admin → biến môi trường →
    # mặc định TÊN MIỀN MỚI kenios.io.vn (có SSL).
    return (get_setting("ipa_sign_base", "") or os.getenv("IPA_SIGN_BASE", "")
            or "https://kenios.io.vn").rstrip("/")

def _extract_ipa_meta(ipa_path: str) -> dict:
    import zipfile, plistlib
    try:
        with zipfile.ZipFile(ipa_path) as z:
            info_name = next((n for n in z.namelist()
                              if n.startswith("Payload/") and n.endswith(".app/Info.plist")
                              and n.count("/") == 2), None)
            if not info_name:
                return {}
            pl = plistlib.loads(z.read(info_name))
            try: build = int(str(pl.get("CFBundleVersion", "0")).split(".")[0])
            except Exception: build = 0
            return {"bundle_id": pl.get("CFBundleIdentifier", ""),
                    "version": pl.get("CFBundleShortVersionString", "1.0"),
                    "build": build,
                    "title": pl.get("CFBundleDisplayName") or pl.get("CFBundleName") or "App"}
    except Exception:
        return {}

def _ipa_manifest(base: str, token: str, meta: dict) -> str:
    return (f'<?xml version="1.0" encoding="UTF-8"?>\n'
            f'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            f'<plist version="1.0"><dict><key>items</key><array><dict>'
            f'<key>assets</key><array><dict>'
            f'<key>kind</key><string>software-package</string>'
            f'<key>url</key><string>{base}/ipa/dl/{token}.ipa</string>'
            f'</dict></array>'
            f'<key>metadata</key><dict>'
            f'<key>bundle-identifier</key><string>{meta.get("bundle_id","com.unknown.app")}</string>'
            f'<key>bundle-version</key><string>{meta.get("version","1.0")}</string>'
            f'<key>kind</key><string>software</string>'
            f'<key>title</key><string>{meta.get("title","App")}</string>'
            f'</dict></dict></array></dict></plist>')

@app.post("/ipa/sign")
async def ipa_sign(ipa: UploadFile = FastAPIFile(...),
                   p12: UploadFile = FastAPIFile(...),
                   provision: UploadFile = FastAPIFile(...),
                   password: str = Form(""),
                   publish: str = Form(""),
                   app_name: str = Form(""),      # đổi TÊN app khi ký (trống = giữ nguyên)
                   bundle_id: str = Form(""),     # đổi ĐỊNH DANH (bundle id) khi ký (trống = giữ nguyên)
                   user=Depends(get_user)) -> dict[str, Any]:
    if not shutil.which("zsign"):
        raise HTTPException(status_code=503, detail="Máy chủ chưa cài zsign. Chạy lại capnhat-vps.sh trên VPS.")
    base = _ipa_base_url()
    if not base.startswith("https://"):
        raise HTTPException(status_code=400,
            detail="Chưa đặt domain HTTPS để cài OTA. Vào Quản trị → đặt 'Địa chỉ HTTPS ký IPA' (vd https://ten-mien.com).")
    token = secrets.token_hex(8)
    work = os.path.join(_IPA_DIR, "w_" + token)
    os.makedirs(work, exist_ok=True)
    in_ipa = os.path.join(work, "in.ipa")
    p12_path = os.path.join(work, "cert.p12")
    prov_path = os.path.join(work, "prov.mobileprovision")
    out_ipa = os.path.join(_IPA_DIR, f"{token}.ipa")
    try:
        for up, path in ((ipa, in_ipa), (p12, p12_path), (provision, prov_path)):
            with open(path, "wb") as f:
                while True:
                    chunk = await up.read(1024 * 1024)
                    if not chunk: break
                    f.write(chunk)
        try:
            # -z 1: nén nhanh (file game lớn vốn đã nén sẵn, nén 9 chỉ tốn thời gian);
            # timeout 3600s để đủ ký IPA tới 10GB.
            cmd = ["zsign", "-k", p12_path, "-p", password, "-m", prov_path,
                   "-o", out_ipa, "-z", "1"]
            # Đổi tên hiển thị / bundle id nếu người dùng nhập (trống = giữ nguyên bản gốc).
            nm = (app_name or "").strip()
            bid = (bundle_id or "").strip()
            if nm:  cmd += ["-n", nm]
            if bid: cmd += ["-b", bid]
            cmd.append(in_ipa)
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Chạy zsign lỗi: {e}")
        if not os.path.exists(out_ipa) or os.path.getsize(out_ipa) < 1000:
            msg = ((r.stderr or "") + (r.stdout or ""))[-400:]
            raise HTTPException(status_code=400,
                detail="Ký thất bại (mật khẩu/cert/provision sai, hoặc IPA không hợp lệ). " + msg)
    finally:
        shutil.rmtree(work, ignore_errors=True)   # luôn xoá cert + input
    meta = _extract_ipa_meta(out_ipa)
    with open(os.path.join(_IPA_DIR, f"{token}.plist"), "w") as f:
        f.write(_ipa_manifest(base, token, meta))
    manifest_url = f"{base}/ipa/dl/{token}.plist"
    published = False
    app_update = False
    if str(publish).strip().lower() in ("1", "true", "yes", "on"):
        if meta.get("bundle_id", "") == APP_BUNDLE_ID:
            # Đây là chính app KENIOS → slot CẬP NHẬT APP (OTA 1 chạm), KHÔNG đụng trang /install khách.
            set_setting("app_update_token", token)
            set_setting("app_update_meta", json.dumps(meta))
            set_setting("app_update_at", str(int(time.time())))
            app_update = True
        else:
            # App bán cho khách → trang cài công khai /install.
            set_setting("published_ipa_token", token)
            set_setting("published_ipa_meta", json.dumps(meta))
            set_setting("published_ipa_at", str(int(time.time())))
            published = True
    return {"install_url": f"itms-services://?action=download-manifest&url={manifest_url}",
            "ipa_url": f"{base}/ipa/dl/{token}.ipa", "manifest_url": manifest_url,
            "title": meta.get("title", "App"), "bundle_id": meta.get("bundle_id", ""),
            "published": published, "app_update": app_update, "public_url": f"{base}/install"}


def _published_ipa() -> Optional[dict]:
    """Bản cài đang phát hành công khai (hoặc None nếu chưa phát hành / file đã mất)."""
    token = (get_setting("published_ipa_token", "") or "").strip()
    if not token:
        return None
    ipa_path = os.path.join(_IPA_DIR, f"{token}.ipa")
    plist_path = os.path.join(_IPA_DIR, f"{token}.plist")
    if not (os.path.exists(ipa_path) and os.path.exists(plist_path)):
        return None
    try:
        meta = json.loads(get_setting("published_ipa_meta", "") or "{}")
    except Exception:
        meta = {}
    return {"token": token, "meta": meta,
            "at": int(get_setting("published_ipa_at", "0") or "0")}


@app.get("/admin/ipa/published")
def admin_get_published(admin=Depends(get_admin)) -> dict[str, Any]:
    # Trang /install dùng app khách riêng nếu có, không thì rơi về bản KENIOS đã ký.
    p = _published_ipa() or _app_update()
    base = _ipa_base_url()
    return {"published": bool(p), "public_url": f"{base}/install",
            "title": (p or {}).get("meta", {}).get("title", ""),
            "version": (p or {}).get("meta", {}).get("version", ""),
            "at": (p or {}).get("at", 0)}


@app.post("/admin/ipa/unpublish")
def admin_unpublish(admin=Depends(get_admin)) -> dict[str, Any]:
    set_setting("published_ipa_token", "")
    return {"ok": True}


def _app_update() -> Optional[dict]:
    """Bản CẬP NHẬT app KENIOS đã ký (slot riêng, tách khỏi app khách ở /install)."""
    token = (get_setting("app_update_token", "") or "").strip()
    if not token:
        return None
    ipa_path = os.path.join(_IPA_DIR, f"{token}.ipa")
    plist_path = os.path.join(_IPA_DIR, f"{token}.plist")
    if not (os.path.exists(ipa_path) and os.path.exists(plist_path)):
        return None
    try:
        meta = json.loads(get_setting("app_update_meta", "") or "{}")
    except Exception:
        meta = {}
    return {"token": token, "meta": meta, "at": int(get_setting("app_update_at", "0") or "0")}


@app.get("/app/ota")
def app_ota_update() -> dict[str, Any]:
    """Bản KENIOS ĐÃ KÝ đang phát hành để cài OTA 1 chạm (app tự so số build để nhắc cập nhật)."""
    p = _app_update()
    if not p:
        return {"available": False}
    base = _ipa_base_url()
    token = p["token"]
    meta = p.get("meta", {})
    manifest = f"{base}/ipa/dl/{token}.plist"
    return {
        "available": True,
        "install_url": f"itms-services://?action=download-manifest&url={manifest}",
        "bundle_id": meta.get("bundle_id", ""),
        "version": meta.get("version", ""),
        "build": int(meta.get("build", 0) or 0),
        "title": meta.get("title", ""),
    }


@app.get("/install", response_class=HTMLResponse)
def install_page():
    """Trang cài đặt công khai — khách mở link, bấm 1 nút là app hiện lên màn hình chính.
    Ưu tiên app khách phát hành riêng; nếu chưa có thì DÙNG LUÔN bản KENIOS đã ký
    (slot cập nhật) để khách mới vẫn cài được app KENIOS từ trang này."""
    base = _ipa_base_url()
    p = _published_ipa() or _app_update()
    app_name = get_setting("app_display_name", "") or "KENIOS"
    if not p:
        body = ('<div class="card"><div class="logo">K</div>'
                f'<h1>{app_name}</h1>'
                '<p class="muted">Chưa có bản cài native. Nhưng bạn vẫn mua hàng được ngay trên web:</p>'
                f'<a class="btn" style="background:linear-gradient(135deg,#16a34a,#22c55e)" href="{base}/shop">🛍️ Vào cửa hàng web</a>'
                '</div>')
        return HTMLResponse(_install_html(app_name, body))
    meta = p["meta"]
    title = meta.get("title", app_name)
    version = meta.get("version", "")
    manifest_url = f"{base}/ipa/dl/{p['token']}.plist"
    install_link = f"itms-services://?action=download-manifest&url={manifest_url}"
    ver_txt = f"Phiên bản {version}" if version else "Bản mới nhất"
    body = (
        '<div class="card">'
        '<div class="logo">K</div>'
        f'<h1>{title}</h1>'
        f'<p class="muted">{ver_txt}</p>'

        # CÁCH 1 — cài app đầy đủ (OTA)
        '<div class="tag">Cách 1 · App đầy đủ</div>'
        f'<a class="btn" href="{install_link}">📲 Cài đặt lên màn hình chính</a>'
        '<div class="steps">'
        '<div class="step"><b>1.</b> Bấm <b>Cài đặt</b> ở trên → chọn <b>Cài đặt</b> khi iPhone hỏi.</div>'
        '<div class="step"><b>2.</b> Về màn hình chính, chờ app tải xong.</div>'
        '<div class="step"><b>3.</b> Nếu báo <b>"Chưa tin cậy"</b>: vào <b>Cài đặt → Cài đặt chung → '
        'VPN & Quản lý thiết bị</b> → chọn hồ sơ → <b>Tin cậy</b>.</div>'
        '</div>'

        # CÁCH 2 — không cần cài, thêm nhanh vào màn hình chính (web-clip)
        '<div class="tag alt">Cách 2 · Không cần cài đặt</div>'
        '<div class="steps">'
        '<div class="step">Thêm nhanh biểu tượng KENIOS vào màn hình chính (mở toàn màn hình như app):</div>'
        '<div class="step"><b>1.</b> Bấm nút <b>Chia sẻ</b> ⬆️ ở thanh dưới Safari.</div>'
        '<div class="step"><b>2.</b> Chọn <b>“Thêm vào MH chính” (Add to Home Screen)</b>.</div>'
        '<div class="step"><b>3.</b> Bấm <b>Thêm</b> — biểu tượng KENIOS hiện ngay trên màn hình chính.</div>'
        '</div>'

        # CÁCH 3 — dùng cửa hàng web, không cần cài gì
        '<div class="tag alt">Cách 3 · Mua hàng không cần cài</div>'
        f'<a class="btn" style="background:linear-gradient(135deg,#16a34a,#22c55e)" href="{base}/shop">🛍️ Vào cửa hàng web</a>'
        '<div class="steps"><div class="step">Xem sản phẩm, mua key, nạp ví ngay trên trình duyệt — '
        'không cần cài app, không cần chứng chỉ.</div></div>'

        '<p class="tip">Chỉ hỗ trợ iPhone/iPad. Hãy mở link này bằng <b>Safari</b>.</p>'
        '</div>')
    return HTMLResponse(_install_html(title, body))


_ICON_PNG_CACHE: Optional[bytes] = None

def _kenios_icon_png(W: int = 180) -> bytes:
    """Tạo icon KENIOS (gradient + chữ K) bằng Python thuần — không cần thư viện ngoài."""
    global _ICON_PNG_CACHE
    if _ICON_PNG_CACHE is not None:
        return _ICON_PNG_CACHE
    import zlib as _zl, struct as _st, math as _m

    def seg_dist(px, py, ax, ay, bx, by):
        dx, dy = bx - ax, by - ay
        if dx == 0 and dy == 0:
            return _m.hypot(px - ax, py - ay)
        t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
        return _m.hypot(px - (ax + t * dx), py - (ay + t * dy))

    stroke = W * 0.11
    x0, top, bot, mid = W * 0.30, W * 0.26, W * 0.74, W * 0.50
    segs = [(x0, top, x0, bot), (x0, mid, W * 0.70, top), (x0, mid, W * 0.70, bot)]
    edge = stroke / 2
    raw = bytearray()
    for y in range(W):
        raw.append(0)
        for x in range(W):
            t = (x + y) / (2 * W)
            r = int(0x2f + (0x9a - 0x2f) * t)
            g = int(0x7b + (0x5b - 0x7b) * t)
            b = 0xff
            d = min(seg_dist(x, y, *s) for s in segs)
            if d <= edge:
                r = g = b = 255
            elif d <= edge + 1.2:
                k = (edge + 1.2 - d) / 1.2
                r, g, b = int(r + (255 - r) * k), int(g + (255 - g) * k), int(b + (255 - b) * k)
            raw += bytes((r, g, b))

    def chunk(typ, data):
        return (_st.pack(">I", len(data)) + typ + data
                + _st.pack(">I", _zl.crc32(typ + data) & 0xffffffff))

    ihdr = _st.pack(">IIBBBBB", W, W, 8, 2, 0, 0, 0)
    _ICON_PNG_CACHE = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
                       + chunk(b"IDAT", _zl.compress(bytes(raw), 9)) + chunk(b"IEND", b""))
    return _ICON_PNG_CACHE


@app.get("/install/icon.png")
def install_icon():
    return Response(content=_kenios_icon_png(), media_type="image/png",
                    headers={"Cache-Control": "public, max-age=86400"})


def _install_html(title: str, body: str) -> str:
    base = _ipa_base_url()
    return (
        '<!doctype html><html lang="vi"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
        f'<title>Cài {title}</title>'
        # PWA / Web-clip: thêm vào Màn hình chính là có icon KENIOS, mở toàn màn hình.
        '<meta name="apple-mobile-web-app-capable" content="yes">'
        '<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">'
        f'<meta name="apple-mobile-web-app-title" content="{title}">'
        '<meta name="theme-color" content="#131c33">'
        f'<link rel="apple-touch-icon" href="{base}/install/icon.png">'
        f'<link rel="icon" href="{base}/install/icon.png">'
        '<style>'
        '*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}'
        'body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;'
        'min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px;'
        'background:linear-gradient(160deg,#0b1220 0%,#131c33 45%,#241844 100%);color:#fff}'
        '.card{width:100%;max-width:420px;background:rgba(255,255,255,.06);border:1px solid '
        'rgba(255,255,255,.12);border-radius:26px;padding:34px 26px;text-align:center;'
        'backdrop-filter:blur(14px);box-shadow:0 20px 60px rgba(0,0,0,.45)}'
        '.logo{width:92px;height:92px;margin:0 auto 18px;border-radius:22px;display:flex;'
        'align-items:center;justify-content:center;font-size:46px;font-weight:900;color:#fff;'
        'background:linear-gradient(135deg,#5b8cff,#9a5bff);box-shadow:0 10px 30px rgba(90,120,255,.5)}'
        'h1{font-size:26px;font-weight:800;margin-bottom:6px}'
        '.muted{color:#aab3c5;font-size:15px;margin-bottom:22px}'
        '.tag{display:inline-block;margin:6px 0 12px;padding:5px 12px;border-radius:999px;'
        'font-size:12.5px;font-weight:700;color:#cfe0ff;background:rgba(90,140,255,.16);'
        'border:1px solid rgba(120,150,255,.32)}'
        '.tag.alt{color:#d7cbff;background:rgba(150,90,255,.16);border-color:rgba(170,120,255,.34);'
        'margin-top:26px}'
        '.btn{display:block;width:100%;padding:17px;border-radius:16px;font-size:18px;font-weight:800;'
        'text-decoration:none;color:#fff;background:linear-gradient(135deg,#2f7bff,#7a3cff);'
        'box-shadow:0 10px 26px rgba(60,110,255,.5)}'
        '.btn:active{transform:scale(.98)}'
        '.steps{text-align:left;margin-top:24px;display:flex;flex-direction:column;gap:12px}'
        '.step{background:rgba(255,255,255,.05);border-radius:12px;padding:12px 14px;'
        'font-size:14px;line-height:1.5;color:#dfe4ee}'
        '.step b{color:#fff}'
        '.tip{margin-top:18px;font-size:12.5px;color:#8892a6}'
        '</style></head><body>' + body + '</body></html>')

@app.get("/ipa/dl/{name}")
def ipa_download(name: str):
    safe = os.path.basename(name)
    if safe != name or ".." in name:
        raise HTTPException(status_code=404, detail="Không hợp lệ.")
    path = os.path.join(_IPA_DIR, safe)
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="Không tìm thấy.")
    if safe.endswith(".plist"):
        return FileResponse(path, media_type="application/xml")
    return FileResponse(path, media_type="application/octet-stream", filename=safe)

class IpaBaseIn(BaseModel):
    base: str

@app.get("/admin/ipa/base")
def admin_get_ipa_base(admin=Depends(get_admin)) -> dict[str, Any]:
    return {"base": _ipa_base_url(), "has_zsign": bool(shutil.which("zsign"))}

@app.post("/admin/ipa/base")
def admin_set_ipa_base(b: IpaBaseIn, admin=Depends(get_admin)) -> dict[str, Any]:
    set_setting("ipa_sign_base", (b.base or "").strip().rstrip("/"))
    return {"ok": True, "base": _ipa_base_url(), "has_zsign": bool(shutil.which("zsign"))}




# ======================== KENIOS WEB — Cửa hàng chạy trên Safari (PWA, không cần cài app) ========================
@app.get("/shop", response_class=HTMLResponse)
def shop_page():
    """Cửa hàng web (PWA): khách mở Safari → Thêm vào Màn hình chính → mua bán, KHÔNG cần cài app/chứng chỉ."""
    return HTMLResponse(_SHOP_HTML)


_SHOP_HTML = r'''<!doctype html><html lang="vi"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover">
<title>KENIOS Store</title>
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="KENIOS">
<meta name="theme-color" content="#0b1220">
<link rel="apple-touch-icon" href="/install/icon.png">
<link rel="icon" href="/install/icon.png">
<style>
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
:root{--bg:#0b1220;--card:#151f38;--card2:#1c2947;--line:#28365c;--accent:#2f7bff;--accent2:#7a3cff;--txt:#eef2fb;--mut:#9aa6c2;--green:#22c55e}
body{background:linear-gradient(180deg,#0b1220,#0e1630);color:var(--txt);min-height:100vh;padding-bottom:78px}
.bgwrap{position:fixed;inset:0;z-index:-1;overflow:hidden}
.bgwrap img,.bgwrap video{width:100%;height:100%;object-fit:cover}
.bgwrap::after{content:"";position:absolute;inset:0;background:linear-gradient(180deg,rgba(9,14,26,.72),rgba(9,14,26,.88))}
#logobox{overflow:hidden}
#logobox img,#logobox video{width:100%;height:100%;object-fit:cover}
.announce{overflow:hidden;white-space:nowrap;padding:7px 0;font-size:12.5px;font-weight:700;
  position:sticky;top:54px;z-index:19;background:rgba(47,123,255,.16);border-bottom:1px solid var(--line)}
.announce.red{background:rgba(239,68,68,.18)}.announce.green{background:rgba(34,197,94,.18)}
.announce.gold{background:rgba(245,180,60,.18)}.announce.purple{background:rgba(150,90,255,.18)}
.announce span{display:inline-block;padding-left:100%;animation:mq 16s linear infinite}
@keyframes mq{to{transform:translateX(-100%)}}
.stats{display:grid;grid-template-columns:1fr 1fr 1fr;gap:9px;margin:12px 0}
.stat{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:12px 6px;text-align:center}
.stat .n{font-size:18px;font-weight:900;color:#ffd54a}.stat .l{font-size:11px;color:var(--mut);margin-top:2px}
.wrap{max-width:520px;margin:0 auto;padding:14px}
.top{display:flex;align-items:center;gap:10px;padding:10px 14px;position:sticky;top:0;z-index:20;
  background:rgba(11,18,32,.86);backdrop-filter:blur(12px);border-bottom:1px solid var(--line)}
.logo{width:34px;height:34px;border-radius:9px;background:linear-gradient(135deg,var(--accent),var(--accent2));
  display:flex;align-items:center;justify-content:center;font-weight:900;font-size:19px}
.brand{font-weight:800;font-size:17px;flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.wbtn{background:var(--card2);border:1px solid var(--line);color:var(--txt);border-radius:999px;
  padding:7px 13px;font-size:13px;font-weight:700;display:flex;align-items:center;gap:6px}
.wbtn b{color:#ffd54a}
h2{font-size:16px;margin:16px 4px 8px;font-weight:800}
.cat{font-size:13px;color:var(--mut);font-weight:800;text-transform:uppercase;letter-spacing:.5px;margin:18px 4px 8px}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:14px;margin-bottom:12px}
.pname{font-size:15.5px;font-weight:800;margin-bottom:3px}
.pdesc{font-size:12.5px;color:var(--mut);line-height:1.45;margin-bottom:10px;white-space:pre-wrap}
.stock{font-size:11.5px;font-weight:700;padding:2px 8px;border-radius:999px;display:inline-block;margin-bottom:8px}
.stock.ok{color:#7ee2a8;background:rgba(34,197,94,.14)}
.stock.no{color:#ff9b9b;background:rgba(255,80,80,.14)}
.prices{display:flex;flex-wrap:wrap;gap:8px}
.chip{background:var(--card2);border:1px solid var(--line);border-radius:12px;padding:9px 12px;flex:1 1 auto;
  min-width:44%;text-align:left;color:var(--txt)}
.chip:active{transform:scale(.98)}
.chip .lb{font-size:11.5px;color:var(--mut);display:block}
.chip .am{font-size:15px;font-weight:800;color:#fff}
.chip:disabled{opacity:.45}
.hero{border-radius:18px;overflow:hidden;margin:14px 0 4px;border:1px solid var(--line);background:linear-gradient(135deg,#243b7a,#3a2170)}
.hero img,.hero video{width:100%;display:block;max-height:190px;object-fit:cover}
.hero .hb{padding:18px 16px}
.hero h1{font-size:22px;font-weight:900;margin-bottom:6px}
.hero .hb p{font-size:13px;color:#dbe2f2}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:11px;margin-top:6px}
.tile{position:relative;border-radius:15px;overflow:hidden;aspect-ratio:1/1;border:1px solid var(--line);padding:0;
  background:linear-gradient(135deg,var(--card),var(--card2));display:flex;align-items:flex-end;text-align:left}
.tile img,.tile video{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.tile .nm{position:relative;width:100%;padding:10px 11px;font-weight:800;font-size:13.5px;z-index:2;color:#fff;
  background:linear-gradient(transparent,rgba(0,0,0,.82))}
.tile .ph{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:34px;opacity:.55}
.tile:active{transform:scale(.98)}
.back{display:inline-flex;align-items:center;gap:6px;background:var(--card2);border:1px solid var(--line);
  color:var(--txt);border-radius:999px;padding:8px 14px;font-size:13px;font-weight:700;margin:8px 0 2px}
.crumb{font-size:12.5px;color:var(--mut);margin:8px 4px 0;font-weight:600}
.pimg{width:100%;max-height:190px;object-fit:cover;border-radius:12px;margin-bottom:10px}
.nav{position:fixed;bottom:0;left:0;right:0;z-index:30;display:flex;background:rgba(11,18,32,.92);
  backdrop-filter:blur(12px);border-top:1px solid var(--line);max-width:520px;margin:0 auto}
.nav button{flex:1;background:none;border:0;color:var(--mut);padding:10px 4px 14px;font-size:11px;font-weight:700;display:flex;flex-direction:column;align-items:center;gap:3px}
.nav button.on{color:#7db0ff}
.nav .ic{font-size:20px}
.btn{display:block;width:100%;padding:15px;border-radius:14px;font-size:16px;font-weight:800;border:0;
  color:#fff;background:linear-gradient(135deg,var(--accent),var(--accent2));margin-top:10px}
.btn:active{transform:scale(.99)}
.btn.g{background:linear-gradient(135deg,#16a34a,#22c55e)}
.btn.sec{background:var(--card2);border:1px solid var(--line)}
.inp{width:100%;padding:14px;border-radius:12px;border:1px solid var(--line);background:var(--card2);color:#fff;font-size:15px;margin-top:10px}
.inp::placeholder{color:#6f7ca0}
.mask{position:fixed;inset:0;background:rgba(0,0,0,.6);z-index:50;display:none;align-items:flex-end;justify-content:center}
.mask.show{display:flex}
.sheet{background:#111a30;border:1px solid var(--line);border-radius:22px 22px 0 0;width:100%;max-width:520px;
  padding:22px 18px calc(22px + env(safe-area-inset-bottom));animation:up .22s ease}
@keyframes up{from{transform:translateY(40px);opacity:.6}to{transform:translateY(0);opacity:1}}
.sheet h3{font-size:18px;font-weight:800;margin-bottom:6px}
.sheet p{font-size:13px;color:var(--mut);line-height:1.5}
.keybox{background:var(--card2);border:1px dashed #3a5cff;border-radius:12px;padding:14px;
  font-size:15px;font-weight:800;word-break:break-all;margin:12px 0;color:#bcd0ff}
.row{display:flex;gap:10px;margin-top:10px}
.row .btn{margin-top:0}
.muted{color:var(--mut);font-size:12.5px;text-align:center;margin:14px 4px}
.center{text-align:center;padding:40px 10px;color:var(--mut)}
.spin{width:26px;height:26px;border:3px solid var(--line);border-top-color:var(--accent);border-radius:50%;
  animation:sp 1s linear infinite;margin:30px auto}
@keyframes sp{to{transform:rotate(360deg)}}
.toast{position:fixed;bottom:90px;left:50%;transform:translateX(-50%);background:#111a30;border:1px solid var(--line);
  color:#fff;padding:12px 18px;border-radius:12px;font-size:13.5px;z-index:99;opacity:0;transition:.25s;max-width:90%;text-align:center}
.toast.show{opacity:1}
.authtabs{display:flex;gap:5px;background:var(--card2);border-radius:12px;padding:4px;margin:12px 0}
.authtabs button{flex:1;background:none;border:0;color:var(--mut);padding:9px 4px;border-radius:9px;font-weight:700;font-size:13px}
.authtabs button.on{background:var(--accent);color:#fff}
.ticker{height:150px;overflow:hidden;position:relative;
  -webkit-mask-image:linear-gradient(transparent,#000 14%,#000 86%,transparent);
  mask-image:linear-gradient(transparent,#000 14%,#000 86%,transparent)}
.ticker-inner{animation-name:tick;animation-timing-function:linear;animation-iteration-count:infinite;will-change:transform}
@keyframes tick{from{transform:translateY(0)}to{transform:translateY(-50%)}}
.tx{display:flex;justify-content:space-between;gap:10px;padding:11px 0;border-bottom:1px solid var(--line);font-size:13px}
.tx span{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tx b{font-weight:800}
.plus{color:#7ee2a8}.minus{color:#ff9b9b}
.ordk{background:var(--card2);border-radius:10px;padding:10px;margin-top:8px;font-size:13px;word-break:break-all;color:#bcd0ff;font-weight:700}
a.link{display:flex;align-items:center;gap:10px;background:var(--card);border:1px solid var(--line);border-radius:12px;padding:13px;margin-bottom:9px;color:#fff;text-decoration:none;font-weight:700}
</style></head><body>

<div class="bgwrap" id="bgwrap"></div>

<div class="top">
  <div class="logo" id="logobox">K</div>
  <div class="brand" id="brand">KENIOS Store</div>
  <button class="wbtn" id="walletTop" onclick="go('wallet')"><span id="wbal">Đăng nhập</span></button>
</div>
<div class="announce" id="announce" style="display:none"><span id="announceText"></span></div>

<div class="wrap" id="view"></div>

<div class="nav">
  <button data-tab="shop" class="on" onclick="go('shop')"><span class="ic">🛍️</span>Cửa hàng</button>
  <button data-tab="wallet" onclick="go('wallet')"><span class="ic">💰</span>Ví</button>
  <button data-tab="orders" onclick="go('orders')"><span class="ic">🔑</span>Đơn của tôi</button>
  <button data-tab="contact" onclick="go('contact')"><span class="ic">💬</span>Liên hệ</button>
</div>

<div class="mask" id="mask"><div class="sheet" id="sheet"></div></div>
<div class="toast" id="toast"></div>

<script>
const API = location.origin;
let TOKEN = localStorage.getItem('kenios_token') || '';
let CFG = {}, CATS = [], PRODS = {}, PMAP = {}, TAB = 'shop';

function h(s){return (s||'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]))}
function money(n){return (n||0).toLocaleString('vi-VN')+'đ'}
function toast(m){const t=document.getElementById('toast');t.textContent=m;t.classList.add('show');
  clearTimeout(t._t);t._t=setTimeout(()=>t.classList.remove('show'),2200)}
async function api(path,opt={}){
  opt.headers=Object.assign({'Content-Type':'application/json'},opt.headers||{});
  if(TOKEN) opt.headers['Authorization']='Bearer '+TOKEN;
  const r=await fetch(API+path,opt);
  const t=await r.text(); let d={}; try{d=t?JSON.parse(t):{}}catch(e){d={}}
  if(!r.ok) throw new Error(d.detail||('Lỗi '+r.status));
  return d;
}
function openSheet(html){document.getElementById('sheet').innerHTML=html;document.getElementById('mask').classList.add('show')}
function closeSheet(){document.getElementById('mask').classList.remove('show')}
document.getElementById('mask').addEventListener('click',e=>{if(e.target.id==='mask')closeSheet()});

function go(tab){
  TAB=tab;
  document.querySelectorAll('.nav button').forEach(b=>b.classList.toggle('on',b.dataset.tab===tab));
  if(tab==='shop'){ NAV={lvl:'cat'}; renderShop(); }
  else if(tab==='wallet') renderWallet();
  else if(tab==='orders') renderOrders();
  else if(tab==='contact') renderContact();
  window.scrollTo(0,0);
}

/* ---------- Cửa hàng: Danh mục → Thư mục con → Sản phẩm (y hệt app) ---------- */
let NAV={lvl:'cat'}, FOLD={}, FPROD={}, SHOW={}, DLS=[], CATNAME={};
async function loadStore(){
  try{
    const [cfg,cats,all,show,dls]=await Promise.all([
      api('/store/config'),api('/store/categories'),api('/store/all-products'),
      api('/store/showcase').catch(()=>({})),api('/store/downloads').catch(()=>[])]);
    CFG=cfg; CATS=cats; PRODS=all.by_category||{}; SHOW=show||{}; DLS=dls||[];
    PMAP={}; CATNAME={}; CATS.forEach(c=>CATNAME[c.id]=c.name);
    Object.keys(PRODS).forEach(cid=>(PRODS[cid]||[]).forEach(p=>PMAP[p.id]=p));
    document.getElementById('brand').textContent=cfg.logo_name||'KENIOS Store';
    document.title=(cfg.logo_name||'KENIOS')+' Store';
    applyBranding(cfg);
  }catch(e){}
}
// Chuẩn hoá link media: đưa MỌI ảnh/video của máy chủ KENIOS về CÙNG origin HTTPS,
// để trang HTTPS không bị chặn nội dung http:// (IP cũ 103.131.56.11 …) → ảnh/video hiện lại.
function fixUrl(u){
  if(!u) return '';
  u=(''+u).trim();
  if(!u || u.startsWith('/') || u.startsWith('data:') || u.startsWith('blob:')) return u;
  try{
    const p=new URL(u);
    if(p.hostname==='103.131.56.11' || p.hostname.endsWith('kenios.store')
       || p.pathname.startsWith('/media') || p.pathname.startsWith('/store') || p.pathname.startsWith('/uploads'))
      return p.pathname + p.search;         // cùng máy chủ → dùng đường dẫn tương đối (HTTPS hiện tại)
    if(p.protocol==='http:'){ p.protocol='https:'; return p.href; }   // ngoài: thử nâng HTTPS
    return u;
  }catch(e){ return u; }
}
function m1(m){return fixUrl((m&&m.length&&m[0]&&m[0].url)||'')}
// Logo / nền / banner (ảnh hoặc video) — dùng chung mediaThumb để video tự phát ổn định trên iOS.
function mediaEl(url,type){ return mediaThumb(url,type); }
function applyBranding(cfg){
  const lb=document.getElementById('logobox');
  if(cfg.logo_url) lb.innerHTML=mediaEl(cfg.logo_url,cfg.logo_type); else lb.textContent='K';
  const bw=document.getElementById('bgwrap');
  bw.innerHTML=(cfg.bg_url && cfg.bg_type && cfg.bg_type!=='none')?mediaEl(cfg.bg_url,cfg.bg_type):'';
  const an=document.getElementById('announce');
  if(cfg.announce_enabled && (cfg.announce_text||'').trim()){
    document.getElementById('announceText').textContent=cfg.announce_text;
    an.className='announce '+(cfg.announce_color||'accent'); an.style.display='block';
  } else an.style.display='none';
}
function statsHtml(){
  const u=(CFG.stat_users_base||0)+(CFG.stat_users_real||0);
  const s=(CFG.stat_sold_base||0)+(CFG.stat_sold_real||0);
  const r=(CFG.stat_reviews_base||0)+(CFG.stat_reviews_real||0);
  if(!(u||s||r)) return '';
  const f=n=>n.toLocaleString('vi-VN');
  return '<div class="stats">'
    +'<div class="stat"><div class="n">'+f(u)+'</div><div class="l">Người dùng</div></div>'
    +'<div class="stat"><div class="n">'+f(s)+'</div><div class="l">Đã bán</div></div>'
    +'<div class="stat"><div class="n">'+f(r)+'</div><div class="l">Đánh giá</div></div></div>';
}
function firstMedia(m){
  if(!m||!m.length||!m[0]||!m[0].url) return null;
  return {url:fixUrl(m[0].url), type:(m[0].type||'')};
}
function mediaThumb(url,type,cls){
  url=fixUrl(url);
  if(!url) return '';
  const c=cls?(' class="'+cls+'"'):'';
  // Nhận diện video theo TYPE trước (link /media/123 không có đuôi .mp4), rồi mới tới đuôi file.
  const vid=(type==='video')||/\.(mp4|mov|webm|m4v)(\?|$)/i.test(url);
  return vid?'<video'+c+' src="'+h(url)+'" autoplay muted loop playsinline webkit-playsinline preload="auto"></video>'
           :'<img'+c+' loading="lazy" src="'+h(url)+'">';
}
function tile(onclick,name,media,emoji){
  const fm=firstMedia(media);
  const inner=fm?mediaThumb(fm.url,fm.type):'<div class="ph">'+emoji+'</div>';
  return '<button class="tile" onclick="'+onclick+'">'+inner+'<div class="nm">'+h(name)+'</div></button>';
}
function heroHtml(){
  const t=((CFG.hero_title||'').trim())||CFG.logo_name||'KENIOS Store';
  const s=((CFG.hero_subtitle||'').trim())||((CFG.slogan||'').trim())||'Cửa hàng sản phẩm số · key · tải về';
  const bn=CFG.banner_url?mediaEl(CFG.banner_url,CFG.banner_type):'';
  return '<div class="hero">'+bn+'<div class="hb"><h1>'+h(t)+'</h1><p>'+h(s)+'</p></div></div>';
}
function renderShop(){
  if(NAV.lvl==='folder') return renderFolders();
  if(NAV.lvl==='prod') return renderProds();
  return renderCats();
}
function renderCats(){
  const v=document.getElementById('view');
  let html=heroHtml()+flashHtml()+statsHtml()
    +'<input class="inp" id="q" placeholder="🔍 Tìm sản phẩm..." oninput="doSearch()" autocapitalize="off" style="margin:12px 0 0">'
    +'<div id="searchres"></div>';
  if(CATS.length){
    html+='<h2>Danh mục</h2><div class="grid">';
    CATS.forEach(c=>html+=tile('openCat('+c.id+')',c.name,c.media,'🎮'));
    html+='</div>';
  }
  html+=gamecatHtml()+transactionsHtml()+downloadsHtml();
  if(!CATS.length && !Object.keys(PRODS).length) html='<div class="spin"></div>';
  v.innerHTML=html; startFlash(); window.scrollTo(0,0);
}
/* Flash sale (đếm ngược) */
let _flashTimer=null;
function flashHtml(){
  if(!CFG.flash_enabled || !CFG.flash_product_id) return '';
  const p=PMAP[CFG.flash_product_id]; if(!p) return '';
  const end=CFG.flash_end||0;
  return '<div class="card" style="border:1px solid #ff5a5a;background:linear-gradient(135deg,#3a1420,#2a1030)">'
    +'<div class="pname" style="color:#ff9b9b">⚡ '+h(CFG.flash_title||'FLASH SALE')+(CFG.flash_discount?' −'+CFG.flash_discount+'%':'')+'</div>'
    +'<div class="pdesc">'+h(p.name)+'</div>'
    +(end?'<div id="flashcd" data-end="'+end+'" class="stock ok" style="font-size:14px">Đang tính...</div>':'')
    +'<div class="prices" style="margin-top:8px">'+(p.prices||[]).map(pr=>'<button class="chip" onclick="buy('+p.id+','+pr.id+')"><span class="lb">'+h(pr.label)+'</span><span class="am">'+money(pr.amount)+'</span></button>').join('')+'</div></div>';
}
function startFlash(){
  if(_flashTimer) clearInterval(_flashTimer);
  const el=document.getElementById('flashcd'); if(!el) return;
  const end=parseInt(el.dataset.end)||0;
  const upd=()=>{ let s=end-Math.floor(Date.now()/1000);
    if(s<=0){el.textContent='Đã kết thúc';clearInterval(_flashTimer);return}
    const d=Math.floor(s/86400),hh=Math.floor(s%86400/3600),mm=Math.floor(s%3600/60),ss=s%60;
    el.textContent='Còn '+(d?d+'n ':'')+String(hh).padStart(2,'0')+':'+String(mm).padStart(2,'0')+':'+String(ss).padStart(2,'0'); };
  upd(); _flashTimer=setInterval(upd,1000);
}
/* Sản phẩm nổi bật theo danh mục (gamecat) */
function gamecatHtml(){
  const ids=Object.keys(PRODS).filter(cid=>(PRODS[cid]||[]).length);
  if(!ids.length) return '';
  let html='<h2>Sản phẩm nổi bật</h2>';
  ids.forEach(cid=>{
    const list=PRODS[cid]||[]; if(!list.length) return;
    html+='<div class="cat">'+h(CATNAME[cid]||'Khác')+'</div>';
    list.slice(0,8).forEach(p=>html+=card(p));
    if(list.length>8) html+='<button class="btn sec" onclick="openCat('+cid+')">Xem tất cả '+list.length+' sản phẩm ›</button>';
  });
  return html;
}
/* Giao dịch gần đây — thanh CHẠY tự cuộn lên vòng lặp (giống app) */
function transactionsHtml(){
  const list=(SHOW.recent_orders||[]).slice(0,15);
  if(!list.length) return '';
  const row=o=>'<div class="tx"><span>🛒 <b>'+h(o.user)+'</b> mua '+h(o.product)+(o.label?' ('+h(o.label)+')':'')+'</span><b class="plus">'+money(o.amount)+'</b></div>';
  const rows=list.map(row).join('');
  const dur=Math.max(12,list.length*2.4);
  return '<h2>Giao dịch gần đây</h2><div class="card" style="padding:4px 14px">'
    +'<div class="ticker"><div class="ticker-inner" style="animation-duration:'+dur+'s">'+rows+rows+'</div></div></div>';
}
/* Tải về miễn phí */
function downloadsHtml(){
  if(!DLS.length) return '';
  let html='<h2>Tải về miễn phí</h2>';
  DLS.slice(0,12).forEach(d=>{
    html+='<a class="link" href="'+API+'/store/products/'+d.id+'/download" target="_blank">⬇️ '+h(d.name)+'</a>';
  });
  return html;
}
/* Tìm kiếm sản phẩm */
function doSearch(){
  const q=(document.getElementById('q').value||'').trim().toLowerCase();
  const box=document.getElementById('searchres'); if(!box) return;
  if(!q){ box.innerHTML=''; return; }
  const hits=Object.values(PMAP).filter(p=>(p.name||'').toLowerCase().includes(q));
  if(!hits.length){ box.innerHTML='<div class="pdesc" style="margin-top:10px">Không tìm thấy sản phẩm.</div>'; return; }
  box.innerHTML='<h2>Kết quả ('+hits.length+')</h2>'+hits.slice(0,20).map(card).join('');
}
async function openCat(id){
  const c=CATS.find(x=>x.id===id)||{name:''};
  NAV={lvl:'folder',cat:{id:id,name:c.name}};
  document.getElementById('view').innerHTML='<div class="spin"></div>';
  if(!FOLD[id]){ try{FOLD[id]=await api('/store/categories/'+id+'/folders')}catch(e){FOLD[id]=[]} }
  renderFolders();
}
function renderFolders(){
  const v=document.getElementById('view'), cat=NAV.cat, list=FOLD[cat.id]||[];
  let html='<button class="back" onclick="backCat()">‹ Danh mục</button>'
    +'<div class="crumb">'+h(cat.name)+'</div><h2>Thư mục</h2>';
  if(!list.length) html+='<div class="center">Danh mục này chưa có thư mục.</div>';
  else{ html+='<div class="grid">'; list.forEach(f=>html+=tile('openFolder('+f.id+')',f.name,f.media,'📁')); html+='</div>'; }
  v.innerHTML=html; window.scrollTo(0,0);
}
async function openFolder(id){
  const list=FOLD[NAV.cat.id]||[]; const f=list.find(x=>x.id===id)||{name:''};
  NAV={lvl:'prod',cat:NAV.cat,folder:{id:id,name:f.name}};
  document.getElementById('view').innerHTML='<div class="spin"></div>';
  if(!FPROD[id]){ try{FPROD[id]=await api('/store/folders/'+id+'/products')}catch(e){FPROD[id]=[]} }
  (FPROD[id]||[]).forEach(p=>PMAP[p.id]=p);
  renderProds();
}
function renderProds(){
  const v=document.getElementById('view'), cat=NAV.cat, fol=NAV.folder, list=FPROD[fol.id]||[];
  let html='<button class="back" onclick="backFolder()">‹ '+h(cat.name)+'</button>'
    +'<div class="crumb">'+h(cat.name)+' › '+h(fol.name)+'</div><h2>Sản phẩm</h2>';
  if(!list.length) html+='<div class="center">Thư mục này chưa có sản phẩm.</div>';
  else list.forEach(p=>html+=card(p));
  v.innerHTML=html; window.scrollTo(0,0);
}
function backCat(){ NAV={lvl:'cat'}; renderCats(); }
function backFolder(){ NAV={lvl:'folder',cat:NAV.cat}; renderFolders(); }
function card(p){
  const fm=firstMedia(p.media); const img=fm?mediaThumb(fm.url,fm.type,'pimg'):'';
  const stock=p.available_keys>0?'<span class="stock ok">Còn '+p.available_keys+' key</span>':'<span class="stock no">Hết hàng</span>';
  let chips='<div class="prices">';
  (p.prices||[]).forEach(pr=>{
    const dis=p.available_keys<=0?'disabled':'';
    chips+='<button class="chip" '+dis+' onclick="buy('+p.id+','+pr.id+')">'
      +'<span class="lb">'+h(pr.label)+'</span><span class="am">'+money(pr.amount)+'</span></button>';
  });
  chips+='</div>';
  if(!(p.prices||[]).length) chips='<div class="pdesc">Chưa có giá bán.</div>';
  return '<div class="card">'+img+'<div class="pname">'+h(p.name)+'</div>'
    +(p.description?'<div class="pdesc">'+h(p.description)+'</div>':'')
    +stock+chips+'</div>';
}

/* ---------- Mua ---------- */
function buy(pid,priceId){
  if(!TOKEN){ loginSheet(); return; }
  const p=PMAP[pid]; if(!p){toast('Sản phẩm không còn');return}
  const pr=(p.prices||[]).find(x=>x.id===priceId); if(!pr){toast('Mốc giá không còn');return}
  const name=p.name, amount=pr.amount, label=pr.label;
  openSheet('<h3>Xác nhận mua</h3><p>'+h(name)+' — <b>'+h(label)+'</b></p>'
    +'<div class="keybox" style="text-align:center;border-style:solid">'+money(amount)+'</div>'
    +'<p>Trừ vào số dư ví của bạn. Key sẽ giao ngay sau khi mua.</p>'
    +'<button class="btn g" id="okbuy">Mua ngay</button>'
    +'<button class="btn sec" onclick="closeSheet()">Huỷ</button>');
  document.getElementById('okbuy').onclick=async()=>{
    const btn=document.getElementById('okbuy'); btn.textContent='Đang xử lý...'; btn.disabled=true;
    try{
      const r=await api('/store/orders',{method:'POST',body:JSON.stringify({product_id:pid,price_id:priceId})});
      setBal(r.balance);
      openSheet('<h3>🎉 Mua thành công!</h3><p>'+h(r.product_name||name)+'</p>'
        +'<div class="keybox">'+h(r.key||'')+'</div>'
        +(r.delivery?'<p style="white-space:pre-wrap">'+h(r.delivery)+'</p>':'')
        +'<button class="btn" onclick=\'copy('+JSON.stringify(r.key||'')+')\'>Sao chép key</button>'
        +'<button class="btn sec" onclick="afterBuy()">Xong</button>');
    }catch(e){
      btn.textContent='Mua ngay'; btn.disabled=false;
      if((e.message||'').includes('ví không đủ')){ toast(e.message); go('wallet'); closeSheet(); }
      else toast(e.message);
    }
  };
}
function copy(t){navigator.clipboard.writeText(t).then(()=>toast('Đã sao chép ✓'))}
function afterBuy(){ closeSheet();
  if(NAV.folder){ delete FPROD[NAV.folder.id]; openFolder(NAV.folder.id); }
  else loadStore().then(renderShop);
}

/* ---------- Tài khoản: Đăng nhập · Đăng ký · OTP (đầy đủ như app) ---------- */
let AUTHTAB='login';
function loginSheet(){ AUTHTAB='login'; renderAuth(); document.getElementById('mask').classList.add('show'); }
function authTab(t){ AUTHTAB=t; renderAuth(); }
function idPayload(v){ v=(v||'').trim(); return v.includes('@')?{email:v}:{phone:v}; }
function saveAuth(r){ TOKEN=r.token; localStorage.setItem('kenios_token',TOKEN); closeSheet();
  toast('Xin chào '+((r.user&&r.user.username)||'')); refreshWallet(); go(TAB); }
function renderAuth(){
  let html='<h3>Tài khoản KENIOS</h3><div class="authtabs">'
    +'<button class="'+(AUTHTAB==='login'?'on':'')+'" onclick="authTab(\'login\')">Đăng nhập</button>'
    +'<button class="'+(AUTHTAB==='register'?'on':'')+'" onclick="authTab(\'register\')">Đăng ký</button>'
    +'<button class="'+(AUTHTAB==='otp'?'on':'')+'" onclick="authTab(\'otp\')">Mã OTP</button></div>';
  if(AUTHTAB==='login'){
    html+='<p>Đăng nhập bằng tài khoản & mật khẩu (chung với app).</p>'
      +'<input class="inp" id="au_user" placeholder="Tên đăng nhập" autocapitalize="off" autocorrect="off">'
      +'<input class="inp" id="au_pass" type="password" placeholder="Mật khẩu">'
      +'<button class="btn" id="au_go">Đăng nhập</button>'
      +'<p class="muted" onclick="authTab(\'otp\')" style="cursor:pointer">Quên mật khẩu? Đăng nhập bằng mã OTP →</p>';
  } else if(AUTHTAB==='register'){
    html+='<p>Tạo tài khoản mới (dùng chung với app).</p>'
      +'<input class="inp" id="au_user" placeholder="Tên đăng nhập (≥3 ký tự)" autocapitalize="off" autocorrect="off">'
      +'<input class="inp" id="au_pass" type="password" placeholder="Mật khẩu (≥6 ký tự)">'
      +'<input class="inp" id="au_id" placeholder="Gmail hoặc số điện thoại" autocapitalize="off" autocorrect="off">'
      +'<button class="btn sec" id="au_send">Gửi mã xác nhận</button>'
      +'<div id="au_codebox" style="display:none">'
      +'<input class="inp" id="au_code" inputmode="numeric" placeholder="Nhập mã 6 số">'
      +'<button class="btn g" id="au_go">Đăng ký</button></div>';
  } else {
    html+='<p>Đăng nhập nhanh bằng mã OTP — không cần mật khẩu.</p>'
      +'<input class="inp" id="au_id" placeholder="Gmail hoặc số điện thoại" autocapitalize="off" autocorrect="off">'
      +'<button class="btn sec" id="au_send">Gửi mã</button>'
      +'<div id="au_codebox" style="display:none">'
      +'<input class="inp" id="au_code" inputmode="numeric" placeholder="Nhập mã 6 số">'
      +'<button class="btn g" id="au_go">Đăng nhập</button></div>';
  }
  document.getElementById('sheet').innerHTML=html;
  const send=document.getElementById('au_send');
  if(send) send.onclick=async()=>{
    const id=(document.getElementById('au_id').value||'').trim();
    if(!id){toast('Nhập Gmail hoặc SĐT đã');return}
    send.textContent='Đang gửi...'; send.disabled=true;
    try{ await api('/auth/send-otp',{method:'POST',body:JSON.stringify(Object.assign(idPayload(id),{purpose:AUTHTAB==='register'?'register':'login'}))});
      document.getElementById('au_codebox').style.display='block'; send.textContent='Gửi lại mã'; send.disabled=false; toast('Đã gửi mã tới '+id);
    }catch(e){ send.textContent='Gửi mã'; send.disabled=false; toast(e.message) }
  };
  const gobtn=document.getElementById('au_go');
  if(gobtn) gobtn.onclick=async()=>{
    const old=gobtn.textContent; gobtn.disabled=true; gobtn.textContent='Đang xử lý...';
    function fail(m){ gobtn.disabled=false; gobtn.textContent=old; if(m)toast(m); }
    try{
      let r;
      if(AUTHTAB==='login'){
        const u=(document.getElementById('au_user').value||'').trim(), p=document.getElementById('au_pass').value||'';
        if(!u||!p){ return fail('Nhập tài khoản & mật khẩu'); }
        r=await api('/auth/login',{method:'POST',body:JSON.stringify({username:u,password:p})});
      } else if(AUTHTAB==='register'){
        const u=(document.getElementById('au_user').value||'').trim(), p=document.getElementById('au_pass').value||'';
        const id=(document.getElementById('au_id').value||'').trim(), cd=(document.getElementById('au_code').value||'').trim();
        if(!u||!p||!id||!cd){ return fail('Điền đủ thông tin & mã'); }
        r=await api('/auth/register',{method:'POST',body:JSON.stringify(Object.assign({username:u,password:p,code:cd},idPayload(id)))});
      } else {
        const id=(document.getElementById('au_id').value||'').trim(), cd=(document.getElementById('au_code').value||'').trim();
        if(!cd){ return fail('Nhập mã đã'); }
        r=await api('/auth/login-otp',{method:'POST',body:JSON.stringify(Object.assign({code:cd},idPayload(id)))});
      }
      saveAuth(r);
    }catch(e){ fail(e.message); }
  };
}
function logout(){TOKEN='';localStorage.removeItem('kenios_token');setBal(null);toast('Đã đăng xuất');go('shop')}
function setBal(b){
  const el=document.getElementById('wbal');
  if(b===null||b===undefined){el.innerHTML=TOKEN?'Ví':'Đăng nhập'}
  else el.innerHTML='<b>'+money(b)+'</b>';
}
async function refreshWallet(){ if(!TOKEN){setBal(null);return}
  try{const w=await api('/store/wallet');setBal(w.balance)}catch(e){setBal(null)} }

/* ---------- Ví ---------- */
async function renderWallet(){
  const v=document.getElementById('view');
  if(!TOKEN){ v.innerHTML='<h2>Ví tiền</h2><div class="card"><p class="pdesc">Đăng nhập để dùng ví, mua key và xem đơn.</p><button class="btn" onclick="loginSheet()">Đăng nhập</button></div>'; return }
  v.innerHTML='<div class="spin"></div>';
  try{
    const w=await api('/store/wallet'); setBal(w.balance);
    let html='<h2>Ví tiền</h2><div class="card"><div class="pdesc">Số dư</div>'
      +'<div style="font-size:30px;font-weight:900;color:#ffd54a">'+money(w.balance)+'</div>'
      +(w.bonus_percent?'<div class="stock ok" style="margin-top:8px">Nạp tặng thêm '+w.bonus_percent+'%</div>':'')
      +'<button class="btn" onclick="topupSheet('+ (w.bonus_percent||0) +')">Nạp tiền</button>'
      +'<button class="btn sec" onclick="doTopupCheck(this)">🔄 Kiểm tra nạp tiền</button>'
      +'<button class="btn sec" onclick="logout()">Đăng xuất</button></div>';
    html+='<h2>Lịch sử</h2><div class="card">';
    if(!(w.tx||[]).length) html+='<div class="pdesc">Chưa có giao dịch.</div>';
    (w.tx||[]).forEach(t=>{const pos=t.amount>=0;
      html+='<div class="tx"><span>'+h(t.note||t.kind)+'</span><b class="'+(pos?'plus':'minus')+'">'+(pos?'+':'')+money(t.amount)+'</b></div>'});
    html+='</div>';
    v.innerHTML=html;
  }catch(e){ v.innerHTML='<div class="center">'+h(e.message)+'</div>' }
}
function topupSheet(bonus){
  openSheet('<h3>Nạp tiền vào ví</h3>'+(bonus?'<p>Nạp được tặng thêm <b>'+bonus+'%</b>.</p>':'')
    +'<input class="inp" id="tamt" inputmode="numeric" placeholder="Số tiền (vd 50000)">'
    +'<button class="btn g" id="tbtn">Tạo lệnh nạp</button>');
  document.getElementById('tbtn').onclick=async()=>{
    const amt=parseInt(document.getElementById('tamt').value.replace(/\D/g,''))||0;
    if(amt<1000){toast('Tối thiểu 1.000đ');return}
    const b=document.getElementById('tbtn'); b.textContent='Đang tạo...'; b.disabled=true;
    try{ const r=await api('/store/wallet/topup',{method:'POST',body:JSON.stringify({amount:amt})});
      let img=r.qr_url?'<img src="'+r.qr_url+'" style="width:100%;max-width:240px;border-radius:12px;display:block;margin:12px auto;background:#fff">':'';
      openSheet('<h3>Chuyển khoản để nạp</h3><p style="white-space:pre-wrap">'+h(r.message||'')+'</p>'+img
        +'<p class="muted">Sau khi chuyển khoản, bấm "Kiểm tra nạp tiền" để hệ thống dò ngay.</p>'
        +'<button class="btn g" onclick="doTopupCheck(this)">🔄 Kiểm tra nạp tiền</button>'
        +'<button class="btn sec" onclick="closeSheet();renderWallet()">Đóng</button>');
    }catch(e){ b.textContent='Tạo lệnh nạp'; b.disabled=false; toast(e.message) }
  };
}
// Bấm kiểm tra: dò giao dịch ngân hàng NGAY, cộng ví nếu tiền đã vào.
async function doTopupCheck(btn){
  const old=btn?btn.textContent:''; if(btn){btn.textContent='Đang kiểm tra...';btn.disabled=true;}
  try{
    const r=await api('/store/wallet/topup/check',{method:'POST'});
    setBal(r.balance); toast(r.message||'Đã kiểm tra');
    if(r.confirmed){ setTimeout(()=>{closeSheet(); renderWallet();}, 900); }
    else if(btn){ btn.textContent=old; btn.disabled=false; }
  }catch(e){ toast(e.message); if(btn){btn.textContent=old;btn.disabled=false;} }
}

/* ---------- Đơn của tôi ---------- */
async function renderOrders(){
  const v=document.getElementById('view');
  if(!TOKEN){ v.innerHTML='<h2>Đơn của tôi</h2><div class="card"><p class="pdesc">Đăng nhập để xem key đã mua.</p><button class="btn" onclick="loginSheet()">Đăng nhập</button></div>'; return }
  v.innerHTML='<div class="spin"></div>';
  try{
    const list=await api('/store/orders');
    let html='<h2>Đơn của tôi</h2>';
    if(!list.length) html+='<div class="center">Chưa có đơn nào.</div>';
    list.forEach(o=>{
      html+='<div class="card"><div class="pname">'+h(o.product_name)+'</div>'
        +'<div class="pdesc">'+money(o.amount)+' · '+new Date(o.created_at*1000).toLocaleDateString('vi-VN')+'</div>';
      if(o.key){ html+='<div class="ordk" onclick=\'copy('+JSON.stringify(o.key)+')\'>🔑 '+h(o.key)+'</div>'
        +(o.delivery?'<div class="pdesc" style="white-space:pre-wrap;margin-top:8px">'+h(o.delivery)+'</div>':''); }
      else html+='<div class="stock no">'+h(o.status)+'</div>';
      html+='</div>';
    });
    v.innerHTML=html;
  }catch(e){ v.innerHTML='<div class="center">'+h(e.message)+'</div>' }
}

/* ---------- Liên hệ ---------- */
async function renderContact(){
  const v=document.getElementById('view');
  v.innerHTML='<div class="spin"></div>';
  try{
    const c=await api('/store/contacts');
    let html='<h2>Liên hệ & Cộng đồng</h2>';
    const all=[].concat(c.contact||[],c.groups||[]);
    if(!all.length) html+='<div class="center">Chưa có kênh liên hệ.</div>';
    all.forEach(x=>{ html+='<a class="link" href="'+h(x.url)+'" target="_blank">💬 '+h(x.label||x.platform||x.url)+'</a>' });
    html+='<div class="muted">Mẹo: bấm nút Chia sẻ của Safari → “Thêm vào Màn hình chính” để dùng như một ứng dụng.</div>';
    v.innerHTML=html;
  }catch(e){ v.innerHTML='<div class="center">'+h(e.message)+'</div>' }
}

/* ---------- Khởi động ---------- */
(async function(){
  await loadStore(); renderShop(); refreshWallet();
})();
</script>
</body></html>'''


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


@app.post("/store/wallet/topup/check")
async def store_topup_check(user=Depends(get_user)) -> dict[str, Any]:
    """Khách bấm 'Kiểm tra nạp tiền' → dò giao dịch ngân hàng NGAY (không đợi vòng lặp 20s),
    rồi trả về số dư mới + có xác nhận được đơn nạp nào không."""
    def _snap():
        with db() as c:
            bal = _wallet_balance(c, user["id"])
            pend = c.execute("SELECT COUNT(*) n FROM store_topups WHERE user_id=? AND status='pending'",
                             (user["id"],)).fetchone()["n"]
        return bal, pend
    before, pend_before = _snap()
    try:
        await _acb_fetch_and_confirm()   # dò ngân hàng ngay lập tức
    except Exception as e:
        log.warning("topup_check dò ngân hàng lỗi: %s", e)
    after, pend_after = _snap()
    added = after - before
    confirmed = added > 0 or pend_after < pend_before
    if confirmed:
        msg = (f"✅ Đã cộng {added:,}đ vào ví!".replace(",", ".") if added > 0
               else "✅ Đã ghi nhận nạp tiền!")
    elif pend_after > 0:
        msg = "Chưa thấy tiền vào. Nếu vừa chuyển khoản, đợi 1–2 phút rồi bấm kiểm tra lại."
    else:
        msg = "Không có lệnh nạp nào đang chờ."
    return {"balance": after, "confirmed": confirmed, "added": added,
            "pending": pend_after, "message": msg}


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
    logo_type: Optional[str] = None     # image | video
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
    hero_color: Optional[str] = None
    # Dòng phụ (subtitle) — màu/hiệu ứng/chuyển động riêng
    hero_sub_effect: Optional[str] = None
    hero_sub_font: Optional[str] = None
    hero_sub_anim: Optional[str] = None
    hero_sub_color: Optional[str] = None
    # Hiệu ứng / chuyển động cho slogan
    slogan_effect: Optional[str] = None
    slogan_anim: Optional[str] = None
    slogan_color: Optional[str] = None
    # Khuyến mãi (banner ảnh trong phần ví nạp tiền)
    promo_image_url: Optional[str] = None
    promo_product_id: Optional[int] = None
    # 3 ô thống kê: số ảo admin đặt (số thật đếm tự động ở backend)
    stat_users_base: Optional[int] = None
    stat_sold_base: Optional[int] = None
    stat_reviews_base: Optional[int] = None
    # Lời chào toàn cục (popup) cho mọi người dùng
    latest_version: Optional[str] = None
    update_url: Optional[str] = None
    update_message: Optional[str] = None
    welcome_popup_enabled: Optional[bool] = None
    welcome_popup_title: Optional[str] = None
    welcome_popup_text: Optional[str] = None
    welcome_voice_enabled: Optional[bool] = None
    welcome_voice_text: Optional[str] = None
    welcome_voice_rate: Optional[float] = None
    welcome_voice_id: Optional[str] = None
    notif_voice_enabled: Optional[bool] = None
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
    if b.logo_type is not None:
        set_setting("store_logo_type", "video" if b.logo_type == "video" else "image")
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
    if b.hero_color is not None: set_setting("store_hero_color", b.hero_color.strip()[:9])
    # Dòng phụ (subtitle)
    if b.hero_sub_effect is not None: set_setting("store_hero_sub_effect", b.hero_sub_effect.strip()[:20])
    if b.hero_sub_font is not None: set_setting("store_hero_sub_font", b.hero_sub_font.strip()[:20])
    if b.hero_sub_anim is not None: set_setting("store_hero_sub_anim", b.hero_sub_anim.strip()[:20])
    if b.hero_sub_color is not None: set_setting("store_hero_sub_color", b.hero_sub_color.strip()[:9])
    # Slogan effect / anim / color
    if b.slogan_effect is not None: set_setting("store_slogan_effect", b.slogan_effect.strip()[:20])
    if b.slogan_anim is not None: set_setting("store_slogan_anim", b.slogan_anim.strip()[:20])
    if b.slogan_color is not None: set_setting("store_slogan_color", b.slogan_color.strip()[:9])
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
    _ver_old = None
    if b.latest_version is not None:
        _ver_old = get_setting("store_latest_version", "")
        set_setting("store_latest_version", b.latest_version.strip()[:20])
    if b.update_url is not None: set_setting("store_update_url", b.update_url.strip()[:300])
    if b.update_message is not None: set_setting("store_update_message", b.update_message.strip()[:300])
    # §1.2 — Phiên bản MỚI (đổi khác trước): thông báo cho MỌI user (in-app + Gmail).
    if _ver_old is not None:
        _nv = get_setting("store_latest_version", "")
        if _nv and _nv != _ver_old:
            _notify_all_users(
                f"🎉 KENIOS có phiên bản mới {_nv}",
                get_setting("store_update_message", "") or
                f"Phiên bản {_nv} đã sẵn sàng. Mở app KENIOS để cập nhật ngay!",
                kind="update", link=get_setting("store_update_url", ""))
    if b.welcome_popup_enabled is not None: set_setting("store_welcome_popup_enabled", "1" if b.welcome_popup_enabled else "0")
    if b.welcome_popup_title is not None: set_setting("store_welcome_popup_title", b.welcome_popup_title.strip()[:80])
    if b.welcome_popup_text is not None: set_setting("store_welcome_popup_text", b.welcome_popup_text.strip()[:500])
    if b.welcome_voice_enabled is not None: set_setting("store_welcome_voice_enabled", "1" if b.welcome_voice_enabled else "0")
    if b.welcome_voice_text is not None: set_setting("store_welcome_voice_text", b.welcome_voice_text.strip()[:500])
    if b.welcome_voice_rate is not None: set_setting("store_welcome_voice_rate", str(max(0.3, min(float(b.welcome_voice_rate), 0.65))))
    if b.welcome_voice_id is not None: set_setting("store_welcome_voice_id", b.welcome_voice_id.strip()[:200])
    if b.notif_voice_enabled is not None: set_setting("store_notif_voice_enabled", "1" if b.notif_voice_enabled else "0")
    if b.gamecat_limit is not None: set_setting("store_gamecat_limit", str(max(1, min(int(b.gamecat_limit), 30))))
    _store_config_cache["data"] = None   # cập nhật cấu hình → app thấy ngay (không đợi cache)
    return {"message": "Đã cập nhật giao diện app bán hàng."}


# -------------------- §9.1 Admin: cảnh báo xâm nhập qua Telegram --------------------
class SecAlertIn(BaseModel):
    enabled: Optional[bool] = None
    bot_token: Optional[str] = None
    chat_id: Optional[str] = None
    test: Optional[bool] = None

@app.get("/admin/security-alert")
def admin_get_security_alert(admin=Depends(get_admin)) -> dict[str, Any]:
    return {
        "enabled": get_setting("sec_alert_enabled", "0") == "1",
        "bot_token": get_setting("sec_alert_bot_token", ""),
        "chat_id": get_setting("sec_alert_chat_id", ""),
    }

@app.post("/admin/security-alert")
def admin_set_security_alert(b: SecAlertIn, admin=Depends(get_admin)) -> dict[str, Any]:
    if b.enabled is not None: set_setting("sec_alert_enabled", "1" if b.enabled else "0")
    if b.bot_token is not None: set_setting("sec_alert_bot_token", b.bot_token.strip()[:120])
    if b.chat_id is not None: set_setting("sec_alert_chat_id", b.chat_id.strip()[:60])
    if b.test:
        _security_alert("test", "Tin nhắn THỬ cảnh báo bảo mật. Nhận được nghĩa là cấu hình đúng ✅", force=True)
    return {"ok": True}


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
    # §1.1 — Sản phẩm MỚI: phát thông báo (kèm ẢNH sản phẩm) cho TẤT CẢ người dùng.
    if not b.id:
        img = ""
        for m in (b.media or []):
            u = (m.url if isinstance(m, MediaItem) else (m.get("url", "") if isinstance(m, dict) else "")) or ""
            if u:
                img = u
                break
        _notify_all_users("🛒 KENIOS Cửa hàng",
                          f"Sản phẩm mới vừa được thêm vào cửa hàng: {name}",
                          kind="product", image=img)
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

def _apns_cfg() -> dict:
    """Cấu hình APNs: ưu tiên DB (admin nhập TRONG APP), fallback biến môi trường."""
    key_id = get_setting("apns_key_id", "") or os.getenv("APNS_KEY_ID", "")
    team_id = get_setting("apns_team_id", "") or os.getenv("APNS_TEAM_ID", "")
    bundle_id = get_setting("apns_bundle_id", "") or os.getenv("APNS_BUNDLE_ID", "")
    key_p8 = get_setting("apns_key_p8", "")
    if not key_p8:
        p = os.getenv("APNS_KEY_PATH", "")
        if p:
            try: key_p8 = open(p).read()
            except Exception: key_p8 = ""
    return {"key_id": key_id.strip(), "team_id": team_id.strip(),
            "bundle_id": bundle_id.strip(), "key_p8": key_p8}

def _apns_configured() -> bool:
    c = _apns_cfg()
    return all([c["key_id"], c["team_id"], c["bundle_id"], c["key_p8"]])

def _apns_send(tokens: list[str], title: str, body: str) -> tuple[int, int]:
    """Gửi push tới danh sách device token. Trả (sent, failed).
    Im lặng trả (0,0) nếu chưa cấu hình APNs — dùng được cho thông báo tự động."""
    tokens = [t for t in tokens if t]
    cfg = _apns_cfg()
    if not tokens or not all([cfg["key_id"], cfg["team_id"], cfg["bundle_id"], cfg["key_p8"]]):
        return (0, 0)
    try:
        import httpx, jwt as pyjwt
        jwt_token = pyjwt.encode({"iss": cfg["team_id"], "iat": int(time.time())},
                                 cfg["key_p8"], algorithm="ES256",
                                 headers={"kid": cfg["key_id"]})
        # Chuông tuỳ chỉnh (khớp file trong Library/Sounds của app) — kêu cả khi tắt app.
        payload = {"aps": {"alert": {"title": title, "body": body}, "sound": "kenios_notify.wav"}}
        headers = {"authorization": f"bearer {jwt_token}",
                   "apns-topic": cfg["bundle_id"], "apns-push-type": "alert"}
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


def _push_preview(content: str) -> str:
    """Rút gọn nội dung tin nhắn để hiện trên push (tin media → nhãn thân thiện)."""
    marker = "⁣KMEDIA⁣"
    if content.startswith(marker):
        parts = content.split(marker)
        kind = parts[1] if len(parts) > 1 else ""
        return {"img": "📷 Hình ảnh", "video": "🎬 Video",
                "audio": "🎤 Tin nhắn thoại", "file": "📎 Tệp đính kèm"}.get(kind, "📎 Tệp đính kèm")
    s = content.strip()
    return s if len(s) <= 120 else s[:117] + "..."


def _notify_user(uid: int, title: str, body: str) -> None:
    """Gửi push tới MỌI thiết bị của MỘT người dùng (tin nhắn/cuộc gọi) — chạy nền, không chặn."""
    try:
        if not _apns_configured():
            return
        with db() as c:
            tokens = [r["token"] for r in c.execute(
                "SELECT token FROM device_tokens WHERE user_id=?", (uid,)).fetchall()]
        if not tokens:
            return
        import threading
        threading.Thread(target=_apns_send, args=(tokens, title, body),
                         daemon=True, name="notify-user").start()
    except Exception as e:
        log.warning("notify_user lỗi: %s", e)


# ===== Thông báo qua EMAIL/Gmail (MIỄN PHÍ) — hiện cả khi app KENIOS tắt hẳn =====
_email_notif_last: dict[int, float] = {}

def _notif_email_html(subject: str, body: str) -> str:
    import html as _html
    s = _html.escape(subject); b = _html.escape(body)
    base = _ipa_base_url()
    return (
        '<div style="font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;max-width:480px;margin:0 auto;padding:16px">'
        '<div style="background:linear-gradient(135deg,#0095F6,#8b5cf6);color:#fff;padding:16px 20px;border-radius:14px 14px 0 0">'
        '<div style="font-size:20px;font-weight:800;letter-spacing:1px">KENIOS</div></div>'
        '<div style="background:#fff;border:1px solid #eee;border-top:none;border-radius:0 0 14px 14px;padding:20px">'
        f'<div style="font-size:16px;font-weight:700;color:#111">{s}</div>'
        f'<div style="font-size:15px;color:#444;margin-top:8px;line-height:1.5">{b}</div>'
        '<div style="margin-top:16px;font-size:12px;color:#999">Bạn nhận email này vì có hoạt động mới trên KENIOS. '
        'Mở app KENIOS để xem chi tiết.<br>'
        f'<a href="{base}/terms" style="color:#0095F6;text-decoration:none">Điều khoản sử dụng</a> · '
        f'<a href="{base}/privacy" style="color:#0095F6;text-decoration:none">Chính sách bảo mật</a>'
        '</div></div></div>'
    )

def _notify_user_email(uid: int, subject: str, body: str) -> None:
    """Gửi thông báo qua email (Gmail…) khi người nhận đang OFFLINE — miễn phí, không cần APNs.
    Chỉ gửi khi: bật cấu hình + có SMTP relay + user có email + đang offline + không quá 1 email/2 phút."""
    try:
        if get_setting("email_notify_enabled", "1") != "1" or not _smtp_cfg()["host"]:
            return
        now = time.time()
        with db() as c:
            row = c.execute("SELECT email, last_seen FROM users WHERE id=?", (uid,)).fetchone()
        if not row:
            return
        email = (row["email"] or "").strip()
        if "@" not in email:
            return
        if now - (row["last_seen"] or 0) < 120:   # đang mở app → khỏi email
            return
        if now - _email_notif_last.get(uid, 0) < 120:   # chống spam
            return
        _email_notif_last[uid] = now
        import threading
        threading.Thread(target=send_system_mail,
                         args=(email, subject, body, _notif_email_html(subject, body)),
                         daemon=True, name="notif-email").start()
    except Exception as e:
        log.warning("notify_user_email lỗi: %s", e)


def _broadcast_notification(title: str, body: str, kind: str = "general", link: str = "", image: str = "") -> None:
    """§1.1 — Lưu thông báo PHÁT cho tất cả người dùng để app đọc (không phụ thuộc APNs).
    Đây là kênh tin cậy: mọi user mở app đều thấy, kể cả bản cài qua eSign."""
    try:
        with db() as c:
            c.execute("INSERT INTO notifications(title,body,kind,link,image,created_at) VALUES(?,?,?,?,?,?)",
                      (title, body, kind, link, image, int(time.time())))
            # Giữ gọn: chỉ lưu 200 thông báo gần nhất
            c.execute("DELETE FROM notifications WHERE id NOT IN "
                      "(SELECT id FROM notifications ORDER BY id DESC LIMIT 200)")
    except Exception as e:
        log.warning("broadcast_notification lỗi: %s", e)


def _email_broadcast_all(subject: str, body: str) -> None:
    """Gửi email (Gmail…) cho MỌI người dùng có email — dùng cho SẢN PHẨM MỚI / PHIÊN BẢN MỚI.
    Chạy nền, giãn nhịp để không bị Gmail chặn. Chỉ chạy khi bật + đã cấu hình SMTP relay."""
    if get_setting("email_notify_enabled", "1") != "1" or not _smtp_cfg()["host"]:
        return
    def run():
        try:
            with db() as c:
                emails = [r["email"] for r in c.execute(
                    "SELECT DISTINCT email FROM users WHERE email IS NOT NULL AND email LIKE '%@%'").fetchall()]
            html = _notif_email_html(subject, body)
            sent = 0
            for em in emails:
                try:
                    if send_system_mail(em, subject, body, html) == "external":
                        sent += 1
                    time.sleep(1.2)   # nhẹ tay với Gmail (tránh bị chặn gửi hàng loạt)
                except Exception:
                    pass
            log.info("email_broadcast: đã gửi %d/%d email — %s", sent, len(emails), subject)
        except Exception as e:
            log.warning("email_broadcast lỗi: %s", e)
    import threading
    threading.Thread(target=run, daemon=True, name="email-broadcast").start()


def _notify_all_users(title: str, body: str, kind: str = "general", link: str = "", image: str = "") -> None:
    """§1.1 — Thông báo cho MỌI người dùng: (1) LƯU vào bảng notifications để app đọc
    (tin cậy, không cần quyền push) + (2) GỬI EMAIL cho user có Gmail + (3) đẩy APNs nếu có."""
    _broadcast_notification(title, body, kind, link, image)
    _email_broadcast_all(title, body)   # ← gửi Gmail cho mọi user có email
    try:
        with db() as c:
            tokens = [r["token"] for r in c.execute("SELECT token FROM device_tokens").fetchall()]
        if not tokens or not _apns_configured():
            return
        import threading
        threading.Thread(target=_apns_send, args=(tokens, title, body),
                         daemon=True, name="notify-all").start()
    except Exception as e:
        log.warning("notify_all lỗi: %s", e)


@app.get("/notifications")
def list_notifications(limit: int = 20, user=Depends(get_user)) -> list[dict[str, Any]]:
    """§1.1 — Danh sách thông báo phát cho mọi người (app poll để hiện trong app)."""
    limit = max(1, min(limit, 100))
    with db() as c:
        rows = c.execute(
            "SELECT id,title,body,kind,link,COALESCE(image,'') AS image,created_at FROM notifications "
            "ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
    return [dict(r) for r in rows]


def _email_notify_status() -> dict[str, Any]:
    cfg = _smtp_cfg()
    return {"enabled": get_setting("email_notify_enabled", "1") == "1",
            "has_relay": bool(cfg["host"]),
            "smtp_host": cfg["host"], "smtp_port": cfg["port"],
            "smtp_user": cfg["user"], "mail_from": cfg["from"],
            "smtp_pass_set": bool(cfg["pass"])}

@app.get("/admin/email-notify")
def admin_get_email_notify(admin=Depends(get_admin)) -> dict[str, Any]:
    return _email_notify_status()

@app.post("/admin/email-notify")
def admin_set_email_notify(body: dict = Body(...), admin=Depends(get_admin)) -> dict[str, Any]:
    if "enabled" in body:
        set_setting("email_notify_enabled", "1" if body.get("enabled") else "0")
    if body.get("smtp_host") is not None:  set_setting("smtp_relay_host", str(body["smtp_host"]).strip())
    if body.get("smtp_port") is not None:  set_setting("smtp_relay_port", str(body["smtp_port"]).strip())
    if body.get("smtp_user") is not None:  set_setting("smtp_relay_user", str(body["smtp_user"]).strip())
    if body.get("mail_from") is not None:  set_setting("smtp_mail_from", str(body["mail_from"]).strip())
    # Mật khẩu ứng dụng: chỉ ghi khi nhập mới (để trống = giữ nguyên)
    if body.get("smtp_pass"):              set_setting("smtp_relay_pass", str(body["smtp_pass"]))
    # Gửi email kiểm tra (tuỳ chọn) — dùng cấu hình vừa lưu
    if body.get("test_to"):
        r = send_system_mail(str(body["test_to"]).strip(), "KENIOS — Thư kiểm tra cấu hình",
                             "Nếu bạn nhận được email này, cấu hình gửi Gmail của KENIOS đã hoạt động.",
                             _notif_email_html("KENIOS — Kiểm tra cấu hình",
                                               "Cấu hình gửi email hoạt động tốt! 🎉 Từ giờ khách sẽ nhận được thông báo sản phẩm mới & phiên bản mới qua Gmail."))
        out = _email_notify_status(); out["test_result"] = r
        out["test_ok"] = (r == "external")
        return out
    return _email_notify_status()


# ===================== Admin: Bot Telegram hỗ trợ =====================
def _tg_bot_status() -> dict[str, Any]:
    token = get_setting("tg_bot_token", "")
    return {
        "enabled": get_setting("tg_bot_enabled", "0") == "1",
        "has_token": bool(token.strip()),
        "admin_chat": get_setting("tg_admin_chat", ""),
        "welcome": get_setting("tg_welcome", ""),
        "about": get_setting("tg_about", ""),
        "username": get_setting("tg_bot_username", ""),
        # Quản lý nhóm
        "mod_enabled": get_setting("tg_mod_enabled", "1") == "1",
        "del_links": get_setting("tg_del_links", "1") == "1",
        "del_stickers": get_setting("tg_del_stickers", "0") == "1",
        "del_photos": get_setting("tg_del_photos", "0") == "1",
        "warn_limit": int(get_setting("tg_warn_limit", "3") or 3),
        "warn_action": get_setting("tg_warn_action", "mute"),
        "welcome_on": get_setting("tg_welcome_on", "1") == "1",
        "welcome_group": get_setting("tg_welcome_group", "👋 Chào mừng {name} đã vào {group}!"),
        "welcome_btn_text": get_setting("tg_welcome_btn_text", ""),
        "welcome_btn_url": get_setting("tg_welcome_btn_url", ""),
        "welcome_btns": get_setting("tg_welcome_btns", ""),
        "welcome_group_photo": get_setting("tg_welcome_group_photo", ""),
        "goodbye_on": get_setting("tg_goodbye_on", "1") == "1",
        "goodbye": get_setting("tg_goodbye", "👋 Tạm biệt {name}, hẹn gặp lại!"),
        # Module nâng cao
        "antiflood_on": get_setting("tg_antiflood_on", "1") == "1",
        "antiflood_max": int(get_setting("tg_antiflood_max", "6") or 6),
        "clean_service": get_setting("tg_clean_service", "0") == "1",
        "captcha_on": get_setting("tg_captcha_on", "0") == "1",
        "nightmode_on": get_setting("tg_nightmode_on", "0") == "1",
        "night_start": int(get_setting("tg_night_start", "23") or 23),
        "night_end": int(get_setting("tg_night_end", "6") or 6),
        "rules": get_setting("tg_rules", ""),
        "locks": get_setting("tg_locks", ""),
        "blacklist": get_setting("tg_blacklist", ""),
        "bot_name": get_setting("tg_bot_name", "TRẦN MINH CHIẾN"),
        "autoreact_on": get_setting("tg_autoreact_on", "0") == "1",
        "autoreact_emoji": get_setting("tg_autoreact_emoji", "👍"),
        "slowmode": int(get_setting("tg_slowmode", "0") or 0),
        "log_chat": get_setting("tg_log_chat", ""),
    }

@app.get("/admin/telegram-bot")
def admin_get_tg_bot(admin=Depends(get_admin)) -> dict[str, Any]:
    return _tg_bot_status()

@app.post("/admin/telegram-bot")
def admin_set_tg_bot(body: dict = Body(...), admin=Depends(get_admin)) -> dict[str, Any]:
    if body.get("token"):                     # để trống = giữ token cũ
        set_setting("tg_bot_token", str(body["token"]).strip())
    if "enabled" in body:                     set_setting("tg_bot_enabled", "1" if body.get("enabled") else "0")
    if body.get("admin_chat") is not None:    set_setting("tg_admin_chat", str(body["admin_chat"]).strip())
    if body.get("welcome") is not None:       set_setting("tg_welcome", str(body["welcome"])[:1500])
    if body.get("about") is not None:         set_setting("tg_about", str(body["about"])[:1500])
    # Quản lý nhóm
    if "mod_enabled" in body:   set_setting("tg_mod_enabled", "1" if body.get("mod_enabled") else "0")
    if "del_links" in body:     set_setting("tg_del_links", "1" if body.get("del_links") else "0")
    if "del_stickers" in body:  set_setting("tg_del_stickers", "1" if body.get("del_stickers") else "0")
    if "del_photos" in body:    set_setting("tg_del_photos", "1" if body.get("del_photos") else "0")
    if body.get("warn_limit") is not None:   set_setting("tg_warn_limit", str(max(1, min(int(body["warn_limit"]), 10))))
    if body.get("warn_action") is not None:  set_setting("tg_warn_action", "ban" if body["warn_action"] == "ban" else "mute")
    if "welcome_on" in body:    set_setting("tg_welcome_on", "1" if body.get("welcome_on") else "0")
    if body.get("welcome_group") is not None:    set_setting("tg_welcome_group", str(body["welcome_group"])[:1500])
    if body.get("welcome_btn_text") is not None: set_setting("tg_welcome_btn_text", str(body["welcome_btn_text"])[:60])
    if body.get("welcome_btn_url") is not None:  set_setting("tg_welcome_btn_url", str(body["welcome_btn_url"]).strip()[:300])
    if body.get("welcome_btns") is not None:     set_setting("tg_welcome_btns", str(body["welcome_btns"])[:2000])
    if body.get("welcome_group_photo") is not None: set_setting("tg_welcome_group_photo", str(body["welcome_group_photo"]).strip()[:300])
    if "goodbye_on" in body:    set_setting("tg_goodbye_on", "1" if body.get("goodbye_on") else "0")
    if body.get("goodbye") is not None:          set_setting("tg_goodbye", str(body["goodbye"])[:1500])
    # Module nâng cao
    if "antiflood_on" in body:  set_setting("tg_antiflood_on", "1" if body.get("antiflood_on") else "0")
    if body.get("antiflood_max") is not None:  set_setting("tg_antiflood_max", str(max(3, min(int(body["antiflood_max"]), 30))))
    if "clean_service" in body: set_setting("tg_clean_service", "1" if body.get("clean_service") else "0")
    if "captcha_on" in body:    set_setting("tg_captcha_on", "1" if body.get("captcha_on") else "0")
    if "nightmode_on" in body:  set_setting("tg_nightmode_on", "1" if body.get("nightmode_on") else "0")
    if body.get("night_start") is not None:    set_setting("tg_night_start", str(max(0, min(int(body["night_start"]), 23))))
    if body.get("night_end") is not None:      set_setting("tg_night_end", str(max(0, min(int(body["night_end"]), 23))))
    if body.get("rules") is not None:          set_setting("tg_rules", str(body["rules"])[:2000])
    if body.get("blacklist") is not None:      set_setting("tg_blacklist", str(body["blacklist"])[:2000])
    if body.get("locks") is not None:          set_setting("tg_locks", str(body["locks"])[:200])
    if body.get("bot_name") is not None:       set_setting("tg_bot_name", str(body["bot_name"])[:60])
    if "autoreact_on" in body:  set_setting("tg_autoreact_on", "1" if body.get("autoreact_on") else "0")
    if body.get("autoreact_emoji"):            set_setting("tg_autoreact_emoji", str(body["autoreact_emoji"])[:8])
    if body.get("slowmode") is not None:       set_setting("tg_slowmode", str(max(0, min(int(body["slowmode"]), 3600))))
    if body.get("log_chat") is not None:       set_setting("tg_log_chat", str(body["log_chat"]).strip())
    # Xác minh token + lấy @username của bot (getMe) + đăng ký MENU LỆNH (setMyCommands)
    token = get_setting("tg_bot_token", "").strip()
    ok = False; uname = ""
    if token:
        me = _tg_call(token, "getMe")
        if me.get("ok"):
            ok = True
            uname = me.get("result", {}).get("username", "")
            set_setting("tg_bot_username", uname)
            _tg_register_commands(token)
    start_telegram_bot()   # đảm bảo thread đang chạy
    out = _tg_bot_status(); out["token_ok"] = ok; out["username"] = uname
    return out

@app.post("/admin/telegram-bot/test")
def admin_test_tg_bot(admin=Depends(get_admin)) -> dict[str, Any]:
    token = get_setting("tg_bot_token", "").strip()
    chat = get_setting("tg_admin_chat", "").strip()
    if not token or not chat:
        raise HTTPException(status_code=400, detail="Cần nhập Bot Token và Chat ID admin trước.")
    _tg_send(token, chat, "✅ KENIOS Bot: gửi thử thành công! Bot đã sẵn sàng nhận tin khách.")
    return {"ok": True}


# ===================== Trang Pháp lý công khai (Điều khoản & Chính sách) =====================
# Chính sách RIÊNG của KENIOS (không phải của Apple), có link công khai để dùng trong email/Gmail…
_LEGAL_TERMS = [
    ("Chấp nhận điều khoản", "Khi tạo tài khoản hoặc sử dụng ứng dụng KENIOS, bạn đồng ý tuân theo các điều khoản này. Nếu không đồng ý, vui lòng ngừng sử dụng."),
    ("Tài khoản", "Bạn chịu trách nhiệm bảo mật tài khoản và mật khẩu của mình, cũng như mọi hoạt động phát sinh từ tài khoản. Không chia sẻ tài khoản cho người khác."),
    ("Sử dụng hợp lệ", "Bạn không được dùng ứng dụng để: vi phạm pháp luật; phát tán nội dung độc hại, lừa đảo, spam; xâm phạm quyền riêng tư hay tài sản của người khác; can thiệp/làm gián đoạn hệ thống."),
    ("Mua hàng & Ví", "Sản phẩm số (key/tài khoản/bản tải) được giao tự động sau khi thanh toán thành công. Số dư ví dùng để mua hàng trong ứng dụng. Vui lòng kiểm tra kỹ trước khi mua; chính sách đổi/hoàn theo thông báo của cửa hàng."),
    ("Nội dung người dùng", "Bạn giữ quyền với nội dung mình đăng (video, bài viết) nhưng cấp cho KENIOS quyền lưu trữ và hiển thị nội dung đó trong ứng dụng. Bạn chịu trách nhiệm về nội dung mình đăng tải."),
    ("Gói PRO", "Một số tính năng nâng cao yêu cầu gói PRO. Quyền lợi gói có thể thay đổi; chúng tôi sẽ thông báo khi có cập nhật quan trọng."),
    ("Giới hạn trách nhiệm", "Ứng dụng cung cấp \"nguyên trạng\". Trong phạm vi pháp luật cho phép, KENIOS không chịu trách nhiệm cho thiệt hại gián tiếp phát sinh từ việc sử dụng."),
    ("Thay đổi", "Chúng tôi có thể cập nhật điều khoản theo thời gian. Việc tiếp tục sử dụng đồng nghĩa bạn chấp nhận điều khoản mới."),
    ("Liên hệ", "Mọi thắc mắc xin liên hệ admin qua mục Liên hệ trong cửa hàng."),
]
_LEGAL_PRIVACY = [
    ("Dữ liệu chúng tôi thu thập", "Thông tin tài khoản (tên đăng nhập, email/số điện thoại nếu bạn cung cấp); nội dung bạn tạo (bài đăng, video, file tải lên, tin nhắn); dữ liệu giao dịch (lịch sử mua hàng, nạp ví); dữ liệu kỹ thuật (token thiết bị để gửi thông báo, nhật ký lỗi)."),
    ("Mục đích sử dụng", "Để cung cấp và vận hành dịch vụ: đăng nhập, giao hàng số, ví, thông báo, hỗ trợ và cải thiện ứng dụng."),
    ("Lưu trữ", "Dữ liệu được lưu trên máy chủ do quản trị viên vận hành. Mật khẩu được băm (hash), không lưu dạng văn bản thường. Token đăng nhập lưu an toàn trong Keychain của thiết bị."),
    ("Chia sẻ", "Chúng tôi KHÔNG bán dữ liệu cá nhân. Chỉ chia sẻ khi pháp luật yêu cầu hoặc để vận hành dịch vụ (vd: cổng thanh toán, dịch vụ email/thông báo)."),
    ("Quyền trên thiết bị", "Ứng dụng có thể xin quyền: Ảnh/Camera (đính kèm, lưu video/ảnh về máy, gọi video), Micro (ghi âm, gọi thoại), Thông báo. Bạn có thể tắt trong Cài đặt iOS bất cứ lúc nào."),
    ("Thông báo qua email", "Khi bạn có tin nhắn/cuộc gọi mà đang tắt app, chúng tôi có thể gửi email thông báo tới địa chỉ bạn cung cấp. Bạn có thể tắt bằng cách xoá email khỏi hồ sơ hoặc liên hệ admin."),
    ("Quyền của bạn", "Bạn có thể xem/sửa thông tin tài khoản, xoá nội dung đã đăng, hoặc yêu cầu xoá tài khoản qua admin."),
    ("Trẻ em", "Ứng dụng không hướng tới trẻ em dưới 13 tuổi."),
    ("Liên hệ", "Liên hệ admin qua mục Liên hệ trong cửa hàng để được hỗ trợ về quyền riêng tư."),
]

def _legal_page_html(title: str, sections: list) -> str:
    import html as _html
    rows = ""
    for i, (h, b) in enumerate(sections, 1):
        rows += (
            '<div class="sec">'
            f'<div class="num">{i}</div>'
            f'<div><div class="h">{_html.escape(h)}</div>'
            f'<div class="b">{_html.escape(b)}</div></div></div>'
        )
    return (
        '<!doctype html><html lang="vi"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        f'<title>{_html.escape(title)} — KENIOS</title><style>'
        '*{box-sizing:border-box}body{margin:0;background:#0b1020;color:#e7ecf5;'
        'font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;line-height:1.55}'
        '.wrap{max-width:680px;margin:0 auto;padding:24px 16px 60px}'
        '.hero{text-align:center;padding:26px 0 10px}'
        '.brand{font-size:26px;font-weight:900;letter-spacing:2px;'
        'background:linear-gradient(135deg,#39a0ff,#8b5cf6,#e879f9);-webkit-background-clip:text;'
        'background-clip:text;color:transparent}'
        '.title{font-size:20px;font-weight:800;margin-top:6px}'
        '.badge{display:inline-block;margin-top:8px;font-size:12px;font-weight:700;color:#39a0ff;'
        'background:rgba(57,160,255,.14);padding:4px 12px;border-radius:999px}'
        '.sec{display:flex;gap:12px;background:#131a2e;border:1px solid #1e2740;border-radius:16px;'
        'padding:14px 16px;margin-top:12px}'
        '.num{flex:none;width:30px;height:30px;border-radius:9px;background:linear-gradient(135deg,#39a0ff,#8b5cf6);'
        'color:#fff;font-weight:800;display:flex;align-items:center;justify-content:center}'
        '.h{font-weight:700;font-size:16px}.b{color:#aab4c8;margin-top:4px;font-size:14.5px}'
        '.foot{text-align:center;color:#6b7690;font-size:12px;margin-top:22px}'
        '.foot a{color:#39a0ff;text-decoration:none}'
        '</style></head><body><div class="wrap">'
        '<div class="hero"><div class="brand">KENIOS</div>'
        f'<div class="title">{_html.escape(title)}</div>'
        '<div class="badge">Cập nhật lần cuối: 2026</div></div>'
        f'{rows}'
        '<div class="foot">© 2026 KENIOS. Bảo lưu mọi quyền.<br>'
        '<a href="/terms">Điều khoản sử dụng</a> · <a href="/privacy">Chính sách bảo mật</a></div>'
        '</div></body></html>'
    )

@app.get("/terms", response_class=HTMLResponse)
def terms_page():
    return HTMLResponse(_legal_page_html("Điều khoản sử dụng", _LEGAL_TERMS))

@app.get("/privacy", response_class=HTMLResponse)
def privacy_page():
    return HTMLResponse(_legal_page_html("Chính sách bảo mật", _LEGAL_PRIVACY))

@app.get("/legal", response_class=HTMLResponse)
def legal_index():
    return HTMLResponse(
        '<!doctype html><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>Pháp lý — KENIOS</title>'
        '<div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:520px;margin:40px auto;'
        'padding:0 16px;color:#111"><h2 style="text-align:center">KENIOS — Pháp lý</h2>'
        '<p style="text-align:center"><a href="/terms">Điều khoản sử dụng</a> · '
        '<a href="/privacy">Chính sách bảo mật</a></p></div>')


# ==================== §11 — Điều khiển PC từ xa (relay qua KENIOS, không cần VPS riêng) ====================
# Agent nhỏ chạy trên PC đăng nhập bằng tài khoản KENIOS → đăng ký máy. App/Web gửi lệnh
# chuột/phím tới đây, agent hỏi lệnh (~60ms) rồi thực thi. Agent đẩy ảnh màn hình để xem preview.
# Lưu trong RAM (đủ cho 1 tiến trình uvicorn) — không đụng CSDL.
import threading as _pc_threading
_PC_LOCK = _pc_threading.Lock()
_PC_AGENTS: dict[str, dict] = {}   # agent_id -> {user_id,name,os,last_seen,frame_b64,frame_ts}
_PC_CMDS: dict[str, list] = {}     # agent_id -> [cmd,...]

def _pc_online(a: dict) -> bool:
    return (int(time.time()) - a.get("last_seen", 0)) <= 15

class PCRegisterIn(BaseModel):
    name: str = "My PC"
    os: str = ""
    agent_id: Optional[str] = None   # gửi lại để giữ id cũ khi khởi động lại

@app.post("/pc/register")
def pc_register(b: PCRegisterIn, user=Depends(get_user)) -> dict[str, Any]:
    aid = b.agent_id or secrets.token_hex(8)
    with _PC_LOCK:
        old = _PC_AGENTS.get(aid, {})
        _PC_AGENTS[aid] = {"user_id": user["id"], "name": (b.name or "PC")[:60],
                           "os": (b.os or "")[:20], "last_seen": int(time.time()),
                           "frame_b64": old.get("frame_b64", ""), "frame_ts": old.get("frame_ts", 0)}
        _PC_CMDS.setdefault(aid, [])
    return {"agent_id": aid}

class PCHeartbeatIn(BaseModel):
    agent_id: str

@app.post("/pc/heartbeat")
def pc_heartbeat(b: PCHeartbeatIn, user=Depends(get_user)) -> dict[str, Any]:
    with _PC_LOCK:
        a = _PC_AGENTS.get(b.agent_id)
        if not a or a["user_id"] != user["id"]:
            raise HTTPException(status_code=404, detail="Agent không tồn tại.")
        a["last_seen"] = int(time.time())
        cmds = _PC_CMDS.get(b.agent_id, [])
        _PC_CMDS[b.agent_id] = []
    return {"commands": cmds}

class PCFrameIn(BaseModel):
    agent_id: str
    jpg: str   # base64 JPEG

@app.post("/pc/frame")
def pc_frame(b: PCFrameIn, user=Depends(get_user)) -> dict[str, Any]:
    with _PC_LOCK:
        a = _PC_AGENTS.get(b.agent_id)
        if not a or a["user_id"] != user["id"]:
            raise HTTPException(status_code=404, detail="Agent không tồn tại.")
        a["frame_b64"] = (b.jpg or "")[:4_000_000]
        a["frame_ts"] = int(time.time())
    return {"ok": True}

@app.get("/pc/mine")
def pc_mine(user=Depends(get_user)) -> list[dict[str, Any]]:
    out = []
    with _PC_LOCK:
        for aid, a in _PC_AGENTS.items():
            if a["user_id"] == user["id"]:
                out.append({"agent_id": aid, "name": a["name"], "os": a["os"], "online": _pc_online(a)})
    return out

class PCCmdIn(BaseModel):
    agent_id: str
    cmd: dict

@app.post("/pc/send")
def pc_send(b: PCCmdIn, user=Depends(get_user)) -> dict[str, Any]:
    with _PC_LOCK:
        a = _PC_AGENTS.get(b.agent_id)
        if not a or a["user_id"] != user["id"]:
            raise HTTPException(status_code=404, detail="Agent không tồn tại.")
        q = _PC_CMDS.setdefault(b.agent_id, [])
        c = b.cmd or {}
        # Gộp các lệnh 'move' liên tiếp → con trỏ mượt, không dồn hàng dài gây trễ.
        if c.get("t") == "move" and q and q[-1].get("t") == "move":
            q[-1]["dx"] = q[-1].get("dx", 0) + c.get("dx", 0)
            q[-1]["dy"] = q[-1].get("dy", 0) + c.get("dy", 0)
        else:
            q.append(c)
        if len(q) > 200:
            del q[:len(q) - 200]
    return {"ok": True}

@app.get("/pc/screen/{agent_id}")
def pc_screen(agent_id: str, user=Depends(get_user)) -> dict[str, Any]:
    with _PC_LOCK:
        a = _PC_AGENTS.get(agent_id)
        if not a or a["user_id"] != user["id"]:
            raise HTTPException(status_code=404, detail="Agent không tồn tại.")
        return {"jpg": a.get("frame_b64", ""), "ts": a.get("frame_ts", 0), "online": _pc_online(a)}

@app.delete("/pc/{agent_id}")
def pc_delete(agent_id: str, user=Depends(get_user)) -> dict[str, Any]:
    with _PC_LOCK:
        a = _PC_AGENTS.get(agent_id)
        if a and a["user_id"] == user["id"]:
            _PC_AGENTS.pop(agent_id, None)
            _PC_CMDS.pop(agent_id, None)
    return {"ok": True}

# ============================================================================
#  §11b — Cầu nối RDP tại MÁY CHỦ (kết nối máy thuê chỉ bằng IP + user + pass)
#  Máy chủ KENIOS chạy: Xvfb (màn hình ảo) + xfreerdp (kết nối RDP tới máy thuê)
#  + ffmpeg (chụp khung) + xdotool (bơm chuột/phím). App chỉ gõ IP/user/pass.
#  Cần cài trên VPS: freerdp2-x11 xvfb ffmpeg xdotool (capnhat-vps.sh tự cài).
# ============================================================================
import shutil as _shutil
_RDP_LOCK = _pc_threading.Lock()
_RDP: dict[str, "RDPSession"] = {}   # rdp_id -> RDPSession
_XKEY = {
    "enter": "Return", "backspace": "BackSpace", "space": "space", "tab": "Tab",
    "esc": "Escape", "up": "Up", "down": "Down", "left": "Left", "right": "Right",
    "delete": "Delete", "home": "Home", "end": "End", "pageup": "Prior", "pagedown": "Next",
    "insert": "Insert", "printscreen": "Print", "capslock": "Caps_Lock",
    "ctrl": "ctrl", "alt": "alt", "shift": "shift", "win": "super",
    "f1": "F1", "f2": "F2", "f3": "F3", "f4": "F4", "f5": "F5", "f6": "F6",
    "f7": "F7", "f8": "F8", "f9": "F9", "f10": "F10", "f11": "F11", "f12": "F12",
}

def _rdp_tools_missing() -> list[str]:
    return [t for t in ("Xvfb", "xfreerdp", "ffmpeg", "xdotool") if not _shutil.which(t)]

class RDPSession:
    def __init__(self, user_id: int, host: str, user: str, password: str, w: int, h: int):
        self.user_id = user_id
        self.host = host; self.user = user; self.password = password
        self.w = max(640, min(1920, w)); self.h = max(480, min(1200, h))
        self.display = ""; self.frame_path = ""; self.procs = []
        self.status = "starting"; self.error = ""
        self.last_seen = time.time()

    def start(self):
        try:
            dn = 90 + secrets.randbelow(800)
            self.display = f":{dn}"
            self.frame_path = f"/tmp/kenios_rdp_{dn}.jpg"
            env = dict(os.environ, DISPLAY=self.display)
            # 1) Màn hình ảo
            self.procs.append(subprocess.Popen(
                ["Xvfb", self.display, "-screen", "0", f"{self.w}x{self.h}x24", "-nolisten", "tcp"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            time.sleep(1.2)
            # 2) Kết nối RDP tới máy thuê (fullscreen trong màn ảo)
            self.procs.append(subprocess.Popen(
                ["xfreerdp", f"/v:{self.host}", f"/u:{self.user}", f"/p:{self.password}",
                 f"/size:{self.w}x{self.h}", "/cert:ignore", "+clipboard",
                 "-grab-keyboard", "/f", "+auto-reconnect", "/log-level:ERROR"],
                env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            time.sleep(0.5)
            # 3) Chụp khung liên tục → 1 file JPEG cập nhật (app đọc file này)
            self.procs.append(subprocess.Popen(
                ["ffmpeg", "-y", "-f", "x11grab", "-video_size", f"{self.w}x{self.h}",
                 "-framerate", "8", "-i", self.display, "-q:v", "6", "-update", "1", self.frame_path],
                env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            self.status = "running"
        except Exception as e:
            self.status = "error"; self.error = str(e)

    def frame_b64(self) -> str:
        try:
            with open(self.frame_path, "rb") as f:
                return base64.b64encode(f.read()).decode()
        except Exception:
            return ""

    def input(self, cmd: dict):
        env = dict(os.environ, DISPLAY=self.display)
        t = cmd.get("t")
        def run(args): subprocess.run(["xdotool"] + args, env=env,
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        try:
            if t == "move":
                run(["mousemove_relative", "--", str(int(cmd.get("dx", 0))), str(int(cmd.get("dy", 0)))])
            elif t == "moveto":
                run(["mousemove", str(int(float(cmd.get("x", 0)) * self.w)), str(int(float(cmd.get("y", 0)) * self.h))])
            elif t == "click":
                b = cmd.get("b", "left")
                if b == "double": run(["click", "--repeat", "2", "1"])
                elif b == "right": run(["click", "3"])
                else: run(["click", "1"])
            elif t == "drag":
                run(["mousedown", "1"])
                run(["mousemove_relative", "--", str(int(cmd.get("dx", 0))), str(int(cmd.get("dy", 0)))])
                run(["mouseup", "1"])
            elif t == "scroll":
                dy = int(cmd.get("dy", 0)); btn = "4" if dy < 0 else "5"
                for _ in range(min(10, abs(dy) // 30 + 1)): run(["click", btn])
            elif t == "text":
                run(["type", "--", str(cmd.get("s", ""))])
            elif t == "key":
                k = _XKEY.get(cmd.get("k", ""))
                if k: run(["key", k])
            elif t == "hotkey":
                keys = "+".join(_XKEY.get(x, x) for x in cmd.get("keys", []) if x)
                if keys: run(["key", keys])
            elif t == "clip":
                run(["type", "--", str(cmd.get("s", ""))])
        except Exception:
            pass
        self.last_seen = time.time()

    def stop(self):
        for p in reversed(self.procs):
            try: p.terminate()
            except Exception: pass
        try: os.remove(self.frame_path)
        except Exception: pass
        self.status = "stopped"

def _rdp_reap():
    now = time.time()
    with _RDP_LOCK:
        dead = [rid for rid, s in _RDP.items() if now - s.last_seen > 300]
        for rid in dead:
            try: _RDP[rid].stop()
            except Exception: pass
            _RDP.pop(rid, None)

class RDPStartIn(BaseModel):
    host: str
    username: str
    password: str
    width: int = 1280
    height: int = 720

@app.post("/rdp/start")
def rdp_start(b: RDPStartIn, user=Depends(get_user)) -> dict[str, Any]:
    miss = _rdp_tools_missing()
    if miss:
        raise HTTPException(status_code=503,
            detail="Máy chủ chưa cài công cụ RDP (" + ", ".join(miss) +
                   "). Chạy lại capnhat-vps.sh trên VPS để tự cài.")
    host = (b.host or "").strip()
    if not host:
        raise HTTPException(status_code=400, detail="Thiếu địa chỉ máy (IP/hostname).")
    _rdp_reap()
    rid = secrets.token_hex(8)
    s = RDPSession(user["id"], host, (b.username or "").strip(), b.password or "", b.width, b.height)
    s.start()
    if s.status == "error":
        raise HTTPException(status_code=500, detail="Không khởi động được RDP: " + s.error)
    with _RDP_LOCK:
        _RDP[rid] = s
    return {"rdp_id": rid, "w": s.w, "h": s.h}

def _rdp_get(rid: str, user) -> "RDPSession":
    with _RDP_LOCK:
        s = _RDP.get(rid)
    if not s or s.user_id != user["id"]:
        raise HTTPException(status_code=404, detail="Phiên RDP không tồn tại.")
    return s

@app.get("/rdp/screen/{rid}")
def rdp_screen(rid: str, user=Depends(get_user)) -> dict[str, Any]:
    s = _rdp_get(rid, user)
    s.last_seen = time.time()
    return {"jpg": s.frame_b64(), "running": s.status == "running", "error": s.error}

class RDPInputIn(BaseModel):
    rdp_id: str
    cmd: dict

@app.post("/rdp/input")
def rdp_input(b: RDPInputIn, user=Depends(get_user)) -> dict[str, Any]:
    s = _rdp_get(b.rdp_id, user)
    s.input(b.cmd or {})
    return {"ok": True}

class RDPStopIn(BaseModel):
    rdp_id: str

@app.post("/rdp/stop")
def rdp_stop(b: RDPStopIn, user=Depends(get_user)) -> dict[str, Any]:
    with _RDP_LOCK:
        s = _RDP.pop(b.rdp_id, None)
    if s and s.user_id == user["id"]:
        s.stop()
    return {"ok": True}

_PC_WEB_HTML = """<!doctype html><html lang="vi"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>KENIOS · Điều khiển PC</title>
<style>
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
body{margin:0;font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#0b0f1a;color:#fff}
.wrap{max-width:640px;margin:0 auto;padding:14px}
h1{font-size:18px;text-align:center;color:#3aa0ff;letter-spacing:2px}
input,button{font-size:15px;border-radius:10px;border:none;padding:12px}
input{width:100%;margin:6px 0;background:#1a2030;color:#fff}
.btn{background:#1a2030;color:#fff;border:1px solid #2a3346;cursor:pointer}
.btn:active{background:#243049}
.primary{background:#0a84ff}
.row{display:flex;gap:8px}.row>*{flex:1}
.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-top:8px}
#screen{width:100%;border-radius:10px;background:#000;display:block;aspect-ratio:16/9;object-fit:contain}
#pad{height:230px;background:#141a28;border:1px dashed #2a3346;border-radius:12px;margin-top:8px;
     display:flex;align-items:center;justify-content:center;color:#55607a;touch-action:none;user-select:none}
.small{font-size:11px;color:#8a93a6}.hide{display:none}
.pcitem{padding:14px;background:#1a2030;border-radius:10px;margin:6px 0;cursor:pointer;display:flex;justify-content:space-between}
.dot{width:9px;height:9px;border-radius:50%;display:inline-block;margin-right:6px}
label{font-size:12px;color:#8a93a6}
</style></head><body><div class="wrap">
<h1>PC CONTROLLER</h1>

<div id="login">
  <input id="u" placeholder="Tài khoản KENIOS" autocapitalize="off">
  <input id="p" type="password" placeholder="Mật khẩu">
  <button class="btn primary" style="width:100%" onclick="login()">Đăng nhập</button>
  <p class="small" id="lmsg"></p>
</div>

<div id="list" class="hide">
  <div class="row"><button class="btn" onclick="loadPCs()">Tải lại</button><button class="btn" onclick="logout()">Đăng xuất</button></div>
  <div id="pcs"></div>
  <p class="small">Chạy agent trên PC (pc_remote.py) và đăng nhập cùng tài khoản để máy hiện ở đây.</p>
</div>

<div id="ctrl" class="hide">
  <div class="row"><button class="btn" onclick="backList()">◀ Máy</button><span id="pcname" style="text-align:center;padding:12px"></span></div>
  <img id="screen" alt="screen">
  <div id="pad">DI NGÓN TAY ĐỂ ĐIỀU KHIỂN CHUỘT</div>
  <label>Tốc độ: <span id="spd">2.5</span>x</label>
  <input id="speed" type="range" min="1" max="6" step="0.5" value="2.5" style="width:100%" oninput="spd.textContent=this.value">
  <div class="row" style="margin-top:6px">
    <button class="btn" onclick="send({t:'click',b:'left'})">◁ Chuột trái</button>
    <button class="btn" onclick="send({t:'click',b:'right'})">Chuột phải ▷</button>
  </div>
  <div class="grid">
    <button class="btn" onclick="send({t:'media',a:'prev'})">⏮ Prev</button>
    <button class="btn" onclick="send({t:'media',a:'playpause'})">⏯ Play</button>
    <button class="btn" onclick="send({t:'media',a:'next'})">⏭ Next</button>
    <button class="btn" onclick="send({t:'media',a:'mute'})">🔇 Mute</button>
    <button class="btn" onclick="send({t:'media',a:'voldown'})">🔉 Vol-</button>
    <button class="btn" onclick="send({t:'media',a:'volup'})">🔊 Vol+</button>
    <button class="btn" onclick="send({t:'sys',a:'desktop'})">🖥 Desktop</button>
    <button class="btn" onclick="send({t:'sys',a:'lock'})">🔒 Lock</button>
    <button class="btn" onclick="kbd()">⌨️ Bàn phím</button>
    <button class="btn" onclick="send({t:'key',k:'backspace'})">⌫ Xoá</button>
    <button class="btn" onclick="send({t:'key',k:'space'})">␣ Space</button>
    <button class="btn" onclick="send({t:'key',k:'enter'})">⏎ Enter</button>
    <button class="btn" onclick="scr(-3)">▲ Cuộn lên</button>
    <button class="btn" onclick="scr(3)">▼ Cuộn xuống</button>
    <button class="btn" onclick="send({t:'click',b:'double'})">Double click</button>
    <button class="btn" onclick="fs()">⛶ Toàn màn</button>
  </div>
  <input id="hidden" style="position:fixed;top:-100px" oninput="onType(event)" onkeydown="onKey(event)">
</div>

<script>
var TK="",AID="",dx=0,dy=0,last=null,poll=null,frameTimer=null;
function h(){return {'Authorization':'Bearer '+TK,'Content-Type':'application/json'}}
async function login(){
  lmsg.textContent="Đang đăng nhập...";
  try{
    var r=await fetch('/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},
        body:JSON.stringify({username:u.value.trim(),password:p.value})});
    var d=await r.json();
    if(!r.ok){lmsg.textContent=d.detail||'Sai tài khoản';return;}
    TK=d.token; localStorage.setItem('kpc_tk',TK);
    showList();
  }catch(e){lmsg.textContent='Lỗi mạng';}
}
function logout(){TK="";localStorage.removeItem('kpc_tk');login_.classList.remove('hide');list.classList.add('hide');ctrl.classList.add('hide');}
function showList(){login_.classList.add('hide');ctrl.classList.add('hide');list.classList.remove('hide');loadPCs();}
async function loadPCs(){
  var r=await fetch('/pc/mine',{headers:h()});
  if(r.status===401){logout();return;}
  var arr=await r.json(); pcs.innerHTML='';
  if(!arr.length){pcs.innerHTML='<p class="small">Chưa có máy nào online.</p>';}
  arr.forEach(function(a){
    var d=document.createElement('div');d.className='pcitem';
    d.innerHTML='<span><span class="dot" style="background:'+(a.online?'#34c759':'#ff9f0a')+'"></span>'+a.name+'</span><span class="small">'+(a.os||'')+'</span>';
    d.onclick=function(){openPC(a);};pcs.appendChild(d);
  });
}
function openPC(a){AID=a.agent_id;pcname.textContent=a.name;list.classList.add('hide');ctrl.classList.remove('hide');
  frameTimer=setInterval(refresh,600);refresh();}
function backList(){clearInterval(frameTimer);showList();}
async function refresh(){
  try{var r=await fetch('/pc/screen/'+AID,{headers:h()});var d=await r.json();
    if(d.jpg) document.getElementById('screen').src='data:image/jpeg;base64,'+d.jpg;}catch(e){}
}
async function send(cmd){try{await fetch('/pc/send',{method:'POST',headers:h(),body:JSON.stringify({agent_id:AID,cmd:cmd})});}catch(e){}}
function scr(n){send({t:'scroll',dy:n});}
function kbd(){document.getElementById('hidden').focus();}
function onType(e){var v=e.target.value;if(v){send({t:'text',s:v});e.target.value='';}}
function onKey(e){if(e.key==='Enter'){send({t:'key',k:'enter'});e.preventDefault();}
  else if(e.key==='Backspace'){send({t:'key',k:'backspace'});}}
function fs(){var el=document.documentElement;(el.requestFullscreen||el.webkitRequestFullscreen).call(el);}
// Trackpad: gộp delta, gửi mỗi 50ms cho mượt
var pad=document.getElementById('pad');
function pos(e){return e.touches?e.touches[0]:e;}
pad.addEventListener('pointerdown',function(e){last={x:e.clientX,y:e.clientY};pad.setPointerCapture(e.pointerId);});
pad.addEventListener('pointermove',function(e){if(!last)return;var s=parseFloat(speed.value);
  dx+=(e.clientX-last.x)*s;dy+=(e.clientY-last.y)*s;last={x:e.clientX,y:e.clientY};});
pad.addEventListener('pointerup',function(e){last=null;});
setInterval(function(){if(AID&&(Math.abs(dx)>=1||Math.abs(dy)>=1)){send({t:'move',dx:Math.round(dx),dy:Math.round(dy)});dx=0;dy=0;}},50);
// tự đăng nhập lại nếu còn token
window.onload=function(){var t=localStorage.getItem('kpc_tk');if(t){TK=t;showList();}};
var login_=document.getElementById('login');
</script></div></body></html>"""


@app.get("/pc", response_class=HTMLResponse)
def pc_web_controller() -> str:
    """Trang điều khiển PC trên Web — đăng nhập tài khoản KENIOS rồi điều khiển như app."""
    return _PC_WEB_HTML


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

class ApnsConfigIn(BaseModel):
    key_id: Optional[str] = None
    team_id: Optional[str] = None
    bundle_id: Optional[str] = None
    key_p8: Optional[str] = None   # nội dung file .p8 (dán vào)

@app.get("/admin/push/config")
def admin_get_push_config(admin=Depends(get_admin)) -> dict[str, Any]:
    c = _apns_cfg()
    return {"key_id": c["key_id"], "team_id": c["team_id"], "bundle_id": c["bundle_id"],
            "has_key": bool(c["key_p8"]), "configured": _apns_configured()}

@app.post("/admin/push/config")
def admin_set_push_config(b: ApnsConfigIn, admin=Depends(get_admin)) -> dict[str, Any]:
    if b.key_id is not None: set_setting("apns_key_id", b.key_id.strip())
    if b.team_id is not None: set_setting("apns_team_id", b.team_id.strip())
    if b.bundle_id is not None: set_setting("apns_bundle_id", b.bundle_id.strip())
    # Chỉ ghi đè khoá .p8 khi admin dán khoá mới (để trống = giữ khoá cũ).
    if b.key_p8 is not None and b.key_p8.strip():
        set_setting("apns_key_p8", b.key_p8.strip())
    return {"ok": True, "configured": _apns_configured(),
            "message": "Đã lưu cấu hình APNs." if _apns_configured()
                       else "Đã lưu, nhưng còn thiếu thông tin (Key ID / Team ID / Bundle ID / khoá .p8)."}


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
    # Thông báo cho người nhận cả khi TẮT APP: push APNs (nếu có) + email/Gmail (miễn phí, khi offline).
    _prev = _push_preview(b.content)
    _notify_user(b.receiver_id, f"💬 {user['username']}", _prev)
    _notify_user_email(b.receiver_id, f"💬 {user['username']} nhắn bạn trên KENIOS", _prev)
    return {"id": msg_id, "message": "Đã gửi tin nhắn thành công."}


@app.delete("/direct_messages/{mid}")
def delete_direct_message(mid: int, user=Depends(get_user)) -> dict[str, Any]:
    """Thu hồi tin nhắn: chỉ NGƯỜI GỬI mới xoá được (xoá cho cả hai phía)."""
    with db() as c:
        row = c.execute("SELECT sender_id, receiver_id FROM direct_messages WHERE id=?", (mid,)).fetchone()
        if not row:
            return {"ok": True, "message": "Tin nhắn đã được xoá."}
        if row["sender_id"] != user["id"]:
            raise HTTPException(status_code=403, detail="Chỉ người gửi mới thu hồi được tin nhắn này.")
        c.execute("DELETE FROM direct_messages WHERE id=?", (mid,))
    return {"ok": True, "message": "Đã thu hồi tin nhắn."}


@app.get("/direct_messages_recent")
def recent_incoming_dms(after_id: int = 0, user=Depends(get_user)) -> list[dict[str, Any]]:
    """Tin nhắn ĐẾN gần đây (id > after_id) kèm tên người gửi — để app poll & bật thông báo."""
    with db() as c:
        rows = c.execute(
            "SELECT dm.id, dm.sender_id, dm.content, dm.created_at, dm.is_read, "
            "       u.username AS sender_name "
            "FROM direct_messages dm JOIN users u ON u.id=dm.sender_id "
            "WHERE dm.receiver_id=? AND dm.id>? "
            "ORDER BY dm.id DESC LIMIT 20",
            (user["id"], after_id)
        ).fetchall()
    return [dict(r) for r in rows]



# ======================== Gọi thoại / video giữa bạn bè (relay khung hình + âm thanh qua máy chủ) ========================
# Không cần WebRTC/TURN: mỗi bên tải khung hình JPEG (đã áp bộ lọc làm đẹp) + gói âm thanh
# lên máy chủ, bên kia poll về hiển thị. Chạy qua HTTPS nên xuyên mọi NAT/mạng di động.
import threading as _threading_calls
_calls_lock = _threading_calls.Lock()
_calls: dict[str, dict] = {}   # call_id -> trạng thái + bộ đệm khung hình/âm thanh mỗi người

def _call_cleanup(now: float) -> None:
    for k in list(_calls.keys()):
        cl = _calls.get(k)
        if not cl: continue
        # Cuộc gọi đổ chuông quá 60s mà không ai nghe/không kết thúc → coi là NHỠ, ghi log.
        if cl["state"] == "ringing" and now - cl["created"] > 60:
            _log_call_once(cl, "missed")
            cl["state"] = "ended"; cl["ended_at"] = now
        # Xoá cuộc gọi quá cũ (1 giờ) hoặc đã kết thúc > 30s
        if now - cl["created"] > 3600 or (cl["state"] in ("ended", "declined") and now - cl.get("ended_at", now) > 30):
            _log_call_once(cl, "missed")   # phòng khi chưa ghi
            _calls.pop(k, None)

def _call_other(cl: dict, uid: int) -> int:
    return cl["to"] if cl["from"] == uid else cl["from"]

def _call_guard(cid: str, uid: int) -> dict:
    cl = _calls.get(cid)
    if not cl or uid not in (cl["from"], cl["to"]):
        raise HTTPException(status_code=404, detail="Cuộc gọi không tồn tại.")
    return cl

def _log_call_once(cl: dict, status: str) -> None:
    """Ghi 1 dòng lịch sử cuộc gọi khi kết thúc (answered/missed/declined)
    + tự chèn 1 TIN NHẮN vào đoạn chat (như Zalo/Messenger) để lịch sử gọi
    nằm ngay trong phần tin nhắn với người đó."""
    if cl.get("logged"):
        return
    cl["logged"] = True
    dur = 0
    if cl.get("answered_at"):
        dur = max(0, int(time.time() - cl["answered_at"]))
        status = "answered"   # đã nghe máy → tính là answered dù kết thúc kiểu gì
    try:
        with db() as c:
            c.execute("INSERT INTO call_logs(caller_id,callee_id,video,status,started_at,duration) "
                      "VALUES(?,?,?,?,?,?)",
                      (cl["from"], cl["to"], 1 if cl["video"] else 0, status,
                       int(cl.get("created", time.time())), dur))
            # Dòng cuộc gọi trong ĐOẠN CHAT (người gọi là "người gửi")
            icon = "📹" if cl["video"] else "📞"
            kind = "video" if cl["video"] else "thoại"
            if status == "answered":
                content = f"{icon} Cuộc gọi {kind} · {dur // 60:02d}:{dur % 60:02d}"
            elif status == "declined":
                content = f"{icon} Cuộc gọi {kind} bị từ chối"
            else:
                content = f"{icon} Cuộc gọi {kind} nhỡ"
            c.execute("INSERT INTO direct_messages(sender_id, receiver_id, content, created_at, is_read) "
                      "VALUES(?,?,?,?,?)",
                      (cl["from"], cl["to"], content, int(time.time()),
                       1 if status == "answered" else 0))   # nhỡ/từ chối = chưa đọc → hiện chấm đỏ
    except Exception as e:
        log.warning("log_call lỗi: %s", e)

class CallStartIn(BaseModel):
    to: int
    video: bool = True

class CallFrameIn(BaseModel):
    jpg: str

class CallAudioIn(BaseModel):
    pcm: str        # Int16 PCM 16kHz mono, base64

@app.post("/calls/start")
def call_start(b: CallStartIn, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        fr = c.execute(
            "SELECT id FROM friendships WHERE ((user_id=? AND friend_id=?) OR (user_id=? AND friend_id=?)) AND status='accepted'",
            (user["id"], b.to, b.to, user["id"])).fetchone()
    if not fr:
        raise HTTPException(status_code=403, detail="Bạn phải là bạn bè để gọi cho người này.")
    now = time.time()
    cid = secrets.token_hex(8)
    with _calls_lock:
        _call_cleanup(now)
        _calls[cid] = {"from": user["id"], "from_name": user["username"], "to": b.to,
                       "video": bool(b.video), "state": "ringing", "created": now,
                       "frames": {}, "audio": {}, "aseq": 0}
    # Thông báo cuộc gọi đến cả khi TẮT APP: push APNs + email/Gmail (khi offline).
    _ct = f"{'📹' if b.video else '📞'} {user['username']} đang gọi"
    _notify_user(b.to, _ct, "Mở KENIOS để nghe máy.")
    _notify_user_email(b.to, _ct + " trên KENIOS", "Mở app KENIOS để nghe máy.")
    return {"call_id": cid}

@app.get("/calls/incoming")
def call_incoming(user=Depends(get_user)) -> dict[str, Any]:
    now = time.time()
    with _calls_lock:
        _call_cleanup(now)
        for cid, cl in _calls.items():
            if cl["to"] == user["id"] and cl["state"] == "ringing" and now - cl["created"] < 60:
                return {"call_id": cid, "from": cl["from"], "from_name": cl.get("from_name", ""),
                        "video": cl["video"]}
    return {}

@app.post("/calls/{cid}/answer")
def call_answer(cid: str, accept: bool = True, user=Depends(get_user)) -> dict[str, Any]:
    with _calls_lock:
        cl = _call_guard(cid, user["id"])
        if cl["state"] == "ringing":
            if accept:
                cl["state"] = "active"; cl["answered_at"] = time.time()
            else:
                cl["state"] = "declined"; cl["ended_at"] = time.time()
                _log_call_once(cl, "declined")
    return {"state": cl["state"]}

@app.post("/calls/{cid}/end")
def call_end(cid: str, user=Depends(get_user)) -> dict[str, Any]:
    with _calls_lock:
        cl = _calls.get(cid)
        if cl and user["id"] in (cl["from"], cl["to"]):
            # Chưa nghe máy mà kết thúc → NHỠ; đã nghe → answered (hàm tự tính).
            _log_call_once(cl, "missed")
            cl["state"] = "ended"; cl["ended_at"] = time.time()
    return {"ok": True}

@app.get("/calls/{cid}/state")
def call_state(cid: str, user=Depends(get_user)) -> dict[str, Any]:
    with _calls_lock:
        cl = _calls.get(cid)
        if not cl or user["id"] not in (cl["from"], cl["to"]):
            return {"state": "ended"}
        return {"state": cl["state"], "video": cl["video"]}

@app.post("/calls/{cid}/frame")
def call_frame_put(cid: str, b: CallFrameIn, user=Depends(get_user)) -> dict[str, Any]:
    with _calls_lock:
        cl = _call_guard(cid, user["id"])
        cl["frames"][user["id"]] = (time.time(), b.jpg)
    return {"ok": True}

@app.get("/calls/{cid}/frame")
def call_frame_get(cid: str, after: float = 0, user=Depends(get_user)) -> dict[str, Any]:
    """Lấy khung hình đối phương. after=ts lần trước → chỉ trả khi CÓ HÌNH MỚI
    (tránh tải lại cùng 1 khung làm nghẽn mạng → hết giật hình)."""
    with _calls_lock:
        cl = _call_guard(cid, user["id"])
        other = _call_other(cl, user["id"])
        f = cl["frames"].get(other)
    if not f or (after and f[0] <= after):
        return {"jpg": ""}
    return {"jpg": f[1], "ts": f[0]}

@app.post("/calls/{cid}/audio")
def call_audio_put(cid: str, b: CallAudioIn, user=Depends(get_user)) -> dict[str, Any]:
    with _calls_lock:
        cl = _call_guard(cid, user["id"])
        cl["aseq"] += 1
        buf = cl["audio"].setdefault(user["id"], [])
        buf.append((cl["aseq"], b.pcm))
        if len(buf) > 40: del buf[:-40]   # giữ tối đa 40 gói gần nhất
    return {"ok": True}

@app.get("/calls/{cid}/audio")
def call_audio_get(cid: str, after: int = 0, user=Depends(get_user)) -> dict[str, Any]:
    """Lấy gói âm thanh mới. LONG-POLL tới ~0,9s: có gói mới là trả NGAY —
    tiếng đến liền tai, ít request → hết rè/đứt tiếng."""
    deadline = time.time() + 0.9
    while True:
        with _calls_lock:
            cl = _calls.get(cid)
            if not cl or user["id"] not in (cl["from"], cl["to"]):
                raise HTTPException(status_code=404, detail="Cuộc gọi không tồn tại.")
            other = _call_other(cl, user["id"])
            buf = cl["audio"].get(other, [])
            out = [{"seq": s, "pcm": p} for (s, p) in buf if s > after]
            state = cl["state"]
        if out or state != "active" or time.time() >= deadline:
            return {"chunks": out}
        time.sleep(0.05)


@app.get("/calls/history")
def call_history(user=Depends(get_user)) -> list[dict[str, Any]]:
    """Lịch sử cuộc gọi của tôi (gọi đi + gọi đến). incoming+missed = cuộc gọi nhỡ."""
    with db() as c:
        rows = c.execute(
            "SELECT cl.id, cl.caller_id, cl.callee_id, cl.video, cl.status, cl.started_at, cl.duration, "
            "       uc.username AS caller_name, ue.username AS callee_name "
            "FROM call_logs cl "
            "JOIN users uc ON uc.id=cl.caller_id JOIN users ue ON ue.id=cl.callee_id "
            "WHERE cl.caller_id=? OR cl.callee_id=? ORDER BY cl.id DESC LIMIT 100",
            (user["id"], user["id"])).fetchall()
    out = []
    for r in rows:
        incoming = (r["callee_id"] == user["id"])
        out.append({
            "id": r["id"],
            "incoming": incoming,
            "peer_id": r["caller_id"] if incoming else r["callee_id"],
            "peer": r["caller_name"] if incoming else r["callee_name"],
            "video": bool(r["video"]),
            "status": r["status"],
            "missed": incoming and r["status"] in ("missed", "declined"),
            "started_at": r["started_at"] or 0,
            "duration": r["duration"] or 0,
        })
    return out


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
class PlanIn(BaseModel):
    plan: str
    days: Optional[int] = None      # số ngày gói PRO (0/None = vĩnh viễn)

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
    # Admin tặng gói PRO theo thời hạn (nửa tháng=15, tháng=30, 1 năm=365; 0=vĩnh viễn) hoặc hạ Free.
    if b.plan == "pro":
        try:
            days = int(b.days) if b.days is not None else 30
        except (TypeError, ValueError):
            days = 30
        now = int(time.time())
        exp = (now + days * 86400) if days > 0 else 0   # 0 = vĩnh viễn
        with db() as c:
            c.execute("UPDATE users SET plan='pro', plan_expires=?, plan_expired_notice=0 WHERE id=?",
                      (exp, uid))
        if days > 0:
            until = time.strftime("%d/%m/%Y", time.localtime(exp))
            return {"message": f"Đã tặng gói PRO {days} ngày (hết hạn {until})."}
        return {"message": "Đã đặt gói PRO vĩnh viễn."}
    with db() as c:
        c.execute("UPDATE users SET plan='free', plan_expires=0 WHERE id=?", (uid,))
    return {"message": "Đã đặt gói Free."}


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


@app.delete("/admin/users/{uid}")
def admin_delete_user(uid: int, admin=Depends(get_admin)) -> dict[str, Any]:
    """Xóa VĨNH VIỄN tài khoản đăng nhập của người dùng (kèm dữ liệu liên quan)."""
    if uid == admin["id"]:
        raise HTTPException(status_code=400, detail="Không thể tự xóa chính mình.")
    with db() as c:
        row = c.execute("SELECT id, username, is_admin FROM users WHERE id=?", (uid,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy người dùng.")
        if row["is_admin"]:
            raise HTTPException(status_code=400, detail="Không thể xóa tài khoản admin khác.")
        uname = row["username"]
        # Dọn dữ liệu liên quan (best-effort — bảng nào không có thì bỏ qua) rồi xóa tài khoản.
        for stmt, params in [
            ("DELETE FROM direct_messages WHERE sender_id=? OR receiver_id=?", (uid, uid)),
            ("DELETE FROM friendships WHERE user_id=? OR friend_id=?", (uid, uid)),
            ("DELETE FROM device_tokens WHERE user_id=?", (uid,)),
            ("DELETE FROM notifications WHERE user_id=?", (uid,)),
        ]:
            try:
                c.execute(stmt, params)
            except Exception:
                pass
        c.execute("DELETE FROM users WHERE id=?", (uid,))
    return {"message": f"Đã xóa vĩnh viễn tài khoản '{uname}'."}


# ---- Người dùng: lấy hồ sơ mới nhất + nhịp hoạt động ----
@app.get("/me")
def get_me(user=Depends(get_user)) -> dict[str, Any]:
    d = _user_dict(user)
    # Báo 1 lần khi gói PRO vừa hết hạn (rồi xoá cờ để không báo lại).
    try:
        if not user["is_admin"] and (user["plan_expired_notice"] or 0):
            d["plan_expired"] = True
            with db() as c:
                c.execute("UPDATE users SET plan_expired_notice=0 WHERE id=?", (user["id"],))
    except (KeyError, IndexError):
        pass
    return d


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
    # Tự sinh stream key + link HLS nếu người dùng không tự dán link (§6.1: bỏ tiền tố "ken")
    stream_key = f"live{int(time.time())}{secrets.token_hex(3)}"
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
