import 'package:sideband_protocol/sideband_protocol.dart';

import 'payer_session.dart';

/// Mirrors the Soroban channel lifecycle (Sideband-channels ADR 0002).
/// `closing`: the payer started a close; the provider may still settle its
/// highest voucher until [ChannelState.closeEffectiveAt]. `closed` and
/// `refunded` are terminal.
enum ChannelStatus { open, closing, closed, refunded }

/// The payer's view of its funded channel.
class ChannelState {
  const ChannelState({
    required this.info,
    required this.status,
    required this.closeWait,
    this.withdrawn,
    this.closeEffectiveAt,
    this.refunded,
    required this.synthetic,
  });

  /// Static binding; `info.deposit` is the total deposit after top-ups.
  final ChannelInfo info;
  final ChannelStatus status;

  /// Dispute window in seconds.
  final int closeWait;

  /// Amount the provider has withdrawn on-chain, when known. Null means "not
  /// observed": offline, or a simulated channel that has no chain to watch.
  final Amount? withdrawn;
  final int? closeEffectiveAt;
  final Amount? refunded;

  /// True for the in-app simulation (no Stellar transaction is ever sent).
  final bool synthetic;

  bool get isTerminal =>
      status == ChannelStatus.closed || status == ChannelStatus.refunded;

  /// Seconds until a refund is possible, or null if not closing.
  int? refundIn(int now) {
    final at = closeEffectiveAt;
    if (status != ChannelStatus.closing || at == null) return null;
    return at > now ? at - now : 0;
  }

  ChannelState copyWith({
    Amount? deposit,
    ChannelStatus? status,
    int? closeEffectiveAt,
    Amount? refunded,
  }) =>
      ChannelState(
        info: deposit == null
            ? info
            : ChannelInfo(
                channelId: info.channelId,
                networkName: info.networkName,
                networkPassphrase: info.networkPassphrase,
                payer: info.payer,
                provider: info.provider,
                deposit: deposit,
                expiresAt: info.expiresAt,
              ),
        status: status ?? this.status,
        closeWait: closeWait,
        withdrawn: withdrawn,
        closeEffectiveAt: closeEffectiveAt ?? this.closeEffectiveAt,
        refunded: refunded ?? this.refunded,
        synthetic: synthetic,
      );
}

class ChannelActionError implements Exception {
  ChannelActionError(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}
