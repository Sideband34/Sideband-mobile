import 'package:flutter/material.dart';

import 'domain/receipt.dart';
import 'features/session/session_view.dart';
import 'package:sideband_protocol/sideband_protocol.dart';

void main() => runApp(const SidebandApp());

/// Shell only. Discovery (BLE/Wi-Fi), secure key storage and on-chain
/// settlement are NOT implemented; the screen below shows a clearly labeled
/// SYNTHETIC receipt so the financial-truth wording can be reviewed.
class SidebandApp extends StatelessWidget {
  const SidebandApp({super.key});

  @override
  Widget build(BuildContext context) {
    final demo = Receipt(
      sessionId: 'demo-synthetic',
      channelId: 'synthetic',
      providerPublicKey: 'synthetic',
      units: 4,
      committed: Amount.parse('0.004'),
      status: SettlementStatus.committed,
      closeReason: 'demo',
      channelExpiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
    );
    return MaterialApp(
      title: 'Sideband',
      theme: ThemeData(
          colorSchemeSeed: const Color(0xFFFF8B24),
          brightness: Brightness.dark),
      home: Scaffold(
        appBar:
            AppBar(title: const Text('Sideband (pre-release, synthetic data)')),
        body: SessionView(
            receipt: demo, now: DateTime.now().millisecondsSinceEpoch ~/ 1000),
      ),
    );
  }
}
