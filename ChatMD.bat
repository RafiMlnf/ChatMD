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
set "EXTRACT_DIR=%TEMP%\ChatMD_7a7b8854"
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
set CHATMD_VERSION=7a7b8854
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
set CHATMD_VERSION=7a7b8854
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
