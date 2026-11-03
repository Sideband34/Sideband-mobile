import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sideband_mobile/transport/ble_transport.dart';
import 'package:sideband_mobile/transport/chunker.dart';
import 'package:sideband_mobile/transport/lan_transport.dart';
import 'package:sideband_protocol/sideband_protocol.dart';

/// Fake GATT peer: records writes, lets the test push notifications.
class FakeGatt implements GattLink {
  FakeGatt({this.mtu = 23});
  final int mtu;
  final List<Uint8List> writes = [];
  final notify = StreamController<Uint8List>();
  final conn = StreamController<bool>();
  bool disconnected = false;

  @override
  Future<int> negotiateMtu(int wanted) async => mtu < wanted ? mtu : wanted;
  @override
  Future<void> write(Uint8List value) async => writes.add(value);
  @override
  Stream<Uint8List> get notifications => notify.stream;
  @override
  Stream<bool> get connected => conn.stream;
  @override
  Future<void> disconnect() async => disconnected = true;
}

final frame = VoucherFrame(
  session: 's1',
  channelRef: 'C' * 56,
  cumulativeAmount: Amount.parse('0.004'),
  commitment: 'a' * 64,
  signature: 'b' * 128,
);

void main() {
  group('FrameChunker / FrameAssembler', () {
    test('round-trips frames of any size up to the limit', () {
      final c = FrameChunker(chunkSize: 20);
      for (final s in ['x', 'a' * 19, 'é' * 50, frame.encode()]) {
        final a = FrameAssembler();
        final parts = c.split(s);
        expect(parts.every((p) => p.length <= 20), isTrue);
        String? out;
        for (final p in parts) {
          out = a.add(p);
        }
        expect(out, s);
      }
    });
    test('detects dropped / reordered chunks and recovers on the next frame',
        () {
      final c = FrameChunker(chunkSize: 10);
      final parts = c.split('0123456789abcdefghijklmnop');
      final a = FrameAssembler();
      a.add(parts[0]);
      expect(() => a.add(parts[2]), throwsA(isA<ChunkException>()));
      String? out;
      for (final p in c.split('ok')) {
        out = a.add(p);
      }
      expect(out, 'ok');
    });
    test('refuses oversize frames on both sides', () {
      final c = FrameChunker(chunkSize: 200);
      expect(() => c.split('x' * (maxFrameBytes + 1)),
          throwsA(isA<ChunkException>()));
      final a = FrameAssembler();
      final big = Uint8List(201)..fillRange(1, 201, 0x61);
      expect(() {
        for (var i = 0; i < 100; i++) {
          big[0] = i & 0x7f; // never final
          a.add(big);
        }
      }, throwsA(isA<ChunkException>()));
    });
    test('rejects invalid UTF-8', () {
      expect(() => FrameAssembler().add(Uint8List.fromList([0x80, 0xff])),
          throwsA(isA<ChunkException>()));
    });
  });

  group('BleTransport (fake GATT, untested on hardware)', () {
    test('chunks writes to the negotiated MTU and decodes notifications',
        () async {
      final g = FakeGatt(mtu: 23);
      final t = await BleTransport.open(g);
      await FrameChannel(t).send(frame);
      expect(g.writes.length, greaterThan(1));
      expect(g.writes.every((w) => w.length <= 20), isTrue);
      final rebuilt = FrameAssembler();
      String? got;
      for (final w in g.writes) {
        got = rebuilt.add(w);
      }
      expect(Frame.decode(got!), isA<VoucherFrame>());

      final incoming = FrameChannel(t).frames.first;
      for (final c in FrameChunker(chunkSize: 20)
          .split(const SessionClose(session: 's1', reason: 'done').encode())) {
        g.notify.add(c);
      }
      expect(await incoming, isA<SessionClose>());
      await t.close();
      expect(g.disconnected, isTrue);
    });

    test('a corrupt chunk sequence surfaces as a stream error', () async {
      final g = FakeGatt();
      final t = await BleTransport.open(g);
      final err =
          t.incoming.first.then<Object?>((_) => null, onError: (Object e) => e);
      g.notify.add(Uint8List.fromList([0x05, 0x41]));
      expect(await err, isA<ChunkException>());
    });

    test('peer disconnect closes the transport; sends then fail', () async {
      final g = FakeGatt();
      final t = await BleTransport.open(g);
      final done = t.incoming.toList();
      g.conn.add(false);
      expect(await done, isEmpty);
      await expectLater(t.send('x'), throwsA(isA<StateError>()));
    });
  });

  group('LanTransport (in-process WebSocket server)', () {
    late HttpServer server;
    final serverSide = Completer<WebSocket>();
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final ws = await WebSocketTransformer.upgrade(req);
        if (!serverSide.isCompleted) serverSide.complete(ws);
      });
    });
    tearDown(() => server.close(force: true));

    test('exchanges frames both ways and rejects binary messages', () async {
      final t = await LanTransport.connect(
          Uri.parse('ws://127.0.0.1:${server.port}'));
      final peer = await serverSide.future;
      final fromPeer = peer.first;
      await FrameChannel(t).send(frame);
      expect(Frame.decode(await fromPeer as String), isA<VoucherFrame>());

      final events = <Object>[];
      final sub = t.incoming.listen(events.add, onError: events.add);
      peer.add(
          const ErrorFrame(session: 's1', code: 'x', message: 'y').encode());
      peer.add(utf8.encode('binary'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(events.first, isA<String>());
      expect(events.last, isA<FormatException>());
      await sub.cancel();
      await t.close();
    });
  });
}
