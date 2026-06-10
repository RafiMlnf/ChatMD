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

  console.log(`[*] Broadcast daftar user aktif (${userList.length} user): [${userList.join(", ")}]`);

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
    console.warn(`[!] REGISTER FAILED: Username "${raw}" invalid format (ip=${userData.ip})`);
    sendTo(userData.socket, {
      type: "error",
      message: "Username tidak valid. Gunakan huruf, angka, titik, atau dash.",
    });
    return;
  }

  // Cek duplikasi username
  const existing = findUserByName(raw);
  if (existing) {
    console.warn(`[!] REGISTER FAILED: Username "${raw}" already in use (ip=${userData.ip})`);
    sendTo(userData.socket, {
      type: "error",
      message: `Username "${raw}" sudah digunakan. Tutup sesi lama terlebih dahulu.`,
    });
    return;
  }

  userData.username = raw;
  console.log(`[+] REGISTER  id=${socketId} username=${raw}`);

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
  });

  // Konfirmasi ke pengirim (opsional, untuk acknowledgement)
  sendTo(senderData.socket, {
    type: "sent",
    to: toUsername,
  });

  console.log(
    `[>] MSG  ${senderData.username} → ${toUsername}  (${payload.length} chars)`
  );
}

function handlePing(userData) {
  sendTo(userData.socket, { type: "pong" });
}

// ─── Main Server ─────────────────────────────────────────────────

const wss = new WebSocketServer({ port: PORT });

console.log("--------------------------------------------");
console.log(`  IP Address : ${LOCAL_IP}`);
console.log(`  Port       : ${PORT}`);
console.log(`  TOKEN      : ${SESSION_TOKEN}`);
console.log("--------------------------------------------\n");
console.log(`[*] Server aktif di ws://${LOCAL_IP}:${PORT}`);
console.log(`[*] Discovery UDP broadcast di port ${DISCOVERY_PORT}`);
console.log(`[*] Rate limit: ${RATE_LIMIT_MAX} pesan / ${RATE_LIMIT_WINDOW / 1000} detik`);
console.log(`[*] Tekan Ctrl+C untuk shutdown\n`);

// ─── HTTP Auto-Update Server ───────────────────────────────────────────────────
const VERSION_FILE = path.join(__dirname, "version.json");
const ZIP_FILE     = path.join(__dirname, "client_files.zip");

let versionInfo = null;
try {
  versionInfo = JSON.parse(fs.readFileSync(VERSION_FILE, "utf8"));
} catch (_) {
  // version.json belum ada — jalankan generate_bat.py terlebih dahulu
}

if (versionInfo && fs.existsSync(ZIP_FILE)) {
  const updateServer = http.createServer((req, res) => {
    res.setHeader("Access-Control-Allow-Origin", "*");

    if (req.method === "GET" && req.url === "/version") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ hash: versionInfo.hash, port: PORT }));

    } else if (req.method === "GET" && req.url === "/update") {
      const stat = fs.statSync(ZIP_FILE);
      res.writeHead(200, {
        "Content-Type": "application/zip",
        "Content-Length": stat.size,
      });
      fs.createReadStream(ZIP_FILE).pipe(res);
      console.log(`[^] UPDATE   download dari ${req.socket.remoteAddress}`);

    } else {
      res.writeHead(404);
      res.end();
    }
  });

  updateServer.listen(UPDATE_PORT, () => {
    console.log(`[*] Auto-update server aktif di port ${UPDATE_PORT} (versi: ${versionInfo.hash})`);
  });

  updateServer.on("error", (err) => {
    console.warn(`[!] Update server error: ${err.message}`);
  });
} else {
  console.log(`[*] Auto-update tidak aktif (version.json/client_files.zip tidak ditemukan).`);
}

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
  console.warn(`[!] UDP error: ${err.message}`);
});

udpSock.bind(DISCOVERY_PORT, () => {
  udpSock.setBroadcast(true);
  // Broadcast periodik sebagai fallback
  setInterval(() => {
    udpSock.send(discPayload, 0, discPayload.length, DISCOVERY_PORT, "255.255.255.255");
  }, BROADCAST_INTERVAL);
  console.log(`[*] UDP discovery aktif di port ${DISCOVERY_PORT} (token=${SESSION_TOKEN})\n`);
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
  console.log(`[~] CONNECT   id=${socketId} ip=${remoteIp} (total: ${users.size})`);

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
    console.log(
      `[-] DISCONNECT id=${socketId} username=${name} (total: ${users.size})`
    );
    // Broadcast list terbaru ke sisa user
    broadcastUserList();

    // Auto-shutdown jika semua klien sudah keluar
    if (hasHadClients && users.size === 0) {
      console.log("[*] Semua klien telah terputus. Mematikan server...");
      shutdown();
    }
  });

  // ── Handler error ──
  socket.on("error", (err) => {
    console.error(`[!] ERROR id=${socketId}: ${err.message}`);
    users.delete(socketId);
    broadcastUserList();
  });
});

wss.on("error", (err) => {
  if (err.code === "EADDRINUSE") {
    console.error(`[FATAL] Port ${PORT} sudah digunakan. Ganti port atau matikan proses lain.`);
  } else {
    console.error(`[FATAL] Server error: ${err.message}`);
  }
  process.exit(1);
});

// ── Graceful shutdown ──
function shutdown() {
  console.log("\n[*] Shutdown... menutup semua koneksi.");
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
    console.log("[*] Server berhenti. Sampai jumpa!");
    process.exit(0);
  });
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
process.on("SIGBREAK", shutdown);
