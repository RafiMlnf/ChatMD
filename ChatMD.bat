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
set "EXTRACT_DIR=%TEMP%\ChatMD_6ea0d322"
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
IAAAAAA=
-----END CERTIFICATE-----
