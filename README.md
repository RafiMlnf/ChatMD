# ChatMD <img src="icon.png" width="32" height="32" />

Aplikasi pesan instan privat berbasis LAN dengan sistem token discovery. Tanpa database, tanpa log file, dan riwayat pesan hanya tersimpan di RAM.

## Persyaratan

* Server: Node.js (hanya untuk host server)
* Client: Windows OS (Python 3.x otomatis diinstall jika belum ada)

## Cara Penggunaan

### 1. Jalankan Server (Hanya di 1 PC)
* Buka folder `server`
* Jalankan `start-server.bat`
* Catat 5 karakter TOKEN yang muncul di layar.

### 2. Jalankan Client (Di PC lain)
* Jalankan `ChatMD.bat`
* Masukkan TOKEN server.
* Pilih kontak dari daftar untuk mulai mengobrol.

## Fitur & Keamanan

* Enkripsi: AES-128-GCM dengan kunci dinamis.
* Auto Discovery: Client mencari IP server secara otomatis menggunakan token via query UDP.
* Anti Forensik: Pesan hilang permanen dari RAM saat aplikasi ditutup.

## Navigasi Chat

* `/b` : Kembali ke menu utama/kontak.
* Q : Keluar dari aplikasi (di menu utama).