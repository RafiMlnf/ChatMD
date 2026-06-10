"""
ChatMD — Volatile Intranet Chat
crypto_utils.py — AES-128-GCM Encryption Helper

Menggunakan library `cryptography` (hazmat layer).
Pre-Shared Key (PSK) 128-bit di-hardcode atau dari env var CHATMD_KEY / VINC_KEY.

Format ciphertext yang dikirim via WebSocket:
  hex( nonce[12] + ciphertext + tag[16] )
"""

import os
import binascii
from cryptography.hazmat.primitives.ciphers.aead import AESGCM


# ─── Pre-Shared Key ────────────────────────────────────────────────────────────
# Ganti nilai ini dengan key 16-byte (32 hex char) yang sama di semua instance.
# Atau set env var CHATMD_KEY untuk override tanpa edit source.
_DEFAULT_KEY_HEX = "436861744d442d414553474d2d4b6579"  # "ChatMD-AESGCM-Key"

def _load_key() -> bytes:
    """Load AES-128 key (16 bytes) dari env var atau default hardcode."""
    raw = os.environ.get("CHATMD_KEY", os.environ.get("VINC_KEY", _DEFAULT_KEY_HEX))
    try:
        key_bytes = binascii.unhexlify(raw)
    except binascii.Error:
        raise ValueError(
            "CHATMD_KEY env var tidak valid. Harus berupa hex string 32 karakter (16 bytes)."
        )
    if len(key_bytes) not in (16, 24, 32):
        raise ValueError(
            f"CHATMD_KEY harus 16, 24, atau 32 bytes. Diterima: {len(key_bytes)} bytes."
        )
    return key_bytes


# Singleton — key dimuat sekali saat import
_KEY: bytes = _load_key()
_AESGCM: AESGCM = AESGCM(_KEY)

# ─── Public API ────────────────────────────────────────────────────────────────

def encrypt(plaintext: str) -> str:
    """
    Enkripsi plaintext string menggunakan AES-128-GCM.

    Returns:
        Hex string: nonce(12B) + ciphertext + tag(16B)
    """
    nonce = os.urandom(12)          # Random nonce baru tiap pesan (WAJIB)
    ct = _AESGCM.encrypt(nonce, plaintext.encode("utf-8"), None)
    return binascii.hexlify(nonce + ct).decode("ascii")


def decrypt(hex_payload: str) -> str:
    """
    Dekripsi hex payload yang dihasilkan oleh encrypt().

    Returns:
        Plaintext string asli.

    Raises:
        ValueError: Jika payload rusak atau autentikasi gagal.
    """
    try:
        raw = binascii.unhexlify(hex_payload)
    except binascii.Error:
        raise ValueError("Payload bukan hex string yang valid.")

    if len(raw) < 12 + 16:  # minimal nonce + tag
        raise ValueError("Payload terlalu pendek (corrupt).")

    nonce = raw[:12]
    ct_with_tag = raw[12:]

    try:
        plaintext_bytes = _AESGCM.decrypt(nonce, ct_with_tag, None)
    except Exception:
        # InvalidTag, dll — pesan diubah atau key salah
        raise ValueError("Dekripsi gagal: autentikasi GCM tidak valid (pesan dimodifikasi?).")

    return plaintext_bytes.decode("utf-8")


# ─── Self-test (jalankan langsung untuk verifikasi) ────────────────────────────
if __name__ == "__main__":
    print("=== ChatMD Crypto Self-Test ===")
    sample = "Halo dari ChatMD! 🔒"
    enc = encrypt(sample)
    dec = decrypt(enc)
    print(f"Plaintext : {sample}")
    print(f"Encrypted : {enc}")
    print(f"Decrypted : {dec}")
    assert dec == sample, "MISMATCH!"
    print("✓ AES-GCM test PASSED")

    # Test bahwa nonce berbeda setiap kali
    enc2 = encrypt(sample)
    assert enc != enc2, "Nonce tidak random!"
    print("✓ Nonce uniqueness test PASSED")
