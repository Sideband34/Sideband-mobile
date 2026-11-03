import 'package:sideband_protocol/sideband_protocol.dart';

/// Result of one metered service call.
class ServeResult {
  const ServeResult(
      {required this.output,
      required this.units,
      required this.cumulativeUnits});
  final String output;
  final int units;
  final int cumulativeUnits;
}

/// The provider refused unpaid work and told us the cumulative amount it needs.
class PaymentRequired implements Exception {
  PaymentRequired({required this.required, required this.current});
  final Amount required;
  final Amount current;
  @override
  String toString() => 'PaymentRequired: need $required, have $current';
}

/// The provider rejected a request with a stable machine-readable [code].
class ProviderRejected implements Exception {
  ProviderRejected(this.code, this.message, {this.details = const {}});
  final String code;
  final String message;

  /// Extra machine-readable fields from the provider (e.g. `expectedBaseline`).
  final Map<String, Object?> details;
  @override
  String toString() => 'ProviderRejected($code): $message';
}

/// Local transport to ONE provider (BLE / local Wi-Fi in production, which is
/// not implemented). Adapters move frames; they never sign payments.
abstract interface class ProviderLink {
  Future<ServiceOffer> requestOffer();
  Future<void> accept(SessionAccept a);
  Future<void> sendVoucher(VoucherFrame v);
  Future<ServeResult> serve(String text);
  Future<void> close();
}

/// A link that can re-attach to the SAME provider session after the payer app
/// restarts (crash resume). [resumeState] is journaled (it may hold a session
/// bearer token, so it goes to the secure store) and handed to [reattach].
abstract interface class ResumableLink implements ProviderLink {
  Map<String, String> get resumeState;

  /// Re-binds to the journaled session. Throws [ProviderRejected] if the
  /// provider no longer has it active.
  Future<void> reattach(Map<String, String> state);
}

/// A provider found by discovery, with its signed manifest (unverified until
/// the payer checks it against its trust policy).
class DiscoveredService {
  const DiscoveredService({required this.signedManifest, required this.open});
  final Map<String, Object?> signedManifest;

  /// Opens a link to this provider.
  final ProviderLink Function() open;

  Map<String, Object?> get manifest =>
      (signedManifest['manifest'] as Map).cast<String, Object?>();
}

abstract interface class Discovery {
  Future<List<DiscoveredService>> scan();
}
