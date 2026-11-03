import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sideband_mobile/app/demo.dart';
import 'package:sideband_mobile/app/providers.dart';
import 'package:sideband_mobile/app/router.dart';
import 'package:sideband_mobile/domain/channel_state.dart';
import 'package:sideband_mobile/domain/payer_session.dart';
import 'package:sideband_mobile/domain/voucher.dart';
import 'package:sideband_mobile/integrations/channel_client.dart';
import 'package:sideband_mobile/integrations/secure_store.dart';
import 'package:sideband_protocol/sideband_protocol.dart';

void main() {
  ChannelInfo info({int expiresAt = 5000}) => ChannelInfo(
        channelId: 'CHAN',
        networkName: 'testnet',
        networkPassphrase: testnetPassphrase,
        payer: 'GPAYER',
        provider: 'GPROV',
        deposit: Amount.parse('2'),
        expiresAt: expiresAt,
      );

  group('SimulatedChannelClient (mirrors contracts/channel rules)', () {
    late InMemorySecureStore store;
    late int clock;
    SimulatedChannelClient client({int expiresAt = 5000}) =>
        SimulatedChannelClient(
            initial: info(expiresAt: expiresAt),
            store: store,
            now: () => clock,
            closeWait: 600);
    setUp(() {
      store = InMemorySecureStore();
      clock = 1000;
    });

    test('top-up raises the deposit and persists; every state is synthetic',
        () async {
      final c = client();
      final s = await c.topUp(Amount.parse('0.5'));
      expect(s.info.deposit, Amount.parse('2.5'));
      expect(s.synthetic, isTrue);
      expect((await client().status()).info.deposit, Amount.parse('2.5'));
      await expectLater(
          c.topUp(Amount.zero), throwsA(isA<ChannelActionError>()));
    });

    test('close_start window never ends before expiry; refund only after it',
        () async {
      final c = client();
      await expectLater(
          c.refund(Amount.zero),
          throwsA(predicate(
              (e) => e is ChannelActionError && e.code == 'not_closing')));
      final s = await c.closeStart();
      expect(s.status, ChannelStatus.closing);
      expect(s.closeEffectiveAt, 5000); // 1000 + 600 < expiry
      await expectLater(
          c.closeStart(),
          throwsA(predicate(
              (e) => e is ChannelActionError && e.code == 'already_closing')));
      await expectLater(
          c.topUp(Amount.parse('1')),
          throwsA(predicate(
              (e) => e is ChannelActionError && e.code == 'not_open')));
      clock = 4999;
      await expectLater(
          c.refund(Amount.zero),
          throwsA(predicate(
              (e) => e is ChannelActionError && e.code == 'not_expired')));
      clock = 5000;
      final r = await c.refund(Amount.parse('0.4'));
      expect(r.status, ChannelStatus.refunded);
      expect(r.refunded, Amount.parse('1.6')); // deposit minus signed
      await expectLater(c.closeStart(), throwsA(isA<ChannelActionError>()));
      await expectLater(
          c.refund(Amount.zero), throwsA(isA<ChannelActionError>()));
    });

    test('late in the channel life the wait itself sets the window', () async {
      clock = 4800;
      final s = await client().closeStart();
      expect(s.closeEffectiveAt, 5400);
      expect(s.refundIn(5000), 400);
      expect(s.refundIn(6000), 0);
    });
  });

  group('Channel screen', () {
    Future<(Widget, ProviderContainer)> app() async {
      final t = jsonDecode(
              File('test/fixtures/session-transcript.json').readAsStringSync())
          as Map<String, dynamic>;
      final signer =
          await SeedSigner.fromSeed(Uint8List(32)..fillRange(0, 32, 22));
      final c = ProviderContainer(overrides: [
        demoProvider.overrideWithValue(DemoEnvironment(t)),
        signerProvider.overrideWithValue(signer),
      ]);
      return (
        UncontrolledProviderScope(
            container: c,
            child: MaterialApp.router(routerConfig: buildRouter())),
        c
      );
    }

    Future<void> nav(WidgetTester t, String label) async {
      await t.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text(label)));
      await t.pumpAndSettle();
    }

    testWidgets('top up, start close, and new sessions are then refused',
        (t) async {
      final (w, c) = await app();
      await t.pumpWidget(w);
      await t.pumpAndSettle();
      await nav(t, 'Channel');
      expect(find.text('Simulated'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      await t.enterText(find.byKey(const Key('topup-field')), '2.5');
      await t.tap(find.byKey(const Key('topup-button')));
      await t.pumpAndSettle();
      expect(
          c.read(channelControllerProvider).info.deposit, Amount.parse('12.5'));
      expect(find.textContaining('Not yet committed: 12.5'), findsOneWidget);

      await t.tap(find.byKey(const Key('close-start-button')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirm-close')));
      await t.pumpAndSettle();
      expect(find.textContaining('Closing - dispute window'), findsOneWidget);
      final refund =
          t.widget<FilledButton>(find.byKey(const Key('refund-button')));
      expect(refund.onPressed, isNull); // window still open

      // Discover -> connect is refused on a closing channel.
      await nav(t, 'Discover');
      await t.tap(find.byType(FilledButton).first);
      await t.pumpAndSettle();
      expect(find.textContaining('channel_closing'), findsOneWidget);
      c.dispose();
    });

    testWidgets('an invalid top-up amount shows an error', (t) async {
      final (w, c) = await app();
      await t.pumpWidget(w);
      await t.pumpAndSettle();
      await nav(t, 'Channel');
      await t.enterText(find.byKey(const Key('topup-field')), '0');
      await t.tap(find.byKey(const Key('topup-button')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('channel-error')), findsOneWidget);
      c.dispose();
    });
  });
}
