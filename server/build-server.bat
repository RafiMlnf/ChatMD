@echo off
setlocal enabledelayedexpansion
title ChatMD Server Builder
echo.
echo  ============================================================
echo   ChatMD Server - Build Standalone EXE (PyInstaller)
echo   Hasil: dist\ChatMD-Server.exe
echo  ============================================================
echo.

:: ── 1. Cek Python ────────────────────────────────────────────
echo  [1/5] Memeriksa Python...
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo  [!] Python tidak ditemukan. Install dulu dari https://python.org
    pause
    exit /b 1
)
for /f "tokens=*" %%v in ('python --version 2^>^&1') do echo  [OK] %%v

:: ── 2. Install semua dependensi build ─────────────────────────
echo.
echo  [2/5] Menginstall dependensi build...
pip install pyinstaller --quiet --disable-pip-version-check
if %errorlevel% neq 0 (
    echo  [!] pip install gagal!
    pause
    exit /b 1
)
echo  [OK] PyInstaller siap

:: ── 3. Siapkan file auto-update ──────────────────────────────
echo.
echo  [3/5] Menyiapkan berkas auto-update (generate_bat.py)...
python ..\generate_bat.py
if %errorlevel% neq 0 (
    echo  [!] Gagal menjalankan generate_bat.py. File auto-update tidak siap.
    pause
    exit /b 1
)

:: ── 4. Bersihkan build lama ───────────────────────────────────
echo.
echo  [4/5] Membersihkan build sebelumnya...
if exist "dist\ChatMD-Server.exe" del /q "dist\ChatMD-Server.exe"
if exist "..\ChatMD-Server.exe" del /q "..\ChatMD-Server.exe"
if exist "build" rmdir /s /q "build" >nul 2>&1
if exist "ChatMD-Server.spec" del /q "ChatMD-Server.spec" >nul 2>&1

:: ── 5. Build dengan PyInstaller ───────────────────────────────
echo.
echo  [5/5] Membangun EXE... (harap tunggu)
echo.

python -m PyInstaller ^
    --onefile ^
    --console ^
    --name "ChatMD-Server" ^
    --icon "IconServer.ico" ^
    start_server.py

if %errorlevel% neq 0 (
    echo.
    echo  [!] Build GAGAL. Lihat error di atas.
    pause
    exit /b 1
)

:: Salin hasil build ke root workspace
copy "dist\ChatMD-Server.exe" "..\ChatMD-Server.exe" >nul

:: ── Hasil ──────────────────────────────────────────────────────
echo.
echo  ============================================================
echo   BUILD BERHASIL!
echo.
echo   File : ChatMD-Server.exe (disalin ke root folder)
echo   Mode : Standalone (menggunakan iconserver.ico)
echo.
echo   User cukup double-click untuk menjalankan server!
echo  ============================================================
echo.
pause
