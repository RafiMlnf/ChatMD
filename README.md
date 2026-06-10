# ChatMD <img src="icon.png" width="32" height="32" />

Aplikasi pesan instan privat berbasis LAN dengan sistem token discovery. Tanpa database, tanpa log file, dan riwayat pesan hanya tersimpan di RAM.

## Unduh & Persyaratan

* **Client**: Windows OS (tinggal jalankan `ChatMD.exe`, tanpa perlu Python).
  * 📥 **[Download ChatMD.exe Terbaru di GitHub Releases](https://github.com/RafiMlnf/ChatMD/releases)**
* **Server**: Node.js (hanya di PC host server).

## Cara Penggunaan

### 1. Jalankan Server (Hanya di 1 PC)
* Masuk ke folder `server`.
* Jalankan `start-server.bat`.
* Catat 5 karakter **TOKEN** yang muncul di layar.

### 2. Jalankan Client (Di PC lain)
* Jalankan `ChatMD.exe`.
* Masukkan **TOKEN** server.
* Pilih kontak dari daftar untuk mulai mengobrol.

## Fitur & Keamanan

* Enkripsi: AES-128-GCM dengan kunci dinamis.
* Auto Discovery: Client mencari IP server secara otomatis menggunakan token via query UDP.
* Anti Forensik: Pesan hilang permanen dari RAM saat aplikasi ditutup.

## Navigasi Chat

* `/b` : Kembali ke menu utama/kontak.
* Q : Keluar dari aplikasi (di menu utama).