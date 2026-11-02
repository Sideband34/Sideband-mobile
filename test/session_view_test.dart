import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sideband_mobile/domain/receipt.dart';
import 'package:sideband_mobile/features/session/session_view.dart';
import 'package:sideband_protocol/sideband_protocol.dart';

Receipt receipt(SettlementStatus s) => Receipt(
      sessionId: 's1',
      channelId: 'c',
      providerPublicKey: 'p',
      units: 4,
      committed: Amount.parse('0.004'),
      status: s,
      closeReason: 'client_close',
      channelExpiresAt: 5000,
    );

Future<void> pump(WidgetTester t, SettlementStatus s) => t.pumpWidget(
      MaterialApp(
          home: Scaffold(body: SessionView(receipt: receipt(s), now: 1000))),
    );

void main() {
  testWidgets(
      'offline commitment shows disclosure and refund hint, never "settled"',
      (t) async {
    await pump(t, SettlementStatus.committed);
    expect(find.textContaining('not settled'), findsOneWidget);
    expect(find.byKey(const Key('disclosure')), findsOneWidget);
    expect(find.byKey(const Key('refund')), findsOneWidget);
    expect(find.textContaining('Settled on Stellar'), findsNothing);
  });

  for (final s in [
    SettlementStatus.settlementSubmitted,
    SettlementStatus.reconciling,
    SettlementStatus.failed,
  ]) {
    testWidgets('$s is not presented as final', (t) async {
      await pump(t, s);
      expect(find.textContaining('Settled on Stellar'), findsNothing);
      expect(find.byKey(const Key('disclosure')), findsOneWidget);
    });
  }

  testWidgets('confirmed is the only state that says settled', (t) async {
    await pump(t, SettlementStatus.confirmed);
    expect(find.textContaining('Settled on Stellar: 0.004'), findsOneWidget);
    expect(find.byKey(const Key('disclosure')), findsNothing);
  });
}
