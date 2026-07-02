@echo off
chcp 65001 >nul
title KENIOS PC Remote Agent
cd /d "%~dp0"

echo ============================================================
echo   KENIOS PC Remote Agent - Cai dat va chay tren Windows
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

REM 2) Cai thu vien can thiet
echo [1/3] Dang cai thu vien (lan dau hoi lau mot chut)...
python -m pip install --upgrade pip >nul 2>&1
python -m pip install fastapi uvicorn pyautogui mss pillow

REM 3) Nhap tai khoan / mat khau
echo.
set /p PC_USER="Dat TAI KHOAN (vi du: admin): "
set /p PASSWORD="Dat MAT KHAU: "
if "%PC_USER%"=="" set PC_USER=admin
if "%PASSWORD%"=="" set PASSWORD=kenios

REM 4) Mo cong 8765 tren Windows Firewall (can chay bang quyen Admin)
echo [2/3] Mo cong 8765 tren tuong lua...
netsh advfirewall firewall add rule name="KENIOS PC Remote" dir=in action=allow protocol=TCP localport=8765 >nul 2>&1

REM 5) Chay agent
echo [3/3] Dang chay agent...
echo.
echo   Tai khoan: %PC_USER%    Mat khau: %PASSWORD%    Cong: 8765
echo   Mo app KENIOS -^> Kham pha -^> PC Remote -^> nhap IP may nay + tai khoan/mat khau.
echo   (De ngat: dong cua so nay)
echo.
python pc_remote.py
pause
