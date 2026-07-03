#!/usr/bin/env python3
# ============================================================================
#  KENIOS PC Agent (relay) — điều khiển máy tính từ app/web KENIOS.
#
#  KHÁC bản cũ: KHÔNG cần ngrok, KHÔNG mở cổng, KHÔNG nhập VPS ở điện thoại.
#  Agent tự kết nối RA máy chủ KENIOS bằng TÀI KHOẢN của bạn rồi đăng ký máy.
#  App (mục Windows App) và Web (…/pc) sẽ tự thấy máy này để điều khiển.
#
#  CÀI (trên PC cần điều khiển — Windows/macOS/Linux):
#     pip install requests pyautogui mss pillow
#  CHẠY:
#     python pc_remote.py
#     → nhập Tài khoản + Mật khẩu KENIOS (giống đăng nhập app). Xong!
#  Hoặc đặt sẵn qua biến môi trường:
#     KENIOS_USER=abc KENIOS_PASS=123 python pc_remote.py
#
#  Máy chủ mặc định đã tích sẵn (đổi nếu cần): KENIOS_SERVER=http://103.131.56.11
# ============================================================================

import os, io, time, base64, platform, threading, getpass, subprocess, sys

try:
    import requests, pyautogui, mss
    from PIL import Image
except Exception:
    print("Thiếu thư viện. Chạy:  pip install requests pyautogui mss pillow")
    sys.exit(1)

pyautogui.FAILSAFE = False
pyautogui.PAUSE = 0

SERVER = os.environ.get("KENIOS_SERVER", "http://103.131.56.11").rstrip("/")
PC_NAME = os.environ.get("KENIOS_PC_NAME", platform.node() or "My PC")
OS_NAME = platform.system()   # 'Windows' | 'Darwin' | 'Linux'
ID_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".kenios_agent_id")

KEYMAP = {
    "enter": "enter", "backspace": "backspace", "space": "space", "tab": "tab",
    "esc": "esc", "up": "up", "down": "down", "left": "left", "right": "right",
    "delete": "delete", "home": "home", "end": "end",
}
MEDIA = {
    "playpause": "playpause", "next": "nexttrack", "prev": "prevtrack",
    "mute": "volumemute", "volup": "volumeup", "voldown": "volumedown",
}


def login() -> str:
    user = os.environ.get("KENIOS_USER") or input("Tài khoản KENIOS: ").strip()
    pw = os.environ.get("KENIOS_PASS") or getpass.getpass("Mật khẩu KENIOS: ")
    r = requests.post(f"{SERVER}/auth/login", json={"username": user, "password": pw}, timeout=20)
    if r.status_code != 200:
        print("Đăng nhập thất bại:", r.json().get("detail", r.text))
        sys.exit(1)
    return r.json()["token"]


def register(token: str) -> str:
    aid = ""
    if os.path.exists(ID_FILE):
        try: aid = open(ID_FILE).read().strip()
        except Exception: aid = ""
    r = requests.post(f"{SERVER}/pc/register",
                      headers={"Authorization": f"Bearer {token}"},
                      json={"name": PC_NAME, "os": OS_NAME, "agent_id": aid or None}, timeout=20)
    r.raise_for_status()
    aid = r.json()["agent_id"]
    try: open(ID_FILE, "w").write(aid)
    except Exception: pass
    return aid


def do(cmd: dict):
    """Thực thi 1 lệnh điều khiển."""
    t = cmd.get("t")
    try:
        if t == "move":
            pyautogui.moveRel(int(cmd.get("dx", 0)), int(cmd.get("dy", 0)), duration=0)
        elif t == "click":
            b = cmd.get("b", "left")
            if b == "double": pyautogui.doubleClick()
            elif b == "right": pyautogui.click(button="right")
            else: pyautogui.click()
        elif t == "scroll":
            pyautogui.scroll(-int(cmd.get("dy", 0)) * 60)
        elif t == "text":
            pyautogui.write(str(cmd.get("s", "")), interval=0)
        elif t == "key":
            k = KEYMAP.get(cmd.get("k", ""))
            if k: pyautogui.press(k)
        elif t == "media":
            m = MEDIA.get(cmd.get("a", ""))
            if m: pyautogui.press(m)
        elif t == "sys":
            a = cmd.get("a")
            if a == "desktop":
                if OS_NAME == "Windows": pyautogui.hotkey("win", "d")
                elif OS_NAME == "Darwin": pyautogui.hotkey("fn", "f11")
            elif a == "lock":
                if OS_NAME == "Windows":
                    import ctypes; ctypes.windll.user32.LockWorkStation()
                elif OS_NAME == "Darwin":
                    subprocess.run(["pmset", "displaysleepnow"])
                else:
                    subprocess.run(["loginctl", "lock-session"])
    except Exception as e:
        print("Lỗi lệnh", t, e)


def control_loop(token: str, aid: str):
    hdr = {"Authorization": f"Bearer {token}"}
    while True:
        try:
            r = requests.post(f"{SERVER}/pc/heartbeat", headers=hdr, json={"agent_id": aid}, timeout=10)
            if r.status_code == 200:
                for cmd in r.json().get("commands", []):
                    do(cmd)
            time.sleep(0.06)
        except Exception:
            time.sleep(1)


def screen_loop(token: str, aid: str):
    hdr = {"Authorization": f"Bearer {token}"}
    with mss.mss() as sct:
        mon = sct.monitors[1]
        while True:
            try:
                img = sct.grab(mon)
                pil = Image.frombytes("RGB", img.size, img.rgb)
                pil.thumbnail((900, 560))
                buf = io.BytesIO(); pil.save(buf, format="JPEG", quality=45)
                b64 = base64.b64encode(buf.getvalue()).decode()
                requests.post(f"{SERVER}/pc/frame", headers=hdr,
                              json={"agent_id": aid, "jpg": b64}, timeout=15)
            except Exception:
                pass
            time.sleep(0.6)


def main():
    print(f"KENIOS PC Agent → {SERVER}")
    token = login()
    aid = register(token)
    print(f"✓ Đã đăng ký máy '{PC_NAME}'. Mở app KENIOS (Windows App) hoặc {SERVER}/pc để điều khiển.")
    print("  Đang chạy... (Ctrl+C để thoát)")
    threading.Thread(target=screen_loop, args=(token, aid), daemon=True).start()
    control_loop(token, aid)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nĐã thoát.")
