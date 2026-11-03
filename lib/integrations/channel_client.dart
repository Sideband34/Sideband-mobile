import 'dart:convert';

import 'package:sideband_protocol/sideband_protocol.dart';

import '../domain/channel_state.dart';
import '../domain/payer_session.dart';
import 'secure_store.dart';

/// Payer-side channel operations (online). A Soroban implementation would
/// submit `top_up`, `close_start` and `refund` to contracts/channel; none is
/// wired into the app yet (no Testnet access was available to verify one).
abstract interface class ChannelClient {
  Future<ChannelState> status();
  Future<ChannelState> topUp(Amount amount);
  Future<ChannelState> closeStart();

  /// [signedByPayer] is the payer's highest signature on the channel (from
  /// the signed ledger), used to bound what the provider could have withdrawn.
  Future<ChannelState> refund(Amount signedByPayer);
}

/// SIMULATED channel for the demo: applies the contract's rules locally and
/// persists the result, but sends NO transaction and moves no funds. Every
/// state it returns has `synthetic: true` and the UI labels it as such.
class SimulatedChannelClient implements ChannelClient {
  SimulatedChannelClient({
    required ChannelInfo initial,
    required this.store,
    required this.now,
    this.closeWait = 3600,
  }) : _initial = initial;

  final ChannelInfo _initial;
  final KeyValueStore store;
  final int Function() now;
  final int closeWait;

  String get _key => 'sideband.sim_channel.${_initial.channelId}.v1';

  Future<ChannelState> _load() async {
    final base = ChannelState(
      info: _initial,
      status: ChannelStatus.open,
      closeWait: closeWait,
      synthetic: true,
    );
    final raw = await store.read(_key);
    if (raw == null) return base;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return base.copyWith(
      deposit: Amount.parse(j['deposit'] as String),
      status: ChannelStatus.values.byName(j['status'] as String),
      closeEffectiveAt: j['closeEffectiveAt'] as int?,
      refunded:
          j['refunded'] == null ? null : Amount.parse(j['refunded'] as String),
    );
  }

  Future<ChannelState> _save(ChannelState s) async {
    await store.write(
        _key,
        jsonEncode({
          'deposit': s.info.deposit.toString(),
          'status': s.status.name,
          if (s.closeEffectiveAt != null)
            'closeEffectiveAt': s.closeEffectiveAt,
          if (s.refunded != null) 'refunded': s.refunded.toString(),
        }));
    return s;
  }

  @override
  Future<ChannelState> status() => _load();

  @override
  Future<ChannelState> topUp(Amount amount) async {
    final s = await _load();
    if (s.status != ChannelStatus.open) {
      throw ChannelActionError(
          'not_open', 'Only an open channel can be topped up');
    }
    if (amount == Amount.zero) {
      throw ChannelActionError('invalid_params', 'Top-up must be positive');
    }
    return _save(s.copyWith(deposit: s.info.deposit + amount));
  }

  @override
  Future<ChannelState> closeStart() async {
    final s = await _load();
    if (s.status == ChannelStatus.closing) {
      throw ChannelActionError('already_closing', 'Close already started');
    }
    if (s.isTerminal) {
      throw ChannelActionError('not_open', 'Channel is ${s.status.name}');
    }
    final afterWait = now() + s.closeWait;
    final at = afterWait > s.info.expiresAt ? afterWait : s.info.expiresAt;
    return _save(
        s.copyWith(status: ChannelStatus.closing, closeEffectiveAt: at));
  }

  /// [signed] is the payer's own highest signature on the channel: the most the
  /// provider could have withdrawn. The simulation cannot see what it actually
  /// settled, so it reports the refund as "deposit minus signed" (the floor).
  @override
  Future<ChannelState> refund(Amount signedByPayer) async {
    final signed = signedByPayer;
    final s = await _load();
    if (s.status == ChannelStatus.open) {
      throw ChannelActionError('not_closing', 'Start a close first');
    }
    if (s.isTerminal) {
      throw ChannelActionError('not_open', 'Channel is ${s.status.name}');
    }
    final wait = s.refundIn(now()) ?? 0;
    if (wait > 0) {
      throw ChannelActionError(
          'not_expired', 'Dispute window open for ${wait}s');
    }
    final rest =
        signed < s.info.deposit ? s.info.deposit - signed : Amount.zero;
    return _save(s.copyWith(status: ChannelStatus.refunded, refunded: rest));
  }
}
