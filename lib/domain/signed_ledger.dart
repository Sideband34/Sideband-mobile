/// Payer-side record of the highest cumulative amount ever SIGNED per channel.
///
/// The payer must persist the new high-water mark BEFORE releasing a voucher,
/// so a crash/restart (or a duplicated meter sample) can never lead to signing
/// a lower or equal cumulative amount for a different purpose. Production
/// implementations must be durable and atomic (secure local DB); the
/// in-memory version is for tests and has NO persistence.
abstract interface class SignedLedger {
  Future<BigInt> highest(String channelId);

  /// Atomically raises the high-water mark. Throws [LedgerRollback] unless
  /// [next] is strictly greater than the stored value.
  Future<void> advance(String channelId, BigInt next);
}

class LedgerRollback implements Exception {
  LedgerRollback(this.current, this.attempted);
  final BigInt current;
  final BigInt attempted;
  @override
  String toString() => 'LedgerRollback: $attempted <= $current';
}

class InMemorySignedLedger implements SignedLedger {
  final Map<String, BigInt> _m = {};

  @override
  Future<BigInt> highest(String channelId) async =>
      _m[channelId] ?? BigInt.zero;

  @override
  Future<void> advance(String channelId, BigInt next) async {
    final cur = _m[channelId] ?? BigInt.zero;
    if (next <= cur) throw LedgerRollback(cur, next);
    _m[channelId] = next;
  }
}
