"""
generate_bat.py — Buat ChatMD.bat AIO (All-In-One)
=====================================================
Script ini:
  1. Zip file-file client (chatmd_client.py + crypto_utils.py) dari folder ./client
  2. Hitung SHA256 hash ZIP sebagai versi unik (8 karakter)
  3. Embed hash + base64 ke dalam template .bat
  4. Simpan sebagai ChatMD.bat

Setiap kali file client berubah dan generate_bat.py dijalankan ulang,
hash berubah → folder temp di device berbeda → re-ekstrak otomatis.

Jalankan di root folder ChatMD:
  python generate_bat.py
"""

import base64
import hashlib
import io
import zipfile
import os

# ── File yang akan di-embed ────────────────────────────────────────────────────
CLIENT_DIR = os.path.join(os.path.dirname(__file__), "client")
FILES_TO_EMBED = [
    "chatmd_client.py",
    "crypto_utils.py",
]

OUTPUT_BAT = os.path.join(os.path.dirname(__file__), "ChatMD.bat")

# ── Template .bat ──────────────────────────────────────────────────────────────
# Placeholder {EXTRACT_HASH} diganti dengan 8 karakter SHA256 dari ZIP
BAT_TEMPLATE = """\
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
    "%LocalAppData%\\Programs\\Python\\Python313\\python.exe"
    "%LocalAppData%\\Programs\\Python\\Python312\\python.exe"
    "%LocalAppData%\\Programs\\Python\\Python311\\python.exe"
    "C:\\Python313\\python.exe"
    "C:\\Python312\\python.exe"
    "C:\\Python311\\python.exe"
    "C:\\Program Files\\Python313\\python.exe"
    "C:\\Program Files\\Python312\\python.exe"
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
set "EXTRACT_DIR=%TEMP%\\ChatMD_{EXTRACT_HASH}"
if not exist "%EXTRACT_DIR%" mkdir "%EXTRACT_DIR%"

:: Jika sudah terekstrak dengan hash yang sama, langsung skip
if exist "%EXTRACT_DIR%\\chatmd_client.py" goto :deps_check

:: Ekstrak base64 dari dalam .bat ini menggunakan PowerShell
powershell -NoProfile -Command "$bat = Get-Content -LiteralPath '%~f0' -Encoding UTF8; $start = ($bat | Select-String -Pattern '^-----BEGIN CERTIFICATE-----$').LineNumber; $end = ($bat | Select-String -Pattern '^-----END CERTIFICATE-----$').LineNumber; if ($start -and $end) { $b64 = ($bat[($start)..($end-2)]) -join ''; $bytes = [Convert]::FromBase64String($b64); [IO.File]::WriteAllBytes('%EXTRACT_DIR%\\client_files.zip', $bytes) }"

if not exist "%EXTRACT_DIR%\\client_files.zip" (
    echo.
    echo  [!] Gagal mengekstrak file embedded. File .bat mungkin rusak.
    pause
    exit /b 1
)

powershell -NoProfile -Command "Expand-Archive -Force '%EXTRACT_DIR%\\client_files.zip' '%EXTRACT_DIR%'" >nul 2>&1
del "%EXTRACT_DIR%\\client_files.zip" >nul 2>&1

if not exist "%EXTRACT_DIR%\\chatmd_client.py" (
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
"""


# ── Fungsi utama ───────────────────────────────────────────────────────────────

def build_zip_bytes() -> bytes:
    """Zip semua file client ke memory buffer dan kembalikan sebagai bytes."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for fname in FILES_TO_EMBED:
            fpath = os.path.join(CLIENT_DIR, fname)
            if not os.path.exists(fpath):
                raise FileNotFoundError(f"File tidak ditemukan: {fpath}")
            zf.write(fpath, arcname=fname)
            print(f"  [+] Ditambahkan: {fname} ({os.path.getsize(fpath):,} bytes)")
    return buf.getvalue()


def bytes_to_base64_lines(data: bytes, width: int = 76) -> str:
    """Encode bytes ke base64 dengan line wrapping."""
    b64 = base64.b64encode(data).decode("ascii")
    lines = [b64[i:i+width] for i in range(0, len(b64), width)]
    return "\n".join(lines)


def generate():
    print("=" * 60)
    print("  ChatMD BAT Generator")
    print("=" * 60)

    # 1. Buat zip
    print("\n[1/3] Membuat ZIP dari file client...")
    zip_bytes = build_zip_bytes()
    print(f"  -> Total ZIP: {len(zip_bytes):,} bytes")

    # 2. Hitung hash unik (8 karakter pertama SHA256)
    extract_hash = hashlib.sha256(zip_bytes).hexdigest()[:8]
    print(f"  -> Hash versi: {extract_hash}")

    # 3. Encode ke base64
    print("\n[2/3] Mengenkode ke Base64...")
    b64_data = bytes_to_base64_lines(zip_bytes)
    print(f"  -> Total Base64: {len(b64_data):,} chars")

    # 4. Gabungkan template + data + tulis
    print(f"\n[3/3] Menulis {os.path.basename(OUTPUT_BAT)}...")

    # Sisipkan hash ke template
    bat_body = BAT_TEMPLATE.replace("{EXTRACT_HASH}", extract_hash)

    # Pastikan line ending CRLF untuk .bat Windows
    bat_content = bat_body.replace("\r\n", "\n").replace("\n", "\r\n")

    payload = (
        "-----BEGIN CERTIFICATE-----\r\n"
        + b64_data.replace("\n", "\r\n")
        + "\r\n-----END CERTIFICATE-----\r\n"
    )

    with open(OUTPUT_BAT, "w", encoding="utf-8", newline="") as f:
        f.write(bat_content)
        f.write(payload)

    final_size = os.path.getsize(OUTPUT_BAT)
    print(f"  -> Selesai! {os.path.basename(OUTPUT_BAT)} ({final_size:,} bytes)")
    print()
    print("=" * 60)
    print(f"  BERHASIL! Hash versi: {extract_hash}")
    print("  Kirimkan ChatMD.bat saja ke PC lain.")
    print("  Update BAT = folder temp baru = re-ekstrak otomatis!")
    print("=" * 60)


if __name__ == "__main__":
    generate()
