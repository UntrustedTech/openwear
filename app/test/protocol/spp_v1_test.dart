import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/crypto.dart';
import 'package:openwear/protocol/l1.dart';
import 'package:openwear/protocol/link.dart';
import 'package:openwear/protocol/pb.dart';
import 'package:openwear/protocol/session_auth.dart';
import 'package:openwear/protocol/spp_v1.dart';

final _keys = SessionKeys(
  Uint8List.fromList(List.generate(16, (i) => i)), // dec
  Uint8List.fromList(List.generate(16, (i) => 0x40 + i)), // enc
  Uint8List.fromList([1, 2, 3, 4]), // dec IV
  Uint8List.fromList([5, 6, 7, 8]), // enc IV
);

/// A band that answers the probe with protocol 1.0.0 and records packets.
class V1Band implements Transport {
  final _out = StreamController<Uint8List>();
  final reader = V1Reader();
  final received = <V1Packet>[];

  @override
  Future<void> connect() async {}

  @override
  Stream<Uint8List> get incoming => _out.stream;

  @override
  Future<void> close() => _out.close();

  void push(Uint8List bytes) => _out.add(bytes);

  @override
  Future<void> write(Uint8List data) async {
    final packets = reader.feed(data);
    for (final p in packets) {
      if (p.channel == v1Version) {
        push(
          V1Packet(
            channel: v1Version,
            dataType: v1Plain,
            opcode: 0,
            payload: Uint8List.fromList([1, 0, 0]),
          ).encode(),
        );
      } else {
        received.add(p);
      }
    }
  }
}

void main() {
  group('V1Packet', () {
    test('encodes the documented layout', () {
      final b = V1Packet(
        channel: v1PbTx,
        dataType: v1Auth,
        serial: 7,
        payload: Uint8List.fromList([0xAA, 0xBB]),
      ).encode();
      expect(b, [
        0xBA, 0xDC, 0xFE, 2, 0x80, 5, 0, 2, 7, 2, 0xAA, 0xBB, 0xEF, //
      ]);
    });

    test('the reader joins split reads and skips junk', () {
      final a = V1Packet(
        channel: v1PbRx,
        dataType: v1Plain,
        payload: Uint8List.fromList([1, 2, 3]),
      ).encode();
      final b = V1Packet(
        channel: v1Fitness,
        dataType: v1Plain,
        payload: Uint8List.fromList([9]),
      ).encode();
      final all = [0x00, 0x11, ...a, ...b];
      final r = V1Reader();
      final out = <V1Packet>[];
      for (var i = 0; i < all.length; i += 3) {
        out.addAll(r.feed(all.sublist(i, (i + 3).clamp(0, all.length))));
      }
      expect(out.map((p) => p.channel), [v1PbRx, v1Fitness]);
      expect(out.first.payload, [1, 2, 3]);
      expect(out.last.payload, [9]);
    });

    test('maps channels between v1 and the v2 ids OpenWear uses', () {
      expect(v2ChannelOf(v1PbRx), channelPb);
      expect(v2ChannelOf(v1Mass), channelMass);
      expect(v1ChannelOf(channelFitness), v1Fitness);
    });
  });

  group('v1 crypto', () {
    test('a sealed command opens with its counter nonce', () {
      final sealed = v1SealCommand(_keys.encKey, _keys.encIv, 3, [1, 2, 3]);
      expect(sealed.sublist(0, 2), [3, 0]);
      final plain = ccmDecrypt(
        _keys.encKey,
        v1Nonce(_keys.encIv, 3),
        sealed.sublist(2),
      );
      expect(plain, [1, 2, 3]);
    });

    test('a tampered packet fails its tag check', () {
      final sealed = v1Seal(_keys.decKey, _keys.decIv, [4, 5, 6]);
      sealed[0] ^= 1;
      expect(
        () => v1Open(_keys.decKey, _keys.decIv, sealed),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Link over SPP v1', () {
    test('a band below 2.0 gets v1 framing and no link session', () async {
      final band = V1Band();
      final link = Link(band);
      await link.open();
      expect(link.isV1, isTrue);
      expect(link.protocolVersion, '1.0.0');
      expect(band.received, isEmpty, reason: 'no v2 start request');
      await link.close();
    });

    test('auth steps go out plain as type 2, later commands sealed', () async {
      final band = V1Band();
      final link = Link(band);
      await link.open();
      await link.send(const Command(typeAuth, 26), encrypted: false);
      link.keys = _keys;
      await link.send(const Command(typeSystem, 1));
      final auth = band.received[0], cmd = band.received[1];
      expect((auth.channel, auth.dataType), (v1PbTx, v1Auth));
      expect(Command.decode(auth.payload).isA(typeAuth, 26), isTrue);
      expect((cmd.channel, cmd.dataType), (v1PbTx, v1Encrypted));
      final counter = cmd.payload[0] | cmd.payload[1] << 8;
      expect(counter, 1);
      final plain = ccmDecrypt(
        _keys.encKey,
        v1Nonce(_keys.encIv, counter),
        cmd.payload.sublist(2),
      );
      expect(Command.decode(plain).isA(typeSystem, 1), isTrue);
      await link.close();
    });

    test('sealed replies from the band arrive as commands', () async {
      final band = V1Band();
      final link = Link(band)..keys = _keys;
      await link.open();
      final reply = Command.of(typeSystem, 1, [const PbVarint(5, 1)]);
      final next = link.commands.first;
      band.push(
        V1Packet(
          channel: v1PbRx,
          dataType: v1Encrypted,
          payload: v1Seal(_keys.decKey, _keys.decIv, reply.encode()),
        ).encode(),
      );
      final got = await next.timeout(const Duration(seconds: 2));
      expect(got.isA(typeSystem, 1), isTrue);
      await link.close();
    });

    test('data channels are sealed and need no ACK', () async {
      final band = V1Band();
      final link = Link(band)..keys = _keys;
      await link.open();
      await link
          .sendChannel(channelMass, opcodePlain, Uint8List.fromList([7, 7]))
          .timeout(const Duration(seconds: 1));
      final p = band.received.single;
      expect((p.channel, p.dataType), (v1Mass, v1Encrypted));
      expect(v1OpenAs(p.payload), [7, 7]);
      await link.close();
    });
  });
}

/// What the band decrypts from a data packet we sealed.
List<int> v1OpenAs(List<int> sealed) =>
    ccmDecrypt(_keys.encKey, v1Nonce(_keys.encIv, 0), sealed);
