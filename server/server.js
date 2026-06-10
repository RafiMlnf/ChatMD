/**
 * ChatMD — Volatile Intranet Chat
 * WebSocket Server (Node.js + ws)
 *
 * Arsitektur:
 *  - Semua data user disimpan di Map in-memory (volatile)
 *  - Rate limiting: sliding window 3 msg/3 detik per socket
 *  - Tidak ada file I/O, tidak ada database
 *  - Otomatis membersihkan user saat disconnect
 */

"use strict";

const { WebSocketServer, WebSocket } = require("ws");

// ─── Konfigurasi ────────────────────────────────────────────────
const PORT = process.env.CHATMD_PORT || process.env.VINC_PORT || 8765;
const RATE_LIMIT_MAX = 3;     // maksimal N pesan...
const RATE_LIMIT_WINDOW = 3000; // ...dalam X milidetik (sliding window)

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

  // Validasi username: alfanumerik + underscore + dash + titik + @ , 1–32 karakter
  if (!/^[\w\-.@]{1,32}$/.test(raw)) {
    sendTo(userData.socket, {
      type: "error",
      message: "Username tidak valid. Gunakan huruf, angka, titik, atau dash.",
    });
    return;
  }

  // Cek duplikasi username
  const existing = findUserByName(raw);
  if (existing) {
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

console.log("╔══════════════════════════════════════════╗");
console.log("║  ChatMD — Volatile Intranet Chat         ║");
console.log("║  WebSocket Server                        ║");
console.log(`║  Port: ${String(PORT).padEnd(35)}║`);
console.log("╚══════════════════════════════════════════╝");
console.log(`[*] Server aktif di ws://0.0.0.0:${PORT}`);
console.log(`[*] Rate limit: ${RATE_LIMIT_MAX} pesan / ${RATE_LIMIT_WINDOW / 1000} detik`);
console.log(`[*] Tekan Ctrl+C untuk shutdown\n`);

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
  wss.close(() => {
    console.log("[*] Server berhenti. Sampai jumpa!");
    process.exit(0);
  });
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
process.on("SIGBREAK", shutdown);
