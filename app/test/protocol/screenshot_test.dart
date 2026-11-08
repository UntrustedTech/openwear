import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/crc32.dart';
import 'package:openwear/protocol/screenshot.dart';

final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4, 5, 6]);

/// Builds the band's packets for [png], split into [parts].
List<Uint8List> packets(Uint8List png, int parts, {bool badCrc = false}) {
  const name = 'shot.png';
  final body = [name.length, ...name.codeUnits, 0, 0, 0, 0, 0, ...png];
  final crc = crc32(body) ^ (badCrc ? 1 : 0);
  final data = [
    ...body,
    crc & 0xff,
    crc >> 8 & 0xff,
    crc >> 16 & 0xff,
    crc >> 24,
  ];
  final size = (data.length / parts).ceil();
  return [
    for (var i = 0; i < parts; i++)
      Uint8List.fromList([
        0,
        0x85,
        parts,
        0,
        i + 1,
        0,
        ...data.sublist(i * size, ((i + 1) * size).clamp(0, data.length)),
      ]),
  ];
}

void main() {
  test('packets join into the PNG', () {
    final a = ScreenshotAssembler();
    final ps = packets(png, 3);
    expect(a.feed(ps[0]), isNull);
    expect(a.feed(ps[1]), isNull);
    final shot = a.feed(ps[2])!;
    expect(shot.png, png);
    expect(shot.name, 'shot.png');
  });

  test('a bad CRC is rejected', () {
    final a = ScreenshotAssembler();
    expect(
      () => a.feed(packets(png, 1, badCrc: true).single),
      throwsFormatException,
    );
  });

  test('out-of-order packets are rejected', () {
    final a = ScreenshotAssembler();
    expect(() => a.feed(packets(png, 3)[1]), throwsFormatException);
  });

  test('other data is ignored', () {
    expect(
      isScreenshotPacket(Uint8List.fromList([2, 0, 1, 0, 9, 9, 9])),
      isFalse,
    );
  });

  test('request and permission answer', () {
    expect(screenshotRequest().isA(2, 108), isTrue);
    final answer = Command.decode(screenshotPermissionGranted().encode());
    final state = answer.body.message(74)!.message(1)!;
    expect((state.int_(1), state.int_(2)), (2, 0));
    expect(isScreenshotPermissionAsk(const Command(2, 112)), isTrue);
  });
}
