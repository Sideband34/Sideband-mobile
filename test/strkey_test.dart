import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sideband_mobile/domain/strkey.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final fx =
      jsonDecode(File('test/fixtures/voucher-vectors.json').readAsStringSync())
          as Map<String, dynamic>;

  test('decodes fixture keys to the same raw bytes as the TS SDK', () {
    expect(_hex(decodeEd25519PublicKey(fx['payer'] as String)),
        fx['payerPublicKeyHex']);
    expect(_hex(decodeEd25519PublicKey(fx['provider'] as String)),
        fx['providerPublicKeyHex']);
    expect(_hex(decodeContract(fx['channelId'] as String)), fx['channelIdHex']);
  });

  test('encode round-trips', () {
    final raw = decodeContract(fx['channelId'] as String);
    expect(encodeContract(raw), fx['channelId']);
    final k = decodeEd25519PublicKey(fx['payer'] as String);
    expect(encodeEd25519PublicKey(k), fx['payer']);
  });

  test('rejects wrong type, bad checksum, bad length and bad characters', () {
    final c = fx['channelId'] as String;
    expect(() => decodeEd25519PublicKey(c), throwsA(isA<StrKeyException>()));
    final tampered =
        '${c.substring(0, 10)}${c[10] == 'A' ? 'B' : 'A'}${c.substring(11)}';
    expect(() => decodeContract(tampered), throwsA(isA<StrKeyException>()));
    expect(
        () => decodeContract(c.substring(1)), throwsA(isA<StrKeyException>()));
    expect(() => decodeContract('${c.substring(0, 55)}1'),
        throwsA(isA<StrKeyException>()));
  });
}
