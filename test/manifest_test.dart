import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sideband_mobile/domain/manifest.dart';

void main() {
  final fx = jsonDecode(
          File('test/fixtures/session-transcript.json').readAsStringSync())
      as Map<String, dynamic>;
  final signed = (fx['manifest'] as Map).cast<String, Object?>();
  final provider = fx['providerPublicKey'] as String;
  final now = fx['now'] as int;

  Future<ManifestFailure?> check({
    Map<String, Object?>? m,
    int? at,
    String network = 'testnet',
    Set<String>? trusted,
    int? maxAge,
  }) async =>
      (await verifyManifest(
        m ?? signed,
        now: at ?? now,
        expectedNetwork: network,
        trustedProviderKeys: trusted ?? {provider},
        maxAgeSec: maxAge,
      ))
          .failure;

  test('accepts the gateway-signed manifest (TS-signed, verified in Dart)',
      () async {
    expect(await check(), isNull);
  });

  test('rejects stale, too-old and not-yet-valid manifests', () async {
    final exp = (signed['manifest'] as Map)['expiresAt'] as int;
    final iss = (signed['manifest'] as Map)['issuedAt'] as int;
    expect(await check(at: exp), ManifestFailure.staleManifest);
    expect(
        await check(at: iss + 100, maxAge: 50), ManifestFailure.staleManifest);
    expect(await check(at: iss - 1), ManifestFailure.notYetValid);
  });

  test('rejects wrong network and untrusted provider', () async {
    expect(await check(network: 'futurenet'), ManifestFailure.wrongNetwork);
    expect(await check(trusted: {'GOTHER'}), ManifestFailure.untrustedProvider);
  });

  test('rejects tampering and malformed input', () async {
    final tampered = {
      'manifest': {
        ...(signed['manifest'] as Map).cast<String, Object?>(),
        'pricePerUnit': '0.000001'
      },
      'signature': signed['signature'],
    };
    expect(await check(m: tampered), ManifestFailure.badSignature);
    expect(await check(m: {'manifest': signed['manifest'], 'signature': 'zz'}),
        ManifestFailure.malformed);
    expect(await check(m: {'nope': 1}), ManifestFailure.malformed);
  });
}
