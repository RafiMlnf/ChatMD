"""
VINC — Volatile Intranet Notepad Chat
vinc_client.py — Main Client Application with Inline CMD Chat UI
"""

import os
import sys
import socket
import threading
import time
import json
import msvcrt
from typing import Optional

# Validasi platform
if sys.platform != "win32":
    print("[FATAL] VINC hanya berjalan di Windows.")
    sys.exit(1)

try:
    from websocket import WebSocketApp, WebSocketConnectionClosedException
except ImportError:
    print("[ERROR] Library 'websocket-client' belum terinstall.")
    print("  Jalankan: pip install websocket-client")
    sys.exit(1)

try:
    from crypto_utils import encrypt, decrypt
except ImportError as e:
    print(f"[ERROR] Gagal import modul VINC: {e}")
    print("  Pastikan crypto_utils.py ada di folder yang sama.")
    sys.exit(1)


# ─── Konstanta ─────────────────────────────────────────────────────────────────
VINC_PORT      = int(os.environ.get("VINC_PORT", "8765"))
RECONNECT_DELAY = 3          # detik sebelum reconnect otomatis
PING_INTERVAL  = 20          # detik antar ping keepalive
VERSION        = "1.1.0"


# ─── State Global ──────────────────────────────────────────────────────────────
g_username: str = ""
g_server_ip: str = ""
g_user_list: list[str] = []
g_ws: Optional[WebSocketApp] = None
g_ws_connected = threading.Event()

# Sesi chat aktif
g_active_partner: Optional[str] = None
# Kontak dengan pesan belum dibaca
g_unread_contacts: set[str] = set()
# Riwayat pesan: partner_name -> list of {"sender": str, "text": str}
g_chat_histories: dict[str, list[dict]] = {}
g_sessions_lock = threading.Lock()

# Referensi UI chat yang aktif saat ini
g_current_ui = None

# Flag shutdown
g_shutdown = threading.Event()


# ─── Utilitas UI ───────────────────────────────────────────────────────────────

def clear():
    os.system("cls")


def banner():
    print("------------------------------------------------------------")
    print(f" VINC - Volatile Intranet Notepad Chat v{VERSION}")
    print(" Anti-Forensic  •  AES-128-GCM")
    print("------------------------------------------------------------")
    print()


def print_status(msg: str):
    print(f"  [VINC] {msg}")


def print_error(msg: str):
    print(f"  [!] {msg}")


def print_info(msg: str):
    print(f"  [i] {msg}")


# ─── Ambil identitas user ───────────────────────────────────────────────────────

def get_identity() -> str:
    """
    Ambil username dari Windows login name.
    Fallback ke hostname jika gagal.
    Format: USERNAME@COMPUTERNAME
    """
    try:
        win_user = os.getlogin()
    except OSError:
        win_user = None

    try:
        host = socket.gethostname().split(".")[0]
    except Exception:
        host = "PC"

    if win_user:
        return f"{win_user}@{host}"
    else:
        return host


# ─── Class UI Chat Inline CMD ──────────────────────────────────────────────────

class TerminalChatUI:
    """
    Thread-safe Chat UI di dalam CMD menggunakan input non-blocking.
    Mencegah tabrakan saat pesan baru masuk ketika user sedang mengetik.
    """
    def __init__(self, partner_name: str, my_name: str):
        self.partner_name = partner_name
        self.my_name = my_name
        self.input_buffer = []
        self.lock = threading.Lock()
        self.active = True
        self.prompt = "  > "
        self.in_get_input = False

    def start(self):
        clear()
        print(f"  Kepada : {self.partner_name} --------")
        print("  [ /b untuk kembali ]\n")

    def print_message(self, sender: str, text: str):
        with self.lock:
            if not self.active:
                return
            # 1. Bersihkan baris input/prompt yang sedang aktif
            current_input_len = len(self.prompt) + len(self.input_buffer)
            sys.stdout.write("\r" + " " * (current_input_len + 4) + "\r")
            
            # 2. Cetak pesan baru
            sys.stdout.write(f"  {sender:<20} : {text}\n")
            
            # 3. Kembalikan prompt dan apa yang sedang diketik user (jika sedang di input)
            if self.in_get_input:
                sys.stdout.write(self.prompt + "".join(self.input_buffer))
                sys.stdout.flush()

    def get_input(self, shutdown_event: threading.Event) -> Optional[str]:
        with self.lock:
            self.in_get_input = True
            self.input_buffer = []  # Kosongkan buffer untuk input baru
            # Print prompt
            sys.stdout.write(self.prompt)
            sys.stdout.flush()

        try:
            while not shutdown_event.is_set() and self.active:
                if msvcrt.kbhit():
                    ch = msvcrt.getch()
                    with self.lock:
                        if ch in (b'\r', b'\n'):  # Enter
                            line = "".join(self.input_buffer)
                            # Jangan kosongkan input_buffer di sini agar print_message tahu berapa karakter yang harus dihapus
                            sys.stdout.flush()
                            return line
                        elif ch == b'\x08':  # Backspace
                            if self.input_buffer:
                                self.input_buffer.pop()
                                sys.stdout.write("\b \b")
                                sys.stdout.flush()
                        elif ch == b'\x03':  # Ctrl+C
                            raise KeyboardInterrupt()
                        elif ch == b'\xe0':  # Tombol khusus (panah, dll)
                            msvcrt.getch()  # consume byte kedua
                        else:
                            try:
                                char = ch.decode("ansi")
                                # Batasi karakter printable yang wajar
                                if len(char) == 1 and ord(char) >= 32:
                                    self.input_buffer.append(char)
                                    sys.stdout.write(char)
                                    sys.stdout.flush()
                            except UnicodeDecodeError:
                                pass
                time.sleep(0.01)
            return None
        finally:
            with self.lock:
                self.in_get_input = False


# ─── WebSocket Handlers ────────────────────────────────────────────────────────

def on_ws_open(ws):
    """Dipanggil saat koneksi WebSocket berhasil terbuka."""
    global g_ws
    g_ws = ws
    g_ws_connected.set()
    # Register ke server
    ws.send(json.dumps({"type": "register", "username": g_username}))
    # Mulai thread ping keepalive
    threading.Thread(target=_ping_loop, args=(ws,), daemon=True).start()


def on_ws_message(ws, raw_msg: str):
    """Dipanggil saat menerima pesan dari server."""
    try:
        data = json.loads(raw_msg)
    except json.JSONDecodeError:
        return

    msg_type = data.get("type", "")

    if msg_type == "user_list":
        _handle_user_list(data.get("users", []))

    elif msg_type == "message":
        _handle_incoming_message(data)

    elif msg_type == "registered":
        print_status(f"Terdaftar sebagai: {data.get('username', g_username)}")

    elif msg_type == "sent":
        pass

    elif msg_type == "error":
        err = data.get("message", "Unknown error")
        # Cetak error jika tidak sedang berada dalam sesi chat aktif
        with g_sessions_lock:
            if g_active_partner is None:
                print_error(f"Server: {err}")
            elif g_current_ui:
                g_current_ui.print_message("Sistem", f"Server error: {err}")

    elif msg_type == "pong":
        pass


def on_ws_error(ws, error):
    """Dipanggil saat terjadi error WebSocket."""
    if not g_shutdown.is_set():
        with g_sessions_lock:
            if g_active_partner is None:
                print_error(f"WebSocket error: {error}")
            elif g_current_ui:
                g_current_ui.print_message("Sistem", f"WebSocket error: {error}")


def on_ws_close(ws, close_status_code, close_msg):
    """Dipanggil saat koneksi WebSocket ditutup."""
    g_ws_connected.clear()
    if not g_shutdown.is_set():
        with g_sessions_lock:
            if g_active_partner is None:
                print_status("Koneksi ke server terputus.")
            elif g_current_ui:
                g_current_ui.print_message("Sistem", "Koneksi terputus dari server.")


def _ping_loop(ws: WebSocketApp):
    """Thread keepalive: kirim ping ke server setiap PING_INTERVAL detik."""
    while not g_shutdown.is_set():
        time.sleep(PING_INTERVAL)
        if g_shutdown.is_set():
            break
        try:
            ws.send(json.dumps({"type": "ping"}))
        except Exception:
            break


# ─── Handler pesan masuk ───────────────────────────────────────────────────────

def _handle_user_list(users: list[str]):
    """Update daftar kontak aktif (hapus diri sendiri dari list)."""
    global g_user_list
    g_user_list = [u for u in users if u != g_username]
    
    # Deteksi jika partner aktif mendadak offline
    with g_sessions_lock:
        if g_active_partner and g_active_partner not in g_user_list:
            if g_current_ui:
                g_current_ui.print_message("Sistem", f"{g_active_partner} telah offline.")


def _handle_incoming_message(data: dict):
    """Terima, decrypt, dan simpan ke riwayat chat."""
    sender = data.get("from", "Unknown")
    payload = data.get("payload", "")

    # Decrypt
    try:
        plaintext = decrypt(payload)
    except ValueError as e:
        with g_sessions_lock:
            if g_active_partner == sender and g_current_ui:
                g_current_ui.print_message("Sistem", f"Gagal decrypt pesan: {e}")
        return

    with g_sessions_lock:
        if sender not in g_chat_histories:
            g_chat_histories[sender] = []
        g_chat_histories[sender].append({"sender": sender, "text": plaintext})

        # Jika sedang aktif chat dengan pengirim ini, print langsung ke UI
        if g_active_partner == sender and g_current_ui:
            g_current_ui.print_message(sender, plaintext)
        else:
            g_unread_contacts.add(sender)
            # Jika user sedang di dalam chat room dengan orang lain:
            if g_active_partner is not None and g_current_ui:
                g_current_ui.print_message("Sistem", f"[NOTIF] Pesan baru dari {sender}! Ketik /b untuk membaca.")
            # Jika user sedang di menu kontak:
            elif g_active_partner is None:
                sys.stdout.write(f"\n\a  [NOTIF] Pesan baru dari {sender}!\n  Pilih kontak (nomor) atau perintah: ")
                sys.stdout.flush()


# ─── Thread WebSocket ──────────────────────────────────────────────────────────

def ws_thread_func(server_url: str):
    """Jalankan WebSocketApp di thread terpisah."""
    app = WebSocketApp(
        server_url,
        on_open=on_ws_open,
        on_message=on_ws_message,
        on_error=on_ws_error,
        on_close=on_ws_close,
    )
    app.run_forever(
        ping_interval=0,   # ping manual
        ping_timeout=10,
        reconnect=0,
    )


# ─── UI: Daftar Kontak ─────────────────────────────────────────────────────────

def show_contact_list() -> Optional[str]:
    """
    Tampilkan daftar kontak aktif di CMD.
    """
    clear()
    banner()
    print(f"  Logged in as : {g_username}")
    print(f"  Server       : ws://{g_server_ip}:{VINC_PORT}")
    print()

    if not g_user_list:
        print("  ┌─────────────────────────────────────────┐")
        print("  │  Tidak ada kontak online saat ini.      │")
        print("  │  Tunggu pengguna lain bergabung...      │")
        print("  └─────────────────────────────────────────┘")
    else:
        print("  ┌─────────────────────────────────────────┐")
        print("  │  KONTAK ONLINE                          │")
        print("  ├─────────────────────────────────────────┤")
        for i, user in enumerate(g_user_list, 1):
            with g_sessions_lock:
                if user in g_unread_contacts:
                    indicator = " [PESAN BARU]"
                elif user in g_chat_histories and len(g_chat_histories[user]) > 0:
                    indicator = " [Pesan]"
                else:
                    indicator = ""
            line = f"  │  [{i}] {user}{indicator}"
            print(line.ljust(46) + "│")
        print("  └─────────────────────────────────────────┘")

    print()
    print("  [R] Refresh daftar kontak")
    print("  [Q] Keluar dari VINC")
    print()

    try:
        choice = input("  Pilih kontak (nomor) atau perintah: ").strip().upper()
    except (EOFError, KeyboardInterrupt):
        return "__EXIT__"

    if choice == "Q":
        return "__EXIT__"
    if choice == "R" or choice == "":
        return "__REFRESH__"

    try:
        idx = int(choice) - 1
        if 0 <= idx < len(g_user_list):
            return g_user_list[idx]
        else:
            print_error("Nomor tidak valid.")
            time.sleep(1)
            return "__REFRESH__"
    except ValueError:
        print_error("Input tidak dikenal.")
        time.sleep(1)
        return "__REFRESH__"


# ─── UI: Sesi Chat ─────────────────────────────────────────────────────────────

def run_chat_session(partner: str):
    """
    Jalankan sesi chat interaktif dengan partner di dalam CMD (inline).
    """
    global g_active_partner, g_current_ui, g_ws

    with g_sessions_lock:
        g_active_partner = partner
        g_unread_contacts.discard(partner)  # Hapus status unread
        if partner not in g_chat_histories:
            g_chat_histories[partner] = []

    # Inisialisasi UI Chat
    ui = TerminalChatUI(partner, g_username)
    g_current_ui = ui
    ui.start()

    # Cetak seluruh history yang ada terlebih dahulu
    with g_sessions_lock:
        for msg in g_chat_histories[partner]:
            sys.stdout.write(f"  {msg['sender']:<20} : {msg['text']}\n")
        sys.stdout.flush()

    try:
        while not g_shutdown.is_set() and ui.active:
            # Dapatkan input secara non-blocking agar tidak mengunci output thread lain
            text = ui.get_input(g_shutdown)
            if text is None:
                break

            text_strip = text.strip()
            if not text_strip:
                continue

            if text_strip.lower() == "/b":
                break

            if text_strip.lower() == "/quit":
                g_shutdown.set()
                break

            if not g_ws_connected.is_set():
                ui.print_message("Sistem", "Tidak terhubung ke server. Pesan gagal terkirim.")
                continue

            # Enkripsi dan kirim pesan
            try:
                encrypted = encrypt(text_strip)
                payload = json.dumps({
                    "type": "message",
                    "to": partner,
                    "payload": encrypted,
                })
                g_ws.send(payload)
            except Exception as e:
                ui.print_message("Sistem", f"Gagal mengirim pesan: {e}")
                continue

            # Simpan ke riwayat pengirim
            with g_sessions_lock:
                g_chat_histories[partner].append({"sender": g_username, "text": text_strip})

            # Tampilkan pesan kita sendiri di CMD
            ui.print_message(g_username, text_strip)

    except KeyboardInterrupt:
        g_shutdown.set()
    finally:
        # Hentikan status UI aktif
        ui.active = False
        with g_sessions_lock:
            g_active_partner = None
            g_current_ui = None


# ─── Main ──────────────────────────────────────────────────────────────────────

def main():
    global g_username, g_server_ip

    clear()
    banner()

    # 1. Ambil identitas user (bisa dari CLI args untuk override nama, berguna untuk test)
    if len(sys.argv) > 1:
        g_username = sys.argv[1].strip()
        print_info(f"Identitas di-override via argumen: {g_username}")
    else:
        g_username = get_identity()
        print_info(f"Identitas terdeteksi: {g_username}")
    print()

    # 2. Minta IP server
    try:
        raw_ip = input("  Masukkan IP Server VINC (Enter = 127.0.0.1): ").strip()
    except (EOFError, KeyboardInterrupt):
        print("\n  Keluar.")
        sys.exit(0)

    if not raw_ip:
        raw_ip = "127.0.0.1"
    g_server_ip = raw_ip
    server_url = f"ws://{g_server_ip}:{VINC_PORT}"

    print()
    print_status(f"Menghubungkan ke {server_url} ...")

    # 3. Jalankan WebSocket di thread background
    ws_t = threading.Thread(target=ws_thread_func, args=(server_url,), daemon=True)
    ws_t.start()

    # Tunggu koneksi (maks 5 detik)
    if not g_ws_connected.wait(timeout=5.0):
        print_error("Gagal terhubung ke server. Pastikan server aktif dan IP benar.")
        sys.exit(1)

    print_status("Terhubung!")
    time.sleep(1.0)  # Beri waktu server kirim user_list awal

    # 4. Loop menu utama
    try:
        while not g_shutdown.is_set():
            choice = show_contact_list()

            if choice is None or choice == "__EXIT__":
                break
            elif choice == "__REFRESH__":
                continue
            else:
                run_chat_session(choice)

    except KeyboardInterrupt:
        pass

    # 5. Cleanup
    g_shutdown.set()
    print()
    print_status("Menutup semua sesi...")

    if g_ws:
        try:
            g_ws.close()
        except Exception:
            pass

    print_status("Sesi VINC berakhir. Semua data chat telah dihapus dari RAM.")
    print_status("Sampai jumpa! 👋")
    print()
    sys.exit(0)


if __name__ == "__main__":
    main()
