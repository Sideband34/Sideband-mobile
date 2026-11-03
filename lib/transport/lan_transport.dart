import 'dart:async';
import 'dart:io';

import 'package:sideband_protocol/sideband_protocol.dart';

/// [Transport] over a WebSocket on the local network (Wi-Fi / hotspot LAN):
/// one text message per encoded frame, bounded by [maxFrameBytes]. Plain `ws:`
/// is for local demos; there is no TLS or peer authentication at this layer
/// (provider identity comes from the signed manifest).
///
/// Tested against an in-process server; not tested across real devices.
class LanTransport implements Transport {
  LanTransport(this._ws) {
    _ws.listen(
      (m) {
        if (m is! String) {
          _in.addError(const FormatException('Binary message'));
        } else if (m.length > maxFrameBytes) {
          _in.addError(const FormatException('Frame too large'));
        } else {
          _in.add(m);
        }
      },
      onError: _in.addError,
      onDone: _in.close,
    );
  }

  static Future<LanTransport> connect(Uri uri,
          {Duration timeout = const Duration(seconds: 10)}) async =>
      LanTransport(await WebSocket.connect(uri.toString()).timeout(timeout));

  final WebSocket _ws;
  final StreamController<String> _in = StreamController<String>();

  @override
  Stream<String> get incoming => _in.stream;

  @override
  Future<void> send(String encodedFrame) async {
    if (_ws.readyState != WebSocket.open) throw StateError('LAN link closed');
    _ws.add(encodedFrame);
  }

  @override
  Future<void> close() => _ws.close();
}
