import 'package:sideband_protocol/sideband_protocol.dart';

import '../domain/payer_session.dart';
import '../domain/receipt.dart';
import '../domain/signed_ledger.dart';
import '../domain/voucher.dart';
import 'history.dart';
import 'provider_link.dart';
import 'session_journal.dart';

/// The provider's record of this channel is BELOW what this payer signed: a
/// voucher was signed (ledger advanced) but never delivered, typically after a
/// crash once the provider session was gone. Starting a new session means the
/// first voucher also pays [gap]. The payer must decide; nothing is signed.
class BaselineGap implements Exception {
  BaselineGap({required this.providerBaseline, required this.signed});
  final Amount providerBaseline;
  final Amount signed;
  Amount get gap => signed - providerBaseline;
  @override
  String toString() =>
      'BaselineGap: provider has $providerBaseline, payer signed $signed';
}

/// Outcome of [SessionRunner.resume].
enum ResumeOutcome {
  /// No journaled session.
  none,

  /// Re-attached to the same provider session; any pending voucher delivered.
  resumed,

  /// The provider session is gone; the receipt is closed as `interrupted`.
  interrupted,
}

/// Drives one payer session against any [ProviderLink]: offer -> accept ->
/// serve, paying only when the provider asks (402) and always through
/// [PayerSession]'s spend caps and monotonic signing. Several sequential
/// sessions can use one channel (protocol v2 baseline). With a [journal], an
/// active session survives an app restart ([resume]).
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
    this.journal,
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
  final SessionJournal? journal;

  PayerSession? session;
  String? lastError;
  JournalEntry? _entry;

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
    // Vouchers are cumulative per channel: this session starts where our last
    // signature on the channel ended (protocol v2 baseline).
    final signed = Amount.fromStroops(await ledger.highest(channel.channelId));
    final SessionAccept accept;
    try {
      accept = s.buildAccept(nonce: newNonce(), baseline: signed);
    } on SessionViolation {
      s.close('channel_exhausted');
      session = s;
      await _record(s);
      rethrow;
    }
    session = s;
    try {
      await link.accept(accept);
    } on ProviderRejected catch (e) {
      s.close('accept_rejected');
      await _record(s);
      if (e.code == 'baseline_mismatch') throw _baselineError(e, signed);
      rethrow;
    } catch (_) {
      s.close('accept_rejected');
      await _record(s);
      rethrow;
    }
    await _record(s);
    final j = journal;
    if (j != null) {
      _entry = JournalEntry(
        offer: offer,
        accept: accept,
        acceptedAt: now(),
        units: 0,
        linkState: link is ResumableLink
            ? (link as ResumableLink).resumeState
            : const {},
      );
      await j.save(_entry!);
    }
  }

  Exception _baselineError(ProviderRejected e, Amount signed) {
    final raw = e.details['expectedBaseline'];
    final Amount provider;
    try {
      provider = Amount.parse(raw as String);
    } on Object {
      return e;
    }
    if (provider < signed) {
      return BaselineGap(providerBaseline: provider, signed: signed);
    }
    // The provider claims more than this payer ever signed on the channel:
    // never sign to "catch up" with it.
    return SessionViolation('provider_baseline_ahead',
        'Provider claims $provider committed; this payer signed $signed');
  }

  /// Uses the service once; pays and retries once if the provider demands it.
  Future<ServeResult> use(String text) async {
    final s = _s;
    try {
      try {
        final r = await link.serve(text);
        await _served(s, r);
        return r;
      } on PaymentRequired catch (p) {
        final v = await s.onPaymentRequired(p.required);
        if (v != null) await _deliver(v);
        final r = await link.serve(text);
        await _served(s, r);
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

  /// Journals the signed voucher BEFORE sending, so a crash between signing
  /// and delivery can be resumed by re-sending the identical bytes.
  Future<void> _deliver(VoucherFrame v) async {
    await _journal((e) => e.copyWith(pendingVoucher: v));
    await link.sendVoucher(v);
    await _journal((e) => e.copyWith(clearPending: true));
  }

  Future<void> _served(PayerSession s, ServeResult r) async {
    s.recordUnits(r.cumulativeUnits);
    await _record(s, units: r.cumulativeUnits);
    await _journal((e) => e.copyWith(units: r.cumulativeUnits));
  }

  Future<void> _journal(JournalEntry Function(JournalEntry) f) async {
    final j = journal, e = _entry;
    if (j == null || e == null) return;
    _entry = f(e);
    await j.save(_entry!);
  }

  /// Re-attaches to a session journaled before an app restart. The pending
  /// voucher (if any) is re-sent byte-for-byte: it is the same commitment the
  /// ledger already recorded, not a new signature.
  Future<ResumeOutcome> resume() async {
    final j = journal;
    final e = j == null ? null : await j.load();
    if (j == null || e == null) return ResumeOutcome.none;
    final s = PayerSession.resume(
      offer: e.offer,
      accept: e.accept,
      units: e.units,
      acceptedAt: e.acceptedAt,
      channel: channel,
      policy: policy,
      limits: limits,
      signer: signer,
      ledger: ledger,
      now: now,
    );
    session = s;
    _entry = e;
    final l = link;
    try {
      if (l is! ResumableLink) {
        throw ProviderRejected('not_resumable', 'Link cannot re-attach');
      }
      await l.reattach(e.linkState);
      final pending = e.pendingVoucher;
      if (pending != null) {
        try {
          await l.sendVoucher(pending);
        } on ProviderRejected catch (x) {
          // Already delivered before the crash: the provider has it.
          if (x.code != 'replay' && x.code != 'non_monotonic') rethrow;
        }
        await _journal((x) => x.copyWith(clearPending: true));
      }
      await _record(s, units: e.units);
      return ResumeOutcome.resumed;
    } on ProviderRejected catch (x) {
      lastError = '${x.code}: ${x.message}';
      s.close('interrupted');
      await _record(s, units: e.units);
      await j.clear();
      _entry = null;
      return ResumeOutcome.interrupted;
    }
  }

  Future<Receipt> finish() async {
    final s = _s;
    s.close(s.phase == SessionPhase.closed ? 'closed' : 'client_close');
    try {
      await link.close();
    } finally {
      await journal?.clear();
      _entry = null;
    }
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
        baseline: r.baseline,
        status: r.status,
        closeReason: r.closeReason,
        channelExpiresAt: r.channelExpiresAt,
      );
    }
    await history.upsert(r);
    return r;
  }
}
