@echo off
title ChatMD Server
echo.
echo  ChatMD - WebSocket Server
echo.

:: Cek apakah Node.js terinstall
where node >nul 2>&1
if %errorlevel% neq 0 (
    echo  [ERROR] Node.js tidak ditemukan!
    echo          Download: https://nodejs.org/
    pause
    exit /b 1
)

:: Cek apakah dependensi sudah diinstall
if not exist "node_modules\ws" (
    echo  [*] Menginstall dependensi...
    npm install
    if %errorlevel% neq 0 (
        echo  [ERROR] npm install gagal!
        pause
        exit /b 1
    )
    echo.
)

:: Cek jika port 8765 sudah dipakai — matikan proses lama
echo  [*] Memeriksa port 8765...
for /f "tokens=5" %%p in ('netstat -ano 2^>nul ^| findstr ":8765 " ^| findstr "LISTENING"') do (
    echo  [!] Port 8765 dipakai oleh PID %%p — mematikan...
    taskkill /PID %%p /F >nul 2>&1
    timeout /t 1 /nobreak >nul
)

echo  [*] Menjalankan server...
echo  [*] Tekan Ctrl+C untuk stop server
echo.

node server.js

echo.
echo  [*] Server telah berhenti.
pause
