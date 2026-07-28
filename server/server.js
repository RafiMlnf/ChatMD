/**
 * ChatMD - WebSocket Server (Node.js + ws)
 *
 * Arsitektur:
 *  - Semua data user disimpan di Map in-memory (volatile)
 *  - Rate limiting: sliding window 3 msg/3 detik per socket
 *  - Tidak ada file I/O, tidak ada database
 *  - Otomatis membersihkan user saat disconnect
 *  - Token-based discovery via UDP broadcast (port 8766)
 */

"use strict";

const { WebSocketServer, WebSocket } = require("ws");
const dgram = require("dgram");
const http  = require("http");
const fs    = require("fs");
const path  = require("path");
const os    = require("os");
const readline = require("readline");

// ─── Konfigurasi File Filter ─────────────────────────────────────
const CONFIG_FILE = path.join(__dirname, "config.json");
let allowedFileTypes = {
  "png": true,
  "jpg": true,
  "jpeg": true,
  "gif": true,
  "webp": true,
  "bmp": true,
  "xls": true,
  "xlsx": true,
  "txt": true,
  "pdf": true,
  "csv": true,
  "ppt": true,
  "pptx": true
};

const startupLogs = [];

try {
  if (fs.existsSync(CONFIG_FILE)) {
    const data = JSON.parse(fs.readFileSync(CONFIG_FILE, "utf8"));
    if (data && typeof data.allowed_file_types === "object") {
      allowedFileTypes = { ...data.allowed_file_types };
    }
  } else {
    const defaultConfig = {
      allowed_file_types: allowedFileTypes
    };
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(defaultConfig, null, 2), "utf8");
    startupLogs.push("[*] File config.json default dibuat");
  }
} catch (err) {
  startupLogs.push(`[!] Gagal memuat/menulis config.json: ${err.message}`);
}

// ─── Konfigurasi ────────────────────────────────────────────────
const PORT            = parseInt(process.env.CHATMD_PORT || process.env.VINC_PORT || "8765", 10);
const DISCOVERY_PORT  = parseInt(process.env.CHATMD_DISC_PORT || "8766", 10);
const UPDATE_PORT     = PORT + 2;  // HTTP server untuk auto-update client
const BROADCAST_INTERVAL = 2000; // ms antar broadcast UDP
const RATE_LIMIT_MAX    = 3;     // maksimal N pesan...
const RATE_LIMIT_WINDOW = 3000;  // ...dalam X milidetik (sliding window)

// ─── Token & IP ──────────────────────────────────────────────────

/**
 * Generate token 5 karakter: huruf kapital + angka.
 * Menghindari karakter yang mirip (0/O, 1/I/L).
 */
function generateToken() {
  const chars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  let t = "";
  for (let i = 0; i < 5; i++) t += chars[Math.floor(Math.random() * chars.length)];
  return t;
}

/**
 * Ambil IP lokal pertama yang bukan loopback (IPv4).
 */
function getLocalIP() {
  const ifaces = os.networkInterfaces();
  for (const name of Object.keys(ifaces)) {
    for (const iface of ifaces[name]) {
      if (iface.family === "IPv4" && !iface.internal) return iface.address;
    }
  }
  return "127.0.0.1";
}

const SESSION_TOKEN = generateToken();
const LOCAL_IP      = getLocalIP();


// ─── Keybind & Menu System ───────────────────────────────────────
let menuActive = false;
let menuSelectedIndex = 0;
const logBuffer = [];
let waitingForShutdownConfirmation = false;

function serverLog(...args) {
  const msg = args.map(arg => typeof arg === 'object' ? JSON.stringify(arg) : arg).join(' ');
  if (menuActive) {
    logBuffer.push(msg);
  } else {
    console.log(msg);
  }
}

function serverWarn(...args) {
  const msg = args.map(arg => typeof arg === 'object' ? JSON.stringify(arg) : arg).join(' ');
  if (menuActive) {
    logBuffer.push(`\x1b[33m${msg}\x1b[0m`);
  } else {
    console.warn(msg);
  }
}

function serverError(...args) {
  const msg = args.map(arg => typeof arg === 'object' ? JSON.stringify(arg) : arg).join(' ');
  if (menuActive) {
    logBuffer.push(`\x1b[31m${msg}\x1b[0m`);
  } else {
    console.error(msg);
  }
}

function renderMenu() {
  console.clear();
  console.log("\x1b[36m==================================================\x1b[0m");
  console.log("\x1b[1m\x1b[35m         CHATMD SERVER - FILE FILTER LIST         \x1b[0m");
  console.log("\x1b[36m==================================================\x1b[0m");
  console.log(" Gunakan [\x1b[1m▲\x1b[0m/\x1b[1m▼\x1b[0m] Panah untuk pilih, [\x1b[1mSpasi\x1b[0m] untuk toggle");
  console.log(" Tekan [\x1b[1mEnter\x1b[0m] untuk simpan, [\x1b[1mCtrl+L\x1b[0m] / [\x1b[1mEsc\x1b[0m] untuk batal\n");

  const fileTypeKeys = Object.keys(allowedFileTypes);
  for (let i = 0; i < fileTypeKeys.length; i++) {
    const key = fileTypeKeys[i];
    const isSelected = i === menuSelectedIndex;
    const isChecked = allowedFileTypes[key];

    const cursorStr = isSelected ? "\x1b[33m > \x1b[0m" : "   ";
    const checkboxStr = isChecked ? "\x1b[32m[X]\x1b[0m" : "\x1b[31m[ ]\x1b[0m";
    const labelStr = isSelected ? `\x1b[1m\x1b[37m${key}\x1b[0m` : `\x1b[90m${key}\x1b[0m`;

    console.log(`${cursorStr}${checkboxStr} ${labelStr}`);
  }
  console.log("\x1b[36m==================================================\x1b[0m");
}

function loadConfig() {
  try {
    if (fs.existsSync(CONFIG_FILE)) {
      const data = JSON.parse(fs.readFileSync(CONFIG_FILE, "utf8"));
      if (data && typeof data.allowed_file_types === "object") {
        allowedFileTypes = { ...data.allowed_file_types };
      }
    }
  } catch (err) {
    // Silent fail
  }
}

function exitMenu(saveChanges) {
  menuActive = false;
  console.clear();
  
  let statusMsg = "";
  if (saveChanges) {
    try {
      const configData = {
        allowed_file_types: allowedFileTypes
      };
      fs.writeFileSync(CONFIG_FILE, JSON.stringify(configData, null, 2), "utf8");
      statusMsg = "\x1b[32m[*] Konfigurasi disimpan dan diterapkan!\x1b[0m\n";
    } catch (err) {
      statusMsg = `\x1b[31m[!] Gagal menyimpan config.json: ${err.message}\x1b[0m\n`;
    }
  } else {
    loadConfig();
    statusMsg = "\x1b[33m[*] Perubahan dibatalkan.\x1b[0m\n";
  }

  // Print initial server info
  console.log("--------------------------------------------");
  console.log(`  IP Address : ${LOCAL_IP}`);
  console.log(`  Port       : ${PORT}`);
  console.log(`  TOKEN      : ${SESSION_TOKEN}`);
  console.log("--------------------------------------------\n");

  if (statusMsg) {
    console.log(statusMsg);
  }

  console.log(`[*] Server aktif di ws://${LOCAL_IP}:${PORT}`);
  console.log(`[*] Discovery UDP broadcast di port ${DISCOVERY_PORT}`);
  console.log(`[*] Rate limit: ${RATE_LIMIT_MAX} pesan / ${RATE_LIMIT_WINDOW / 1000} detik`);
  console.log(`[*] Tekan Ctrl+C untuk shutdown`);
  console.log(`[*] Tekan Ctrl+L untuk membuka menu filter file\n`);

  // Flush buffered logs
  if (logBuffer.length > 0) {
    console.log("[*] Riwayat aktivitas selama menu dibuka:");
    while (logBuffer.length > 0) {
      console.log(logBuffer.shift());
    }
    console.log("");
  }
}

function handleServerKeypress(str, key) {
  if (!key) return;
  if (key.ctrl && key.name === 'c') {
    shutdown();
    return;
  }

  if (waitingForShutdownConfirmation) {
    const char = str ? str.toLowerCase() : "";
    if (char === 'y') {
      waitingForShutdownConfirmation = false;
      process.stdout.write("Y\n");
      shutdown();
      return;
    } else if (char === 'n' || key.name === 'escape') {
      waitingForShutdownConfirmation = false;
      const inputChar = key.name === 'escape' ? 'Esc' : 'N';
      process.stdout.write(`${inputChar}\n\x1b[32m[*] Server tetap berjalan.\x1b[0m\n\n`);
      return;
    }
    return; // block other keypresses
  }

  if (key.ctrl && key.name === 'l') {
    if (!menuActive) {
      menuActive = true;
      menuSelectedIndex = 0;
      renderMenu();
    } else {
      exitMenu(false); // Cancel
    }
    return;
  }

  if (menuActive) {
    const fileTypeKeys = Object.keys(allowedFileTypes);
    if (key.name === 'up') {
      menuSelectedIndex = (menuSelectedIndex - 1 + fileTypeKeys.length) % fileTypeKeys.length;
      renderMenu();
    } else if (key.name === 'down') {
      menuSelectedIndex = (menuSelectedIndex + 1) % fileTypeKeys.length;
      renderMenu();
    } else if (key.name === 'space') {
      const typeKey = fileTypeKeys[menuSelectedIndex];
      allowedFileTypes[typeKey] = !allowedFileTypes[typeKey];
      renderMenu();
    } else if (key.name === 'return') {
      exitMenu(true); // Save
    } else if (key.name === 'escape') {
      exitMenu(false); // Cancel
    }
  }
}

readline.emitKeypressEvents(process.stdin);
if (process.stdin.isTTY) {
  process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdin.on('keypress', handleServerKeypress);
}

// ─── In-Memory Storage ──────────────────────────────────────────
// Map<socketId, { username: string, socket: WebSocket, msgTimestamps: number[] }>
const users = new Map();
let nextId = 1;

// ─── Utilitas ───────────────────────────────────────────────────

/**
 * Broadcast daftar username aktif ke semua klien yang terkoneksi.
 */
function broadcastUserList() {
  const userList = Array.from(users.values())
    .filter((u) => u.username !== null)
    .map((u) => u.username);
  const payload = JSON.stringify({ type: "user_list", users: userList });

  serverLog(`[*] Broadcast daftar user aktif (${userList.length} user): [${userList.join(", ")}]`);

  for (const [, userData] of users) {
    if (userData.socket.readyState === WebSocket.OPEN) {
      userData.socket.send(payload);
    }
  }
}

/**
 * Kirim pesan JSON ke socket tertentu. Aman (catch error).
 */
function sendTo(socket, obj) {
  if (socket.readyState === WebSocket.OPEN) {
    try {
      socket.send(JSON.stringify(obj));
    } catch (err) {
      // socket sudah mati, abaikan
    }
  }
}

/**
 * Rate limiting — sliding window.
 * Kembalikan true jika pesan DIIZINKAN, false jika melebihi batas.
 */
function checkRateLimit(userData) {
  const now = Date.now();
  // Hapus timestamp yang sudah di luar window
  userData.msgTimestamps = userData.msgTimestamps.filter(
    (ts) => now - ts < RATE_LIMIT_WINDOW
  );

  if (userData.msgTimestamps.length >= RATE_LIMIT_MAX) {
    return false; // terlalu cepat
  }

  userData.msgTimestamps.push(now);
  return true;
}

/**
 * Cari userData berdasarkan username (case-insensitive).
 * Kembalikan [socketId, userData] atau null.
 */
function findUserByName(username) {
  for (const [id, data] of users) {
    if (data.username && data.username.toLowerCase() === username.toLowerCase()) {
      return [id, data];
    }
  }
  return null;
}

// ─── Handler pesan per jenis ─────────────────────────────────────

function handleRegister(socketId, userData, data) {
  const raw = (data.username || "").trim();

  // Validasi username: alfanumerik + spasi + underscore + dash + titik + @ , 1–32 karakter
  if (!/^[\w\-.@ ]{1,32}$/.test(raw)) {
    serverWarn(`[!] REGISTER FAILED: Username "${raw}" invalid format (ip=${userData.ip})`);
    sendTo(userData.socket, {
      type: "error",
      message: "Username tidak valid. Gunakan huruf, angka, titik, atau dash.",
    });
    return;
  }

  // Cek duplikasi username
  const existing = findUserByName(raw);
  if (existing) {
    serverWarn(`[!] REGISTER FAILED: Username "${raw}" already in use (ip=${userData.ip})`);
    sendTo(userData.socket, {
      type: "error",
      message: `Username "${raw}" sudah digunakan. Tutup sesi lama terlebih dahulu.`,
    });
    return;
  }

  userData.username = raw;
  serverLog(`[+] REGISTER  id=${socketId} username=${raw}`);

  sendTo(userData.socket, {
    type: "registered",
    username: raw,
    message: `Selamat datang di ChatMD, ${raw}!`,
  });

  broadcastUserList();
}

function handleMessage(socketId, senderData, data) {
  // Rate limiting
  if (!checkRateLimit(senderData)) {
    sendTo(senderData.socket, {
      type: "error",
      message: "Rate limit: terlalu cepat. Tunggu sebentar.",
    });
    return;
  }

  const toUsername = (data.to || "").trim();
  const payload = data.payload; // string terenkripsi AES-GCM (hex)
  const fileExt = data.file_ext; // metadata file extension (optional)

  if (!toUsername || !payload) {
    sendTo(senderData.socket, {
      type: "error",
      message: "Field 'to' dan 'payload' wajib diisi.",
    });
    return;
  }

  if (!senderData.username) {
    sendTo(senderData.socket, {
      type: "error",
      message: "Anda harus register terlebih dahulu.",
    });
    return;
  }

  // Filter file berdasarkan ekstensi jika dikirim
  if (fileExt) {
    const extClean = fileExt.toLowerCase().trim().replace(/^\./, "");
    if (!allowedFileTypes[extClean]) {
      serverWarn(`[!] BLOCKED FILE: ${senderData.username} mencoba mengirim file .${extClean} ke ${toUsername} (Dilarang server)`);
      sendTo(senderData.socket, {
        type: "error",
        message: `Pengiriman file dengan ekstensi '.${extClean}' dilarang oleh server.`,
      });
      return;
    }
  }

  // Cari target
  const target = findUserByName(toUsername);
  if (!target) {
    sendTo(senderData.socket, {
      type: "error",
      message: `User "${toUsername}" tidak ditemukan atau offline.`,
    });
    return;
  }

  const [, targetData] = target;

  // Forward pesan terenkripsi ke target
  sendTo(targetData.socket, {
    type: "message",
    from: senderData.username,
    payload: payload,
    file_ext: fileExt,
  });

  // Konfirmasi ke pengirim (opsional, untuk acknowledgement)
  sendTo(senderData.socket, {
    type: "sent",
    to: toUsername,
  });

  serverLog(
    `[>] MSG  ${senderData.username} → ${toUsername}  (${payload.length} chars)${fileExt ? ` [FILE: .${fileExt}]` : ""}`
  );
}

function handlePing(userData) {
  sendTo(userData.socket, { type: "pong" });
}

// ─── Main Server & HTTP Static Web Client ─────────────────────────────────
const VERSION_FILE = path.join(__dirname, "version.json");
const ZIP_FILE     = path.join(__dirname, "client_files.zip");
const PUBLIC_DIR   = path.join(__dirname, "public");

let versionInfo = null;
try {
  versionInfo = JSON.parse(fs.readFileSync(VERSION_FILE, "utf8"));
} catch (_) {
  // version.json belum ada
}

const httpServer = http.createServer((req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");

  const reqPath = req.url.split("?")[0];

  if (req.method === "GET" && (reqPath === "/" || reqPath === "/index.html")) {
    const indexPath = path.join(PUBLIC_DIR, "index.html");
    if (fs.existsSync(indexPath)) {
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      fs.createReadStream(indexPath).pipe(res);
      return;
    }
  } else if (req.method === "GET" && reqPath === "/version" && versionInfo) {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ hash: versionInfo.hash, port: PORT }));
    return;
  } else if (req.method === "GET" && reqPath === "/update" && fs.existsSync(ZIP_FILE)) {
    const stat = fs.statSync(ZIP_FILE);
    res.writeHead(200, {
      "Content-Type": "application/zip",
      "Content-Length": stat.size,
    });
    fs.createReadStream(ZIP_FILE).pipe(res);
    serverLog(`[^] UPDATE   download dari ${req.socket.remoteAddress}`);
    return;
  }

  res.writeHead(404);
  res.end("Not Found");
});

const wss = new WebSocketServer({ server: httpServer });

httpServer.listen(PORT, () => {
  console.clear();
  console.log("--------------------------------------------");
  console.log(`  IP Address : ${LOCAL_IP}`);
  console.log(`  Port       : ${PORT}`);
  console.log(`  TOKEN      : ${SESSION_TOKEN}`);
  console.log(`  Web Client : http://${LOCAL_IP}:${PORT}`);
  console.log("--------------------------------------------\n");

  if (startupLogs.length > 0) {
    for (const log of startupLogs) {
      console.log(log);
    }
  }

  console.log(`[*] Server aktif di ws://${LOCAL_IP}:${PORT}`);
  console.log(`[*] Web Mobile Client aktif di http://${LOCAL_IP}:${PORT}`);
  console.log(`[*] Discovery UDP broadcast di port ${DISCOVERY_PORT}`);
  console.log(`[*] Rate limit: ${RATE_LIMIT_MAX} pesan / ${RATE_LIMIT_WINDOW / 1000} detik`);
  console.log(`[*] Tekan Ctrl+C untuk shutdown`);
  console.log(`[*] Tekan Ctrl+L untuk membuka menu filter file\n`);
});

// ─── UDP Discovery (Broadcast + Query-Response) ──────────────────
// Server bind ke DISCOVERY_PORT agar bisa:
//   1. Broadcast periodik (pasif — client dengerin)
//   2. Balas query langsung dari client (aktif — lebih andal)
const udpSock = dgram.createSocket("udp4");
const discPayload = Buffer.from(
  JSON.stringify({ token: SESSION_TOKEN, ip: LOCAL_IP, port: PORT })
);

udpSock.on("message", (data, rinfo) => {
  // Balas query discovery dari client secara langsung
  try {
    const msg = JSON.parse(data.toString());
    if (msg.type === "discover" && msg.token?.toUpperCase() === SESSION_TOKEN) {
      udpSock.send(discPayload, 0, discPayload.length, rinfo.port, rinfo.address);
    }
  } catch (_) {}
});

udpSock.on("error", (err) => {
  serverWarn(`[!] UDP error: ${err.message}`);
});

udpSock.bind(DISCOVERY_PORT, () => {
  udpSock.setBroadcast(true);
  // Broadcast periodik sebagai fallback
  setInterval(() => {
    udpSock.send(discPayload, 0, discPayload.length, DISCOVERY_PORT, "255.255.255.255");
  }, BROADCAST_INTERVAL);
  serverLog(`[*] UDP discovery aktif di port ${DISCOVERY_PORT} (token=${SESSION_TOKEN})\n`);
});

let hasHadClients = false;

wss.on("connection", (socket, req) => {
  const socketId = nextId++;
  const remoteIp =
    req.headers["x-forwarded-for"] || req.socket.remoteAddress;

  const userData = {
    username: null, // belum register
    socket: socket,
    msgTimestamps: [],
    ip: remoteIp,
  };

  users.set(socketId, userData);
  hasHadClients = true;

  if (waitingForShutdownConfirmation) {
    waitingForShutdownConfirmation = false;
    process.stdout.write("\n\x1b[32m[*] Klien baru terhubung. Pembatalan otomatis konfirmasi shutdown.\x1b[0m\n\n");
  }

  serverLog(`[~] CONNECT   id=${socketId} ip=${remoteIp} (total: ${users.size})`);

  // ── Handler pesan masuk ──
  socket.on("message", (raw) => {
    let data;
    try {
      data = JSON.parse(raw.toString());
    } catch {
      sendTo(socket, { type: "error", message: "Format JSON tidak valid." });
      return;
    }

    switch (data.type) {
      case "register":
        handleRegister(socketId, userData, data);
        break;
      case "message":
        handleMessage(socketId, userData, data);
        break;
      case "ping":
        handlePing(userData);
        break;
      default:
        sendTo(socket, {
          type: "error",
          message: `Tipe pesan tidak dikenal: "${data.type}"`,
        });
    }
  });

  // ── Handler disconnect ──
  socket.on("close", (code, reason) => {
    const name = userData.username || `<unregistered#${socketId}>`;
    users.delete(socketId);
    serverLog(
      `[-] DISCONNECT id=${socketId} username=${name} (total: ${users.size})`
    );
    // Broadcast list terbaru ke sisa user
    broadcastUserList();

    // Auto-shutdown jika semua klien sudah keluar
    if (hasHadClients && users.size === 0) {
      waitingForShutdownConfirmation = true;
      if (menuActive) {
        serverLog("\x1b[33m[?] Semua klien telah terputus. Matikan server? (Y/N): \x1b[0m");
      } else {
        process.stdout.write("\n\x1b[33m[?] Semua klien telah terputus. Matikan server? (Y/N): \x1b[0m");
      }
    }
  });

  // ── Handler error ──
  socket.on("error", (err) => {
    serverError(`[!] ERROR id=${socketId}: ${err.message}`);
    users.delete(socketId);
    broadcastUserList();
  });
});

wss.on("error", (err) => {
  if (err.code === "EADDRINUSE") {
    serverError(`[FATAL] Port ${PORT} sudah digunakan. Ganti port atau matikan proses lain.`);
  } else {
    serverError(`[FATAL] Server error: ${err.message}`);
  }
  process.exit(1);
});

// ── Graceful shutdown ──
function shutdown() {
  serverLog("\n[*] Shutdown... menutup semua koneksi.");
  for (const [, userData] of users) {
    sendTo(userData.socket, {
      type: "error",
      message: "Server dimatikan. Sesi berakhir.",
    });
    userData.socket.terminate();
  }
  users.clear();
  udpSock.close();
  wss.close(() => {
    serverLog("[*] Server berhenti. Sampai jumpa!");
    process.exit(0);
  });
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
process.on("SIGBREAK", shutdown);
