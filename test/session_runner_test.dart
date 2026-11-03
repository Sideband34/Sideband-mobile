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
import 'package:sideband_mobile/integrations/session_journal.dart';
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

  LoopbackProvider loop(
          {String network = 'testnet',
          int? clock,
          SyntheticChannelBook? book,
          String session = 'loopback-session-1'}) =>
      LoopbackProvider(
        domain: VoucherDomain(
          networkPassphrase: testnetPassphrase,
          channelId: channelId,
          payer: payerKey,
          provider: provider,
        ),
        network: network,
        now: () => clock ?? now,
        book: book,
        sessionId: session,
      );

  SessionRunner runner(
    LoopbackProvider p, {
    String limit = '1',
    InMemorySecureStore? disk,
    ChannelInfo? ch,
    ProviderLink? link,
    bool journaled = false,
  }) {
    final store = disk ?? InMemorySecureStore();
    var n = 0;
    return SessionRunner(
      journal: journaled ? SessionJournal(store) : null,
      link: link ?? p,
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
    expect(receipt.refundHint(now), contains('If the provider never settles'));
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

  group('several sessions per channel (protocol v2 baseline)', () {
    test('restart: the next session starts at the signed baseline', () async {
      final disk = InMemorySecureStore();
      final book = SyntheticChannelBook();
      final r1 = runner(loop(book: book), disk: disk);
      await r1.start();
      await r1.use('a b c d e'); // 0.005 signed
      await r1.finish();

      final copy = InMemorySecureStore()..load(disk.snapshot()); // restart
      final p2 = loop(book: book, session: 's2');
      final r2 = runner(p2, disk: copy, limit: '0.004');
      await r2.start();
      expect(r2.session!.baseline, Amount.parse('0.005'));
      await r2.use('x y'); // session owes 0.002 -> channel cumulative 0.007
      expect(p2.log, ['voucher 0.007']);
      final rec = await r2.session!.receipt();
      expect(rec.committed, Amount.parse('0.002'));
      expect(rec.baseline, Amount.parse('0.005'));
      expect(rec.channelCumulative, Amount.parse('0.007'));
      // The session budget is measured from the baseline (0.005 + 0.004).
      await expectLater(r2.use('a b c'), throwsA(isA<BudgetExceeded>()));
      expect(await StoreBackedSignedLedger(copy).highest(channelId),
          Amount.parse('0.007').stroops);
      final hist = await HistoryRepository(copy).all();
      expect(hist.map((h) => h.committed.toString()), ['0.002', '0.005']);
    });

    test('an undelivered voucher surfaces as a BaselineGap; nothing is signed',
        () async {
      final disk = InMemorySecureStore();
      final r1 = runner(loop(), disk: disk);
      await r1.start();
      await r1.use('a b c d e'); // provider book A saw 0.005
      final copy = InMemorySecureStore()..load(disk.snapshot());
      final fresh = loop(session: 's2'); // provider that never saw it
      final e = await runner(fresh, disk: copy)
          .start()
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(e, isA<BaselineGap>());
      expect((e as BaselineGap).gap, Amount.parse('0.005'));
      expect(fresh.log, isEmpty);
    });

    test('a provider claiming more than was ever signed is refused', () async {
      final book = SyntheticChannelBook()
        ..record(channelId, Amount.parse('0.01'));
      await expectLater(
        runner(loop(book: book)).start(),
        throwsA(predicate((e) =>
            e is SessionViolation && e.code == 'provider_baseline_ahead')),
      );
    });

    test('a fully committed deposit needs a top-up first', () async {
      final book = SyntheticChannelBook();
      final disk = InMemorySecureStore();
      final ch = channel(deposit: Amount.parse('0.005'));
      final r1 = runner(loop(book: book), disk: disk, ch: ch);
      await r1.start();
      await r1.use('a b c d e');
      await r1.finish();
      await expectLater(
        runner(loop(book: book, session: 's2'), disk: disk, ch: ch).start(),
        throwsA(predicate(
            (e) => e is SessionViolation && e.code == 'channel_exhausted')),
      );
    });
  });

  group('payer crash resume (journal)', () {
    test('a voucher signed but not sent before a crash is re-sent on resume',
        () async {
      final disk = InMemorySecureStore();
      final p = loop();
      final crashing = _CrashOnVoucher(p, deliverFirst: false);
      final r1 = runner(p, disk: disk, link: crashing, journaled: true);
      await r1.start();
      await expectLater(r1.use('a b c'), throwsA(isA<_Crash>()));
      expect(p.log, isEmpty); // never reached the provider

      final copy = InMemorySecureStore()..load(disk.snapshot()); // restart
      final r2 = runner(p, disk: copy, journaled: true);
      expect(await r2.resume(), ResumeOutcome.resumed);
      expect(p.log, ['voucher 0.003']); // identical voucher, re-sent once
      expect((await r2.use('a b c')).output, 'A B C');
      expect(r2.session!.units, 3);
      expect(await StoreBackedSignedLedger(copy).highest(channelId),
          Amount.parse('0.003').stroops);
      await r2.finish();
      expect(await runner(p, disk: copy, journaled: true).resume(),
          ResumeOutcome.none);
    });

    test('a voucher the provider already has is treated as delivered',
        () async {
      final disk = InMemorySecureStore();
      final p = loop();
      final r1 = runner(p,
          disk: disk,
          link: _CrashOnVoucher(p, deliverFirst: true),
          journaled: true);
      await r1.start();
      await expectLater(r1.use('a b'), throwsA(isA<_Crash>()));
      final copy = InMemorySecureStore()..load(disk.snapshot());
      final r2 = runner(p, disk: copy, journaled: true);
      expect(await r2.resume(), ResumeOutcome.resumed);
      expect(p.log, ['voucher 0.002', 'voucher 0.002']); // re-send refused
      expect((await r2.use('a b')).cumulativeUnits, 2);
    });

    test('resume against a provider that lost the session is "interrupted"',
        () async {
      final disk = InMemorySecureStore();
      final r1 = runner(loop(), disk: disk, journaled: true);
      await r1.start();
      await r1.use('a');
      final copy = InMemorySecureStore()..load(disk.snapshot());
      final r2 = runner(loop(session: 'other'), disk: copy, journaled: true);
      expect(await r2.resume(), ResumeOutcome.interrupted);
      final rec = (await HistoryRepository(copy).all()).single;
      expect(rec.closeReason, 'interrupted');
      expect(rec.units, 1);
      expect(rec.status, SettlementStatus.committed);
      expect(await SessionJournal(copy).load(), isNull);
    });

    test('a corrupt journal is dropped, never guessed at', () async {
      final disk = InMemorySecureStore();
      await disk.write('sideband.session_journal.v1', '{"v":9}');
      expect(await runner(loop(), disk: disk, journaled: true).resume(),
          ResumeOutcome.none);
      expect(await disk.read('sideband.session_journal.v1'), isNull);
    });
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

class _Crash implements Exception {}

/// Simulates the app dying around the first voucher delivery: before it
/// reaches the provider ([deliverFirst] false) or right after (true).
class _CrashOnVoucher implements ResumableLink {
  _CrashOnVoucher(this.inner, {required this.deliverFirst});
  final LoopbackProvider inner;
  final bool deliverFirst;
  bool _crashed = false;

  @override
  Future<ServiceOffer> requestOffer() => inner.requestOffer();
  @override
  Future<void> accept(SessionAccept a) => inner.accept(a);
  @override
  Future<void> sendVoucher(VoucherFrame v) async {
    if (!_crashed) {
      _crashed = true;
      if (deliverFirst) await inner.sendVoucher(v);
      throw _Crash();
    }
    await inner.sendVoucher(v);
  }

  @override
  Future<ServeResult> serve(String text) => inner.serve(text);
  @override
  Future<void> close() => inner.close();
  @override
  Map<String, String> get resumeState => inner.resumeState;
  @override
  Future<void> reattach(Map<String, String> state) => inner.reattach(state);
}
