import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sideband_mobile/domain/receipt.dart';
import 'package:sideband_mobile/domain/voucher.dart';
import 'package:sideband_mobile/integrations/durable_ledger.dart';
import 'package:sideband_mobile/integrations/file_store.dart';
import 'package:sideband_mobile/integrations/flutter_secure_store.dart';
import 'package:sideband_mobile/integrations/history.dart';
import 'package:sideband_mobile/integrations/secure_store.dart';
import 'package:sideband_mobile/integrations/stored_key_signer.dart';
import 'package:sideband_protocol/sideband_protocol.dart';

const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Fake keychain behind the real plugin's platform channel.
class FakeKeychain {
  final Map<String, String> data = {};
  final List<String> calls = [];
  bool failWrites = false;

  Future<Object?> handle(MethodCall c) async {
    calls.add(c.method);
    final a = (c.arguments as Map).cast<String, Object?>();
    switch (c.method) {
      case 'read':
        return data[a['key']];
      case 'write':
        if (failWrites) throw PlatformException(code: 'KeystoreError');
        data[a['key'] as String] = a['value'] as String;
        return null;
      case 'delete':
        data.remove(a['key']);
        return null;
      case 'containsKey':
        return data.containsKey(a['key']);
      case 'readAll':
        return Map.of(data);
      default:
        return null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain kc;
  setUp(() {
    kc = FakeKeychain();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, kc.handle);
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  group('FlutterSecureStore (mocked platform channel)', () {
    test('reads, writes and deletes through the plugin', () async {
      final s = FlutterSecureStore();
      expect(await s.read('k'), isNull);
      await s.write('k', 'v');
      expect(kc.data, {'k': 'v'});
      expect(await s.read('k'), 'v');
      await s.delete('k');
      expect(kc.data, isEmpty);
      expect(kc.calls, containsAllInOrder(['read', 'write', 'read', 'delete']));
    });

    test('keystore failures propagate (callers must not release vouchers)',
        () async {
      kc.failWrites = true;
      final ledger = StoreBackedSignedLedger(FlutterSecureStore());
      await expectLater(ledger.advance('C1', BigInt.from(5)),
          throwsA(isA<PlatformException>()));
      expect(await ledger.highest('C1'), BigInt.zero);
    });

    test('the signed ledger survives a "restart" (new store instance)',
        () async {
      await StoreBackedSignedLedger(FlutterSecureStore())
          .advance('C1', BigInt.from(7));
      expect(await StoreBackedSignedLedger(FlutterSecureStore()).highest('C1'),
          BigInt.from(7));
    });
  });

  group('StoredKeySigner', () {
    test('creates a device key once and reloads the same key', () async {
      final a = await StoredKeySigner.loadOrCreate(FlutterSecureStore(),
          random: Random(1));
      expect(kc.data.keys, [StoredKeySigner.seedKey]);
      final b = await StoredKeySigner.loadOrCreate(FlutterSecureStore());
      expect(b.publicKey, a.publicKey);
      expect(a.publicKey, startsWith('G'));
      final msg = Uint8List.fromList([1, 2, 3]);
      expect(await a.sign(msg), await b.sign(msg)); // ed25519 deterministic
    });

    test('signs vouchers that verify against its public key', () async {
      final s = await StoredKeySigner.loadOrCreate(InMemorySecureStore());
      final d = VoucherDomain(
        networkPassphrase: testnetPassphrase,
        channelId: 'CAEQSCIJBEEQSCIJBEEQSCIJBEEQSCIJBEEQSCIJBEEQSCIJBEEQTD2L',
        payer: s.publicKey,
        provider: s.publicKey,
      );
      final v = await createVoucher(s, d, BigInt.from(10));
      expect(
          await verifyVoucherSignature(d,
              channelRef: v.channelRef,
              cumulative: v.cumulativeStroops,
              commitment: v.commitment,
              signature: v.signature),
          isNull);
    });

    test('refuses a corrupt seed and a store that drops writes', () async {
      final bad = InMemorySecureStore();
      await bad.write(StoredKeySigner.seedKey, 'AAAA');
      await expectLater(
          StoredKeySigner.loadOrCreate(bad), throwsA(isA<FormatException>()));
      await expectLater(StoredKeySigner.loadOrCreate(_DroppingStore()),
          throwsA(isA<StateError>()));
    });
  });

  group('AtomicFileStore (durable history)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('sideband-'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('persists across instances and leaves no temp file', () async {
      final a = AtomicFileStore(dir);
      await a.write('x', '1');
      await a.write('y', '2');
      await a.delete('x');
      final b = AtomicFileStore(dir);
      expect(await b.read('y'), '2');
      expect(await b.read('x'), isNull);
      expect(dir.listSync().map((e) => e.uri.pathSegments.last),
          ['sideband-data.json']);
    });

    test('concurrent writes are serialized (none lost)', () async {
      final s = AtomicFileStore(dir);
      await Future.wait([for (var i = 0; i < 20; i++) s.write('k$i', '$i')]);
      final again = AtomicFileStore(dir);
      for (var i = 0; i < 20; i++) {
        expect(await again.read('k$i'), '$i');
      }
    });

    test('a corrupt file is set aside, not trusted', () async {
      File('${dir.path}/sideband-data.json').writeAsStringSync('{torn');
      final s = AtomicFileStore(dir);
      expect(await s.read('anything'), isNull);
      expect(
          File('${dir.path}/sideband-data.json.corrupt').existsSync(), isTrue);
    });

    test('history repository on the file store survives a restart', () async {
      final r = Receipt(
        sessionId: 's1',
        channelId: 'C1',
        providerPublicKey: 'GP',
        units: 3,
        committed: Amount.parse('0.003'),
        baseline: Amount.parse('0.01'),
        status: SettlementStatus.committed,
        closeReason: 'client_close',
        channelExpiresAt: 9,
      );
      await HistoryRepository(AtomicFileStore(dir)).upsert(r);
      final back = (await HistoryRepository(AtomicFileStore(dir)).all()).single;
      expect(back.committed, Amount.parse('0.003'));
      expect(back.channelCumulative, Amount.parse('0.013'));
    });
  });
}

class _DroppingStore implements SecureStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}
