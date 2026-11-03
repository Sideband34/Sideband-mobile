import 'dart:convert';

import 'package:sideband_protocol/sideband_protocol.dart';

import '../domain/manifest.dart';
import '../domain/payer_session.dart';
import '../domain/voucher.dart';
import '../integrations/loopback_provider.dart';
import '../integrations/provider_link.dart';

/// Demo wiring: a SYNTHETIC provider backed by the gateway's fixture
/// transcript. The clock is frozen at the fixture's time so its signed
/// manifest verifies. Nothing here touches a network or real funds.
class DemoEnvironment implements Discovery {
  /// [payerKey] overrides the fixture payer, e.g. with the device key from
  /// `StoredKeySigner`, so the synthetic channel is bound to this device.
  DemoEnvironment(Map<String, dynamic> transcript, {String? payerKey})
      : signedManifest =
            (transcript['manifest'] as Map).cast<String, Object?>(),
        now = transcript['now'] as int,
        providerKey = transcript['providerPublicKey'] as String,
        payerKey = payerKey ?? transcript['payerPublicKey'] as String,
        channelId = transcript['channelId'] as String;

  factory DemoEnvironment.fromJson(String json, {String? payerKey}) =>
      DemoEnvironment(jsonDecode(json) as Map<String, dynamic>,
          payerKey: payerKey);

  final Map<String, Object?> signedManifest;
  final int now;
  final String providerKey;
  final String payerKey;
  final String channelId;

  int clock() => now;

  ChannelInfo get channel => ChannelInfo(
        channelId: channelId,
        networkName: 'testnet',
        networkPassphrase: testnetPassphrase,
        payer: payerKey,
        provider: providerKey,
        deposit: Amount.parse('10'),
        expiresAt: now + 3600,
      );

  PayerPolicy get policy => PayerPolicy(
        expectedNetwork: 'testnet',
        expectedCurrency: 'TEST-TOKEN',
        maxPricePerUnit: Amount.parse('0.01'),
        trustedProviderKeys: {providerKey},
      );

  /// The synthetic provider's channel records, shared by its sessions.
  final SyntheticChannelBook book = SyntheticChannelBook();

  ProviderLink openLink() => LoopbackProvider(
        domain: channel.domain,
        network: 'testnet',
        now: clock,
        sessionId: 'demo-${DateTime.now().microsecondsSinceEpoch}',
        book: book,
      );

  @override
  Future<List<DiscoveredService>> scan() async => [
        DiscoveredService(signedManifest: signedManifest, open: openLink),
      ];

  Future<ManifestResult> verify(DiscoveredService s) => verifyManifest(
        s.signedManifest,
        now: now,
        expectedNetwork: 'testnet',
        trustedProviderKeys: {providerKey},
      );
}
