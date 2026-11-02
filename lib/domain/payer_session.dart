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
  }) : _machine = SessionMachine(sessionId: sessionId, now: now);

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

  SessionPhase get phase => _closed ? SessionPhase.closed : _machine.phase;
  int get units => _units;
  Amount? _maxSpend;
  Amount? get maxSpend => _maxSpend;

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

  /// Builds the accept frame; the spend cap is the smallest of the payer's
  /// limit, the offer's total cap and the channel deposit.
  SessionAccept buildAccept({required String nonce}) {
    final o = _machine.offer;
    if (o == null) throw SessionViolation('bad_state', 'No offer received');
    var cap = o.pricePerUnit.times(o.maxSessionUnits);
    if (limits.perSession < cap) cap = limits.perSession;
    if (channel.deposit < cap) cap = channel.deposit;
    final a = SessionAccept(
      session: sessionId,
      channelRef: channel.channelId,
      maxSpend: cap,
      nonce: nonce,
    );
    _machine.sendAccept(a);
    _maxSpend = cap;
    return a;
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

  /// Receipt for what was committed. Starts as `committed`, never final.
  Future<Receipt> receipt() async => Receipt(
        sessionId: sessionId,
        channelId: channel.channelId,
        providerPublicKey: channel.provider,
        units: _units,
        committed: Amount.fromStroops(await ledger.highest(channel.channelId)),
        status: SettlementStatus.committed,
        closeReason: _closeReason ?? 'open',
        channelExpiresAt: channel.expiresAt,
      );
}
