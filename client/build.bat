@echo off
setlocal enabledelayedexpansion
title ChatMD Builder
echo.
echo  ============================================================
echo   ChatMD - Build Standalone EXE (PyInstaller)
echo   Hasil: dist\chatmd-client.exe (zero dependensi)
echo  ============================================================
echo.

:: ── 1. Cek Python ────────────────────────────────────────────
echo  [1/4] Memeriksa Python...
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo  [!] Python tidak ditemukan. Install dulu dari https://python.org
    pause
    exit /b 1
)
for /f "tokens=*" %%v in ('python --version 2^>^&1') do echo  [OK] %%v

:: ── 2. Install semua dependensi build ─────────────────────────
echo.
echo  [2/4] Menginstall dependensi build...
pip install cryptography websocket-client pyinstaller --quiet --disable-pip-version-check
if %errorlevel% neq 0 (
    echo  [!] pip install gagal!
    pause
    exit /b 1
)
echo  [OK] Semua dependensi siap

:: ── 3. Bersihkan build lama ───────────────────────────────────
echo.
echo  [3/4] Membersihkan build sebelumnya...
if exist "dist\chatmd-client.exe" del /q "dist\chatmd-client.exe"
if exist "build" rmdir /s /q "build" >nul 2>&1
if exist "chatmd-client.spec" del /q "chatmd-client.spec" >nul 2>&1

:: ── 4. Build dengan PyInstaller ───────────────────────────────
echo.
echo  [4/4] Membangun EXE... (1-3 menit, harap tunggu)
echo.

python -m PyInstaller ^
    --onefile ^
    --console ^
    --name "chatmd-client" ^
    --collect-all cryptography ^
    --collect-all websocket ^
    --hidden-import cryptography.hazmat.primitives.ciphers.aead ^
    --hidden-import cryptography.hazmat.backends.openssl ^
    --hidden-import cryptography.hazmat.bindings._rust ^
    --hidden-import websocket ^
    --hidden-import ctypes ^
    --hidden-import ctypes.wintypes ^
    chatmd_client.py

if %errorlevel% neq 0 (
    echo.
    echo  [!] Build GAGAL. Lihat error di atas.
    pause
    exit /b 1
)

:: ── Hasil ──────────────────────────────────────────────────────
echo.
echo  ============================================================
echo   BUILD BERHASIL!
echo.
echo   File : dist\chatmd-client.exe
echo   Mode : Standalone (tidak butuh Python atau pip)
echo.
echo   Distribusikan dist\chatmd-client.exe ke semua laptop.
echo   User cukup double-click — langsung jalan!
echo  ============================================================
echo.
pause
