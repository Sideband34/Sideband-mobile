import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

import 'strkey.dart';

/// Signed bytes: the `Commitment` XDR of stellar-experimental/one-way-channel
/// (`sideband-commit-v2` in sideband-channels): an `ScVal::Map` of
/// amount (I128), channel (contract Address), domain (Symbol "chancmmt") and
/// network (Bytes32 = sha256(passphrase)), keys ascending. Encoded by hand
/// (the structure is fixed) and verified byte-for-byte against the
/// TypeScript SDK's golden vectors in `test/fixtures/voucher-vectors.json`.
/// Not checked against a live upstream contract; upstream is unaudited.
const String commitmentDomain = 'chancmmt';

const String testnetPassphrase = 'Test SDF Network ; September 2015';
const String publicPassphrase =
    'Public Global Stellar Network ; September 2015';
const Set<String> allowedPassphrases = {
  testnetPassphrase,
  'Test SDF Future Network ; October 2022',
  'Local Sandbox Stellar Network ; September 2022',
  'Standalone Network ; February 2017',
};

class VoucherException implements Exception {
  VoucherException(this.message);
  final String message;
  @override
  String toString() => 'VoucherException: $message';
}

final BigInt maxStroops = (BigInt.one << 127) - BigInt.one;

class VoucherDomain {
  const VoucherDomain({
    required this.networkPassphrase,
    required this.channelId,
    required this.payer,
    required this.provider,
  });
  final String networkPassphrase;
  final String channelId;
  final String payer;
  final String provider;
}

void _u32(BytesBuilder b, int v) {
  b.add([(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);
}

void _symbol(BytesBuilder b, String s) {
  _u32(b, 15); // SCV_SYMBOL
  _u32(b, s.length);
  b.add(ascii.encode(s));
  final pad = (4 - s.length % 4) % 4;
  b.add(List.filled(pad, 0));
}

Uint8List buildPreimage(VoucherDomain d, BigInt cumulative) {
  if (cumulative <= BigInt.zero || cumulative > maxStroops) {
    throw VoucherException('Cumulative amount out of range');
  }
  final Uint8List channel;
  try {
    channel = decodeContract(d.channelId);
    decodeEd25519PublicKey(d.payer);
    decodeEd25519PublicKey(d.provider);
  } on StrKeyException catch (e) {
    throw VoucherException('Invalid strkey: ${e.message}');
  }
  final b = BytesBuilder();
  _u32(b, 17); // SCV_MAP
  _u32(b, 1); // optional map present
  _u32(b, 4); // entries
  _symbol(b, 'amount');
  _u32(b, 10); // SCV_I128
  final mask64 = (BigInt.one << 64) - BigInt.one;
  for (final part in [cumulative >> 64, cumulative & mask64]) {
    for (var i = 7; i >= 0; i--) {
      b.addByte(((part >> (8 * i)) & BigInt.from(0xff)).toInt());
    }
  }
  _symbol(b, 'channel');
  _u32(b, 18); // SCV_ADDRESS
  _u32(b, 1); // contract address
  b.add(channel);
  _symbol(b, 'domain');
  _symbol(b, commitmentDomain);
  _symbol(b, 'network');
  _u32(b, 13); // SCV_BYTES
  _u32(b, 32);
  b.add(hash.sha256.convert(utf8.encode(d.networkPassphrase)).bytes);
  return b.toBytes();
}

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Wire voucher; field names match sideband_protocol `VoucherFrame`.
class SignedVoucher {
  const SignedVoucher({
    required this.channelRef,
    required this.cumulativeStroops,
    required this.commitment,
    required this.signature,
  });
  final String channelRef;
  final BigInt cumulativeStroops;
  final String commitment;
  final String signature;
}

/// Signing boundary. Production implementations must sit on the platform
/// keystore/keychain (NOT implemented yet); [SeedSigner] is for tests only.
abstract interface class VoucherSigner {
  /// `G...` strkey of the payer commitment key.
  String get publicKey;
  Future<Uint8List> sign(Uint8List message);
}

/// TEST-ONLY signer holding a seed in memory.
class SeedSigner implements VoucherSigner {
  SeedSigner._(this._pair, this.publicKey);

  final SimpleKeyPair _pair;
  @override
  final String publicKey;

  static Future<SeedSigner> fromSeed(List<int> seed) async {
    final pair = await Ed25519().newKeyPairFromSeed(seed);
    final pub = await pair.extractPublicKey();
    return SeedSigner._(pair, encodeEd25519PublicKey(pub.bytes));
  }

  @override
  Future<Uint8List> sign(Uint8List message) async {
    final sig = await Ed25519().sign(message, keyPair: _pair);
    return Uint8List.fromList(sig.bytes);
  }
}

Future<SignedVoucher> createVoucher(
  VoucherSigner signer,
  VoucherDomain domain,
  BigInt cumulative,
) async {
  if (domain.networkPassphrase == publicPassphrase) {
    throw VoucherException(
        'Public network is forbidden: Testnet/synthetic only');
  }
  if (!allowedPassphrases.contains(domain.networkPassphrase)) {
    throw VoucherException('Unrecognized network passphrase');
  }
  if (signer.publicKey != domain.payer) {
    throw VoucherException('Signer is not the channel payer');
  }
  final pre = buildPreimage(domain, cumulative);
  final sig = await signer.sign(pre);
  return SignedVoucher(
    channelRef: domain.channelId,
    cumulativeStroops: cumulative,
    commitment: hex(hash.sha256.convert(pre).bytes),
    signature: hex(sig),
  );
}

/// Verifies a voucher's commitment and signature against the channel domain.
/// Used by provider-side test doubles and by tests; payers do not verify their
/// own vouchers. Returns null when valid, else a stable failure code.
Future<String?> verifyVoucherSignature(
  VoucherDomain d, {
  required String channelRef,
  required BigInt cumulative,
  required String commitment,
  required String signature,
}) async {
  if (channelRef != d.channelId) {
    return 'wrong_channel';
  }
  if (!RegExp(r'^[0-9a-f]{128}$').hasMatch(signature) ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(commitment)) {
    return 'malformed';
  }
  final Uint8List pre;
  try {
    pre = buildPreimage(d, cumulative);
  } on VoucherException {
    return 'malformed';
  }
  if (hex(hash.sha256.convert(pre).bytes) != commitment) {
    return 'commitment_mismatch';
  }
  final sig = List<int>.generate(
    64,
    (i) => int.parse(signature.substring(i * 2, i * 2 + 2), radix: 16),
  );
  final ok = await Ed25519().verify(
    pre,
    signature: Signature(
      sig,
      publicKey: SimplePublicKey(decodeEd25519PublicKey(d.payer),
          type: KeyPairType.ed25519),
    ),
  );
  return ok ? null : 'bad_signature';
}
