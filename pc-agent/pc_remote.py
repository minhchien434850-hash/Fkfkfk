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
    "pageup": "pageup", "pagedown": "pagedown", "insert": "insert",
    "capslock": "capslock", "printscreen": "printscreen",
    "ctrl": "ctrl", "alt": "alt", "shift": "shift",
    "win": "winleft", "cmd": "command", "option": "option",
    "f1": "f1", "f2": "f2", "f3": "f3", "f4": "f4", "f5": "f5", "f6": "f6",
    "f7": "f7", "f8": "f8", "f9": "f9", "f10": "f10", "f11": "f11", "f12": "f12",
}
# Cấu hình chất lượng/fps màn hình (đổi bằng biến môi trường nếu muốn).
SCR_MAXW = int(os.environ.get("KENIOS_MAXW", "1280"))     # bề rộng tối đa khung gửi
SCR_QUALITY = int(os.environ.get("KENIOS_QUALITY", "60"))  # chất lượng JPEG 1..95
SCR_FPS = float(os.environ.get("KENIOS_FPS", "7"))         # số khung/giây mục tiêu

try:
    import pyperclip   # đồng bộ clipboard (tuỳ chọn)
except Exception:
    pyperclip = None
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
        elif t == "moveto":
            # Di chuyển tuyệt đối theo tỉ lệ 0..1 của màn hình (điều khiển chính xác).
            w, h = pyautogui.size()
            pyautogui.moveTo(int(float(cmd.get("x", 0)) * w), int(float(cmd.get("y", 0)) * h), duration=0)
        elif t == "click":
            b = cmd.get("b", "left")
            if b == "double": pyautogui.doubleClick()
            elif b == "right": pyautogui.click(button="right")
            else: pyautogui.click()
        elif t == "drag":
            # Kéo thả từ điểm hiện tại theo delta (giữ chuột trái).
            pyautogui.dragRel(int(cmd.get("dx", 0)), int(cmd.get("dy", 0)), duration=0.1, button="left")
        elif t == "scroll":
            pyautogui.scroll(-int(cmd.get("dy", 0)) * 60)
        elif t == "text":
            pyautogui.write(str(cmd.get("s", "")), interval=0)
        elif t == "key":
            k = KEYMAP.get(cmd.get("k", ""))
            if k: pyautogui.press(k)
        elif t == "hotkey":
            # Tổ hợp phím, ví dụ ["ctrl","c"] / ["alt","tab"] / ["ctrl","shift","esc"].
            keys = [KEYMAP.get(x, x) for x in cmd.get("keys", []) if x]
            if keys: pyautogui.hotkey(*keys)
        elif t == "clip":
            # Dán văn bản từ điện thoại vào clipboard PC rồi Ctrl/Cmd+V.
            s = str(cmd.get("s", ""))
            if pyperclip is not None:
                pyperclip.copy(s)
                pyautogui.hotkey("command" if OS_NAME == "Darwin" else "ctrl", "v")
            else:
                pyautogui.write(s, interval=0)
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


# Token dùng chung giữa 2 luồng; tự làm mới khi hết hạn (401) để agent chạy mãi.
_AUTH = {"token": ""}

def _refresh_token():
    try:
        _AUTH["token"] = login()
        print("↻ Đã đăng nhập lại (token mới).")
    except SystemExit:
        raise
    except Exception as e:
        print("Làm mới token lỗi:", e); time.sleep(3)


def control_loop(aid: str):
    delay = 1.0 / 15.0   # hỏi lệnh ~15 lần/giây → phản hồi nhanh
    while True:
        try:
            hdr = {"Authorization": f"Bearer {_AUTH['token']}"}
            r = requests.post(f"{SERVER}/pc/heartbeat", headers=hdr, json={"agent_id": aid}, timeout=10)
            if r.status_code == 401:
                _refresh_token(); continue
            if r.status_code == 200:
                for cmd in r.json().get("commands", []):
                    do(cmd)
            time.sleep(delay)
        except Exception:
            time.sleep(1)


def screen_loop(aid: str):
    interval = 1.0 / max(1.0, SCR_FPS)
    idle = 0
    last_sig = None
    with mss.mss() as sct:
        mon = sct.monitors[1]
        while True:
            try:
                img = sct.grab(mon)
                pil = Image.frombytes("RGB", img.size, img.rgb)
                if pil.width > SCR_MAXW:
                    pil = pil.resize((SCR_MAXW, int(pil.height * SCR_MAXW / pil.width)), Image.BILINEAR)
                # Bỏ qua khung TRÙNG (không đổi) → đỡ băng thông, giảm giật.
                sig = hash(pil.resize((48, 27)).tobytes())
                if sig == last_sig:
                    idle = min(idle + 1, 8)          # màn hình đứng yên → giãn nhịp gửi
                    time.sleep(interval * (1 + idle * 0.5)); continue
                last_sig = sig; idle = 0
                buf = io.BytesIO(); pil.save(buf, format="JPEG", quality=SCR_QUALITY)
                b64 = base64.b64encode(buf.getvalue()).decode()
                hdr = {"Authorization": f"Bearer {_AUTH['token']}"}
                rr = requests.post(f"{SERVER}/pc/frame", headers=hdr,
                                   json={"agent_id": aid, "jpg": b64}, timeout=15)
                if rr.status_code == 401:
                    _refresh_token()
            except Exception:
                pass
            time.sleep(interval)


def main():
    print(f"KENIOS PC Agent → {SERVER}")
    _AUTH["token"] = login()
    aid = register(_AUTH["token"])
    print(f"✓ Đã đăng ký máy '{PC_NAME}'. Mở app KENIOS (Windows App) hoặc {SERVER}/pc để điều khiển.")
    print(f"  Màn hình: {SCR_MAXW}px · chất lượng {SCR_QUALITY} · ~{int(SCR_FPS)} fps. (Ctrl+C để thoát)")
    threading.Thread(target=screen_loop, args=(aid,), daemon=True).start()
    control_loop(aid)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nĐã thoát.")
