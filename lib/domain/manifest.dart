import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sideband_protocol/sideband_protocol.dart';

import 'strkey.dart';

/// Payer-side verification of the provider-signed service manifest served at
/// `/.well-known/sideband-service.json` by sideband-gateway (TEST FORMAT:
/// ed25519 over "sideband/manifest/v1" 0x00 canonicalJson(manifest)).
enum ManifestFailure {
  untrustedProvider,
  wrongNetwork,
  badSignature,
  notYetValid,
  staleManifest,
  malformed,
}

class ManifestResult {
  const ManifestResult.ok() : failure = null;
  const ManifestResult.fail(ManifestFailure this.failure);
  final ManifestFailure? failure;
  bool get isOk => failure == null;
}

Future<ManifestResult> verifyManifest(
  Map<String, Object?> signed, {
  required int now,
  required String expectedNetwork,
  required Set<String> trustedProviderKeys,
  int? maxAgeSec,
}) async {
  final m = signed['manifest'];
  final sig = signed['signature'];
  if (m is! Map<String, Object?> ||
      sig is! String ||
      !RegExp(r'^[0-9a-f]{128}$').hasMatch(sig)) {
    return const ManifestResult.fail(ManifestFailure.malformed);
  }
  final key = m['providerPublicKey'];
  final network = m['network'];
  final issuedAt = m['issuedAt'];
  final expiresAt = m['expiresAt'];
  if (key is! String ||
      network is! String ||
      issuedAt is! int ||
      expiresAt is! int) {
    return const ManifestResult.fail(ManifestFailure.malformed);
  }
  if (!trustedProviderKeys.contains(key)) {
    return const ManifestResult.fail(ManifestFailure.untrustedProvider);
  }
  if (network != expectedNetwork) {
    return const ManifestResult.fail(ManifestFailure.wrongNetwork);
  }
  final Uint8List raw;
  try {
    raw = decodeEd25519PublicKey(key);
  } on StrKeyException {
    return const ManifestResult.fail(ManifestFailure.malformed);
  }
  final msg = Uint8List.fromList([
    ...ascii.encode('sideband/manifest/v1'),
    0,
    ...utf8.encode(canonicalJson(m)),
  ]);
  final sigBytes = List<int>.generate(
      64, (i) => int.parse(sig.substring(i * 2, i * 2 + 2), radix: 16));
  final ok = await Ed25519().verify(
    msg,
    signature: Signature(sigBytes,
        publicKey: SimplePublicKey(raw, type: KeyPairType.ed25519)),
  );
  if (!ok) {
    return const ManifestResult.fail(ManifestFailure.badSignature);
  }
  if (issuedAt > now) {
    return const ManifestResult.fail(ManifestFailure.notYetValid);
  }
  if (expiresAt <= now) {
    return const ManifestResult.fail(ManifestFailure.staleManifest);
  }
  if (maxAgeSec != null && now - issuedAt > maxAgeSec) {
    return const ManifestResult.fail(ManifestFailure.staleManifest);
  }
  return const ManifestResult.ok();
}
