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
set "EXTRACT_DIR=%TEMP%\ChatMD_820a7492"
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
set CHATMD_VERSION=820a7492
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
set CHATMD_VERSION=820a7492
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
BgAAAAACAAIAewAAANErAAAAAA==
-----END CERTIFICATE-----
