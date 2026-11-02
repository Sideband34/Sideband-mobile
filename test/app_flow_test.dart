import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sideband_mobile/app/demo.dart';
import 'package:sideband_mobile/app/providers.dart';
import 'package:sideband_mobile/app/router.dart';
import 'package:sideband_mobile/domain/voucher.dart';

Map<String, dynamic> transcript() =>
    jsonDecode(File('test/fixtures/session-transcript.json').readAsStringSync())
        as Map<String, dynamic>;

Future<Widget> app({Map<String, dynamic>? t}) async {
  final signer = await SeedSigner.fromSeed(Uint8List(32)..fillRange(0, 32, 22));
  final router = buildRouter();
  return ProviderScope(
    overrides: [
      demoProvider.overrideWithValue(DemoEnvironment(t ?? transcript())),
      signerProvider.overrideWithValue(signer),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> nav(WidgetTester t, String label) async {
  await t.tap(find.descendant(
      of: find.byType(NavigationBar), matching: find.text(label)));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
      'banner is always visible and discover shows a verified synthetic provider',
      (t) async {
    await t.pumpWidget(await app());
    await t.pumpAndSettle();
    expect(find.byKey(const Key('banner')), findsOneWidget);
    expect(find.textContaining('Provider verified'), findsOneWidget);
    expect(find.textContaining('Demo mode'), findsOneWidget);
  });

  testWidgets(
      'a stale manifest is shown as NOT trusted and cannot be connected',
      (t) async {
    final j = transcript();
    j['now'] = (j['now'] as int) + 1000000;
    await t.pumpWidget(await app(t: j));
    await t.pumpAndSettle();
    expect(find.textContaining('NOT trusted'), findsOneWidget);
    expect(find.textContaining('stale'), findsOneWidget);
    final btn = t.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets(
      'connect, use the service (pay on demand), end, then see an honest receipt and history',
      (t) async {
    await t.pumpWidget(await app());
    await t.pumpAndSettle();
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('stage')), findsOneWidget);
    expect(find.textContaining('Session active'), findsOneWidget);

    await t.tap(find.byKey(const Key('use-button')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('output')), findsOneWidget);
    expect(find.textContaining('HELLO BRAVE NEW WORLD'), findsOneWidget);
    expect(find.textContaining('0.004'), findsWidgets);
    expect(find.textContaining('signed, not settled'), findsOneWidget);

    await t.tap(find.byKey(const Key('finish-button')));
    await t.pumpAndSettle();
    expect(find.textContaining('Session closed'), findsOneWidget);
    expect(find.byKey(const Key('disclosure')), findsOneWidget);
    expect(find.textContaining('Settled on Stellar'), findsNothing);

    await nav(t, 'History');
    expect(find.textContaining('4 units'), findsOneWidget);
    await t.tap(find.textContaining('4 units'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('status')), findsOneWidget);
    expect(find.textContaining('not settled'), findsWidgets);
  });

  testWidgets(
      'spending limit: invalid input is rejected; a low limit stops the session',
      (t) async {
    await t.pumpWidget(await app());
    await t.pumpAndSettle();
    await nav(t, 'Limit');
    await t.enterText(find.byKey(const Key('limit-field')), '-3');
    await t.tap(find.text('Save limit'));
    await t.pumpAndSettle();
    expect(find.textContaining('Invalid amount'), findsOneWidget);
    expect(find.textContaining('Current: 0.05'), findsOneWidget);

    await t.enterText(find.byKey(const Key('limit-field')), '0.002');
    await t.tap(find.text('Save limit'));
    await t.pumpAndSettle();
    expect(find.textContaining('Current: 0.002'), findsOneWidget);

    await nav(t, 'Discover');
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('use-button'))); // 4 words = 0.004 > 0.002
    await t.pumpAndSettle();
    expect(find.byKey(const Key('error')), findsOneWidget);
    expect(find.textContaining('Spending limit reached'), findsOneWidget);
    expect(find.textContaining('Session closed'), findsOneWidget);
  });

  testWidgets('empty states: no session and no history', (t) async {
    await t.pumpWidget(await app());
    await t.pumpAndSettle();
    await nav(t, 'Session');
    expect(find.textContaining('No active session'), findsOneWidget);
    await nav(t, 'History');
    expect(find.text('No sessions yet'), findsOneWidget);
  });
}
