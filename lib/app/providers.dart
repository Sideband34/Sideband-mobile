import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sideband_protocol/sideband_protocol.dart';

import '../domain/manifest.dart';
import '../domain/payer_session.dart';
import '../domain/receipt.dart';
import '../domain/signed_ledger.dart';
import '../domain/voucher.dart';
import '../integrations/durable_ledger.dart';
import '../integrations/history.dart';
import '../integrations/provider_link.dart';
import '../integrations/secure_store.dart';
import '../integrations/session_runner.dart';
import 'demo.dart';

/// Must be overridden at startup (see main.dart / tests).
final demoProvider = Provider<DemoEnvironment>(
    (ref) => throw UnimplementedError('demoProvider'));
final signerProvider = Provider<VoucherSigner>(
    (ref) => throw UnimplementedError('signerProvider'));

/// Defaults to a VOLATILE in-memory store. A keychain/keystore-backed
/// [SecureStore] is not implemented yet; override this provider with one.
final secureStoreProvider =
    Provider<SecureStore>((ref) => InMemorySecureStore());
final ledgerProvider = Provider<SignedLedger>(
    (ref) => StoreBackedSignedLedger(ref.watch(secureStoreProvider)));
final historyRepoProvider = Provider<HistoryRepository>(
    (ref) => HistoryRepository(ref.watch(secureStoreProvider)));

class SpendLimitNotifier extends Notifier<Amount> {
  @override
  Amount build() => Amount.parse('0.05');
  void set(Amount a) => state = a;
}

final spendLimitProvider =
    NotifierProvider<SpendLimitNotifier, Amount>(SpendLimitNotifier.new);

class ListingState {
  const ListingState(this.service, this.manifestFailure);
  final DiscoveredService service;
  final ManifestFailure? manifestFailure;
  bool get trusted => manifestFailure == null;
}

final discoveryProvider = FutureProvider<List<ListingState>>((ref) async {
  final demo = ref.watch(demoProvider);
  final out = <ListingState>[];
  for (final s in await demo.scan()) {
    out.add(ListingState(s, (await demo.verify(s)).failure));
  }
  return out;
});

final historyProvider = FutureProvider<List<Receipt>>(
    (ref) => ref.watch(historyRepoProvider).all());

enum SessionStage { idle, active, closed }

class SessionUiState {
  const SessionUiState({
    this.stage = SessionStage.idle,
    this.units = 0,
    this.committed,
    this.output,
    this.error,
    this.receipt,
    this.busy = false,
  });
  final SessionStage stage;
  final int units;
  final Amount? committed;
  final String? output;
  final String? error;
  final Receipt? receipt;
  final bool busy;

  SessionUiState copyWith({
    SessionStage? stage,
    int? units,
    Amount? committed,
    String? output,
    String? error,
    Receipt? receipt,
    bool? busy,
    bool clearError = false,
  }) =>
      SessionUiState(
        stage: stage ?? this.stage,
        units: units ?? this.units,
        committed: committed ?? this.committed,
        output: output ?? this.output,
        error: clearError ? null : (error ?? this.error),
        receipt: receipt ?? this.receipt,
        busy: busy ?? this.busy,
      );
}

class SessionController extends Notifier<SessionUiState> {
  SessionRunner? _runner;

  @override
  SessionUiState build() => const SessionUiState();

  String _nonce() =>
      '${Random.secure().nextInt(1 << 32)}-${DateTime.now().microsecondsSinceEpoch}';

  Future<void> start(DiscoveredService service) async {
    final demo = ref.read(demoProvider);
    state = const SessionUiState(busy: true);
    final r = SessionRunner(
      link: service.open(),
      channel: demo.channel,
      policy: demo.policy,
      limits: SpendingLimits(perSession: ref.read(spendLimitProvider)),
      signer: ref.read(signerProvider),
      ledger: ref.read(ledgerProvider),
      history: ref.read(historyRepoProvider),
      now: demo.clock,
      newNonce: _nonce,
    );
    try {
      await r.start();
      _runner = r;
      state = const SessionUiState(stage: SessionStage.active);
    } catch (e) {
      state = SessionUiState(stage: SessionStage.closed, error: _msg(e));
    }
    ref.invalidate(historyProvider);
  }

  Future<void> use(String text) async {
    final r = _runner;
    if (r == null) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final res = await r.use(text);
      final rec = await r.session!.receipt();
      state = state.copyWith(
          busy: false,
          units: res.cumulativeUnits,
          committed: rec.committed,
          output: res.output);
    } catch (e) {
      final closed = r.session?.phase == SessionPhase.closed;
      state = state.copyWith(
        busy: false,
        error: _msg(e),
        stage: closed ? SessionStage.closed : null,
        committed: (await r.session!.receipt()).committed,
      );
    }
    ref.invalidate(historyProvider);
  }

  Future<void> finish() async {
    final r = _runner;
    if (r == null) return;
    final receipt = await r.finish();
    state = state.copyWith(
        stage: SessionStage.closed, receipt: receipt, busy: false);
    _runner = null;
    ref.invalidate(historyProvider);
  }

  void reset() => state = const SessionUiState();

  String _msg(Object e) => switch (e) {
        BudgetExceeded() =>
          'Spending limit reached. No further commitments will be signed.',
        SessionViolation(:final code, :final message) => '$code: $message',
        ProviderRejected(:final code, :final message) => '$code: $message',
        _ => e.toString(),
      };
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionUiState>(SessionController.new);
