import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sideband_mobile/domain/voucher.dart';

void main() {
  final fx =
      jsonDecode(File('test/fixtures/voucher-vectors.json').readAsStringSync())
          as Map<String, dynamic>;
  final domain = VoucherDomain(
    networkPassphrase: fx['networkPassphrase'] as String,
    channelId: fx['channelId'] as String,
    payer: fx['payer'] as String,
    provider: fx['provider'] as String,
  );
  late SeedSigner payer;
  setUpAll(() async =>
      payer = await SeedSigner.fromSeed(Uint8List(32)..fillRange(0, 32, 1)));

  test('test signer derives the fixture payer key', () {
    expect(payer.publicKey, fx['payer']);
  });

  test('Dart preimage, commitment and signature equal the TS golden vectors',
      () async {
    for (final v in fx['vectors'] as List<dynamic>) {
      final stroops = BigInt.parse(v['cumulativeStroops'] as String);
      expect(hex(buildPreimage(domain, stroops)), v['preimageHex']);
      final signed = await createVoucher(payer, domain, stroops);
      expect(signed.commitment, v['commitment']);
      expect(signed.signature, v['signature']); // ed25519 is deterministic
      expect(signed.channelRef, fx['channelId']);
    }
  });

  test('refuses the public network, unknown networks and foreign signers',
      () async {
    expect(
      () => createVoucher(
        payer,
        VoucherDomain(
          networkPassphrase: publicPassphrase,
          channelId: domain.channelId,
          payer: domain.payer,
          provider: domain.provider,
        ),
        BigInt.one,
      ),
      throwsA(isA<VoucherException>()),
    );
    expect(
      () => createVoucher(
        payer,
        VoucherDomain(
          networkPassphrase: 'Mystery',
          channelId: domain.channelId,
          payer: domain.payer,
          provider: domain.provider,
        ),
        BigInt.one,
      ),
      throwsA(isA<VoucherException>()),
    );
    final other = await SeedSigner.fromSeed(Uint8List(32)..fillRange(0, 32, 3));
    expect(() => createVoucher(other, domain, BigInt.one),
        throwsA(isA<VoucherException>()));
  });

  test('rejects zero and out-of-range amounts', () {
    expect(() => buildPreimage(domain, BigInt.zero),
        throwsA(isA<VoucherException>()));
    expect(() => buildPreimage(domain, BigInt.one << 127),
        throwsA(isA<VoucherException>()));
  });

  test('i128 encoding splits into hi/lo 64-bit words for amounts above 2^64',
      () {
    final big = (BigInt.one << 64) + BigInt.from(5);
    final h = hex(buildPreimage(domain, big));
    // after: map header (12 bytes) + symbol "amount" (16) + I128 tag (4) => 32 bytes
    final amountWords = h.substring(32 * 2, (32 + 16) * 2);
    expect(amountWords, '0000000000000001' '0000000000000005');
  });

  test('verifyVoucherSignature accepts TS vectors and rejects tampering',
      () async {
    final v = (fx['vectors'] as List).last as Map<String, dynamic>;
    final stroops = BigInt.parse(v['cumulativeStroops'] as String);
    Future<String?> check(
            {String? sig, BigInt? amt, String? commitment, String? channel}) =>
        verifyVoucherSignature(
          domain,
          channelRef: channel ?? domain.channelId,
          cumulative: amt ?? stroops,
          commitment: commitment ?? v['commitment'] as String,
          signature: sig ?? v['signature'] as String,
        );
    expect(await check(), isNull);
    expect(await check(amt: stroops + BigInt.one), 'commitment_mismatch');
    expect(await check(channel: 'CX'), 'wrong_channel');
    expect(await check(sig: 'zz'), 'malformed');
    final bad = (v['signature'] as String)
        .replaceRange(0, 1, v['signature'][0] == '0' ? '1' : '0');
    expect(await check(sig: bad), 'bad_signature');
  });
}
