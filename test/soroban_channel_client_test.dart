import 'package:flutter_test/flutter_test.dart';
import 'package:sideband_protocol/sideband_protocol.dart';
import 'package:sideband_mobile/domain/channel_state.dart';
import 'package:sideband_mobile/domain/payer_session.dart';
import 'package:sideband_mobile/integrations/soroban_channel_client.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart';

/// A fake chain that follows the contract's rules, so the client's mapping and
/// refusals are tested without a network. It records every invoke.
class FakePort implements SorobanPort {
  FakePort(this.snap);
  ChannelSnapshot snap;
  final calls = <String>[];
  bool dropWrites = false; // applied tx whose effect is not visible yet

  @override
  Future<ChannelSnapshot> readChannel() async => snap;

  @override
  Future<String> invoke(String method, List<XdrSCVal> args) async {
    calls.add(method);
    if (dropWrites) return 'ab' * 32;
    switch (method) {
      case 'top_up':
        final amt =
            (args.single.i128!.hi.int64 << 64) + args.single.i128!.lo.uint64;
        snap = _copy(snap, deposit: snap.deposit + amt);
      case 'close_start':
        snap = _copy(snap,
            status: 'Closing', closeEffectiveAt: 1000 + snap.closeWait);
      case 'refund':
        snap = _copy(snap,
            status: 'Refunded',
            refundedToPayer: snap.deposit - snap.paidToProvider);
    }
    return 'cd' * 32;
  }
}

ChannelSnapshot _copy(ChannelSnapshot s,
        {String? status,
        BigInt? deposit,
        BigInt? refundedToPayer,
        int? closeEffectiveAt}) =>
    ChannelSnapshot(
      status: status ?? s.status,
      deposit: deposit ?? s.deposit,
      paidToProvider: s.paidToProvider,
      refundedToPayer: refundedToPayer ?? s.refundedToPayer,
      expiresAt: s.expiresAt,
      closeWait: s.closeWait,
      closeEffectiveAt: closeEffectiveAt ?? s.closeEffectiveAt,
      payer: s.payer,
      provider: s.provider,
    );

const payer = 'GC7ZWRDXDPR6OFB6R72463R6PQQJHOEII5EVEEKOSK5ZQDQRYJSHPHRX';
const provider = 'GBGVFJ3SDXJMUHW7WDZQSV6GXNU6MVY2BMTK2G6QREAZYW7OI64J75MP';

void main() {
  var clock = 1000;
  late FakePort port;
  late SorobanChannelClient client;
  final info = ChannelInfo(
    channelId: 'CTEST',
    networkName: 'testnet',
    networkPassphrase: 'Test SDF Network ; September 2015',
    payer: payer,
    provider: provider,
    deposit: Amount.fromStroops(BigInt.from(10000000)),
    expiresAt: 1000,
  );

  setUp(() {
    clock = 1000;
    port = FakePort(ChannelSnapshot(
      status: 'Open',
      deposit: BigInt.from(10000000),
      paidToProvider: BigInt.from(3000000),
      refundedToPayer: BigInt.zero,
      expiresAt: 1000,
      closeWait: 600,
      closeEffectiveAt: 0,
      payer: payer,
      provider: provider,
    ));
    client = SorobanChannelClient(info: info, port: port, now: () => clock);
  });

  test('status maps chain state and is never synthetic', () async {
    final s = await client.status();
    expect(s.synthetic, isFalse);
    expect(s.status, ChannelStatus.open);
    expect(s.withdrawn, Amount.fromStroops(BigInt.from(3000000)));
    expect(s.closeEffectiveAt, isNull);
  });

  test('top_up sends one transaction and reports its hash', () async {
    final s = await client.topUp(Amount.parse('0.5'));
    expect(port.calls, ['top_up']);
    expect(s.info.deposit, Amount.parse('1.5'));
    expect(s.lastTxHash, 'cd' * 32);
  });

  test('top_up refuses zero and non-open channels without sending', () async {
    await expectLater(
        client.topUp(Amount.zero), throwsA(isA<ChannelActionError>()));
    await client.closeStart();
    port.calls.clear();
    await expectLater(
        client.topUp(Amount.parse('0.1')), throwsA(isA<ChannelActionError>()));
    expect(port.calls, isEmpty);
  });

  test('close_start then refund follows the dispute window', () async {
    final c = await client.closeStart();
    expect(c.status, ChannelStatus.closing);
    expect(c.closeEffectiveAt, 1600);
    await expectLater(
      client.refund(Amount.zero),
      throwsA(isA<ChannelActionError>()
          .having((e) => e.code, 'code', 'not_expired')),
    );
    expect(port.calls, ['close_start'],
        reason: 'no refund tx while the window is open');
    clock = 1600;
    final r = await client.refund(Amount.zero);
    expect(r.status, ChannelStatus.refunded);
    expect(r.refunded, Amount.fromStroops(BigInt.from(7000000)));
    expect(r.lastTxHash, isNotNull);
  });

  test('refund before close_start and a second close_start are refused',
      () async {
    await expectLater(
      client.refund(Amount.zero),
      throwsA(isA<ChannelActionError>()
          .having((e) => e.code, 'code', 'not_closing')),
    );
    await client.closeStart();
    await expectLater(
      client.closeStart(),
      throwsA(isA<ChannelActionError>()
          .having((e) => e.code, 'code', 'already_closing')),
    );
  });

  test(
      'an applied transaction whose effect is not visible is reported, not faked',
      () async {
    port.dropWrites = true;
    await expectLater(client.closeStart(), throwsA(isA<SorobanFailure>()));
  });
}
