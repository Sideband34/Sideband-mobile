import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sideband_protocol/sideband_protocol.dart';

import '../domain/channel_state.dart';
import '../domain/manifest.dart';
import '../domain/payer_session.dart';
import '../domain/receipt.dart';
import '../domain/signed_ledger.dart';
import '../domain/voucher.dart';
import '../integrations/channel_client.dart';
import '../integrations/durable_ledger.dart';
import '../integrations/history.dart';
import '../integrations/provider_link.dart';
import '../integrations/secure_store.dart';
import '../integrations/session_journal.dart';
import '../integrations/session_runner.dart';
import 'demo.dart';

/// Must be overridden at startup (see main.dart / tests).
final demoProvider = Provider<DemoEnvironment>(
    (ref) => throw UnimplementedError('demoProvider'));
final signerProvider = Provider<VoucherSigner>(
    (ref) => throw UnimplementedError('signerProvider'));

/// Defaults to a VOLATILE in-memory store (tests). The app overrides it with
/// [FlutterSecureStore] (keychain / keystore), see main.dart.
final secureStoreProvider =
    Provider<SecureStore>((ref) => InMemorySecureStore());
final ledgerProvider = Provider<SignedLedger>(
    (ref) => StoreBackedSignedLedger(ref.watch(secureStoreProvider)));
final historyRepoProvider = Provider<HistoryRepository>(
    (ref) => HistoryRepository(ref.watch(appDataStoreProvider)));
final journalProvider = Provider<SessionJournal>(
    (ref) => SessionJournal(ref.watch(secureStoreProvider)));

/// Durable, non-secret app data (history). Defaults to the secure store; the
/// app overrides it with a file-backed store (see main.dart).
final appDataStoreProvider =
    Provider<KeyValueStore>((ref) => ref.watch(secureStoreProvider));

/// The payer's channel operations. Defaults to the labelled simulation.
final channelClientProvider = Provider<ChannelClient>((ref) {
  final demo = ref.watch(demoProvider);
  return SimulatedChannelClient(
    initial: demo.channel,
    store: ref.watch(secureStoreProvider),
    now: demo.clock,
  );
});

class ChannelController extends Notifier<ChannelState> {
  @override
  ChannelState build() => ChannelState(
        info: ref.watch(demoProvider).channel,
        status: ChannelStatus.open,
        closeWait: 3600,
        synthetic: true,
      );

  ChannelClient get _client => ref.read(channelClientProvider);

  Future<void> refresh() async => state = await _client.status();

  Future<void> topUp(Amount a) async => state = await _client.topUp(a);

  Future<void> closeStart() async => state = await _client.closeStart();

  Future<void> refund() async {
    final signed = Amount.fromStroops(
        await ref.read(ledgerProvider).highest(state.info.channelId));
    state = await _client.refund(signed);
  }
}

final channelControllerProvider =
    NotifierProvider<ChannelController, ChannelState>(ChannelController.new);

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
    this.baseline,
  });
  final SessionStage stage;
  final int units;
  final Amount? committed;

  /// Channel cumulative signed before this session (protocol v2).
  final Amount? baseline;
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
        baseline: baseline,
      );
}

class SessionController extends Notifier<SessionUiState> {
  SessionRunner? _runner;

  @override
  SessionUiState build() => const SessionUiState();

  String _nonce() =>
      '${Random.secure().nextInt(1 << 32)}-${DateTime.now().microsecondsSinceEpoch}';

  SessionRunner _runnerFor(ProviderLink link) {
    final demo = ref.read(demoProvider);
    return SessionRunner(
      link: link,
      channel: ref.read(channelControllerProvider).info,
      policy: demo.policy,
      limits: SpendingLimits(perSession: ref.read(spendLimitProvider)),
      signer: ref.read(signerProvider),
      ledger: ref.read(ledgerProvider),
      history: ref.read(historyRepoProvider),
      now: demo.clock,
      newNonce: _nonce,
      journal: ref.read(journalProvider),
    );
  }

  Future<void> start(DiscoveredService service) async {
    state = const SessionUiState(busy: true);
    final channel = ref.read(channelControllerProvider);
    if (channel.status != ChannelStatus.open) {
      state = SessionUiState(
          stage: SessionStage.closed,
          error: 'channel_${channel.status.name}: this channel cannot back a '
              'new session. Open the Channel tab.');
      return;
    }
    final r = _runnerFor(service.open());
    try {
      await r.start();
      _runner = r;
      state = SessionUiState(
          stage: SessionStage.active,
          committed: Amount.zero,
          baseline: r.session!.baseline);
    } catch (e) {
      state = SessionUiState(stage: SessionStage.closed, error: _msg(e));
    }
    ref.invalidate(historyProvider);
  }

  /// Called at app start: re-attaches to a session journaled before the app
  /// was killed. With the in-memory demo provider the provider side does not
  /// survive a restart, so this ends `interrupted` (honestly recorded).
  Future<ResumeOutcome> resume(ProviderLink link) async {
    final r = _runnerFor(link);
    final out = await r.resume();
    if (out == ResumeOutcome.resumed) {
      _runner = r;
      final rec = await r.session!.receipt();
      state = SessionUiState(
          stage: SessionStage.active,
          units: r.session!.units,
          committed: rec.committed,
          baseline: rec.baseline,
          error: 'Resumed the session that was open when the app closed.');
    } else if (out == ResumeOutcome.interrupted) {
      state = SessionUiState(
          stage: SessionStage.closed,
          error: 'The session open when the app closed could not be resumed '
              '(${r.lastError}). Its receipt is marked interrupted.');
    }
    ref.invalidate(historyProvider);
    return out;
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
        BaselineGap(:final gap) =>
          'A commitment of $gap signed earlier never reached this provider. '
              'Starting a new session would pay it again, so nothing was signed.',
        SessionViolation(:final code, :final message) => '$code: $message',
        ProviderRejected(:final code, :final message) => '$code: $message',
        _ => e.toString(),
      };
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionUiState>(SessionController.new);
