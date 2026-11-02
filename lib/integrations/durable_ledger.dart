import 'dart:convert';

import '../domain/signed_ledger.dart';
import 'secure_store.dart';

/// [SignedLedger] persisted through a [SecureStore]. Writes are serialized so
/// two concurrent `advance` calls cannot interleave read-modify-write and
/// lose a high-water mark. If persisting fails the error propagates and the
/// in-flight voucher must NOT be released (callers advance before signing).
class StoreBackedSignedLedger implements SignedLedger {
  StoreBackedSignedLedger(this._store,
      {this.key = 'sideband.signed_ledger.v1'});

  final SecureStore _store;
  final String key;
  Future<void> _tail = Future.value();

  Future<Map<String, String>> _load() async {
    final raw = await _store.read(key);
    if (raw == null) return {};
    final j = jsonDecode(raw);
    if (j is! Map) throw const FormatException('Corrupt signed ledger');
    return j.map((k, v) => MapEntry(k as String, v as String));
  }

  @override
  Future<BigInt> highest(String channelId) async {
    await _tail; // see any in-flight write
    return BigInt.parse((await _load())[channelId] ?? '0');
  }

  @override
  Future<void> advance(String channelId, BigInt next) {
    final run = _tail.then((_) async {
      final m = await _load();
      final cur = BigInt.parse(m[channelId] ?? '0');
      if (next <= cur) throw LedgerRollback(cur, next);
      m[channelId] = next.toString();
      await _store.write(key, jsonEncode(m));
    });
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }
}
