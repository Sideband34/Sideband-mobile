import 'dart:typed_data';

/// Minimal Stellar strkey codec (ed25519 public keys `G...` and contract ids
/// `C...`). Only what voucher domain building needs; no secret-seed support.
class StrKeyException implements Exception {
  StrKeyException(this.message);
  final String message;
  @override
  String toString() => 'StrKeyException: $message';
}

const int _versionAccount = 6 << 3; // 'G'
const int _versionContract = 2 << 3; // 'C'
const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

int _crc16(List<int> data) {
  var crc = 0;
  for (final b in data) {
    crc ^= b << 8;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
      crc &= 0xffff;
    }
  }
  return crc;
}

String _encode(int version, List<int> payload) {
  final data = [version, ...payload];
  final crc = _crc16(data);
  data.addAll([crc & 0xff, crc >> 8]);
  final out = StringBuffer();
  var buf = 0, bits = 0;
  for (final b in data) {
    buf = (buf << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out.write(_alphabet[(buf >> (bits - 5)) & 31]);
      bits -= 5;
    }
    buf &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(_alphabet[(buf << (5 - bits)) & 31]);
  return out.toString();
}

Uint8List _decode(String s, int version) {
  if (s.length != 56) throw StrKeyException('Bad length');
  final bytes = <int>[];
  var buf = 0, bits = 0;
  for (final ch in s.split('')) {
    final v = _alphabet.indexOf(ch);
    if (v < 0) throw StrKeyException('Bad character');
    buf = (buf << 5) | v;
    bits += 5;
    if (bits >= 8) {
      bytes.add((buf >> (bits - 8)) & 0xff);
      bits -= 8;
      buf &= (1 << bits) - 1;
    }
  }
  if (bytes.length != 35 || bytes[0] != version) {
    throw StrKeyException('Wrong version or length');
  }
  final crc = _crc16(bytes.sublist(0, 33));
  if (bytes[33] != (crc & 0xff) || bytes[34] != (crc >> 8)) {
    throw StrKeyException('Checksum mismatch');
  }
  return Uint8List.fromList(bytes.sublist(1, 33));
}

Uint8List decodeEd25519PublicKey(String g) => _decode(g, _versionAccount);
Uint8List decodeContract(String c) => _decode(c, _versionContract);
String encodeEd25519PublicKey(List<int> raw) => _encode(_versionAccount, raw);
String encodeContract(List<int> raw) => _encode(_versionContract, raw);
