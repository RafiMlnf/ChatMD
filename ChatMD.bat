@echo off
setlocal enabledelayedexpansion
title ChatMD

:: ── Cari Python ──────────────────────────────────────────────────────────────
set PYTHON_CMD=

python --version >nul 2>&1
if %errorlevel% equ 0 ( set PYTHON_CMD=python & goto :python_found )

py --version >nul 2>&1
if %errorlevel% equ 0 ( set PYTHON_CMD=py & goto :python_found )

for %%P in (
    "%LocalAppData%\Programs\Python\Python313\python.exe"
    "%LocalAppData%\Programs\Python\Python312\python.exe"
    "%LocalAppData%\Programs\Python\Python311\python.exe"
    "C:\Python313\python.exe"
    "C:\Python312\python.exe"
    "C:\Python311\python.exe"
    "C:\Program Files\Python313\python.exe"
    "C:\Program Files\Python312\python.exe"
) do (
    if exist %%P ( set PYTHON_CMD=%%~P & goto :python_found )
)

:: Python tidak ditemukan
cls
echo.
echo  ChatMD - Volatile Intranet Chat
echo.
echo  [!] Python tidak ditemukan.
echo.
echo  [1] Install otomatis via winget
echo  [2] Buka halaman download Python
echo  [Q] Keluar
echo.
set /p PYCHOICE=" Pilihan: "

if /i "!PYCHOICE!"=="1" (
    echo  Menginstall Python 3.13...
    winget install -e --id Python.Python.3.13 --accept-package-agreements --accept-source-agreements
    python --version >nul 2>&1
    if !errorlevel! equ 0 ( set PYTHON_CMD=python & goto :python_found )
    py --version >nul 2>&1
    if !errorlevel! equ 0 ( set PYTHON_CMD=py & goto :python_found )
    echo.
    echo  [!] Tutup dan buka ulang jendela ini setelah install selesai.
    pause & exit /b 1
) else if /i "!PYCHOICE!"=="2" (
    start https://www.python.org/downloads/
    echo  Jalankan kembali setelah Python terinstall.
    pause & exit /b 1
) else (
    exit /b 0
)

:python_found

:: ── Ekstrak File Client Embedded ─────────────────────────────────────────────
:: Folder nama unik per versi: jika BAT diupdate, hash berbeda = folder baru = re-ekstrak
set "EXTRACT_DIR=%TEMP%\ChatMD_32c53e2d"
if not exist "%EXTRACT_DIR%" mkdir "%EXTRACT_DIR%"

:: Jika sudah terekstrak dengan hash yang sama, langsung skip
if exist "%EXTRACT_DIR%\chatmd_client.py" goto :deps_check

:: Ekstrak base64 dari dalam .bat ini menggunakan PowerShell
powershell -NoProfile -Command "$bat = Get-Content -LiteralPath '%~f0' -Encoding UTF8; $start = ($bat | Select-String -Pattern '^-----BEGIN CERTIFICATE-----$').LineNumber; $end = ($bat | Select-String -Pattern '^-----END CERTIFICATE-----$').LineNumber; if ($start -and $end) { $b64 = ($bat[($start)..($end-2)]) -join ''; $bytes = [Convert]::FromBase64String($b64); [IO.File]::WriteAllBytes('%EXTRACT_DIR%\client_files.zip', $bytes) }"

if not exist "%EXTRACT_DIR%\client_files.zip" (
    echo.
    echo  [!] Gagal mengekstrak file embedded. File .bat mungkin rusak.
    pause
    exit /b 1
)

powershell -NoProfile -Command "Expand-Archive -Force '%EXTRACT_DIR%\client_files.zip' '%EXTRACT_DIR%'" >nul 2>&1
del "%EXTRACT_DIR%\client_files.zip" >nul 2>&1

if not exist "%EXTRACT_DIR%\chatmd_client.py" (
    echo.
    echo  [!] Ekstrak gagal. File client tidak ditemukan.
    pause
    exit /b 1
)

:: ── Install dependensi jika belum ada ────────────────────────────────────────
:deps_check
!PYTHON_CMD! -c "import cryptography" >nul 2>&1
if !errorlevel! neq 0 (
    echo  Menginstall cryptography...
    !PYTHON_CMD! -m pip install cryptography --quiet --disable-pip-version-check
)

!PYTHON_CMD! -c "import websocket" >nul 2>&1
if !errorlevel! neq 0 (
    echo  Menginstall websocket-client...
    !PYTHON_CMD! -m pip install websocket-client --quiet --disable-pip-version-check
)

:: ── Menu Utama ────────────────────────────────────────────────────────────────
:menu
cls
echo.
echo  ChatMD - Volatile Intranet Chat
echo.
echo  [1] Jalankan sebagai Client (Nama Utama)
echo  [2] Jalankan sebagai Client Kedua (Bot_Testing)
echo  [Q] Keluar
echo.
set /p CHOICE=" Pilihan: "

if /i "!CHOICE!"=="1" goto :run_client
if /i "!CHOICE!"=="2" goto :run_bot
if /i "!CHOICE!"=="Q" exit /b 0
goto :menu

:: ── Jalankan Client ───────────────────────────────────────────────────────────
:run_client
cls
cd /d "%EXTRACT_DIR%"
set CHATMD_VERSION=32c53e2d
!PYTHON_CMD! chatmd_client.py
if %errorlevel% neq 0 (
    echo.
    echo  [!] ChatMD berhenti dengan error.
    pause
)
goto :menu

:: ── Jalankan Client Kedua (Bot_Testing) ──────────────────────────────────────
:run_bot
cls
cd /d "%EXTRACT_DIR%"
set CHATMD_VERSION=32c53e2d
!PYTHON_CMD! chatmd_client.py Bot_Testing
if %errorlevel% neq 0 (
    echo.
    echo  [!] ChatMD berhenti dengan error.
    pause
)
goto :menu

:: ── Akhir dari Script Utama ──────────────────────────────────────────────────
exit /b 0
-----BEGIN CERTIFICATE-----
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
-----END CERTIFICATE-----
