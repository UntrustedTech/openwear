import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/device.dart';
import 'package:openwear/protocol/l1.dart';
import 'package:openwear/protocol/link.dart';
import 'package:openwear/protocol/link_events.dart';
import 'package:openwear/protocol/pb.dart';
import 'package:openwear/services/band_log.dart';

/// A band that answers the version probe, the link start and a battery request.
class FakeBand implements Transport {
  final _out = StreamController<Uint8List>();
  final _reader = FrameReader();
  int _seq = 0;

  @override
  Future<void> connect() async {}

  @override
  Stream<Uint8List> get incoming => _out.stream;

  @override
  Future<void> close() => _out.close();

  @override
  Future<void> write(Uint8List data) async {
    if (data[0] == 0xBA) {
      // SPP v1 reply: protocol 2.0.97
      _out.add(
        Uint8List.fromList([
          0xBA,
          0xDC,
          0xFE,
          0,
          0,
          6,
          0,
          0,
          1,
          0,
          2,
          0,
          0x61,
          0xEF,
        ]),
      );
      return;
    }
    for (final frame in _reader.feed(data)) {
      if (frame.type == frameCmd) {
        _out.add(
          Frame(frameCmd, 0, Uint8List.fromList([cmdStartRsp])).encode(),
        );
      } else if (frame.type == frameData) {
        final (_, _, payload) = l2Decode(frame.payload);
        final cmd = Command.decode(payload);
        if (cmd.isA(typeSystem, 1)) {
          final reply = Command.of(typeSystem, 1, [
            PbBytes(
              2,
              pbEncode([
                PbBytes(1, pbEncode([const PbVarint(1, 87)])),
              ]),
            ),
          ]);
          _out.add(
            Frame(
              frameData,
              _seq++,
              l2Encode(channelPb, opcodePlain, reply.encode()),
            ).encode(),
          );
        }
      }
    }
  }
}

void main() {
  test('link reports every step and the log names and decodes it', () async {
    final link = Link(FakeBand());
    final events = <LinkEvent>[];
    final log = BandLog();
    link.events.listen(events.add);
    link.events.listen(log.onLinkEvent);

    await link.open();
    final reply = await link.request(batteryRequest(), encrypted: false);
    await link.close();

    expect(batteryPercent(reply), 87);
    final status = events.whereType<LinkStatus>().map((e) => e.message);
    expect(status, contains(startsWith('Bluetooth socket open (')));
    expect(status, contains(startsWith('Connected, band protocol 2.0.97')));
    expect(status, contains(startsWith('Link session started (')));
    expect(status, contains('Disconnected'));
    expect(
      events.whereType<LinkStatus>().last.detail,
      contains('commands sent: 1, received: 1'),
    );
    expect(events.whereType<CommandSent>().single.command.subtype, 1);
    expect(events.whereType<CommandReceived>().single.command.type, typeSystem);

    final received = log.entries.firstWhere(
      (e) => e.direction == LogDirection.fromBand,
    );
    expect(received.title, '2/1  Battery');
    expect(received.summary, contains('battery 87%'));
    expect(received.summary, contains('#0'));
    expect(received.summary, contains(RegExp(r'reply in \d+ ms')));
    final sent = log.entries.firstWhere(
      (e) => e.direction == LogDirection.toBand,
    );
    expect(sent.summary, contains('plain'));
    expect(received.detail, contains('1: 87'));
    log.sessionInfo['phone'] = 'Test Phone';
    final exported = log.export();
    expect(exported, startsWith('# OpenWear log'));
    expect(exported, contains('# phone: Test Phone'));
    expect(exported, contains('band → phone  2/1  Battery'));
    expect(
      exported,
      contains('\n        1: 87'),
      reason: 'details are indented',
    );
  });

  test('auth payloads are hidden in the log', () {
    final log = BandLog()
      ..onLinkEvent(
        CommandSent(
          Command.of(typeAuth, 26, [PbBytes(30, Uint8List(16))]),
          encrypted: false,
        ),
      );
    expect(log.entries.single.detail, contains('hidden'));
  });

  test('pause stops recording and the buffer is bounded', () {
    final log = BandLog();
    for (var i = 0; i < BandLog.capacity + 10; i++) {
      log.app('line $i');
    }
    expect(log.entries.length, BandLog.capacity);
    expect(log.entries.first.title, 'line ${BandLog.capacity + 9}');
    log.togglePause();
    log.app('ignored');
    expect(log.entries.first.title, isNot('ignored'));
  });

  test('a request without a reply is logged as a warning', () async {
    final link = Link(FakeBand());
    final log = BandLog();
    link.events.listen(log.onLinkEvent);
    await link.open();
    await expectLater(
      link.request(
        Command.of(typeSystem, 99, const []),
        encrypted: false,
        timeout: const Duration(milliseconds: 50),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await link.close();
    expect(
      log.entries.map((e) => e.title),
      contains(startsWith('No reply to 2/99')),
    );
  });

  test('errors are logged with their type and stack', () {
    final log = BandLog();
    try {
      throw const FormatException('bad bytes');
    } on FormatException catch (e, stack) {
      log.error('Decoding failed', e, stack);
    }
    final entry = log.entries.single;
    expect(entry.direction, LogDirection.warning);
    expect(entry.title, contains('bad bytes'));
    expect(entry.detail, contains('type FormatException'));
    expect(entry.detail, contains('link_log_test.dart'));
  });
}
