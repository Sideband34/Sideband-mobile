import 'package:sideband_protocol/sideband_protocol.dart';

import '../domain/payer_session.dart';
import '../domain/receipt.dart';
import '../domain/signed_ledger.dart';
import '../domain/voucher.dart';
import 'history.dart';
import 'provider_link.dart';

/// Drives one payer session against any [ProviderLink]: offer -> accept ->
/// serve, paying only when the provider asks (402) and always through
/// [PayerSession]'s spend caps and monotonic signing.
class SessionRunner {
  SessionRunner({
    required this.link,
    required this.channel,
    required this.policy,
    required this.limits,
    required this.signer,
    required this.ledger,
    required this.history,
    required this.now,
    required this.newNonce,
  });

  final ProviderLink link;
  final ChannelInfo channel;
  final PayerPolicy policy;
  final SpendingLimits limits;
  final VoucherSigner signer;
  final SignedLedger ledger;
  final HistoryRepository history;
  final int Function() now;
  final String Function() newNonce;

  PayerSession? session;
  String? lastError;

  PayerSession get _s => session ?? (throw StateError('Session not started'));

  Future<void> start() async {
    final offer = await link.requestOffer();
    final s = PayerSession(
      sessionId: offer.session,
      channel: channel,
      policy: policy,
      limits: limits,
      signer: signer,
      ledger: ledger,
      now: now,
    );
    s.receiveOffer(offer);
    // Cumulative amounts are per channel: a channel that already carries signed
    // commitments cannot back a new session (providers refuse it too).
    if (await ledger.highest(channel.channelId) > BigInt.zero) {
      s.close('channel_used');
      session = s;
      await _record(s);
      throw SessionViolation(
          'channel_used', 'Channel already carries commitments');
    }
    final accept = s.buildAccept(nonce: newNonce());
    session = s;
    try {
      await link.accept(accept);
    } catch (e) {
      s.close('accept_rejected');
      await _record(s);
      rethrow;
    }
    await _record(s);
  }

  /// Uses the service once; pays and retries once if the provider demands it.
  Future<ServeResult> use(String text) async {
    final s = _s;
    try {
      try {
        final r = await link.serve(text);
        await _record(s, units: r.cumulativeUnits);
        return r;
      } on PaymentRequired catch (p) {
        final v = await s.onPaymentRequired(p.required);
        if (v != null) await link.sendVoucher(v);
        final r = await link.serve(text);
        await _record(s, units: r.cumulativeUnits);
        return r;
      }
    } on BudgetExceeded catch (e) {
      lastError = 'Budget reached: $e';
      await _record(s);
      rethrow;
    } on ProviderRejected catch (e) {
      lastError = '${e.code}: ${e.message}';
      if (e.code == 'shutting_down') s.close('provider_shutdown');
      await _record(s);
      rethrow;
    }
  }

  Future<Receipt> finish() async {
    final s = _s;
    s.close(s.phase == SessionPhase.closed ? 'closed' : 'client_close');
    await link.close();
    return _record(s);
  }

  Future<Receipt> _record(PayerSession s, {int? units}) async {
    var r = await s.receipt();
    final prior = await history.byId(s.sessionId);
    if (units != null || prior != null) {
      r = Receipt(
        sessionId: r.sessionId,
        channelId: r.channelId,
        providerPublicKey: r.providerPublicKey,
        units: units ?? prior?.units ?? r.units,
        committed: r.committed,
        status: r.status,
        closeReason: r.closeReason,
        channelExpiresAt: r.channelExpiresAt,
      );
    }
    await history.upsert(r);
    return r;
  }
}
