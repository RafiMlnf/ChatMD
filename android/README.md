# ChatMD Android Client (APK)

Aplikasi Client ChatMD khusus Android (Client Only). HP terhubung ke Server PC via Wi-Fi/Intranet.

---

## 📱 Cara Menggunakan

### Metode 1: Web App Mobile (Tanpa Install APK)
1. Jalankan `start-server.bat` di PC.
2. Di HP Android / iPhone, buka browser (Chrome / Safari) lalu akses:
   `http://<IP_SERVER_PC>:8765`
3. Masukkan Username & IP PC. Langsung terhubung & bisa digunakan!
4. Klik **"Add to Home Screen"** di browser HP agar menjadi ikon aplikasi PWA di HP.

---

### Metode 2: Install File ChatMD.apk
1. Buka folder `android/` di Android Studio atau compile dengan Gradle:
   ```bash
   cd android
   ./gradlew assembleRelease
   ```
2. Salin file `ChatMD.apk` ke HP Android lalu install.
3. Buka aplikasi **ChatMD** di HP, masukkan Username dan IP Server PC.

---

## 🔐 Keamanan & Fitur
- **Enkripsi End-to-End**: AES-128-GCM di-render via Web Crypto API.
- **Volatile Storage**: Pesan hanya tersimpan di RAM HP selama aplikasi terbuka.
- **Pure Client**: HP hanya bertindak sebagai pengirim/penerima pesan, tidak pernah menjadi server.
