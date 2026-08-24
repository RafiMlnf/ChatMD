import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt_lib;

class CryptoHelper {
  static const String keyHex = "436861744d442d414553474d2d4b6579"; // "ChatMD-AESGCM-Key"

  static Uint8List _hexToBytes(String hex) {
    final bytes = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  /// Enkripsi string teks menggunakan AES-128-GCM.
  /// Format output: hex( nonce[12] + ciphertext + tag[16] )
  static String encrypt(String plaintext) {
    final keyBytes = _hexToBytes(keyHex);
    final key = encrypt_lib.Key(keyBytes);

    final rnd = Random.secure();
    final nonceBytes = Uint8List.fromList(List<int>.generate(12, (_) => rnd.nextInt(256)));
    final iv = encrypt_lib.IV(nonceBytes);

    final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key, mode: encrypt_lib.AESMode.gcm));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);

    final combined = Uint8List(nonceBytes.length + encrypted.bytes.length);
    combined.setRange(0, nonceBytes.length, nonceBytes);
    combined.setRange(nonceBytes.length, combined.length, encrypted.bytes);

    return _bytesToHex(combined);
  }

  /// Dekripsi hex payload yang dikirim dari Python / Web Client.
  static String decrypt(String hexStr) {
    try {
      final combined = _hexToBytes(hexStr);
      if (combined.length < 28) return "[Pesan tidak valid]";

      final nonceBytes = combined.sublist(0, 12);
      final cipherAndTagBytes = combined.sublist(12);

      final keyBytes = _hexToBytes(keyHex);
      final key = encrypt_lib.Key(keyBytes);
      final iv = encrypt_lib.IV(nonceBytes);

      final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key, mode: encrypt_lib.AESMode.gcm));
      final encrypted = encrypt_lib.Encrypted(cipherAndTagBytes);

      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      return "[Pesan gagal didekripsi]";
    }
  }
}
