#!/usr/bin/env python3
# ============================================================================
#  PC Remote Agent — server điều khiển máy tính cho app KENIOS (PC Remote)
#  App gọi HTTP tới server này (mở ra ngoài bằng ngrok) để:
#   - Xem màn hình PC (GET /screen)
#   - Di chuyển chuột, click, cuộn
#   - Gõ phím, phím đặc biệt
#   - Media (play/pause, next, prev, mute, vol)
#   - Desktop / Lock PC
#
#  CÀI ĐẶT (trên PC — Windows/macOS/Linux):
#     pip install fastapi uvicorn pyautogui mss pillow
#  CHẠY:
#     python pc_remote.py            (mặc định cổng 8765, token 'kenios')
#     TOKEN=matkhau PORT=8765 python pc_remote.py
#  MỞ RA NGOÀI bằng ngrok (cửa sổ khác):
#     ngrok http 8765
#     → copy link https://xxxx.ngrok-free.dev dán vào app (ô Địa chỉ Agent)
#     → nhập đúng TOKEN vào app
#
#  BẢO MẬT: mọi lệnh phải kèm header X-Token khớp với TOKEN. Đặt token khó đoán
#  vì link ngrok là công khai.
# ============================================================================

import os
import io
import platform
import subprocess

from fastapi import FastAPI, Request, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn

import pyautogui
import mss
from PIL import Image

pyautogui.FAILSAFE = False
pyautogui.PAUSE = 0

TOKEN = os.environ.get("TOKEN", "kenios")
PORT = int(os.environ.get("PORT", "8765"))
OS_NAME = platform.system()   # 'Windows' | 'Darwin' | 'Linux'

app = FastAPI(title="KENIOS PC Remote Agent")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"],
)


def check(request: Request):
    if request.headers.get("X-Token", "") != TOKEN:
        raise HTTPException(status_code=401, detail="Sai token")


# ----- Models -----
class Move(BaseModel):
    dx: int = 0
    dy: int = 0

class Click(BaseModel):
    button: str = "left"      # left | right | double

class Scroll(BaseModel):
    amount: int = 0           # dương = lên, âm = xuống

class TypeText(BaseModel):
    text: str = ""

class Key(BaseModel):
    name: str = ""            # enter | backspace | space | esc | tab | up/down/left/right...

class Media(BaseModel):
    action: str = ""          # playpause | next | prev | mute | volup | voldown

class System(BaseModel):
    action: str = ""          # desktop | lock


# ----- Kiểm tra kết nối -----
@app.get("/ping")
def ping(request: Request):
    check(request)
    return {"ok": True, "host": platform.node(), "os": OS_NAME}


# ----- Xem màn hình (JPEG, thu nhỏ cho nhẹ) -----
@app.get("/screen")
def screen(request: Request):
    check(request)
    with mss.mss() as sct:
        shot = sct.grab(sct.monitors[0])   # toàn bộ màn hình
        img = Image.frombytes("RGB", shot.size, shot.rgb)
    # Thu nhỏ chiều rộng tối đa 900px để truyền nhanh qua ngrok
    max_w = 900
    if img.width > max_w:
        h = int(img.height * max_w / img.width)
        img = img.resize((max_w, h))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=50)
    return Response(content=buf.getvalue(), media_type="image/jpeg")


# ----- Chuột -----
@app.post("/move")
def move(body: Move, request: Request):
    check(request)
    pyautogui.moveRel(body.dx, body.dy, duration=0)
    return {"ok": True}

@app.post("/click")
def click(body: Click, request: Request):
    check(request)
    if body.button == "right":
        pyautogui.click(button="right")
    elif body.button == "double":
        pyautogui.doubleClick()
    else:
        pyautogui.click(button="left")
    return {"ok": True}

@app.post("/scroll")
def scroll(body: Scroll, request: Request):
    check(request)
    pyautogui.scroll(body.amount * 40)   # nhân lên cho cuộn rõ
    return {"ok": True}


# ----- Bàn phím -----
@app.post("/type")
def type_text(body: TypeText, request: Request):
    check(request)
    if body.text:
        pyautogui.typewrite(body.text, interval=0)
    return {"ok": True}

KEY_MAP = {
    "enter": "enter", "backspace": "backspace", "space": "space",
    "esc": "esc", "tab": "tab", "up": "up", "down": "down",
    "left": "left", "right": "right", "delete": "delete", "home": "home",
    "end": "end",
}

@app.post("/key")
def key(body: Key, request: Request):
    check(request)
    k = KEY_MAP.get(body.name.lower())
    if k:
        pyautogui.press(k)
    return {"ok": True}


# ----- Media -----
@app.post("/media")
def media(body: Media, request: Request):
    check(request)
    a = body.action.lower()
    keymap = {
        "playpause": "playpause",
        "next": "nexttrack",
        "prev": "prevtrack",
        "mute": "volumemute",
        "volup": "volumeup",
        "voldown": "volumedown",
    }
    k = keymap.get(a)
    if k:
        try:
            pyautogui.press(k)
        except Exception:
            pass
    return {"ok": True}


# ----- Hệ thống: Show Desktop / Lock PC -----
@app.post("/system")
def system(body: System, request: Request):
    check(request)
    a = body.action.lower()
    if a == "lock":
        if OS_NAME == "Windows":
            import ctypes
            ctypes.windll.user32.LockWorkStation()
        elif OS_NAME == "Darwin":
            subprocess.run(["pmset", "displaysleepnow"])
        else:
            subprocess.run(["loginctl", "lock-session"])
    elif a == "desktop":
        if OS_NAME == "Windows":
            pyautogui.hotkey("win", "d")
        elif OS_NAME == "Darwin":
            pyautogui.hotkey("fn", "f11")
        else:
            pyautogui.hotkey("ctrl", "alt", "d")
    return {"ok": True}


if __name__ == "__main__":
    print("=" * 56)
    print("  KENIOS PC Remote Agent")
    print(f"  OS: {OS_NAME}  |  Cổng: {PORT}  |  Token: {TOKEN}")
    print("  Mở ra ngoài:  ngrok http", PORT)
    print("  Rồi dán link ngrok + token vào app KENIOS (PC Remote).")
    print("=" * 56)
    uvicorn.run(app, host="0.0.0.0", port=PORT)
