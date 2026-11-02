import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sideband_mobile/domain/payer_session.dart';
import 'package:sideband_mobile/domain/receipt.dart';
import 'package:sideband_mobile/domain/signed_ledger.dart';
import 'package:sideband_mobile/domain/voucher.dart';
import 'package:sideband_protocol/sideband_protocol.dart';

void main() {
  final fx = jsonDecode(
          File('test/fixtures/session-transcript.json').readAsStringSync())
      as Map<String, dynamic>;
  final frames = (fx['frames'] as Map).cast<String, dynamic>();
  final now = fx['now'] as int;
  final provider = fx['providerPublicKey'] as String;
  final payerKey = fx['payerPublicKey'] as String;
  final channelId = fx['channelId'] as String;
  late SeedSigner signer;
  setUpAll(() async =>
      signer = await SeedSigner.fromSeed(Uint8List(32)..fillRange(0, 32, 22)));

  Frame frame(String name, [Map<String, Object?>? patch]) =>
      Frame.decode(jsonEncode(
          {...(frames[name] as Map).cast<String, Object?>(), ...?patch}));

  final policy = PayerPolicy(
    expectedNetwork: 'testnet',
    expectedCurrency: 'TEST-TOKEN',
    maxPricePerUnit: Amount.parse('0.01'),
    trustedProviderKeys: {provider},
  );

  ChannelInfo channel(
          {Amount? deposit, int expiresAt = 100000, String? providerKey}) =>
      ChannelInfo(
        channelId: channelId,
        networkName: 'testnet',
        networkPassphrase: testnetPassphrase,
        payer: payerKey,
        provider: providerKey ?? provider,
        deposit: deposit ?? Amount.parse('10'),
        expiresAt: expiresAt,
      );

  PayerSession session({
    ChannelInfo? ch,
    Amount? limit,
    SignedLedger? ledger,
    PayerPolicy? pol,
    int? at,
  }) =>
      PayerSession(
        sessionId: 'sess-fixture-0001',
        channel: ch ?? channel(),
        policy: pol ?? policy,
        limits: SpendingLimits(perSession: limit ?? Amount.parse('1')),
        signer: signer,
        ledger: ledger ?? InMemorySignedLedger(),
        now: () => at ?? now,
      );

  MeterSample sample(int seq, int units) => MeterSample(
        session: 'sess-fixture-0001',
        seq: seq,
        cumulativeUnits: units,
        sampleHash: 'h$seq',
      );

  Future<PayerSession> active({PayerSession? s}) async {
    final p = s ?? session();
    p.receiveOffer(frame('service_offer') as ServiceOffer);
    p.buildAccept(nonce: 'n-1');
    return p;
  }

  group('gateway fixture parity', () {
    test(
        'decodes gateway frames and signs the exact voucher the gateway accepted',
        () async {
      final p = session();
      p.receiveOffer(frame('service_offer') as ServiceOffer);
      final accept = p.buildAccept(nonce: 'nonce-fixture-0001');
      final gwAccept = frame('session_accept') as SessionAccept;
      expect(
          accept.encode(), gwAccept.encode()); // byte-identical canonical frame
      final gwSample = frame('meter_sample') as MeterSample;
      final v = await p.onMeterSample(gwSample);
      final gwVoucher = frame('voucher_high') as VoucherFrame;
      expect(
          v!.encode(), gwVoucher.encode()); // TS and Dart sign identical bytes
      expect(p.phase, SessionPhase.active);
    });

    test('every gateway fixture frame decodes with the protocol package', () {
      for (final name in frames.keys) {
        expect(() => frame(name), returnsNormally, reason: name);
      }
    });
  });

  group('offer validation', () {
    test('rejects stale offers, wrong network, untrusted provider, high price',
        () {
      final offer = frame('service_offer') as ServiceOffer;
      expect(
        () => session(at: offer.expiresAt).receiveOffer(offer),
        throwsA(
            predicate((e) => e is SessionViolation && e.code == 'stale_offer')),
      );
      final other =
          frame('service_offer', {'network': 'futurenet'}) as ServiceOffer;
      expect(
        () => session().receiveOffer(other),
        throwsA(predicate(
            (e) => e is SessionViolation && e.code == 'wrong_network')),
      );
      final untrusted = PayerPolicy(
        expectedNetwork: 'testnet',
        expectedCurrency: 'TEST-TOKEN',
        maxPricePerUnit: Amount.parse('0.01'),
        trustedProviderKeys: {'GSOMEONEELSE'},
      );
      expect(
        () => session(pol: untrusted).receiveOffer(offer),
        throwsA(predicate(
            (e) => e is SessionViolation && e.code == 'untrusted_provider')),
      );
      final pricey =
          frame('service_offer', {'pricePerUnit': '5'}) as ServiceOffer;
      expect(
        () => session().receiveOffer(pricey),
        throwsA(predicate(
            (e) => e is SessionViolation && e.code == 'price_too_high')),
      );
    });

    test('rejects an offer from a provider other than the funded channel\'s',
        () {
      expect(
        () => session(ch: channel(providerKey: 'GOTHER'))
            .receiveOffer(frame('service_offer') as ServiceOffer),
        throwsA(predicate(
            (e) => e is SessionViolation && e.code == 'wrong_provider')),
      );
    });

    test('rejects an expired funded channel', () {
      expect(
        () => session(ch: channel(expiresAt: now))
            .receiveOffer(frame('service_offer') as ServiceOffer),
        throwsA(predicate(
            (e) => e is SessionViolation && e.code == 'channel_expired')),
      );
    });

    test('accept cap is the smallest of limit, offer cap and deposit',
        () async {
      final a = (await active(s: session(limit: Amount.parse('0.5')))).maxSpend;
      expect(a, Amount.parse('0.5'));
      final b =
          (await active(s: session(ch: channel(deposit: Amount.parse('0.25')))))
              .maxSpend;
      expect(b, Amount.parse('0.25'));
      final c = (await active(s: session(limit: Amount.parse('9'))))
          .maxSpend; // offer cap 1000*0.001
      expect(c, Amount.parse('1'));
    });
  });

  group('signing discipline', () {
    test(
        'signs cumulative amounts monotonically and skips already covered usage',
        () async {
      final ledger = InMemorySignedLedger();
      final p = await active(s: session(ledger: ledger));
      expect((await p.onMeterSample(sample(1, 2)))!.cumulativeAmount,
          Amount.parse('0.002'));
      expect((await p.onMeterSample(sample(2, 5)))!.cumulativeAmount,
          Amount.parse('0.005'));
      expect(await p.onMeterSample(sample(3, 5)),
          isNull); // no new usage, nothing to sign
      expect(await ledger.highest(channelId), Amount.parse('0.005').stroops);
    });

    test('rejects replayed/stale samples and meter regression without signing',
        () async {
      final ledger = InMemorySignedLedger();
      final p = await active(s: session(ledger: ledger));
      await p.onMeterSample(sample(1, 3));
      await expectLater(
        p.onMeterSample(sample(1, 4)),
        throwsA(predicate(
            (e) => e is SessionViolation && e.code == 'stale_sample')),
      );
      await expectLater(
        p.onMeterSample(sample(2, 2)),
        throwsA(predicate(
            (e) => e is SessionViolation && e.code == 'meter_regression')),
      );
      expect(await ledger.highest(channelId), Amount.parse('0.003').stroops);
    });

    test(
        'after an app restart the persisted ledger prevents lower or equal signing',
        () async {
      final ledger = InMemorySignedLedger();
      final first = await active(s: session(ledger: ledger));
      await first.onMeterSample(sample(1, 4));
      final restarted =
          await active(s: session(ledger: ledger)); // new process, same store
      expect(await restarted.onMeterSample(sample(1, 3)), isNull);
      expect(await restarted.onMeterSample(sample(2, 4)), isNull);
      expect((await restarted.onMeterSample(sample(3, 6)))!.cumulativeAmount,
          Amount.parse('0.006'));
    });

    test('ledger refuses rollback directly', () async {
      final l = InMemorySignedLedger();
      await l.advance('c', BigInt.from(10));
      await expectLater(
          l.advance('c', BigInt.from(10)), throwsA(isA<LedgerRollback>()));
      await expectLater(
          l.advance('c', BigInt.from(3)), throwsA(isA<LedgerRollback>()));
    });

    test('budget cap: never signs past maxSpend, closes the session', () async {
      final ledger = InMemorySignedLedger();
      final p = await active(
          s: session(limit: Amount.parse('0.003'), ledger: ledger));
      await p.onMeterSample(sample(1, 3));
      await expectLater(
          p.onMeterSample(sample(2, 4)), throwsA(isA<BudgetExceeded>()));
      expect(p.phase, SessionPhase.closed);
      expect(await ledger.highest(channelId), Amount.parse('0.003').stroops);
      final r = await p.receipt();
      expect(r.closeReason, 'budget_exhausted');
    });

    test('unit cap from the offer is enforced by the protocol machine',
        () async {
      final p = await active();
      await expectLater(
        p.onMeterSample(sample(1, 1001)),
        throwsA(
            predicate((e) => e is SessionViolation && e.code == 'unit_cap')),
      );
    });
  });

  group('provider shutdown and receipts', () {
    test(
        'provider close/error stops the session and the receipt stays "committed"',
        () async {
      final p = await active();
      await p.onMeterSample(sample(1, 4));
      p.onProviderClose(ErrorFrame(
          session: 'sess-fixture-0001', code: 'shutting_down', message: 'bye'));
      expect(p.phase, SessionPhase.closed);
      final r = await p.receipt();
      expect(r.closeReason, 'provider_error:shutting_down');
      expect(r.status, SettlementStatus.committed);
      expect(r.isFinal, isFalse);
      expect(r.statusLabel, contains('not settled'));
      expect(r.statusLabel.toLowerCase(), isNot(contains('paid')));
      expect(r.refundHint(now), contains('if the provider never settles'));
      expect(
          r.refundHint(r.channelExpiresAt), startsWith('Refund available now'));
    });

    test('only a confirmed receipt may claim settlement', () async {
      final p = await active();
      await p.onMeterSample(sample(1, 4));
      final r = await p.receipt();
      for (final s in SettlementStatus.values) {
        final label = r.withStatus(s).statusLabel;
        if (s == SettlementStatus.confirmed) {
          expect(label, startsWith('Settled on Stellar'));
          expect(r.withStatus(s).isFinal, isTrue);
        } else {
          expect(label.startsWith('Settled'), isFalse, reason: '$s');
          expect(r.withStatus(s).isFinal, isFalse);
        }
      }
    });
  });
}
