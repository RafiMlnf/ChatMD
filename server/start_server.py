# -*- coding: utf-8 -*-
import os
import sys
import subprocess
import time
import ctypes

def set_title(title):
    try:
        ctypes.windll.kernel32.SetConsoleTitleW(title)
    except Exception:
        os.system(f"title {title}")

def check_node():
    try:
        # Check node availability
        subprocess.run(["node", "--version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False

def get_server_dir():
    # Sy.argv[0] gives the path to the executable or script
    script_dir = os.path.dirname(os.path.abspath(sys.argv[0]))
    
    # 1. Check if server.js is in the same directory as this script/exe
    if os.path.exists(os.path.join(script_dir, "server.js")):
        return script_dir
        
    # 2. Check if server.js is in a subdirectory 'server' (if run from root)
    sub_dir = os.path.join(script_dir, "server")
    if os.path.exists(os.path.join(sub_dir, "server.js")):
        return sub_dir
        
    # 3. Fallback to current working directory
    cwd = os.getcwd()
    if os.path.exists(os.path.join(cwd, "server.js")):
        return cwd
    if os.path.exists(os.path.join(cwd, "server", "server.js")):
        return os.path.join(cwd, "server")
        
    return script_dir

def install_dependencies(server_dir):
    node_modules_ws = os.path.join(server_dir, "node_modules", "ws")
    if not os.path.exists(node_modules_ws):
        print(" [*] Menginstall dependensi...")
        try:
            # Run npm install with shell=True on Windows
            subprocess.run(["npm", "install"], cwd=server_dir, shell=True, check=True)
            print(" [OK] Dependensi terinstall.\n")
        except subprocess.CalledProcessError:
            print(" [ERROR] npm install gagal!")
            input("\n Tekan Enter untuk keluar...")
            sys.exit(1)

def kill_port_8765():
    print(" [*] Memeriksa port 8765...")
    try:
        # Run netstat -ano to find process using port 8765
        # We search specifically for TCP port 8765 in LISTENING state
        cmd = 'netstat -ano | findstr ":8765" | findstr "LISTENING"'
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        
        if res.stdout:
            lines = res.stdout.strip().split('\n')
            pids_to_kill = set()
            for line in lines:
                parts = line.strip().split()
                if len(parts) >= 5:
                    pid = parts[-1]
                    if pid != "0":
                        pids_to_kill.add(pid)
            
            for pid in pids_to_kill:
                print(f" [!] Port 8765 dipakai oleh PID {pid} — mematikan...")
                subprocess.run(f"taskkill /PID {pid} /F", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                time.sleep(1)
    except Exception as e:
        print(f" [!] Gagal memeriksa atau mematikan port: {e}")

def main():
    set_title("ChatMD Server")
    print("")
    print("  ChatMD - WebSocket Server")
    print("")

    if not check_node():
        print(" [ERROR] Node.js tidak ditemukan!")
        print("         Download: https://nodejs.org/")
        input("\n Tekan Enter untuk keluar...")
        sys.exit(1)

    server_dir = get_server_dir()
    
    # Ensure dependencies
    install_dependencies(server_dir)
    
    # Ensure port is free
    kill_port_8765()

    print(" [*] Menjalankan server...")
    print(" [*] Tekan Ctrl+C untuk stop server")
    print("")

    try:
        # Run node server.js
        server_js = os.path.join(server_dir, "server.js")
        # Use shell=True for windows to properly run node
        process = subprocess.Popen(["node", "server.js"], cwd=server_dir, shell=True)
        process.wait()
    except KeyboardInterrupt:
        print("\n [*] Server diberhentikan oleh user.")
    except Exception as e:
        print(f"\n [ERROR] Terjadi kesalahan: {e}")

    print("")
    print(" [*] Server telah berhenti.")
    input(" Tekan Enter untuk menutup...")

if __name__ == "__main__":
    main()
