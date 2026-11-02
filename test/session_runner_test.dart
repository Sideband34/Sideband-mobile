import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sideband_mobile/domain/payer_session.dart';
import 'package:sideband_mobile/domain/receipt.dart';
import 'package:sideband_mobile/domain/voucher.dart';
import 'package:sideband_mobile/integrations/durable_ledger.dart';
import 'package:sideband_mobile/integrations/history.dart';
import 'package:sideband_mobile/integrations/loopback_provider.dart';
import 'package:sideband_mobile/integrations/provider_link.dart';
import 'package:sideband_mobile/integrations/secure_store.dart';
import 'package:sideband_mobile/integrations/session_runner.dart';
import 'package:sideband_protocol/sideband_protocol.dart';

void main() {
  final fx = jsonDecode(
          File('test/fixtures/session-transcript.json').readAsStringSync())
      as Map<String, dynamic>;
  final now = fx['now'] as int;
  final provider = fx['providerPublicKey'] as String;
  final payerKey = fx['payerPublicKey'] as String;
  final channelId = fx['channelId'] as String;
  late SeedSigner signer;
  setUpAll(() async =>
      signer = await SeedSigner.fromSeed(Uint8List(32)..fillRange(0, 32, 22)));

  ChannelInfo channel({String net = 'testnet', Amount? deposit}) => ChannelInfo(
        channelId: channelId,
        networkName: net,
        networkPassphrase: testnetPassphrase,
        payer: payerKey,
        provider: provider,
        deposit: deposit ?? Amount.parse('10'),
        expiresAt: 100000,
      );

  PayerPolicy policy() => PayerPolicy(
        expectedNetwork: 'testnet',
        expectedCurrency: 'TEST-TOKEN',
        maxPricePerUnit: Amount.parse('0.01'),
        trustedProviderKeys: {provider},
      );

  LoopbackProvider loop({String network = 'testnet', int? clock}) =>
      LoopbackProvider(
        domain: VoucherDomain(
          networkPassphrase: testnetPassphrase,
          channelId: channelId,
          payer: payerKey,
          provider: provider,
        ),
        network: network,
        now: () => clock ?? now,
      );

  SessionRunner runner(
    LoopbackProvider p, {
    String limit = '1',
    InMemorySecureStore? disk,
    ChannelInfo? ch,
  }) {
    final store = disk ?? InMemorySecureStore();
    var n = 0;
    return SessionRunner(
      link: p,
      channel: ch ?? channel(),
      policy: policy(),
      limits: SpendingLimits(perSession: Amount.parse(limit)),
      signer: signer,
      ledger: StoreBackedSignedLedger(store),
      history: HistoryRepository(store),
      now: () => now,
      newNonce: () => 'nonce-${n++}-${store.hashCode}',
    );
  }

  test('pays only on 402, serves repeatedly, and records an honest receipt',
      () async {
    final p = loop();
    final r = runner(p);
    await r.start();
    final a = await r.use('hello brave world');
    expect(a.output, 'HELLO BRAVE WORLD');
    expect(p.log, ['voucher 0.003']);
    await r.use('one more');
    expect(p.log, ['voucher 0.003', 'voucher 0.005']);
    final receipt = await r.finish();
    expect(receipt.units, 5);
    expect(receipt.committed, Amount.parse('0.005'));
    expect(receipt.status, SettlementStatus.committed);
    expect(receipt.statusLabel, contains('not settled'));
    expect(receipt.closeReason, 'client_close');
  });

  test('spending limit stops the session before signing past the cap',
      () async {
    final p = loop();
    final r = runner(p, limit: '0.004');
    await r.start();
    await r.use('a b c d'); // exactly 0.004
    await expectLater(r.use('e'), throwsA(isA<BudgetExceeded>()));
    expect(r.session!.phase, SessionPhase.closed);
    final receipt = await r.finish();
    expect(receipt.committed, Amount.parse('0.004'));
    expect(receipt.closeReason, 'budget_exhausted');
    expect(p.log.length, 1);
  });

  test(
      'provider shutdown mid-session closes cleanly and keeps the committed amount',
      () async {
    final p = loop();
    final r = runner(p);
    await r.start();
    await r.use('a b');
    p.shutDown = true;
    await expectLater(
      r.use('c'),
      throwsA(
          predicate((e) => e is ProviderRejected && e.code == 'shutting_down')),
    );
    final receipt = await r.finish();
    expect(receipt.closeReason, 'provider_shutdown');
    expect(receipt.committed, Amount.parse('0.002'));
    expect(receipt.isFinal, isFalse);
    expect(receipt.refundHint(now), contains('if the provider never settles'));
  });

  test('wrong-network provider is refused before any accept or signing',
      () async {
    final p = loop(network: 'futurenet');
    final r = runner(p);
    await expectLater(
      r.start(),
      throwsA(
          predicate((e) => e is SessionViolation && e.code == 'wrong_network')),
    );
    expect(p.log, isEmpty);
  });

  test('stale offer (provider clock far behind) is refused', () async {
    final p = loop(clock: now - 1000); // offer expired relative to payer clock
    final r = runner(p);
    await expectLater(
      r.start(),
      throwsA(
          predicate((e) => e is SessionViolation && e.code == 'stale_offer')),
    );
  });

  test(
      'restart: a new runner on the same durable store never re-signs lower amounts',
      () async {
    final disk = InMemorySecureStore();
    final p1 = loop();
    final r1 = runner(p1, disk: disk);
    await r1.start();
    await r1.use('a b c d e'); // 0.005 signed

    final copy = InMemorySecureStore()
      ..load(disk.snapshot()); // "app restarted"
    final p2 = loop();
    final r2 = runner(p2, disk: copy);
    await r2.start();
    // provider (fresh session) wants 0.002 only: already covered by the high-water mark,
    // so the payer must NOT sign a lower voucher; the provider keeps asking and we
    // honestly cannot comply with a lower cumulative.
    await expectLater(r2.use('a b'), throwsA(isA<PaymentRequired>()));
    expect(p2.log, isEmpty);
  });

  test('provider replay/rollback is rejected by the provider side', () async {
    final p = loop();
    final r = runner(p);
    await r.start();
    await r.use('a b c');
    final v = await r.session!.onPaymentRequired(Amount.parse('0.003'));
    expect(v, isNull); // already signed, nothing lower/equal is ever re-issued
  });

  test('history keeps one row per session across updates', () async {
    final disk = InMemorySecureStore();
    final r = runner(loop(), disk: disk);
    await r.start();
    await r.use('a');
    await r.use('b c');
    await r.finish();
    final all = await HistoryRepository(disk).all();
    expect(all, hasLength(1));
    expect(all.single.units, 3);
  });
}
