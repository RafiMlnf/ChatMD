"""
ChatMD — Volatile Intranet Chat
chatmd_client.py — Main Client Application with Inline CMD Chat UI
"""

import os
import sys
import socket
import threading
import time
import json
import msvcrt
import shutil
import textwrap
import base64
import subprocess
from typing import Optional

# Validasi platform
if sys.platform != "win32":
    print("[FATAL] ChatMD hanya berjalan di Windows.")
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
    print(f"[ERROR] Gagal import modul ChatMD: {e}")
    print("  Pastikan crypto_utils.py ada di folder yang sama.")
    sys.exit(1)


# ─── Konstanta ─────────────────────────────────────────────────────────────────
CHATMD_PORT      = int(os.environ.get("CHATMD_PORT", os.environ.get("VINC_PORT", "8765")))
DISCOVERY_PORT   = int(os.environ.get("CHATMD_DISC_PORT", "8766"))
UPDATE_PORT      = CHATMD_PORT + 2  # HTTP server auto-update (default 8767)
DISCOVERY_TIMEOUT = 12       # detik tunggu UDP broadcast
RECONNECT_DELAY  = 3         # detik sebelum reconnect otomatis
PING_INTERVAL    = 20        # detik antar ping keepalive
VERSION          = "1.3.0"
CHATMD_VERSION   = os.environ.get("CHATMD_VERSION", "")  # hash versi dari BAT


# ─── State Global ──────────────────────────────────────────────────────────────
g_username: str = ""
g_server_ip: str = ""
g_user_list: list[str] = []
g_ws: Optional[WebSocketApp] = None
g_ws_connected = threading.Event()

# Sesi chat aktif
g_active_partner: Optional[str] = None
# Kontak dengan jumlah pesan belum dibaca
g_unread_messages: dict[str, int] = {}
# Riwayat pesan: partner_name -> list of {"sender": str, "text": str}
g_chat_histories: dict[str, list[dict]] = {}
g_sessions_lock = threading.Lock()

# Referensi UI chat yang aktif saat ini
g_current_ui = None

# Flag shutdown
g_shutdown = threading.Event()

# Flag status registrasi
g_registered = threading.Event()
g_registration_error: Optional[str] = None

# Flag redraw untuk menu utama (daftar kontak)
g_menu_needs_redraw = False


# ─── Utilitas UI ───────────────────────────────────────────────────────────────

def clear():
    os.system("cls")


def format_message(sender: str, text: str) -> str:
    """
    Format pesan agar teks panjang dibungkus (wrapped) dan baris kedua dst.
    sejajar dengan titik dua (:).
    """
    try:
        columns, _ = shutil.get_terminal_size()
    except Exception:
        columns = 80

    prefix = f"  {sender:<32} : "
    prefix_len = len(prefix)  # 37
    wrap_width = max(30, columns - prefix_len)

    paragraphs = text.splitlines()
    wrapped_lines = []

    for paragraph in paragraphs:
        if not paragraph:
            wrapped_lines.append("")
        else:
            lines = textwrap.wrap(
                paragraph,
                width=wrap_width,
                break_long_words=True,
                replace_whitespace=False
            )
            wrapped_lines.extend(lines)

    if not wrapped_lines:
        return prefix

    result = [f"{prefix}{wrapped_lines[0]}"]
    indent = " " * prefix_len
    for line in wrapped_lines[1:]:
        result.append(f"{indent}{line}")

    return "\n".join(result)



def print_status(msg: str):
    print(f"  \033[96m[ChatMD]\033[0m {msg}")


def print_error(msg: str):
    print(f"  \033[91m[!] {msg}\033[0m")


def print_info(msg: str):
    print(f"  \033[90m[i] {msg}\033[0m")


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
        raw_name = f"{win_user}@{host}"
    else:
        raw_name = host

    # Bersihkan username: ganti spasi dengan underscore, buang karakter ilegal
    # Server hanya menerima: alfanumerik, _, -, ., dan @
    raw_name = raw_name.replace(" ", "_")
    cleaned = "".join(c for c in raw_name if c.isalnum() or c in "_-.@")
    return cleaned[:32]


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
        print("[/b] Kembali | [Drag & Drop] Kirim File\n")
        print(f"  Kepada : {self.partner_name}")
        print("\n")

    def print_message(self, sender: str, text: str):
        with self.lock:
            if not self.active:
                return
            # 1. Bersihkan baris input/prompt yang sedang aktif
            current_input_len = len(self.prompt) + len(self.input_buffer)
            sys.stdout.write("\r" + " " * (current_input_len + 4) + "\r")
            
            # 2. Cetak pesan baru
            sys.stdout.write(format_message(sender, text) + "\n")
            
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
        g_registered.set()

    elif msg_type == "sent":
        pass

    elif msg_type == "error":
        err = data.get("message", "Unknown error")
        # Jika belum terdaftar, ini kemungkinan error registrasi (misal nama duplikat)
        if not g_registered.is_set():
            global g_registration_error
            g_registration_error = err
            g_shutdown.set()
        
        # Cetak error jika tidak sedang berada dalam sesi chat aktif
        with g_sessions_lock:
            if g_active_partner is None:
                print_error(f"Server: {err}")
            elif g_current_ui:
                g_current_ui.print_message("Sistem", f"\033[91mServer error: {err}\033[0m")

    elif msg_type == "pong":
        pass


def on_ws_error(ws, error):
    """Dipanggil saat terjadi error WebSocket."""
    if not g_shutdown.is_set():
        with g_sessions_lock:
            if g_active_partner is None:
                print_error(f"WebSocket error: {error}")
            elif g_current_ui:
                g_current_ui.print_message("Sistem", f"\033[91mWebSocket error: {error}\033[0m")


def on_ws_close(ws, close_status_code, close_msg):
    """Dipanggil saat koneksi WebSocket ditutup."""
    g_ws_connected.clear()
    if not g_shutdown.is_set():
        with g_sessions_lock:
            if g_active_partner is None:
                print_status("Koneksi ke server terputus.")
            elif g_current_ui:
                g_current_ui.print_message("Sistem", "\033[91mKoneksi terputus dari server.\033[0m")


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
    global g_user_list, g_menu_needs_redraw
    g_user_list = [u for u in users if u != g_username]
    
    # Deteksi jika partner aktif mendadak offline
    with g_sessions_lock:
        if g_active_partner and g_active_partner not in g_user_list:
            if g_current_ui:
                g_current_ui.print_message("Sistem", f"{g_active_partner} telah offline.")
        elif not g_active_partner:
            g_menu_needs_redraw = True


def _process_image_payload(plaintext: str) -> str:
    """
    Decode payload [IMAGE:filename:base64] dan simpan ke Downloads/ChatMD_Received.
    Otomatis buka dengan aplikasi default Windows.
    Return string tampilan singkat.
    """
    try:
        # plaintext[7:-1] = "filename:base64data"
        inner = plaintext[7:-1]
        colon_idx = inner.index(":")
        filename  = inner[:colon_idx]
        b64_data  = inner[colon_idx + 1:]

        img_data = base64.b64decode(b64_data)

        downloads_dir = os.path.join(os.path.expanduser("~"), "Downloads", "ChatMD_Received")
        os.makedirs(downloads_dir, exist_ok=True)

        base_name, ext = os.path.splitext(filename)
        unique_name = filename
        dest_path   = os.path.join(downloads_dir, unique_name)
        counter = 1
        while os.path.exists(dest_path):
            unique_name = f"{base_name}_{counter}{ext}"
            dest_path   = os.path.join(downloads_dir, unique_name)
            counter += 1

        with open(dest_path, "wb") as f:
            f.write(img_data)

        try:
            # Buka folder dan pilih file yang diterima di Windows Explorer
            subprocess.Popen(f'explorer /select,"{os.path.normpath(dest_path)}"')
        except Exception:
            try:
                os.startfile(downloads_dir)
            except Exception:
                pass

        is_img = ext.lower() in (".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp")
        label = "GAMBAR" if is_img else "FILE"
        return f"[{label}: {unique_name}] (Tersimpan di Downloads/ChatMD_Received)"
    except Exception as e:
        return f"[FILE: Gagal memproses: {e}]"


def _handle_incoming_message(data: dict):
    """Terima, decrypt, dan simpan ke riwayat chat."""
    sender  = data.get("from", "Unknown")
    payload = data.get("payload", "")

    # Decrypt
    try:
        plaintext = decrypt(payload)
    except ValueError as e:
        with g_sessions_lock:
            if g_active_partner == sender and g_current_ui:
                g_current_ui.print_message("Sistem", f"\033[91mGagal decrypt pesan: {e}\033[0m")
        return

    with g_sessions_lock:
        if sender not in g_chat_histories:
            g_chat_histories[sender] = []

        # Jika sedang aktif chat dengan pengirim ini
        if g_active_partner == sender and g_current_ui:
            # Gambar: proses & tampilkan langsung
            if plaintext.startswith("[IMAGE:") and plaintext.endswith("]"):
                display_text = _process_image_payload(plaintext)
            else:
                display_text = plaintext
            g_chat_histories[sender].append({"sender": sender, "text": display_text})
            g_current_ui.print_message(sender, display_text)
        else:
            # Simpan apa adanya; gambar akan diproses saat user buka chat
            g_chat_histories[sender].append({"sender": sender, "text": plaintext})
            g_unread_messages[sender] = g_unread_messages.get(sender, 0) + 1
            # Jika user sedang di dalam chat room dengan orang lain:
            if g_active_partner is not None and g_current_ui:
                g_current_ui.print_message("Sistem", f"\033[93m[NOTIF] Pesan baru dari {sender}! Ketik /b untuk membaca.\033[0m")
            # Jika user sedang di menu kontak:
            elif g_active_partner is None:
                sys.stdout.write("\a")
                sys.stdout.flush()
                global g_menu_needs_redraw
                g_menu_needs_redraw = True


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

def render_contact_list_only():
    """Renders the contact list menu content strictly without prompting for input."""
    print(f"  Logged in as : {g_username}")
    print(f"  Server       : ws://{g_server_ip}:{CHATMD_PORT}")
    print()

    print("  KONTAK YANG SEDANG AKTIF")
    print("  ---------------------------------------------")
    if not g_user_list:
        print("  Tidak ada kontak online saat ini, tunggu pengguna lain bergabung...")
    else:
        for i, user in enumerate(g_user_list, 1):
            with g_sessions_lock:
                unread_count = g_unread_messages.get(user, 0)
                has_chat = (user in g_chat_histories and len(g_chat_histories[user]) > 0)
            
            contact_label = f"  [{i}] {user}"
            if unread_count > 0:
                raw_indicator = f"[{unread_count} Pesan]"
                indicator = f"\033[93m{raw_indicator}\033[0m"
                # Rata kanan sejajar dengan total lebar garis hubung (47 karakter)
                total_width = 47
                spaces_count = total_width - len(contact_label) - len(raw_indicator)
                if spaces_count < 2:
                    spaces_count = 2
                line = f"{contact_label}{' ' * spaces_count}{indicator}"
            elif has_chat:
                raw_indicator = "[Pesan]"
                indicator = f"\033[90m{raw_indicator}\033[0m"
                total_width = 47
                spaces_count = total_width - len(contact_label) - len(raw_indicator)
                if spaces_count < 2:
                    spaces_count = 2
                line = f"{contact_label}{' ' * spaces_count}{indicator}"
            else:
                line = contact_label
            print(line)
    print("  ---------------------------------------------")

    print()
    print("  [R] Refresh daftar kontak")
    print("  [Q] Tutup App")
    print()


def show_contact_list() -> Optional[str]:
    """
    Tampilkan daftar kontak aktif di CMD (Desain Grid Sederhana).
    Menggunakan input non-blocking agar bisa refresh otomatis saat ada pesan/kontak baru.
    """
    global g_menu_needs_redraw
    
    clear()
    render_contact_list_only()
    
    prompt = "  Pilih nomor kontak untuk chat : "
    input_buffer = []
    
    sys.stdout.write(prompt)
    sys.stdout.flush()
    
    g_menu_needs_redraw = False
    
    try:
        while not g_shutdown.is_set():
            if g_menu_needs_redraw:
                current_input = "".join(input_buffer)
                clear()
                render_contact_list_only()
                sys.stdout.write(prompt + current_input)
                sys.stdout.flush()
                g_menu_needs_redraw = False
                
            if msvcrt.kbhit():
                ch = msvcrt.getch()
                if ch in (b'\r', b'\n'):  # Enter
                    choice = "".join(input_buffer).strip().upper()
                    print()  # Pindah baris baru setelah enter
                    
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
                        
                elif ch == b'\x08':  # Backspace
                    if input_buffer:
                        input_buffer.pop()
                        sys.stdout.write("\b \b")
                        sys.stdout.flush()
                elif ch == b'\x03':  # Ctrl+C
                    raise KeyboardInterrupt()
                elif ch == b'\xe0':  # Tombol khusus
                    msvcrt.getch()
                else:
                    try:
                        char = ch.decode("ansi")
                        if len(char) == 1 and ord(char) >= 32:
                            input_buffer.append(char)
                            sys.stdout.write(char)
                            sys.stdout.flush()
                    except UnicodeDecodeError:
                        pass
            time.sleep(0.01)
        return "__EXIT__"
    except KeyboardInterrupt:
        return "__EXIT__"


# ─── UI: Sesi Chat ─────────────────────────────────────────────────────────────

def run_chat_session(partner: str):
    """
    Jalankan sesi chat interaktif dengan partner di dalam CMD (inline).
    """
    global g_active_partner, g_current_ui, g_ws

    with g_sessions_lock:
        g_active_partner = partner
        g_unread_messages.pop(partner, None)  # Hapus status unread
        if partner not in g_chat_histories:
            g_chat_histories[partner] = []

    # Inisialisasi UI Chat
    ui = TerminalChatUI(partner, g_username)
    g_current_ui = ui
    ui.start()

    # Cetak seluruh history — gambar yang belum diproses akan di-download sekarang
    with g_sessions_lock:
        history_snapshot = list(g_chat_histories[partner])

    for msg in history_snapshot:
        text = msg["text"]
        if text.startswith("[IMAGE:") and text.endswith("]"):
            text = _process_image_payload(text)
            # Update entry di history agar tidak di-download ulang
            with g_sessions_lock:
                msg["text"] = text
        sys.stdout.write(format_message(msg['sender'], text) + "\n")
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
                ui.print_message("Sistem", "\033[91mTidak terhubung ke server. Pesan gagal terkirim.\033[0m")
                continue

            # Daftar tipe file yang diizinkan (Gambar + Dokumen)
            ALLOWED_IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp")
            ALLOWED_DOC_EXTS = (".xls", ".xlsx", ".txt", ".pdf", ".csv", ".ppt", ".pptx")
            ALLOWED_ALL_EXTS = ALLOWED_IMAGE_EXTS + ALLOWED_DOC_EXTS

            # Cek apakah input adalah perintah kirim file atau drag-and-drop file langsung
            is_file_cmd = False
            file_path = None

            # Deteksi drag & drop otomatis jika input berupa file path yang ada di lokal disk
            path_check = text_strip.strip("'\"")
            if os.path.exists(path_check) and os.path.isfile(path_check):
                _, ext = os.path.splitext(path_check)
                if ext.lower().strip() in ALLOWED_ALL_EXTS:
                    is_file_cmd = True
                    file_path = path_check
                else:
                    allowed_str = ", ".join(ALLOWED_ALL_EXTS)
                    ui.print_message("Sistem", f"\033[91mFile terdeteksi, namun tipe '{ext}' tidak diizinkan. Diizinkan: {allowed_str}\033[0m")
                    continue
            elif text_strip.lower().startswith(("/i ", "/img ")):
                is_file_cmd = True
                parts = text_strip.split(None, 1)
                file_path = parts[1].strip() if len(parts) > 1 else ""
            elif text_strip.lower().startswith(("/f ", "/file ")):
                is_file_cmd = True
                parts = text_strip.split(None, 1)
                file_path = parts[1].strip() if len(parts) > 1 else ""

            if is_file_cmd:
                if not file_path:
                    ui.print_message("Sistem", "\033[96mGunakan: /f <path_file> atau /file <path_file>\033[0m")
                    continue

                # Bersihkan tanda kutip dari Windows drag-and-drop
                file_path = file_path.strip("'\"")

                if not os.path.exists(file_path) or not os.path.isfile(file_path):
                    ui.print_message("Sistem", f"\033[91mFile tidak ditemukan: {file_path}\033[0m")
                    continue

                # Cek tipe file (ekstensi)
                _, ext = os.path.splitext(file_path)
                ext_clean = ext.lower().strip()
                if ext_clean not in ALLOWED_ALL_EXTS:
                    allowed_str = ", ".join(ALLOWED_ALL_EXTS)
                    ui.print_message("Sistem", f"\033[91mTipe file '{ext}' tidak diizinkan. Diizinkan: {allowed_str}\033[0m")
                    continue

                # Cek ukuran file (maks 10MB)
                MAX_SIZE = 10 * 1024 * 1024
                if os.path.getsize(file_path) > MAX_SIZE:
                    ui.print_message("Sistem", "\033[91mUkuran file terlalu besar (maksimal 10MB).\033[0m")
                    continue

                try:
                    _, ext = os.path.splitext(file_path)
                    ext_clean = ext.lower().strip()
                    is_img = ext_clean in ALLOWED_IMAGE_EXTS
                    label = "GAMBAR" if is_img else "FILE"

                    ui.print_message("Sistem", f"\033[96mMembaca dan mengirim {label.lower()}...\033[0m")
                    with open(file_path, "rb") as f:
                        file_bytes = f.read()
                    b64_str = base64.b64encode(file_bytes).decode("utf-8")
                    filename = os.path.basename(file_path)
                    
                    message_payload = f"[IMAGE:{filename}:{b64_str}]"
                    display_text = f"[{label}: {filename}] (Terkirim)"
                except Exception as e:
                    ui.print_message("Sistem", f"\033[91mGagal membaca file: {e}\033[0m")
                    continue
            else:
                message_payload = text_strip
                display_text = text_strip

            # Enkripsi dan kirim pesan
            try:
                encrypted = encrypt(message_payload)
                msg_data = {
                    "type": "message",
                    "to": partner,
                    "payload": encrypted,
                }
                if is_file_cmd:
                    _, ext = os.path.splitext(file_path)
                    msg_data["file_ext"] = ext.strip(".").lower()

                payload = json.dumps(msg_data)
                g_ws.send(payload)
            except Exception as e:
                ui.print_message("Sistem", f"\033[91mGagal mengirim pesan: {e}\033[0m")
                continue

            # Simpan ke riwayat pengirim
            with g_sessions_lock:
                g_chat_histories[partner].append({"sender": g_username, "text": display_text})

            # Tampilkan pesan kita sendiri di CMD
            ui.print_message(g_username, display_text)

    except KeyboardInterrupt:
        g_shutdown.set()
    finally:
        # Hentikan status UI aktif
        ui.active = False
        with g_sessions_lock:
            g_active_partner = None
            g_current_ui = None


# ─── Token Discovery ──────────────────────────────────────────────────

def discover_server(token: str):
    """
    Temukan server ChatMD menggunakan sistem query-response aktif via UDP.
    Client mengirim query ke broadcast, server membalas langsung ke client.
    Client tidak perlu bind ke port khusus — pakai port ephemeral (random).
    Return (ip, port) jika ditemukan, None jika timeout.
    """
    token = token.strip().upper()

    # Pakai port ephemeral (0) — OS yang pilih, tidak ada konflik port
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.settimeout(0.8)
    sock.bind(("", 0))  # port acak — tidak perlu 8766

    query = json.dumps({"type": "discover", "token": token}).encode("utf-8")

    deadline  = time.time() + DISCOVERY_TIMEOUT
    found_ip  = None
    found_port = CHATMD_PORT
    spinner   = ["|", "/", "-", "\\"]
    spin_i    = 0

    try:
        while time.time() < deadline:
            remaining = int(deadline - time.time())
            sys.stdout.write(
                f"\r  Mencari server [{token}] {spinner[spin_i % 4]} ({remaining}s)  "
            )
            sys.stdout.flush()
            spin_i += 1

            # Kirim query aktif ke broadcast — server akan balas langsung
            try:
                sock.sendto(query, ("255.255.255.255", DISCOVERY_PORT))
            except OSError:
                pass

            # Tunggu balasan dari server
            try:
                data, addr = sock.recvfrom(512)
                msg = json.loads(data.decode("utf-8"))
                if msg.get("token", "").upper() == token:
                    found_ip   = msg.get("ip") or addr[0]
                    found_port = int(msg.get("port", CHATMD_PORT))
                    break
            except (socket.timeout, json.JSONDecodeError, OSError):
                pass
    finally:
        sock.close()

    if found_ip:
        sys.stdout.write(f"\r  Server ditemukan: {found_ip}:{found_port}               \n")
        sys.stdout.flush()
        return found_ip, found_port
    else:
        sys.stdout.write(f"\r  [!] Token [{token}] tidak ditemukan. Coba lagi.          \n")
        sys.stdout.flush()
        return None

# ─── Auto-Update ───────────────────────────────────────────────────────────────

def check_for_update(server_ip: str) -> bool:
    """
    Bandingkan versi client saat ini dengan versi di server.
    Jika ada versi lebih baru: unduh zip, ekstrak, re-launch dari folder baru.
    Return True jika update berhasil dan proses saat ini harus berhenti.
    Return False jika tidak ada update atau update gagal.
    """
    if not CHATMD_VERSION:
        # Tidak bisa cek versi karena env var tidak di-set (dijalankan langsung dari .py)
        return False

    import urllib.request
    import zipfile
    import io

    url_version = f"http://{server_ip}:{UPDATE_PORT}/version"
    try:
        with urllib.request.urlopen(url_version, timeout=3) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        remote_hash = data.get("hash", "")
    except Exception:
        # Server tidak menyediakan endpoint update — lanjut normal
        return False

    if not remote_hash or remote_hash == CHATMD_VERSION:
        # Sudah versi terbaru
        return False

    # ── Ada versi baru ──
    print()
    print_status(f"Pembaruan tersedia! ({CHATMD_VERSION} → {remote_hash})")
    print_status("Mengunduh...")

    url_update = f"http://{server_ip}:{UPDATE_PORT}/update"
    try:
        with urllib.request.urlopen(url_update, timeout=60) as resp:
            zip_data = resp.read()
    except Exception as e:
        print_status(f"Gagal mengunduh: {e}. Melanjutkan dengan versi lama.")
        return False

    # Ekstrak ke folder temp baru dengan hash terbaru
    temp_base = os.environ.get("TEMP", os.environ.get("TMP", os.getcwd()))
    new_dir = os.path.join(temp_base, f"ChatMD_{remote_hash}")
    os.makedirs(new_dir, exist_ok=True)

    try:
        with zipfile.ZipFile(io.BytesIO(zip_data)) as zf:
            zf.extractall(new_dir)
    except Exception as e:
        print_status(f"Gagal mengekstrak: {e}. Melanjutkan dengan versi lama.")
        return False

    new_script = os.path.join(new_dir, "chatmd_client.py")
    if not os.path.exists(new_script):
        print_status("Ekstrak berhasil tapi chatmd_client.py tidak ditemukan. Lanjut versi lama.")
        return False

    print_status("Update selesai! Meluncurkan versi baru...")
    time.sleep(0.8)

    # Re-launch di folder baru; pass argumen yang sama (username override jika ada)
    env = os.environ.copy()
    env["CHATMD_VERSION"] = remote_hash
    try:
        subprocess.Popen(
            [sys.executable, new_script] + sys.argv[1:],
            cwd=new_dir,
            env=env,
        )
    except Exception as e:
        print_status(f"Gagal meluncurkan versi baru: {e}")
        return False

    return True  # sinyal ke main() untuk exit


# ─── Main ──────────────────────────────────────────────────────────────────────

def main():
    global g_username, g_server_ip

    clear()

    # 1. Ambil identitas user (bisa dari CLI args untuk override nama, berguna untuk test)
    if len(sys.argv) > 1:
        g_username = sys.argv[1].strip()
        print_info(f"Identitas di-override via argumen: {g_username}")
    else:
        g_username = get_identity()
        print_info(f"Identitas terdeteksi: {g_username}")
    print()

    # 2. Minta token dan lakukan discovery
    while True:
        try:
            raw_token = input(
                "  Masukkan TOKEN server ChatMD \033[90m(5 karakter dari host)\033[0m: "
            ).strip().upper()
        except (EOFError, KeyboardInterrupt):
            print("\n  Keluar.")
            sys.exit(0)

        if not raw_token:
            print_error("Token tidak boleh kosong.")
            continue
        if len(raw_token) != 5 or not raw_token.isalnum():
            print_error("Token harus tepat 5 karakter huruf/angka.")
            continue

        print()
        result = discover_server(raw_token)
        if result is None:
            print()
            continue  # kembali minta token
        break

    found_ip, found_port = result
    g_server_ip = found_ip
    server_url  = f"ws://{found_ip}:{found_port}"

    # 3. Cek auto-update sebelum connect (hanya jika dijalankan dari BAT)
    if check_for_update(found_ip):
        sys.exit(0)

    print()
    print_status(f"Menghubungkan ke {server_url} ...")

    # 3. Jalankan WebSocket di thread background
    ws_t = threading.Thread(target=ws_thread_func, args=(server_url,), daemon=True)
    ws_t.start()

    # Tunggu koneksi (maks 5 detik)
    if not g_ws_connected.wait(timeout=5.0):
        print_error("Gagal terhubung ke server. Pastikan server aktif dan IP benar.")
        sys.exit(1)

    print_status("Terhubung, mendaftarkan sesi...")
    
    # Tunggu registrasi berhasil (maks 3 detik)
    if not g_registered.wait(timeout=3.0):
        if g_registration_error:
            print_error(f"Pendaftaran ditolak oleh server: {g_registration_error}")
        else:
            print_error("Gagal terdaftar ke server (Timeout).")
        sys.exit(1)

    print_status("Sesi terdaftar dengan sukses.")
    time.sleep(0.5)

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

    print_status("Sesi ChatMD berakhir. Semua data chat telah dihapus dari RAM.")
    print()
    sys.exit(0)


if __name__ == "__main__":
    main()
