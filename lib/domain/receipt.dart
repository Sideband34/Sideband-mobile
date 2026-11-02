import 'package:sideband_protocol/sideband_protocol.dart';

/// Lifecycle of a payment as the payer may truthfully describe it. Only
/// [confirmed] may ever be presented as settled/final.
enum SettlementStatus {
  committed,
  settlementSubmitted,
  reconciling,
  confirmed,
  failed
}

class Receipt {
  const Receipt({
    required this.sessionId,
    required this.channelId,
    required this.providerPublicKey,
    required this.units,
    required this.committed,
    required this.status,
    required this.closeReason,
    required this.channelExpiresAt,
  });

  final String sessionId;
  final String channelId;
  final String providerPublicKey;
  final int units;

  /// Highest cumulative amount the payer signed. A commitment, not a payment.
  final Amount committed;
  final SettlementStatus status;
  final String closeReason;

  /// Unix seconds after which the payer can reclaim an unsettled deposit.
  final int channelExpiresAt;

  bool get isFinal => status == SettlementStatus.confirmed;

  Receipt withStatus(SettlementStatus s) => Receipt(
        sessionId: sessionId,
        channelId: channelId,
        providerPublicKey: providerPublicKey,
        units: units,
        committed: committed,
        status: s,
        closeReason: closeReason,
        channelExpiresAt: channelExpiresAt,
      );

  /// User-facing wording. Never says "paid"/"settled" before confirmation.
  String get statusLabel => switch (status) {
        SettlementStatus.committed => 'Committed $committed (not settled)',
        SettlementStatus.settlementSubmitted =>
          'Settlement submitted, awaiting confirmation',
        SettlementStatus.reconciling => 'Checking settlement outcome',
        SettlementStatus.confirmed => 'Settled on Stellar: $committed',
        SettlementStatus.failed =>
          'Settlement failed; deposit may be refundable after expiry',
      };

  /// When the deposit becomes refundable if the provider never settles.
  String refundHint(int now) => now >= channelExpiresAt
      ? 'Refund available now if the channel is unsettled'
      : 'Refund available in ${channelExpiresAt - now}s if the provider never settles';
}
