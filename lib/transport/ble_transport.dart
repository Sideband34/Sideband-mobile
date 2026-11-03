import 'dart:async';
import 'dart:typed_data';

import 'package:sideband_protocol/sideband_protocol.dart';

import 'chunker.dart';

/// Sideband GATT layout (provider = peripheral, payer = central). Draft UUIDs,
/// randomly generated for this project; not registered with the Bluetooth SIG.
const sidebandServiceUuid = '6a1d0001-5b8e-4c39-9f2e-2f6d7c1a9b10';

/// Payer -> provider (write with response).
const sidebandRxCharUuid = '6a1d0002-5b8e-4c39-9f2e-2f6d7c1a9b10';

/// Provider -> payer (notify).
const sidebandTxCharUuid = '6a1d0003-5b8e-4c39-9f2e-2f6d7c1a9b10';

/// The minimal GATT operations [BleTransport] needs, so it can be tested with
/// a fake and backed by a plugin ([UniversalBleGattLink]) in the app.
abstract interface class GattLink {
  /// Negotiated ATT MTU (payload per write is `mtu - 3`).
  Future<int> negotiateMtu(int wanted);
  Future<void> write(Uint8List value);
  Stream<Uint8List> get notifications;
  Stream<bool> get connected;
  Future<void> disconnect();
}

/// [Transport] over a BLE GATT link: frames are chunked to the MTU and
/// reassembled with sequence checks. Moves opaque frames only; never signs.
///
/// UNTESTED ON HARDWARE: covered by unit tests with a fake [GattLink] only.
class BleTransport implements Transport {
  BleTransport._(this._link, this._chunker) {
    _sub = _link.notifications.listen((chunk) {
      try {
        final frame = _assembler.add(chunk);
        if (frame != null) _in.add(frame);
      } on ChunkException catch (e) {
        _in.addError(e);
      }
    }, onError: _in.addError);
    _connSub = _link.connected.listen((up) {
      if (!up) _closeLocal();
    });
  }

  /// Negotiates the MTU and starts listening.
  static Future<BleTransport> open(GattLink link, {int wantedMtu = 247}) async {
    final mtu = await link.negotiateMtu(wantedMtu);
    // ATT header is 3 bytes; never go below the BLE minimum payload (20).
    final payload = (mtu - 3) < 20 ? 20 : mtu - 3;
    return BleTransport._(link, FrameChunker(chunkSize: payload));
  }

  final GattLink _link;
  final FrameChunker _chunker;
  final FrameAssembler _assembler = FrameAssembler();
  final StreamController<String> _in = StreamController<String>();
  late final StreamSubscription<Uint8List> _sub;
  late final StreamSubscription<bool> _connSub;
  bool _closed = false;

  @override
  Stream<String> get incoming => _in.stream;

  @override
  Future<void> send(String encodedFrame) async {
    if (_closed) throw StateError('BLE link closed');
    for (final c in _chunker.split(encodedFrame)) {
      await _link.write(c);
    }
  }

  void _closeLocal() {
    if (_closed) return;
    _closed = true;
    _sub.cancel();
    _connSub.cancel();
    _in.close();
  }

  @override
  Future<void> close() async {
    _closeLocal();
    await _link.disconnect();
  }
}
