// LIVE test against a Testnet channel. Skipped unless these are set (never commit values):
//   SIDEBAND_LIVE_CHANNEL_ID  the channel contract id (C...)
//   SIDEBAND_LIVE_SEED_B64    base64 of the payer's 32-byte ed25519 seed (the device key)
// Run:  flutter test test/live/soroban_live_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sideband_mobile/domain/channel_state.dart';
import 'package:sideband_mobile/domain/payer_session.dart';
import 'package:sideband_mobile/integrations/secure_store.dart';
import 'package:sideband_mobile/integrations/soroban_channel_client.dart';
import 'package:sideband_mobile/integrations/stored_key_signer.dart';
import 'package:sideband_protocol/sideband_protocol.dart';

void main() {
  final id = Platform.environment['SIDEBAND_LIVE_CHANNEL_ID'];
  final seed = Platform.environment['SIDEBAND_LIVE_SEED_B64'];
  final skip = (id == null || seed == null)
      ? 'set SIDEBAND_LIVE_CHANNEL_ID and SIDEBAND_LIVE_SEED_B64'
      : false;

  test('reads the real channel and tops it up with a real transaction',
      () async {
    final store = InMemorySecureStore();
    await store.write(StoredKeySigner.seedKey, seed!);
    final port = await StellarSorobanPort.open(store: store, channelId: id!);
    final before = await port.readChannel();
    final info = ChannelInfo(
      channelId: id,
      networkName: 'testnet',
      networkPassphrase: 'Test SDF Network ; September 2015',
      payer: before.payer,
      provider: before.provider,
      deposit: Amount.fromStroops(before.deposit),
      expiresAt: before.expiresAt,
    );
    final client = SorobanChannelClient(
      info: info,
      port: port,
      now: () => DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    final s0 = await client.status();
    expect(s0.synthetic, isFalse);
    expect(s0.status, ChannelStatus.open);
    final s1 = await client.topUp(Amount.parse('0.1'));
    expect(s1.info.deposit, s0.info.deposit + Amount.parse('0.1'));
    expect(s1.lastTxHash, matches(RegExp(r'^[0-9a-f]{64}$')));
    // ignore: avoid_print
    print('LIVE top_up tx ${s1.lastTxHash} deposit ${s1.info.deposit}');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 4)));
}
