import 'dart:convert';

import 'package:sideband_protocol/sideband_protocol.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart';

import '../domain/channel_state.dart';
import '../domain/payer_session.dart';
import 'channel_client.dart';
import 'stored_key_signer.dart';
import 'secure_store.dart';

/// What the channel contract's `get()` returns, decoded. Amounts are stroops.
class ChannelSnapshot {
  const ChannelSnapshot({
    required this.status,
    required this.deposit,
    required this.paidToProvider,
    required this.refundedToPayer,
    required this.expiresAt,
    required this.closeWait,
    required this.closeEffectiveAt,
    required this.payer,
    required this.provider,
  });

  /// `Open`, `Closing`, `Closed` or `Refunded` (the contract's Status enum).
  final String status;
  final BigInt deposit;
  final BigInt paidToProvider;
  final BigInt refundedToPayer;
  final int expiresAt;
  final int closeWait;
  final int closeEffectiveAt;
  final String payer;
  final String provider;
}

/// The only network surface of [SorobanChannelClient]. The app uses
/// [StellarSorobanPort]; tests use a fake, so the state mapping is tested
/// without a network.
abstract interface class SorobanPort {
  Future<ChannelSnapshot> readChannel();

  /// Builds, simulates, signs (with the payer key) and submits [method], waits
  /// for the ledger result and returns the transaction hash. Throws
  /// [SorobanFailure] on a contract error or a failed transaction.
  Future<String> invoke(String method, List<XdrSCVal> args);
}

class SorobanFailure implements Exception {
  SorobanFailure(this.message);
  final String message;
  @override
  String toString() => 'SorobanFailure: $message';
}

/// Real payer-side channel actions (`top_up`, `close_start`, `refund`) through
/// Soroban RPC. Every state it returns has `synthetic: false` and carries the
/// hash of the transaction that produced it.
class SorobanChannelClient implements ChannelClient {
  SorobanChannelClient({
    required this.info,
    required this.port,
    required this.now,
  });

  final ChannelInfo info;
  final SorobanPort port;
  final int Function() now;

  ChannelState _state(ChannelSnapshot s, {String? txHash}) {
    final status = switch (s.status) {
      'Open' => ChannelStatus.open,
      'Closing' => ChannelStatus.closing,
      'Closed' => ChannelStatus.closed,
      'Refunded' => ChannelStatus.refunded,
      final other => throw SorobanFailure('unknown channel status $other'),
    };
    return ChannelState(
      info: ChannelInfo(
        channelId: info.channelId,
        networkName: info.networkName,
        networkPassphrase: info.networkPassphrase,
        payer: info.payer,
        provider: info.provider,
        deposit: Amount.fromStroops(s.deposit),
        expiresAt: s.expiresAt,
      ),
      status: status,
      closeWait: s.closeWait,
      withdrawn: Amount.fromStroops(s.paidToProvider),
      closeEffectiveAt: s.closeEffectiveAt == 0 ? null : s.closeEffectiveAt,
      refunded: status == ChannelStatus.refunded
          ? Amount.fromStroops(s.refundedToPayer)
          : null,
      synthetic: false,
      lastTxHash: txHash,
    );
  }

  @override
  Future<ChannelState> status() async => _state(await port.readChannel());

  @override
  Future<ChannelState> topUp(Amount amount) async {
    if (amount == Amount.zero) {
      throw ChannelActionError('invalid_params', 'Top-up must be positive');
    }
    final before = await port.readChannel();
    if (before.status != 'Open') {
      throw ChannelActionError(
          'not_open', 'Only an open channel can be topped up');
    }
    final hash = await _invoke('top_up', [
      XdrSCVal.forI128Parts(BigInt.zero, amount.stroops),
    ]);
    final after = await port.readChannel();
    if (after.deposit < before.deposit + amount.stroops) {
      throw SorobanFailure(
          'top_up applied (tx $hash) but the deposit is not visible yet; refresh');
    }
    return _state(after, txHash: hash);
  }

  @override
  Future<ChannelState> closeStart() async {
    final before = await port.readChannel();
    if (before.status == 'Closing') {
      throw ChannelActionError('already_closing', 'Close already started');
    }
    if (before.status != 'Open') {
      throw ChannelActionError('not_open', 'Channel is ${before.status}');
    }
    final hash = await _invoke('close_start', const []);
    final after = await port.readChannel();
    if (after.status != 'Closing') {
      throw SorobanFailure(
          'close_start applied (tx $hash) but the closing state is not visible yet; refresh');
    }
    return _state(after, txHash: hash);
  }

  /// [signedByPayer] is unused on-chain: the contract pays the provider what it
  /// settled and returns the rest, so the chain state is authoritative.
  @override
  Future<ChannelState> refund(Amount signedByPayer) async {
    final before = await port.readChannel();
    if (before.status == 'Open') {
      throw ChannelActionError('not_closing', 'Start a close first');
    }
    if (before.status != 'Closing') {
      throw ChannelActionError('not_open', 'Channel is ${before.status}');
    }
    final wait = before.closeEffectiveAt - now();
    if (wait > 0) {
      throw ChannelActionError(
          'not_expired', 'Dispute window open for ${wait}s');
    }
    final hash = await _invoke('refund', const []);
    final after = await port.readChannel();
    if (after.status != 'Refunded') {
      throw SorobanFailure(
          'refund applied (tx $hash) but the final state is not visible yet; refresh');
    }
    return _state(after, txHash: hash);
  }

  Future<String> _invoke(String method, List<XdrSCVal> args) async {
    try {
      return await port.invoke(method, args);
    } on SorobanFailure {
      rethrow;
    } catch (e) {
      throw SorobanFailure('$method failed: $e');
    }
  }
}

/// [SorobanPort] over the maintained `stellar_flutter_sdk` (MIT). The payer's
/// seed is read from the secure store only to build the signing key pair.
class StellarSorobanPort implements SorobanPort {
  StellarSorobanPort._(this._client);

  final SorobanClient _client;

  /// Opens the channel contract [channelId] on Testnet. The payer key comes
  /// from [store] (the same device key the voucher signer uses).
  static Future<StellarSorobanPort> open({
    required SecureStore store,
    required String channelId,
    String rpcUrl = 'https://soroban-testnet.stellar.org:443',
    Network? network,
  }) async {
    final raw = await store.read(StoredKeySigner.seedKey);
    if (raw == null) {
      throw SorobanFailure('no device key yet; create the wallet first');
    }
    final seed = base64Decode(raw);
    final client = await SorobanClient.forClientOptions(
      options: ClientOptions(
        sourceAccountKeyPair: KeyPair.fromSecretSeedList(seed),
        contractId: channelId,
        network: network ?? Network.TESTNET,
        rpcUrl: rpcUrl,
      ),
    );
    return StellarSorobanPort._(client);
  }

  @override
  Future<ChannelSnapshot> readChannel() async {
    final v = await _client.invokeMethod(name: 'get', args: const []);
    return decodeChannel(v);
  }

  @override
  Future<String> invoke(String method, List<XdrSCVal> args) async {
    final tx = await _client.buildInvokeMethodTx(name: method, args: args);
    final response = await tx.signAndSend();
    if (response.error != null) {
      throw SorobanFailure('$method: ${response.error!.message}');
    }
    if (response.status != GetTransactionResponse.STATUS_SUCCESS) {
      throw SorobanFailure(
          '$method failed on the ledger: ${response.resultXdr}');
    }
    final hash = response.txHash;
    if (hash == null) throw SorobanFailure('$method: no transaction hash');
    return hash;
  }

  /// Decodes the contract's `Channel` struct (an ScMap keyed by symbol).
  static ChannelSnapshot decodeChannel(XdrSCVal v) {
    final entries = v.map;
    if (entries == null) throw SorobanFailure('get() did not return a map');
    final byKey = <String, XdrSCVal>{
      for (final e in entries) e.key.sym ?? '': e.val,
    };
    BigInt i128(String k) {
      final p = byKey[k]?.i128;
      if (p == null) throw SorobanFailure('channel field $k missing');
      return (p.hi.int64 << 64) + p.lo.uint64;
    }

    int u64(String k) {
      final p = byKey[k]?.u64;
      if (p == null) throw SorobanFailure('channel field $k missing');
      return p.uint64.toInt();
    }

    String addr(String k) {
      final a = byKey[k]?.address;
      if (a == null) throw SorobanFailure('channel field $k missing');
      return Address.fromXdr(a).accountId!;
    }

    String sym(String k) {
      // The Status enum is a unit-variant enum: a vec holding one symbol.
      final x = byKey[k];
      final s = x?.sym ?? x?.vec?.first.sym;
      if (s == null) throw SorobanFailure('channel field $k missing');
      return s;
    }

    return ChannelSnapshot(
      status: sym('status'),
      deposit: i128('deposit'),
      paidToProvider: i128('paid_to_provider'),
      refundedToPayer: i128('refunded_to_payer'),
      expiresAt: u64('expires_at'),
      closeWait: u64('close_wait'),
      closeEffectiveAt: u64('close_effective_at'),
      payer: addr('payer'),
      provider: addr('provider'),
    );
  }
}
