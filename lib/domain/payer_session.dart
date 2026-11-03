import 'package:sideband_protocol/sideband_protocol.dart';

import 'receipt.dart';
import 'signed_ledger.dart';
import 'voucher.dart';

/// Hard payer-side spending limits.
class SpendingLimits {
  const SpendingLimits({required this.perSession});

  /// The most this payer will commit in one session.
  final Amount perSession;
}

/// What the payer knows about its funded channel (from the online setup).
class ChannelInfo {
  const ChannelInfo({
    required this.channelId,
    required this.networkName,
    required this.networkPassphrase,
    required this.payer,
    required this.provider,
    required this.deposit,
    required this.expiresAt,
  });
  final String channelId;
  final String networkName; // wire name, e.g. "testnet"
  final String networkPassphrase;
  final String payer;
  final String provider;
  final Amount deposit;
  final int expiresAt;

  VoucherDomain get domain => VoucherDomain(
        networkPassphrase: networkPassphrase,
        channelId: channelId,
        payer: payer,
        provider: provider,
      );
}

class BudgetExceeded implements Exception {
  BudgetExceeded(this.owed, this.cap);
  final Amount owed;
  final Amount cap;
  @override
  String toString() => 'BudgetExceeded: owed $owed > cap $cap';
}

/// Payer side of one session. Wraps the protocol [SessionMachine] and adds
/// the things only the payer can enforce: spending limits, provider/channel
/// binding, monotonic signing and honest receipts.
class PayerSession {
  PayerSession({
    required this.sessionId,
    required this.channel,
    required this.policy,
    required this.limits,
    required this.signer,
    required this.ledger,
    required this.now,
    int Function()? machineClock,
  }) : _machine =
            SessionMachine(sessionId: sessionId, now: machineClock ?? now);

  final String sessionId;
  final ChannelInfo channel;
  final PayerPolicy policy;
  final SpendingLimits limits;
  final VoucherSigner signer;
  final SignedLedger ledger;
  final int Function() now;
  final SessionMachine _machine;

  int _units = 0;
  String? _closeReason;
  bool _closed = false;
  Amount _baseline = Amount.zero;

  SessionPhase get phase => _closed ? SessionPhase.closed : _machine.phase;
  int get units => _units;
  Amount? _maxSpend;
  Amount? get maxSpend => _maxSpend;
  String? get closeReason => _closeReason;
  ServiceOffer? get offer => _machine.offer;

  /// Channel cumulative already signed before this session (protocol v2).
  /// Vouchers stay cumulative per channel; this session's own spend is
  /// `signed - baseline` and is capped by [maxSpend].
  Amount get baseline => _baseline;

  /// Validates the provider's offer against policy AND this channel.
  void receiveOffer(ServiceOffer o) {
    if (o.providerPublicKey != channel.provider) {
      throw SessionViolation(
          'wrong_provider', 'Offer is not from the channel provider');
    }
    if (o.network != channel.networkName) {
      throw SessionViolation('wrong_network', 'Offer network ${o.network}');
    }
    if (channel.expiresAt <= now()) {
      throw SessionViolation('channel_expired', 'Funded channel expired');
    }
    _machine.receiveOffer(o, policy);
  }

  /// Builds the accept frame. [baseline] is the highest amount this payer
  /// ever signed on the channel (from the [SignedLedger]); the session cap is
  /// the smallest of the payer's limit, the offer's total cap and what is left
  /// of the deposit above the baseline.
  SessionAccept buildAccept({required String nonce, Amount? baseline}) {
    final o = _machine.offer;
    if (o == null) throw SessionViolation('bad_state', 'No offer received');
    final base = baseline ?? Amount.zero;
    if (base >= channel.deposit) {
      throw SessionViolation(
          'channel_exhausted', 'Deposit fully committed; top up the channel');
    }
    var cap = o.pricePerUnit.times(o.maxSessionUnits);
    if (limits.perSession < cap) cap = limits.perSession;
    final left = channel.deposit - base;
    if (left < cap) cap = left;
    final a = SessionAccept(
      session: sessionId,
      channelRef: channel.channelId,
      maxSpend: cap,
      nonce: nonce,
      baseline: base,
    );
    _machine.sendAccept(a);
    _maxSpend = cap;
    _baseline = base;
    return a;
  }

  /// Rebuilds an active session after an app restart from what was journaled
  /// before the crash (see `SessionJournal`). The offer and accept are
  /// replayed against a machine whose clock is pinned to [acceptedAt], so an
  /// offer that has since expired does not prevent resuming the same session.
  static PayerSession resume({
    required ServiceOffer offer,
    required SessionAccept accept,
    required int units,
    required int acceptedAt,
    required ChannelInfo channel,
    required PayerPolicy policy,
    required SpendingLimits limits,
    required VoucherSigner signer,
    required SignedLedger ledger,
    required int Function() now,
  }) {
    final s = PayerSession(
      sessionId: offer.session,
      channel: channel,
      policy: policy,
      limits: limits,
      signer: signer,
      ledger: ledger,
      now: now,
      machineClock: () => acceptedAt,
    );
    s._machine.receiveOffer(offer, policy);
    s._machine.sendAccept(accept);
    s._maxSpend = accept.maxSpend;
    s._baseline = accept.baseline;
    s._units = units;
    return s;
  }

  /// Handles a provider meter sample. Returns the voucher to send, or null if
  /// the existing commitment already covers the usage. Throws
  /// [BudgetExceeded] (and closes the session) rather than sign over the cap.
  Future<VoucherFrame?> onMeterSample(MeterSample s) async {
    _machine.receiveSample(s);
    _units = s.cumulativeUnits;
    final owed = _machine.offer!.pricePerUnit.times(s.cumulativeUnits);
    final cap = _maxSpend!;
    if (owed > cap) {
      close('budget_exhausted');
      throw BudgetExceeded(owed, cap);
    }
    return _signUpTo(_baseline + owed);
  }

  /// Pay-before-serve flow: the provider answered 402 with the CHANNEL
  /// cumulative amount it requires (baseline + session owed). Same discipline
  /// as a meter sample: never above baseline + budget, never lower than what
  /// was already signed.
  Future<VoucherFrame?> onPaymentRequired(Amount required) async {
    if (phase != SessionPhase.active) {
      throw SessionViolation('bad_state', 'Session is not active');
    }
    final limit = _baseline + _maxSpend!;
    if (required > limit) {
      close('budget_exhausted');
      throw BudgetExceeded(required - _baseline, _maxSpend!);
    }
    return _signUpTo(required);
  }

  Future<VoucherFrame?> _signUpTo(Amount owed) async {
    final target = owed.stroops;
    if (target <= BigInt.zero) return null;
    if (target <= await ledger.highest(channel.channelId)) return null;
    // Persist the high-water mark first, then sign.
    await ledger.advance(channel.channelId, target);
    final v = await createVoucher(signer, channel.domain, target);
    return VoucherFrame(
      session: sessionId,
      channelRef: v.channelRef,
      cumulativeAmount: Amount.fromStroops(v.cumulativeStroops),
      commitment: v.commitment,
      signature: v.signature,
    );
  }

  /// Units the provider reported for a served request (pay-before-serve flow).
  void recordUnits(int cumulativeUnits) {
    if (cumulativeUnits > _units) _units = cumulativeUnits;
  }

  /// Provider closed or errored: stop signing.
  void onProviderClose(Frame f) {
    if (f is SessionClose) {
      close('provider_close:${f.reason}');
    } else if (f is ErrorFrame) {
      close('provider_error:${f.code}');
    }
  }

  void close(String reason) {
    if (_closed) return;
    _closed = true;
    _closeReason = reason;
    _machine.close();
  }

  /// Receipt for what was committed IN THIS SESSION. Starts as `committed`,
  /// never final.
  Future<Receipt> receipt() async {
    final signed = Amount.fromStroops(await ledger.highest(channel.channelId));
    var mine = signed > _baseline ? signed - _baseline : Amount.zero;
    // Later sessions on the same channel sign above our cap: never claim them.
    if (_maxSpend != null && mine > _maxSpend!) mine = _maxSpend!;
    return Receipt(
      sessionId: sessionId,
      channelId: channel.channelId,
      providerPublicKey: channel.provider,
      units: _units,
      committed: mine,
      baseline: _baseline,
      status: SettlementStatus.committed,
      closeReason: _closeReason ?? 'open',
      channelExpiresAt: channel.expiresAt,
    );
  }
}
