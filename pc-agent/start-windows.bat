@echo off
chcp 65001 >nul
title KENIOS PC Agent
cd /d "%~dp0"

echo ============================================================
echo   KENIOS PC Agent - dieu khien may nay tu app/web KENIOS
echo ============================================================
echo.

REM 1) Kiem tra Python
python --version >nul 2>&1
if errorlevel 1 (
  echo [!] Chua co Python. Tai tai: https://www.python.org/downloads/
  echo     Khi cai NHO tich "Add python.exe to PATH".
  pause
  exit /b
)

REM 2) Cai thu vien
echo [1/2] Dang cai thu vien (lan dau hoi lau)...
python -m pip install --upgrade pip >nul 2>&1
python -m pip install requests pyautogui mss pillow

REM 3) Chay agent (se hoi TAI KHOAN + MAT KHAU KENIOS - giong dang nhap app)
echo [2/2] Dang chay agent...
echo   Sau khi dang nhap, mo app KENIOS -^> Kham pha -^> Windows App
echo   (hoac vao http://103.131.56.11/pc tren trinh duyet) de dieu khien.
echo.
python pc_remote.py
pause
