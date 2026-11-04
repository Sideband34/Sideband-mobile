// Cross-repo end-to-end: this Dart payer talks real HTTP to the real
// sideband-gateway (TypeScript, test channel adapter, loopback only).
// Skipped automatically when the gateway checkout/dependencies are absent.
// Set SIDEBAND_GATEWAY_DIR to override ../Sideband-gateway.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sideband_mobile/domain/payer_session.dart';
import 'package:sideband_mobile/domain/voucher.dart';
import 'package:sideband_mobile/integrations/durable_ledger.dart';
import 'package:sideband_mobile/integrations/history.dart';
import 'package:sideband_mobile/integrations/http_link.dart';
import 'package:sideband_mobile/integrations/secure_store.dart';
import 'package:sideband_mobile/integrations/session_runner.dart';
import 'package:sideband_protocol/sideband_protocol.dart';

final gatewayDir = Directory(
  Platform.environment['SIDEBAND_GATEWAY_DIR'] ?? '../Sideband-gateway',
);
final tsx = File('${gatewayDir.path}/node_modules/.bin/tsx');
final available = tsx.existsSync() &&
    Directory('${gatewayDir.path}/../Sideband-channels/dist').existsSync();

const adminToken = 'e2e-admin-token';

class RunningGateway {
  RunningGateway(this.process, this.port, this.providerKey, this.channelId);
  final Process process;
  final int port;
  final String providerKey;
  final String channelId;
  Uri get base => Uri.parse('http://127.0.0.1:$port');
}

Future<RunningGateway> startGateway(String payerKey) async {
  final probe = await ServerSocket.bind('127.0.0.1', 0);
  final port = probe.port;
  await probe.close();
  final p = await Process.start(
    // `node --import tsx` works on every OS; the .bin/tsx shim is a shell script that Windows cannot spawn.
    'node',
    ['--import', 'tsx', 'src/main.ts'],
    workingDirectory: gatewayDir.path,
    environment: {
      'PORT': '$port',
      'HOST': '127.0.0.1',
      'DB_PATH': ':memory:',
      'DEV_PAYER_PUBLIC_KEY': payerKey,
      'SESSION_SECRET': 'e2e-session-secret-0123456789abcdef',
      'ADMIN_TOKEN': adminToken,
      'PATH': Platform.environment['PATH'] ?? '',
    },
  );
  final lines = p.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();
  p.stderr.transform(utf8.decoder).listen((s) => stderr.write(s));
  String? provider;
  String? channel;
  final ready = Completer<void>();
  lines.listen((l) {
    final pk = RegExp(r'provider public key: (G\w+)').firstMatch(l);
    if (pk != null) {
      provider = pk.group(1);
    }
    final ch =
        RegExp(r'synthetic dev channel \(test adapter\): (C\w+)').firstMatch(l);
    if (ch != null) {
      channel = ch.group(1);
    }
    if (l.contains('sideband-gateway (TEST ADAPTER') && !ready.isCompleted) {
      ready.complete();
    }
  });
  await ready.future.timeout(const Duration(seconds: 30));
  await Future<void>.delayed(const Duration(milliseconds: 300));
  return RunningGateway(p, port, provider!, channel!);
}

void main() {
  group('Dart payer vs TypeScript gateway (real HTTP, test adapter)', () {
    late SeedSigner signer;
    late RunningGateway gw;
    // The payer device's durable state, shared by sequential sessions.
    final payerStore = InMemorySecureStore();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    setUpAll(() async {
      signer = await SeedSigner.fromSeed(Uint8List(32)..fillRange(0, 32, 22));
      gw = await startGateway(signer.publicKey);
    });
    tearDownAll(() async {
      gw.process.kill(ProcessSignal.sigterm);
      await gw.process.exitCode.timeout(const Duration(seconds: 10),
          onTimeout: () {
        gw.process.kill(ProcessSignal.sigkill);
        return -1;
      });
    });

    SessionRunner runner(HttpProviderLink link, InMemorySecureStore store,
        {String limit = '1'}) {
      var n = 0;
      return SessionRunner(
        link: link,
        channel: ChannelInfo(
          channelId: gw.channelId,
          networkName: 'testnet',
          networkPassphrase: testnetPassphrase,
          payer: signer.publicKey,
          provider: gw.providerKey,
          deposit: Amount.parse('10'),
          expiresAt: now + 3000,
        ),
        policy: PayerPolicy(
          expectedNetwork: 'testnet',
          expectedCurrency: 'TEST-TOKEN',
          maxPricePerUnit: Amount.parse('0.01'),
          trustedProviderKeys: {gw.providerKey},
        ),
        limits: SpendingLimits(perSession: Amount.parse(limit)),
        signer: signer,
        ledger: StoreBackedSignedLedger(store),
        history: HistoryRepository(store),
        now: () => DateTime.now().millisecondsSinceEpoch ~/ 1000,
        newNonce: () =>
            'e2e-nonce-${n++}-${DateTime.now().microsecondsSinceEpoch}',
      );
    }

    test(
        'full session: offer, accept, pay-on-402 with a Dart-signed voucher the gateway verifies, settle prep',
        () async {
      final link = HttpProviderLink(gw.base);
      final r = runner(link, payerStore);
      await r.start();
      final out = await r
          .use('hello brave new world'); // 4 words => 402 => voucher 0.004
      expect(out.output, 'HELLO BRAVE NEW WORLD');
      expect(out.cumulativeUnits, 4);
      final receipt = await r.finish();
      expect(receipt.committed, Amount.parse('0.004'));
      expect(receipt.isFinal, isFalse);

      // Provider-side view over the admin API: commitment accepted, NOT settled.
      final (s1, status) = await link.raw(
          'GET', '/v1/channels/${gw.channelId}/status',
          headers: {'x-admin-token': adminToken});
      expect(s1, 200);
      expect(status['highestVoucher'], '0.004');
      expect(status['onChainStatus'], 'open');
    });

    test('a second session reuses the channel with a v2 baseline', () async {
      final link = HttpProviderLink(gw.base);
      final r = runner(link, payerStore);
      await r.start();
      expect(r.session!.baseline, Amount.parse('0.004'));
      final out = await r.use('again please'); // 402 => voucher 0.006
      expect(out.cumulativeUnits, 2);
      final receipt = await r.finish();
      expect(receipt.committed, Amount.parse('0.002'));
      expect(receipt.channelCumulative, Amount.parse('0.006'));
    });

    test(
        'a payer device that never signed on the channel cannot start below the gateway baseline',
        () async {
      final link = HttpProviderLink(gw.base);
      // fresh payer store: it believes the channel is unused (baseline 0)
      final r = runner(link, InMemorySecureStore());
      await expectLater(
        r.start(),
        throwsA(predicate((e) =>
            e is SessionViolation && e.code == 'provider_baseline_ahead')),
      );
    });

    test(
        'gateway rejects calls without the session token and unknown admin access',
        () async {
      final link = HttpProviderLink(gw.base);
      final (s, j) = await link.raw('GET', '/v1/sessions/whatever/usage');
      expect(s, 401);
      expect((j['error'] as Map)['code'], 'unauthorized');
      final (s2, _) =
          await link.raw('GET', '/v1/channels/${gw.channelId}/status');
      expect(s2, 401);
    });

    test(
        'settlement preparation is a stateful intent; the synthetic adapter never confirms',
        () async {
      final link = HttpProviderLink(gw.base);
      // Settlement preparation: stateful intent, and the synthetic adapter can never confirm.
      final (s2, intent) = await link.raw(
          'POST', '/v1/channels/${gw.channelId}/settle',
          headers: {'x-admin-token': adminToken});
      expect(s2, 202);
      expect(intent['state'], 'SUBMITTED');
      expect(intent['kind'], 'settle'); // channel stays open for more sessions
      expect(intent['amount'], '0.006');
      expect(intent['txHash'], startsWith('synthetic:'));
      final (_, status) = await link.raw(
          'GET', '/v1/channels/${gw.channelId}/status',
          headers: {'x-admin-token': adminToken});
      expect(status['onChainStatus'], 'open');
      expect(status['withdrawn'], '0.006');
    });

    test('gateway manifest verifies in Dart', () async {
      final link = HttpProviderLink(gw.base);
      final (s, j) =
          await link.raw('GET', '/.well-known/sideband-service.json');
      expect(s, 200);
      expect((j['manifest'] as Map)['providerPublicKey'], gw.providerKey);
    });
  },
      skip:
          available ? false : 'gateway checkout or node_modules not available');
}
