import 'package:flutter_test/flutter_test.dart';
import 'package:sideband_mobile/domain/receipt.dart';
import 'package:sideband_mobile/domain/signed_ledger.dart';
import 'package:sideband_mobile/integrations/durable_ledger.dart';
import 'package:sideband_mobile/integrations/history.dart';
import 'package:sideband_mobile/integrations/secure_store.dart';
import 'package:sideband_protocol/sideband_protocol.dart';

Receipt r(String id, SettlementStatus s, [String amount = '0.004']) => Receipt(
      sessionId: id,
      channelId: 'c',
      providerPublicKey: 'p',
      units: 4,
      committed: Amount.parse(amount),
      status: s,
      closeReason: 'client_close',
      channelExpiresAt: 5000,
    );

void main() {
  group('StoreBackedSignedLedger', () {
    test('persists high-water marks across a restart and blocks rollback',
        () async {
      final disk = InMemorySecureStore();
      final a = StoreBackedSignedLedger(disk);
      await a.advance('c1', BigInt.from(40));
      final b =
          StoreBackedSignedLedger(InMemorySecureStore()..load(disk.snapshot()));
      expect(await b.highest('c1'), BigInt.from(40));
      expect(await b.highest('other'), BigInt.zero);
      await expectLater(
          b.advance('c1', BigInt.from(40)), throwsA(isA<LedgerRollback>()));
      await expectLater(
          b.advance('c1', BigInt.from(10)), throwsA(isA<LedgerRollback>()));
      await b.advance('c1', BigInt.from(41));
      expect(await b.highest('c1'), BigInt.from(41));
    });

    test('concurrent advances never lose the maximum', () async {
      final l = StoreBackedSignedLedger(InMemorySecureStore());
      final results = await Future.wait([
        for (final n in [3, 9, 5, 9, 7, 1])
          l
              .advance('c', BigInt.from(n))
              .then((_) => true, onError: (_) => false),
      ]);
      expect(await l.highest('c'), BigInt.from(9));
      expect(results.where((x) => x).length,
          lessThanOrEqualTo(4)); // 3,9 then 5/7/1/9 rejected as lower/equal
    });

    test('a failing store surfaces the error so no voucher can be released',
        () async {
      final l = StoreBackedSignedLedger(_FailingStore());
      await expectLater(l.advance('c', BigInt.one), throwsA(isA<StateError>()));
    });

    test('corrupt persisted data fails loudly instead of resetting to zero',
        () async {
      final s = InMemorySecureStore();
      await s.write('sideband.signed_ledger.v1', '[1,2]');
      await expectLater(StoreBackedSignedLedger(s).highest('c'),
          throwsA(isA<FormatException>()));
    });
  });

  group('HistoryRepository', () {
    test('stores newest first, round-trips receipts and updates in place',
        () async {
      final h = HistoryRepository(InMemorySecureStore());
      await h.upsert(r('s1', SettlementStatus.committed));
      await h.upsert(r('s2', SettlementStatus.committed, '0.01'));
      expect((await h.all()).map((x) => x.sessionId), ['s2', 's1']);
      await h.upsert(r('s1', SettlementStatus.settlementSubmitted));
      expect(
          (await h.byId('s1'))!.status, SettlementStatus.settlementSubmitted);
      expect((await h.byId('s2'))!.committed, Amount.parse('0.01'));
      expect(await h.byId('nope'), isNull);
    });

    test('a confirmed receipt is never downgraded by a stale write', () async {
      final h = HistoryRepository(InMemorySecureStore());
      await h.upsert(r('s1', SettlementStatus.confirmed));
      await h.upsert(r('s1', SettlementStatus.reconciling));
      expect((await h.byId('s1'))!.status, SettlementStatus.confirmed);
    });
  });
}

class _FailingStore implements SecureStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('disk full');
  @override
  Future<void> delete(String key) async {}
}
