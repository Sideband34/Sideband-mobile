import 'dart:convert';
import 'dart:typed_data';

import 'package:sideband_protocol/sideband_protocol.dart';

class ChunkException implements Exception {
  ChunkException(this.message);
  final String message;
  @override
  String toString() => 'ChunkException: $message';
}

/// Splits encoded frames into BLE-sized writes and reassembles them.
///
/// Each chunk is `[header][payload]`; header bit 7 marks the final chunk of a
/// frame and bits 0-6 are a sequence number (mod 128) that must increase by
/// one within a frame, so a dropped or reordered chunk is detected instead of
/// producing a corrupt frame. Frames above [maxFrameBytes] are refused.
class FrameChunker {
  FrameChunker({required this.chunkSize}) {
    if (chunkSize < 2) throw ArgumentError.value(chunkSize, 'chunkSize');
  }

  /// Bytes per write, including the 1-byte header (ATT MTU - 3 for BLE).
  final int chunkSize;

  List<Uint8List> split(String encodedFrame) {
    final bytes = utf8.encode(encodedFrame);
    if (bytes.length > maxFrameBytes) {
      throw ChunkException('Frame exceeds $maxFrameBytes bytes');
    }
    final body = chunkSize - 1;
    final out = <Uint8List>[];
    var seq = 0;
    for (var off = 0; off < bytes.length || out.isEmpty; off += body) {
      final end = (off + body < bytes.length) ? off + body : bytes.length;
      final last = end == bytes.length;
      out.add(Uint8List.fromList(
          [(last ? 0x80 : 0) | (seq & 0x7f), ...bytes.sublist(off, end)]));
      seq++;
    }
    return out;
  }
}

/// Stateful reassembly of one direction of a link.
class FrameAssembler {
  final BytesBuilder _buf = BytesBuilder(copy: false);
  int _next = 0;

  /// Feeds one chunk; returns the decoded frame string when complete.
  String? add(Uint8List chunk) {
    if (chunk.isEmpty) throw ChunkException('Empty chunk');
    final h = chunk[0];
    final seq = h & 0x7f;
    if (seq != (_next & 0x7f)) {
      _reset();
      throw ChunkException(
          'Out-of-order chunk $seq (expected ${_next & 0x7f})');
    }
    _buf.add(chunk.sublist(1));
    _next++;
    if (_buf.length > maxFrameBytes) {
      _reset();
      throw ChunkException('Frame exceeds $maxFrameBytes bytes');
    }
    if (h & 0x80 == 0) return null;
    final bytes = _buf.takeBytes();
    _next = 0;
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw ChunkException('Frame is not valid UTF-8');
    }
  }

  void _reset() {
    _buf.clear();
    _next = 0;
  }
}
