import 'package:sideband_protocol/sideband_protocol.dart';

import '../domain/voucher.dart';
import 'provider_link.dart';

/// IN-MEMORY SYNTHETIC PROVIDER (test double / demo). It mirrors the
/// sideband-gateway rules (funded-channel check, monotonic verified vouchers,
/// 402 until covered, unit cap, shutdown) using the protocol package's
/// [SessionMachine] and this app's voucher verifier. It is NOT the gateway and
/// moves no money. The real gateway is exercised in test/e2e.
///
/// Channel state (highest accepted voucher) lives in a [SyntheticChannelBook]
/// shared by every session on the same synthetic provider, so sequential
/// sessions on one channel must agree on the baseline, as with the gateway.
class LoopbackProvider implements ResumableLink {
  LoopbackProvider({
    required this.domain,
    required this.network,
    required this.now,
    this.sessionId = 'loopback-session-1',
    this.pricePerUnit = '0.001',
    this.maxUnits = 1000,
    this.currency = 'TEST-TOKEN',
    SyntheticChannelBook? book,
  })  : book = book ?? SyntheticChannelBook(),
        _machine = SessionMachine(sessionId: sessionId, now: now);

  final VoucherDomain domain;
  final String network;
  final int Function() now;
  final String sessionId;
  final String pricePerUnit;
  final int maxUnits;
  final String currency;
  final SyntheticChannelBook book;
  final SessionMachine _machine;

  int units = 0;
  bool shutDown = false;
  final List<String> log = [];

  Amount get _price => Amount.parse(pricePerUnit);

  @override
  Future<ServiceOffer> requestOffer() async {
    if (shutDown) {
      throw ProviderRejected('shutting_down', 'Provider is shutting down');
    }
    final o = ServiceOffer(
      session: sessionId,
      serviceId: 'demo-text-words',
      providerPublicKey: domain.provider,
      pricePerUnit: _price,
      unit: 'word',
      currency: currency,
      network: network,
      maxSessionUnits: maxUnits,
      expiresAt: now() + 300,
    );
    _machine.sendOffer(o);
    return o;
  }

  @override
  Future<void> accept(SessionAccept a) async {
    try {
      _machine.receiveAccept(a,
          knownChannelRefs: {domain.channelId},
          channelCumulative: book.highest(domain.channelId));
    } on SessionViolation catch (e) {
      throw ProviderRejected(e.code, e.message, details: {
        if (e.code == 'baseline_mismatch')
          'expectedBaseline': book.highest(domain.channelId).toString(),
      });
    }
  }

  @override
  Future<void> sendVoucher(VoucherFrame v) async {
    log.add('voucher ${v.cumulativeAmount}');
    final bad = await verifyVoucherSignature(
      domain,
      channelRef: v.channelRef,
      cumulative: v.cumulativeAmount.stroops,
      commitment: v.commitment,
      signature: v.signature,
    );
    if (bad != null) {
      throw ProviderRejected(bad, 'Voucher failed verification');
    }
    try {
      _machine.commitVoucher(v);
    } on SessionViolation catch (e) {
      throw ProviderRejected(e.code, e.message);
    }
    book.record(domain.channelId, v.cumulativeAmount);
  }

  @override
  Future<ServeResult> serve(String text) async {
    if (shutDown) {
      throw ProviderRejected('shutting_down', 'Provider is shutting down');
    }
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (words == 0) {
      throw ProviderRejected('invalid_request', 'empty input');
    }
    if (units + words > maxUnits) {
      throw ProviderRejected('unit_cap', 'Session unit cap reached');
    }
    // Channel cumulative the payer must have signed: baseline + session owed.
    final required = _machine.accept!.baseline + _price.times(units + words);
    if (required > _machine.highestCumulative) {
      throw PaymentRequired(
          required: required, current: _machine.highestCumulative);
    }
    units += words;
    return ServeResult(
        output: text.toUpperCase(), units: words, cumulativeUnits: units);
  }

  @override
  Future<void> close() async => _machine.close();

  @override
  Map<String, String> get resumeState => {'session': sessionId};

  @override
  Future<void> reattach(Map<String, String> state) async {
    if (state['session'] != sessionId) {
      throw ProviderRejected('unknown_session', 'Unknown session');
    }
    if (_machine.phase != SessionPhase.active) {
      throw ProviderRejected('session_closed', 'Session is not active');
    }
  }
}

/// Highest accepted voucher per channel for the synthetic provider.
class SyntheticChannelBook {
  final Map<String, Amount> _highest = {};
  Amount highest(String channelId) => _highest[channelId] ?? Amount.zero;
  void record(String channelId, Amount a) {
    if (a > highest(channelId)) _highest[channelId] = a;
  }
}
