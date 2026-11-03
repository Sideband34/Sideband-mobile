import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../domain/strkey.dart';
import '../domain/voucher.dart';
import 'secure_store.dart';

/// Voucher signer whose ed25519 seed is generated on the device and kept in
/// a [SecureStore] (keychain/keystore via [FlutterSecureStore] in the app).
/// The seed never leaves this class; only signatures and the public key do.
class StoredKeySigner implements VoucherSigner {
  StoredKeySigner._(this._pair, this.publicKey);

  static const seedKey = 'sideband.signer.seed.v1';

  final SimpleKeyPair _pair;
  @override
  final String publicKey;

  /// Loads the device key, creating it with a CSPRNG on first use.
  static Future<StoredKeySigner> loadOrCreate(SecureStore store,
      {Random? random}) async {
    final raw = await store.read(seedKey);
    final List<int> seed;
    if (raw == null) {
      final rng = random ?? Random.secure();
      seed = List<int>.generate(32, (_) => rng.nextInt(256));
      await store.write(seedKey, base64Encode(seed));
      // Read back: a store that silently drops writes must not hand out a
      // key whose seed is lost on restart.
      if (await store.read(seedKey) != base64Encode(seed)) {
        throw StateError('Secure store did not persist the signer seed');
      }
    } else {
      seed = base64Decode(raw);
      if (seed.length != 32) throw const FormatException('Corrupt signer seed');
    }
    final pair = await Ed25519().newKeyPairFromSeed(seed);
    final pub = await pair.extractPublicKey();
    return StoredKeySigner._(pair, encodeEd25519PublicKey(pub.bytes));
  }

  @override
  Future<Uint8List> sign(Uint8List message) async {
    final sig = await Ed25519().sign(message, keyPair: _pair);
    return Uint8List.fromList(sig.bytes);
  }
}
