import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/demo.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'design_system/theme.dart';
import 'integrations/file_store.dart';
import 'integrations/flutter_secure_store.dart';
import 'integrations/stored_key_signer.dart';

/// The app runs against a SYNTHETIC in-memory provider built from the gateway
/// fixture and a SIMULATED channel (no Stellar transactions). What is real:
/// the voucher signer's key is generated on the device and kept in the
/// platform keychain/keystore, the signed-amount ledger and session journal
/// live there too, and receipt history is persisted to an atomic file. BLE /
/// Wi-Fi transports exist as adapters but are not wired in (untested on
/// hardware).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final secure = FlutterSecureStore();
  final signer = await StoredKeySigner.loadOrCreate(secure);
  final appData = AtomicFileStore(await getApplicationSupportDirectory());
  final demo = DemoEnvironment.fromJson(
      await rootBundle.loadString('assets/demo/session-transcript.json'),
      payerKey: signer.publicKey);
  final container = ProviderContainer(overrides: [
    demoProvider.overrideWithValue(demo),
    signerProvider.overrideWithValue(signer),
    secureStoreProvider.overrideWithValue(secure),
    appDataStoreProvider.overrideWithValue(appData),
  ]);
  await container.read(channelControllerProvider.notifier).refresh();
  // Re-attach to a session that was active when the app was killed.
  await container
      .read(sessionControllerProvider.notifier)
      .resume(demo.openLink());
  runApp(UncontrolledProviderScope(
      container: container, child: const SidebandApp()));
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
        debugShowCheckedModeBanner: false,
        theme: sidebandTheme(Brightness.light),
        darkTheme: sidebandTheme(Brightness.dark),
        themeMode: ThemeMode.system,
      );
}
