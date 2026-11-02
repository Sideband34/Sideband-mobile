// Renders key screens to PNG for docs/screenshots. Skipped unless
// SIDEBAND_SCREENSHOTS=1, so normal `flutter test` runs never write files:
//
//   SIDEBAND_SCREENSHOTS=1 flutter test test/screenshots_test.dart
//
// These are widget-test renders on the SYNTHETIC demo provider (Roboto loaded
// from the Flutter SDK), not captures from a physical device.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sideband_mobile/app/demo.dart';
import 'package:sideband_mobile/app/providers.dart';
import 'package:sideband_mobile/app/router.dart';
import 'package:sideband_mobile/design_system/theme.dart';
import 'package:sideband_mobile/domain/voucher.dart';

import 'app_flow_test.dart' show transcript;

final _enabled = Platform.environment['SIDEBAND_SCREENSHOTS'] == '1';

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> f(String n) async =>
      ByteData.sublistView(await File('$dir/$n').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold', 'Black']) {
    roboto.addFont(f('Roboto-$w.ttf'));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(f('MaterialIcons-Regular.otf')))
      .load();
}

Future<void> _shot(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('docs/screenshots/$name.png');
    await out.parent.create(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('screens ($mode)', skip: !_enabled, (t) async {
      await t.runAsync(_loadFonts);
      t.view.physicalSize = const Size(390 * 2, 844 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);

      final signer =
          await SeedSigner.fromSeed(Uint8List(32)..fillRange(0, 32, 22));
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: ProviderScope(
          overrides: [
            demoProvider.overrideWithValue(DemoEnvironment(transcript())),
            signerProvider.overrideWithValue(signer),
          ],
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: sidebandTheme(Brightness.light),
            darkTheme: sidebandTheme(Brightness.dark),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            routerConfig: buildRouter(),
          ),
        ),
      ));
      await t.runAsync(() => precacheImage(
          const AssetImage('brand/icon-192.png'),
          t.element(find.byType(Scaffold).first)));
      await t.pumpAndSettle();
      await _shot(t, key, 'mobile-discover-$mode');

      await t.tap(find.text('Connect'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('use-button')));
      await t.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await _shot(t, key, 'mobile-session-$mode');

      await t.tap(find.byKey(const Key('finish-button')));
      await t.pumpAndSettle();
      await t.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text('History')));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('4 units'));
      await t.pumpAndSettle();
      await _shot(t, key, 'mobile-receipt-$mode');

      await t.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text('Limit')));
      await t.pumpAndSettle();
      await _shot(t, key, 'mobile-limit-$mode');
    });
  }
}
