import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/demo.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'domain/voucher.dart';

/// Shell only. Discovery over BLE/Wi-Fi, a keychain-backed signer/store and
/// on-chain settlement are NOT implemented. The app runs against a SYNTHETIC
/// in-memory provider built from the gateway fixture, with a test-only signer
/// seeded from public test data. Never put real keys here.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final demo = DemoEnvironment.fromJson(
      await rootBundle.loadString('assets/demo/session-transcript.json'));
  final signer = await SeedSigner.fromSeed(Uint8List(32)..fillRange(0, 32, 22));
  runApp(ProviderScope(
    overrides: [
      demoProvider.overrideWithValue(demo),
      signerProvider.overrideWithValue(signer)
    ],
    child: const SidebandApp(),
  ));
}

class SidebandApp extends StatefulWidget {
  const SidebandApp({super.key});
  @override
  State<SidebandApp> createState() => _SidebandAppState();
}

class _SidebandAppState extends State<SidebandApp> {
  final _router = buildRouter();

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Sideband',
        routerConfig: _router,
        theme: ThemeData(
            colorSchemeSeed: const Color(0xFFFF8B24),
            brightness: Brightness.dark),
      );
}
