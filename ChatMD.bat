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
set "EXTRACT_DIR=%TEMP%\ChatMD_8ebc8e14"
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
set CHATMD_VERSION=8ebc8e14
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
set CHATMD_VERSION=8ebc8e14
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
UEsDBBQAAAAIADdrz1wIkd2BRSYAAL6SAAAQAAAAY2hhdG1kX2NsaWVudC5wee097XLbSHL/XeV3
mIUqJ/BM0ZK13t0wq62TJdmrs2U5Er2Xi1aFAklQhAkCOHxY1jJM5VceIJUnvCdJd88HZgYAScm+
OFcV3K1FgjM9Mz09Pf054zjO40dHU784O2Z//Y//Zr8kkV+EUcBO4yLz46Bg+OPjRyP4dz72RlEY
xEUvvaPCZ34YsyN6xQ7TNApHUDeJ2W1YTAFAFMYBOwLACIK9P338yMHWHj8K52mSFSzJ1cf8Tvuc
jGZBob4W0yzwx2F8U70J54H68iFPYvVlnn8cZVXVfFrCWKp6wafiNvNT9WLo58F331bFy2GaJaMg
h75MsmTOirsU2mXi5/MUB+dHOIIt9osfhWM/D1kKCJsk2RzATHAcPfmCfXPAnNsw3n/m9B8/YvCk
WRgXrnP18nBw+OaaCbRP/fjOZ8Mg++BHfszGIftTGI+T27zndHg9hBp8Cgt3r4ONF9mdAEi9vA2G
HGWyo38Khpf0AuakW307SuI4GOEYjqIkD8Ynn0YBDenxo4A+slOqf5JlSWb1+OTi4vzimr0Jh5mf
3bFt1eYOp4ht6H9UAsYCqJAXfhSpzgsQjP0Rhzfz4z5Lw5SJYsyGtNmYR9ldWiQeTm8uhx3E9LbL
xgF9aBoW83MWGGObqMG98m/8SAKbJ+MyEjPUZ4tgWRvOOz8vQhiO0RdcGf7Yx0mcJNE4yNidDxSU
+3O/bTaRmP763//B/89eJ4iXuPCrd3+//wfO8vPh4OzYe3d+MWD0HDBEXwIYiD+GWRL3bgLAplbM
6TL7119O3x7J35wfvv/uudPpAOqOTy+Pzn85ufizBL8SNpbWgXznIIz3744PBydG//QuP2HPGNti
Pw8G71geZB9hPv2ySHbKdOwXAXPHwcQvo4IBvO+NHg1Oz07O3w8A3N4zDhjAjAMgGFaU8c1Nyd4f
v2PDLPHHI6Cjx48uTo7O3749ORp4xydvDv+MHdlnzKqaB3yVZcGIr2WWFMkceC4wrHenb195p28H
Jxe/HL7hI3m2awNAwsoYMbVZEKTAwj4CJ4UeX56ev1XNQVVnr7ff23XUBFZFDmrTYxZB9DodbHLq
51MGKAMeOfazkL04HNTp/bJARL6KkiGsva9OsJ9B6TdeCRQS+/Ogz/IiQxw6+JaTjRem5mss7EVh
XvQZ/nsFv13Dj1fX+ONt3le7zZXOzbHI2yQOeCFPUEEwhtdqm+ydfAQ26nY4pi8DQD9u3syfFeEE
K/qwB3wMvNTPijjItJZEH3gDW8iKCn8GlBPfAJf7UM4jf8rSIIcvnAzH4dAf+TSaGBv35rB1+jcB
9H4cjmhMXVySCHSxRJAX4a1/B30hKLAP8C54iDW28xNhgiUTtnDyIAbm6RDOgKBw5+Zfltgcjseb
QuEkC83WCJf49Vo2ijOQ5zDA3IsAjQam3sALiaiLYBJkQQzYen/KEUacm7AG/Bu+h3FIjZcZlCu8
MlS4wvovI/+GBA7YuWNqVnxunxteBRZAmcOSvoGuZyBQYF3+DfrTMrOyREbylhfQjt0ykaolgJb5
t6yMi3LG5kFcsrKAfQm4mD9BtjCj+Sbo+KsXB8E490StA/bSj/KgvoDfw7YXFrCtAtq++jL8vCX8
+BHwczaKAj9zO0JIAGYH+3URzF1nFOWO2LGxHIp4QIaC5l1OsYJgkV7pYwfJGv4KaCT/4oeXVFms
JpA7Mqgyy2FBxB+Q6mBlwS4xA7pwUWBNg3EHeCisO+CjObDucQkiRl70hEARfPA/AAixUosQWT0W
cfudntVwJUfhM0pgHcd5l3kwwVxaRp7uAenNQ6AkLw9/C1whtwhpSomNdTgA5IddxA8XlIJJ+Ale
TUBYWgj0/Lj/bMn6zNGLeFGAiwT+dfkL2j32v+dlcPzebTgGjeKAzf1P7v5uV7W3o4HoqIb9zL+B
WlPsD85ELwfVpEBtJJdjEVj16KXgu0K8BCFRQYA1r4HTBgw8IU6K6jftpxr4Hn6Ox64jBUBCJiwm
q5Lsi1RTeviPa5Yxxtet/0aIOqhw1lBkCNxkBrwwhi0kycb5wSArg4ZyWQCKzCjwbqdhEeQpfDwQ
LEAv1Vk1cBgIDpy+qOkRqDNKapjIgqLMYjGvsk4W5ChmwTxNnAX/abkwIFztXi+da9ECkFqMpR34
3+81EqlmmFRTmFwTxl7/2ugJNipnDxrmcJcLLLx0OlXnqMfOr7HT+5CEscsrClbBmQVpDR7n9e48
v+HMwVJEGPt1d3//6h+/m19xxeOavu/O2QKqLHXmw+ER318Lbm9+9c01ByHg1SGF8SRZC2h3fhU2
A9I3hMP5MAQ1ClFF+wJKOn8fO4NECXJA0f87t42D82FKmY9LuEJvZ1FyA7SF7wX7hYUTgaw0A9bN
pkleUJUPoD2yG1Q6ZSnaFPrs/eXJxdvDs5M/HJ2fvXs/4F9W8vHbMCaJkkvn0H/qgcW4zy91zd6q
JmWFOmzsL+4OJIMibDkAt8MZq+uAagvrb+0uISA5744cjRnITugrz7/lMiFuHgtZYPmHBUJYCgxY
HFSrg6VkA1vsBWogU1TUKwEdtskiZMDUUDfhu2aJ+1M+SrKgy4YlbsIz4LMz2AlZGAU3aPbh8C65
HsitNiAoBVk49/vMjyZ+XM7h2wy20y7b6bJelzbtPwg2UXVQfuwJHusCowIp15MbBIogMcl+jmAp
I+JaI2RZCg7gbtQLcz+CZoFM5e+Ot9P7g4QkeJMAeNXff3ZdX7FHkZ+T/EZ2Os1u99VXZOsyHVGX
B0JMwX6/P7VX6IDk5p3cnwTSAol2mbEf+XMaHkweaOKxj7QRxmlZwMYU7wxRTUBpm0M5C+IRTP+U
Ff4wo6KkDAg9yM9KEEryElc2WoM4t8uDMRIQwse3tgyGPMYDlhsWngdyYzTpGpqQkCHnd9W3jkbo
WKFnaE4HRnWrpACDwtNd0+80cG9YTibEB66urd9blSajFNcpoRwKE3Zfs2Se8u2Y/SRFP619j/gt
4V/TMiSiYM/MCsKSjgQhpFcvpKHy6fCavQ7mQz8K2b+xq2MQldjv2HGWgO78OoSlyl7CcoatulYX
97nXQYrWuz7KqxaWl/UaDgdT9ZXvpZVGgDPbohcYXBhkW4VrSygU0pKGZKtAtcrN91tsr6fxPq45
EJafignhlklOqsI4oAOQei4nkEpG1+a0w55Ur3RCsqRCtHjmoAyXBci0IE0C5jIH6nL5zK239IR9
i7CxmAXKHuSzHjsK0ExRLcg1bTfqbXxqeJvxujb3e5LEELMCm8jp/dQ3sDoOiStwpuDSfq9+4XPR
qc12bVE0zHdtTPo6e6I2jfq0dFbCmkRlPnUNila9kNQsjBpegKaIvm2bIGHJMENsSudNvMDkJVop
i2PhnLxOctBoiNL5D9zMwUHVqWKLvcO1KiZvDcXoFN9a1EIePqYcRSiYomuNFrSBSNjGvTwoYBf3
4/GaxQ40wt1cvdkQVDO301AGnxEpzLwkYHU0dRtmf+28WC2PSCV2h9u/ZtsgJ23/Gm93+ojOkxgk
pfaq+JBYcbCCOldX32J/9ElSm6mpNigBllQOeyq3phicGLbuaYkONlyfSqqjhToFysih6tRPy3x1
+01zvaq8EL1w1O0Fg4gj9eAAkflp94dtwuYL0BVI5V7dRMUuKjysmD81ErtOL03SdcOhinU+PmS/
Dm1+uabqWuzZSNnnSDkqsujJ0Rqk+2EeAHe+GyZ+Nj5FoszKtLhHa8Eub22QzIdJxGbTMkczXOrH
/hTk+ShaM1hzxSGkURLnoBiw4V0RcNvdqs7UzEL2U+cqTc8IKBsW22jaGwejZAxT5cd5uMlMIfUV
qBiplUKLyR8C56I1c4vGxvVwAKsoG2BHOojcPeJtSTYWr346YPvPNhgJPnWKFVYZArUhDJt4H1Z3
o7UvlOD3cYi4P6YZsJXvtgeU0gZOhDEPvTwKgtTd7e3uWe0LXsOVePlygqpRVNuC1nH7lVK5qTgq
1xT7GeY2AmHz/6jK2G7rSWJ0pCVATO5t3qlUyOMQVvzNTRhxdW8GmJ3BmqhGDNvJFFZJhCEPw3Lm
95R6d8OdmeihEy/gEyBR/1q57nq070vjwoVw/KChiHsOhb0a6A/pHaNdeuNynubuwinu0sDpM0d6
i9CGIG0c8L7ySC47qoGzMvJDIbbVHMFEaEqi4/qzC/oXkMKBh4W9KEnSLoM3+QHgq9tBC0cwT2Iy
Ind6XFnTrIscvVLWhhpkvrANjXV8S7uKEOvJusbx0WsxgY2BaQGSCUFR4o9zV7RkGsHo9z9enr9t
XpRSk+JvoLaHSAa4CJ67uwnr5OTWjFhVyQM+B+TbdTTI3pSWSOX4dSuQ+C4HmFfXHQWUtiUDrMBi
E9AwHiVznB+JaYS9AlTlX9ShGUbqiTMIMuEZzIMhSFUhqMWqz9uStkAMrAitY2jJuh9Tknlbj3IM
/dH7QlywrTQZvvXi8MKYJIkrmKf38SxGNyyvo3UPBErUyFTgEh8seqxh7wvm6IADDioqag5a5s7R
6ob2XZ+NyxTVQF0xECq7MXop31v8VrGKujvXKthQAgYMf+1yUrHQ+Qo++ri5xsyBkFZahGN/JnVT
FJQxhInsZLkdPyCh0D5iOdfrtgs72oCFOe1SDfuO7tKYONzKipFXWba0xRYiCN0T3wBO/7lnGmac
S5yWORDHxJEuEmHVFZ50atXwcTTTYQqKSBPV6syPjwhZH31q53kFRgCCFsPnRe00FcNThKXmuIGs
/sbzUm2AGqqS/5Upamu6wanFMT/CMEfCPH0SnM1Dvi9f4f5wj01/HBZlUabaXm/u5YZZ8mtOl2Di
zmsxBCVOIJWBTFdWwaVffMbUhMnGZZPGNt4wa5WI4WIElB74pE0SF0sqsaXPZmTXFcKMHCcgOvRT
ZobFjckcr2avMsesniRN+DbgmUx/NQx8yPW+0j60SszDATpL3Ya3wtemNWdL7UJWF6IV9158dXn8
PjJ7XZQiAUqLpNPI5T0P1TRinERUl0tWH1jURJUx/SUSRTidBoFeNYgyTy1GSnIEVQqNkyU57kq0
mlEnkVBKjAyvhCbhcZES+nFQ0KqhjVmud95haHLs406dTCaVXWkNC2liH6iJ117iOoBu6rGJDYzo
S3D0hd32EngERheKcfXMSBnFSK3IRVv0aYpa4zbkisPw+H4PVIsbBHSHqoKbgk4Ur43Z4hoDE5XY
1enZ4auT/gRYCPnpeDLBNTkC8nCeoqUyYMfADkgdecpDOryLYBTAIMbCKXguAngZ6pDSF+2TTEm+
aR5fLBMCeJ0Lru1DF5HlFf48DSNqFK2ixeqIry2mBnv1fX9nD+MEHWsMKEZrbrowjsnQblWsCoyS
CDbccPyJIrChcA8jZT65Tl+fR9kIk6Wu+qqiBmz43bce6XKqWAX+CdvrX+sW9nB+4wnFj3e9B9WF
wUsCMkzyYzkdHqx2Hi2R+sWUW6Tll+ATTN4YV4Hr/LsDOq6jZhG3N2si9TEChLk/CwB27hpNgfD3
CejfS2ZcU9b7hD0nFyMWKrROUXQFvHIl6rSWyjj8SxmoKAlRQBtoAK0hFMbsYVod0yB19Dkt0XiK
AeyasEL7ZYUmGBGMU7Zk73ZWF52FGujSWwj4ywWMb+mYFT+373r/n9AALHmLzD2qFZjS26HTwdSQ
iTWEiTAVSjpb497ZYi9wFYvMD2QEsDLDKU0Pt52CAMntGlWWD2zfaZRktvekSkbqvaP+TrYDUZA9
zYMIBM6us5DIiZNsjh+02Vg625uLCs1GZQx+RYsO9t9EvS07roaOj67Q4xMiE75BHfZT0YuSW1hs
HfItOb0U5ByYlN6HVP4N+IebcEJ/b4NhSh+G81RffpEPyjwytFeHZy8OLxzcsUQ7aFhnzsvTNyca
sQmz6cS5WlDVJegUGkktr5k7QA86MXOYsVZm3pExSRYe9HQjs0HsSV+kHM2DOUx1jpHsC2jU0far
VfYdHveuS8ZEWir/qWttRZkIvkdtvhJuuP+bGdYTTLHSTCcq9UnsfHpR8c40iKEQI1Kw6sSlthGE
w4u5AoppqvvFj8qglrWFzwOVJtDYxWi5/PMllVM+k2I8Mr8BZlNTc0wikLhaL72JPivxzMp+sKUg
8+crXlvmltSsX3r8B7fzCBkEWM4N6VWU9vBF0LoF9D4f+qC5c3JnvxPCC/pyQYK5yUvM8rSmUdEL
50U5Isx1hPTlcI95VQY6IkpcO02e8XEIu6p/5wkCXCcQ1nTkRvecBVTV3mxqpC9Lz3oRQSky8UVv
YNmpgW0jVAlGr746Bn2LXXJ+ga5yUDXiO/+f2A3NGqPgt3Eo5o4sJBTYQpLriLKEv9BwFQLrY7Uy
jTTyrv1GDEqC3sXYnj17sH+0Q/ZUfCAthSxJ5nI9JBn+jh3bzDyDyxVNNF+c1+zPr96eD05fXrN3
VQwiqa0iyWL5DXtNYUdPhyrZZ46ZWr0GZtSOB8oQ4vpy314F9zNJNYQN+E2e6E28rEoXb1G/TbSu
1gh1o4iwKlWmvq9u7XiQaeQ297gDz5uU8cgVyYdlFtn+NpmMbVjZcNqFaxBtdmHuTytBAZYtYE8v
ruWmVA1pmSSgtaHkelD5WM0fBY0fGE5CswhZeA80Q7r5MxlxDzRrr/i5o7rcy8rYm4DUDN3T+kuW
RuQx2Uc/Otjt0iogC+Lcj0sZ7K1KogEQyPJgb1drX2XhHuxWzdbS40777JjbnkQ+5VenlftTVUZ8
Be3cBSx6Mg15SRzduRpBXVCZHOgnYKIgz+ckPoJvMCcHbRajIrojsQcwKgLwEPFoJ6N4g4rkqsDc
N8nNTTBG+QdEQRCsNN+2mZiPhYUvhz99WBP9p08XWibusr/QkrwtAFUamUz0f33+dnD4mv358O0r
dnlyjH8OXwMDrp0IsHOfR9ZWxq0mq5sCPSAHHbrlhAUz4VH6MjG1K9PKUxHTTjsVuvJufEwl7PWU
Tc3a9QntXc78oUZAOQw+MGnD3Llny1IbiOD4iC2ZtPHWPRrbwR26Xn3q5yRFQFVX9tCWK2iDxUij
msCBNa477KcaaNtUIMhaaI9IQleLELS/BaWdWNYJNODqowLwTSHZ/i3wlzGeiEKeWtQx9WpLvntf
O/WqZjW56S8MiEqvqFffYhdoEQPejtqflRqaFLB5RgGKczcUET4tkTyY++33Kt6rYR6onsrC/Pb7
hr0boxVzNdF6hR0eB6ZjuSNeGmNqaBe1Hx3wj6wtYsxq/1m9lAg/nTgLoyvLxTbbZr83ACwXFaIt
DJPsI8lyg3l3ru41z7ubz/P/z0k1J41amQBuQDZLcfaK5T6blVtbiAHs6uIajxfIgnxq+qFqO8jV
P1+zAXqY8Tilhn2Jb8f5NLk1NmO3Ne6+SoZSinaTJwzkPkyIco+BVoHFvsrCMeyiYwxxi/1OlQm1
Il2Kx10PQWYEcYGPVR5Owncp3LzILvJUNI2Ki+2sWCfe838NN3u7cKJX0ZOQ3pFRNk7miUID15No
q1HZ6S2ZUcJsZus0Rn5AmyYjBrnqfIWqmJXiuaGvWizRhjYaloiReaPF5q8Jy69lX8ln3VzoTwsG
QU03evVQPXEdjvWnhr21CRYbJVc8MF9iNE3CUdA2Gz0UoVO30yvTNGicBHwEz6BEF+Cb/lQkgJGx
AEiGvK1Bex+a39KAeOegd//stPB9fGRSvOed/MvpwPMaNrA6xAuHslirF5u1cHHy8uLk8mdqpLn8
6ph56bksXN407oR7K4pP2C778YCq/SgkTyUqt2XjWL3WalyZ/k/72SAjQI/Qct4SW+MBfR/xjLpa
oI/9aNEtdlx5S+8tnDd227bhrxiD0f9TYkW8/5g/BxvayhFs2PvNe45P/ZeHJeqg/2mz3Jz7pOM8
IA1nE5b5gLSbe6TbbJJm09zIOja7YoWsXvf3z5H5EjktD0xjeUj6yqZpKw9JV6mnqbSnqLRsBqLZ
GvnUHaZ6zSYLG51yRjn+X91m9pmWtjLmVgxhWHHVKW2m+ZZ/UEbcKkqbbJpCqBeOPGGfN44+AJmC
1J5W+ds07ncNF0VX5LbwKmssQXV3oeyRXsY2CyEHVG2jW4FEmZ8pXk+cmMarVEDQVWhHst3PVSqq
m77SLXYah3kIO2nu88PhjpSri46AMw+hcDWMqawIKfYbR8eVoQSip83wJnmAfh5EZVZOGe8hP3JX
+OLueKA+P4VPeOSEf25HBmpAfTTpSJfqmnkSjXh57KegYKI2QKplK5ZUd9GCOM9vEOM2ED2GlvtG
oeAVd/NdG1O3xsG71re72p/b4MrdYiIyFCYEcAurQ6KZH8cmBJAKm2Xk297pDY2g2pjF8V5VmXXH
E2Ddbe7X275uPKWgPQf9HgokIRkosTHrfIsd+6lfVHp/HoyAsBrUf441PPekjEchgz6RMMddSmiR
bpw0aLc6Z6DqXP1sBCrf7mdU8c52Gx7pTOo0OK5A1aAjaqrSTUofqLVhXAZ2E6JnvJ6KZUL95emw
SYNp7OcKIH8pw6IJTnuyz7qWOBUYqQstpgR8Non15w4K2HuEQVkF4veEm5oOusICFK3f5opeheYt
6UgrwjQwYurC30LaBl0eXwLr4ziZlfPAJqHDN2/O/3Ry7BFrAYlicImOhc8IONOBHp8faSA/RRQr
in8/0YcClj/+Tccc5Cj/yL+nhfz7qQ00/JWgG4bwpNaFOuaOghmGdMz8qVjCPsoCeJwr5XZPRQ4F
IdUv/JKNM/9mB5jCzjhLUv6+JUIn9/BXbzQfNxtY6FeK5jRPGdOmVUS8j/lhPdSish1SGLw4xiMA
6dDnnSGA/IRWftx2lMwwACvMZyZ4LAhbWMBPMapWGOcCzvavjo11WB9WiGsFgzNK+XOYU2Sk9nPD
6vFaw3q1eo3GIy0yUjIt3GRtqmgR0s2JqZ+l0jQ/VY/upWb5EXZz7IkDjmkJoeHK7mmL+rFRgB0e
20RZmpxYuph+WcacF2xTFPG22rQFP+ixY/mxzxZaJ5ui8vSn4kAmAhp5tC61uM7TkMb/FGNOnU4T
PWwyLyhj5Ra90lF7uIDQG1uvYk4jVL/au66ohuut9B4donsiHrbJubV2hBM+QlqGfxdDrC1vrX/N
B+zg/qhaayH69bvid/NX3F3SZ4C0H2lxIdSfOIvlGNReb0yV9d/1Yw4LYFE+m5WwNMxjKQ2evhq9
6rPFJ1uxZXFMVZ/OJdQLCJ5ZFbg/em2mIFY9/Fjypa6Ab77Qm1CKm2Yla7jAdgo8ILwBVjuPr8bZ
wFGB8ulkRjMKvllAFbiu6ggld8Pd4H+DRQ8Urv52DLltnspZCaqumKm5P8vZ3u7ZiwZwZ4f/4l2e
/usJZrbsst/DP8++FX8aES5nFDQUOgxbo+yfFLAHs4i9+Xut47C9RX6ER1XlIMXSMECPjfhQVonM
63DUbgd9GOXic2/qJYRqWR+itkbDlVDbXHvT/I4H0/B38zMeKkupE3MZAs+zQ+QIl73eurmosowU
FmHKs5YsI/2h8nhSFO6Nkx6dwNLSCCa48eVc5b4FMRmyKygdZdsui8nOD20dVsl5FSEgUDrmdx0h
tFjtOZK9KmlkIm06C9nasr8Qg1g2BcjgY4XWG6k6CgzP0yEVptMAZ11Wjv7cI9lDRFUT7tpyPfSn
TapsFKvr6KsEpXppC0t6UVvZOoln8J7uZIll5jwq6JbVpJFhiBuW6GRi8dm1OtowdjwxQyRpLpox
o1Lc1bEtbeUSR90a0lZGZiT1q+42FF02MvvVgiE+D+eXEg1XlG7rSXNgZZHCY7Qlj2niYRUpaMcD
SKiNIRDyOIHmudl0WdxrSQiOuTIBSj7thp7LWtKaTEd6kAG21YbdkItSme3b02/s7lbBVfxMhVlY
+NWJAhRbZVapoVRv1crW4TU38JU1mwPrp8BtsZ/xbHvyG3FXyvtT+3QfZQqu23Q2wHmDz8c8mk5M
StNNOlZaRjILYpAa81HyMUAXyNd21K303o1FP0WouVtg75tddwOurMjTSsRVgPqJ5DktMvaXEsa9
kwV5CsgORLzex9DHC8SE907cwKgWH1XBxaPuF+vKdmjPimChS2MeFhOXOhrAuOSegkAK4ijoj1iO
LsYTB2KiLwrtiSF/G6TTAOPGI+aCNDtO5h3zrAI3TLtUssMNekpb4949eQoVZVnUDjAgGjjgf+vh
T7zQFnvX2JvdDnX1/JIbCykfuytGJ8LpJ1E4o3rCn8IPPBf3HfA/rvh2+NI7fXsy6MpfL8+PXnvH
ry4OzzpVZVx9+DdJVb3L8zceljWqehcn7y9PDo+PLypzx73qv7g4Pzw+Orwc1OsLVLq7vR/0X3Am
XddxMNqePKqELhBiZoQlfdLxijyJXE5Qxr5THUsjiR6VGpoieEl/l52eEEcr2ZPDG4NUS9G5OKsY
NYD/uOjXqt2gJ5hYUsZjL0yZwUn4WxqCcW2fGHDKD67AOlfOv5HNCv/ZIe3rV+l/xGJeyKjY7irP
md7RH9UQLM6XBXM/jNEfxgPK1Eh39PrWXljzATbYZpxfM34XQXWEErtacDxfs4UY7JUYzT+wb6+X
zF2o7ixzmG5LNG7vRWOwiABtH6jAF99rjfFwFqWzHyIueX8iP41e50GbiJ6CsONxkbjUTJe5zrPn
z3vafzCx5p2QNqJbL0KRj31IAR/cgKfWUKfNwyg36TlKZ13gNeNMcBVQ6kYfMcXefb73rFleNg+y
pGx7S41rtg5BVXFIJS1ESsqXnBJ9iXxDalEB1RrjbnoOKEwdMuFh/9UdL81VxUJEslfV8R10Q1uc
TT3HxzobCx8xXZIJCp7WbTzDsytntcmeWMUq1aUhmhF+UpziT+FEYUMvWXPV06IU2WaG/VFUBv22
Qs3S6pR5z8Cq1SdPjRBQuxq+hXBo6pAtHcVboLg8VTEOy3baY0fJEHPHbsLeZ/S0uniwkuQO8d5U
EXLx1QW2LyHskZsMU0s9fhusmxs3fVJKxjBJIlvyewHyUcjPr+eXo3LxS6XyybgtcXOqOjCP16ZM
bRRc+M9RMAwptrvs4w1G5ZT9hgSCpurMn3VhQnYiv4xHU861xMk0WuaFkM/QR8OFMHG1rTreeMyv
uFAp/9hDfmo+FkFFwoRE2oJ+qih2VgAlt4f4rF98ZZ9wad4oa6guPM6A0kxGwUxgYeaDHuGDvv+R
fdRjd0AQYu44/CDD5JTQS8jopXd10jXunxF3QZdZFIVDYNuw8eSF8RNgG7V5412YyPpQ0aMeJjHZ
rqZFkWIuqp6Jqt1AvHwqCrfc8QV6l9mVHnwlK6PWUFeK0Qf7ZGxEzcFiiQ1HJUMhYWtcsdGANJEU
gUf3+upnwOALeQAMsaP204DU9VkqUuguGIckE8DeniZ4J4cgEJQZYMI+UJ5RNtdzshvnipOO3kc6
tVfr8sEqwrosMUuC0xMe6W1cGdLUoGRu7FCtRsqukFwCy9Tzwarjld+hKpaV6LCDyoiFb0BiM3u4
ZH/9z/9iC20Uy47TBM45o5grYAAi07ciQIHOjeiPl30Q+fGqFfV9t9tGfrBmpD1Qo7tm0rFtUhYO
K6sTjZ0MTj0QkzndUDykzkwj/Rr29nk94dwTRVjBMGF7TMVBGxweEZRBJljEQ5s5q9+QPTg5e9dw
r/lAvsXQ9lvAgVxscXDbdD6dagINb+IEKoM25ND0Y+gErLYD6BomWfC03r+GKfpX3TDpvUBXwum5
K6euQ3P7m+3I+G2CV35m/qgAIUu2/LkzK/ayLzK32KV8lIVpYeNWoclBU+F87AmjSHpnJepbju4K
YqdtMI6kp+rKAD/l4dp6O3VZ7A3nfvcYn9mukLbwsLjcD79B3IEoUGaV6EGCQHU0gBHB/4NmW7mo
xAhDiPgnEq3xPgCMthN3X9Gd0upiTDQNZOFYiAQgDEh6gM3aWCmjJFV5gvDuyr5X/pr4hSL2JvKt
nZlnkucViq7Bp2BU0m0mXY0crtkTEmxhJB/xGljLYwCr80BSiKWjxB8P4D/t7efRe9MMEemvm/pM
E+RgxvIwvgOAwMLQAgDaH89wBaot6lbWM0z6/eqC9d9MUucYELg3DvPlBnftaBCJTZXhKlfAXq/5
YluXRFGSJ4/enNLNGALVivDxnoAuHcWB53LwH4GdFhVfoTv0BPVR7JJh1VdL6UAj0eu6n127yXfi
nKpughysuoJ2Y7FYmw9RsTRJo3HzWty17VaxeqvOa9FQ/Ay4OwajCoPvmAT2WcmzGoQDgJflBjkk
dT3BoGZ9wZMMpPGYB5fXTQMOA+rPyxm2Mjh/ffLWssjLYxnc59V9SDTbeMlsRzi3+jXTWnuWrjRq
nJy/FIaLmk/HNmGo2ybxgsqo9LNaQiRnbGHh7hreKSkTSzw0wZV5l9wywPegYRIFU3HPWq2tuhtb
ULBqpoPnWz+XgV/qdXVX7fp+cA2zCGCrZRrmp2VWTp76qD2v6JdFmqaBQlwkbrtqqs4b4xLlm3MO
atD1biBFz8RFpPOKrKvCRmx+k22Hy8fQvGBcFZdCYV5U4L9Vx28xEvT5kUfNZiinWnH7PR4YjqaZ
UgoLPKtIJAbgGel4z7Fw2ihNmpbAi8NBxcNq5hDZeseyTFl0ukpFQqWG5xPMuDd4UQ10yQxNhwZT
P9RMO9EM79++ybBTgonkHsVKtNx3ZJ6kJu880s45s+4+qoDW07mEAVneJ8Hj057z2whM6dJKyrj1
AVdSo3re263LmGLVvJLZFQ3pF34unL3SAE/JgfDi9B3sSrHFTtQU7XWapcqBbKTLz6PHlAyZg6jJ
ktbYtetzlBjM8bDfjAft8hwDC/smFuioi/rdOCs4DGreotu0sxRJhOdpIcfL5aUzTSANCawhaqd5
PuRpK+peCnfAB9K5H9Ypw7WCJ1Qf2LgA7c3y+3ONAL8FZSJJUn4WG0i/c79R+7vHESPqkIqGw2ga
Iq5FccFHrVMeVHJve66U/kpkkmvVq5T+lVlbJpDGsKta/q04EeIeYRi6D2mLPQcWi2GOZaq4eEOQ
RjsTRB5IBwLloBX6+iJT6wV5xko5iAKBlItDYWD1md36MBpIUYhHeFfUbBoCm7mk/pFdhxKR+REj
4mZVvl9cHJ71atIffrG2hcePQrwgHaVFzxNTjDJ8Nb9con/86H8AUEsDBBQAAAAIAAN0ylyOPSNP
nwUAAA4OAAAPAAAAY3J5cHRvX3V0aWxzLnB51VfdjtNGFL73Uxy8N7bYuErIBhp1W4VNIAssWpEt
tELInMSTZJrx2B2PF9IKiWdouazUd+MJ+gg9M2M7TvgRqtQLokixfP7P+c5PfN/3ztaoL8bw/u07
eJoJ1FwwOJdaoWQaDNFbqG2us7gkUhHlW8s6msw63d6dzv2zC5hIy8EzCVMmcqY874LJ1aqUuEEJ
gs8Vqi28dHpWCvP19iUEa/wtRQ0Ct0yFkXepWGe2RsUSeMi2EFzOHoZgTMy5hoR3iJQssoQBaiwh
QcWByWu4RgVn09HVxTh+OPkZvoGn54/PzGPkefcyZSwseL5mSrPXGrYoV6RswxVP4ZojPGPzWbbY
MD30ANbsdQAykwv2vNt7ATfbkjdB4+p5d/ACQs+ntHk8zTOlISvqpzmXWCw495YqS6EdbORCjXKy
yjW/ZkXkNBcRMkygUkA5pXR6nncE79+9dV84SEtD+Iq+FM99lJqD5AI5cMkhIXwQNDYUUXfQmW81
g+BWzxQAFhRs6ApVYIpULShYWiLJFRqpNhHpGxkMFATQj0CglLrcQHbNlOIEF5LJEVhCKCqyUhn5
eDy5N/rx0ZVhj6eTn+AU/P6twZ1B93a/n/T7vaTf7Z+c3Orf7if0PB+c3P7WBzgC3zVLx1WqQwUh
ICRsCbHIMIkpnCCEzvdgAioMogAIK4+IVjeMDTnoDhxLuI9jh2y2xFJoqPEeGbQZTQpfkaNZERE7
V5mMVkwH/i5w//gDYt0LRDqMOQytUq22zk/zId9i6xfZqdEclZKqIvhyG5ADToi9XrB8B/hoolSm
dmoU8oLBUxQls5SgodiEtEpVB655ght6EjyJYIqqLGDOVEl1M4gotOKEBsLHBhVuNFOtDEZ+o905
x5cgmAyaWELqaE3gMTLH0Osfk6LwS51dtr1dW8dqLbZY5JM1EsGYk188xSH8vm/+TcVx6KdiulRy
l3Pb9zMKVDBNk9QMWYOVhBP2CbpsQ9mhjqBnNy4849MQ6nq1EOjFDp/DaqIQ1T0ERiQ8mC/lXPAF
jC7Pv8rZsjdnbCsyt42CnGaNNKN7aABk25J+m6a0vxO5UTwvODTMNdjS1gJr7TpaKkbuia1dsUPR
tIHp0C2QoNu7G35kgxAI74Z7Plh219glLd0kS0k23EHwCJ7YtxXjnEBI/YI55Kwg54JnowfnlcqF
NkBwtY7qPFix412EhkBjJfBLvezc8cNjeJxJtofJprHrznemKRodRglz4pbDJzTZrNNba40k4hy3
BoyfyfuYVXk37V2x17t5jQUXJu2ZYOummuGnMn95WDksBK+ZTW+3eHddPoQHfIONaeprmj+2o7HU
jHbVhryAFa5QRHue781LN5E/MilbWfhvE9O/rDyblyYVrSlos+QmpUl+a+KZ8Qzf0clEheoOhgY5
Ke3aFAXU9SMAfoFNGmSCXhPAZMI2ECwyRbOYSl8brCFLFp8P6VKqwBe/4nodk42K1O0NX3gfZq1B
YrNrasjWIKog29LYBmmVy4n9oaNzp/mIDlebmisjkQhhp6jrk4SXc1y7Gpu5WqDA9WeS0UDUgmC4
hwszU1srC4LaRJolfGl5fthlq2qqg7CbPqra8ODsmzGx7BCbhuAX8lTaQ5pKX5RUfnfh0IFTGQv/
l9HtEa7iWGLK4hhO6USK45RCiGPfZZyuWUk3ximRqv8QZ/bmdb5fGd+J5rui0SmXC4MZf4oic2eP
k7oB//z97g/XXdTtxFL3vJNx8pQtotQAIY6w5cPS300B2r9O7o2/z1L9S6E7mlhIwSF9zFp0MlTT
sShogDsHTqs4jsG/OJ9djK7Opjf8djLe//WnXRcWISYDl6PZbDKuoXAENi0ExFdYz3Om5ixBc8ya
oW62fJ2K3idyUXlkknXDcvTIn8dWm0OlWyMfeuZ4Ssl/LZlkRXHg4r9QSwECFAAUAAAACAA3a89c
CJHdgUUmAAC+kgAAEAAAAAAAAAAAAAAAtoEAAAAAY2hhdG1kX2NsaWVudC5weVBLAQIUABQAAAAI
AAN0ylyOPSNPnwUAAA4OAAAPAAAAAAAAAAAAAAC2gXMmAABjcnlwdG9fdXRpbHMucHlQSwUGAAAA
AAIAAgB7AAAAPywAAAAA
-----END CERTIFICATE-----
