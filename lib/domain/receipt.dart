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
  Receipt({
    required this.sessionId,
    required this.channelId,
    required this.providerPublicKey,
    required this.units,
    required this.committed,
    Amount? baseline,
    required this.status,
    required this.closeReason,
    required this.channelExpiresAt,
  }) : baseline = baseline ?? Amount.zero;

  final String sessionId;
  final String channelId;
  final String providerPublicKey;
  final int units;

  /// Amount the payer committed in THIS session (signed channel cumulative
  /// minus [baseline]). A commitment, not a payment.
  final Amount committed;

  /// Channel cumulative already signed before this session.
  final Amount baseline;

  /// Channel cumulative at the end of this session (what the provider can
  /// settle on-chain, together with earlier sessions).
  Amount get channelCumulative => baseline + committed;
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
        baseline: baseline,
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

  /// How the payer gets unspent funds back if the provider never settles: a
  /// payer close (close_start) opens a dispute window that never ends before
  /// the channel expiry; then the remainder is refundable.
  String refundHint(int now) => now >= channelExpiresAt
      ? 'If the provider never settles: start a close from Channel; refund after the dispute window'
      : 'If the provider never settles: start a close from Channel; refund no earlier than in ${channelExpiresAt - now}s';
}
