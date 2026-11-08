import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/crc32.dart';
import 'package:openwear/services/band_log.dart';
import 'package:openwear/services/face_previews.dart';

/// One-packet screenshot carrying [png].
Uint8List shotPacket(List<int> png) {
  final body = [0, 0, 0, 0, 0, 0, ...png];
  final crc = crc32(body);
  return Uint8List.fromList([
    0,
    0x85,
    1,
    0,
    1,
    0,
    ...body,
    crc & 0xff,
    crc >> 8 & 0xff,
    crc >> 16 & 0xff,
    crc >> 24,
  ]);
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('faces'));
  tearDown(() => dir.deleteSync(recursive: true));

  FacePreviews make() =>
      FacePreviews(log: BandLog(), directory: () async => dir);

  test(
    'each face is shown, captured, saved, then the old face returns',
    () async {
      final previews = make();
      var shown = '';
      final switches = <String>[];
      Future<void> send(Command c) async {
        expect(c.isA(2, 108), isTrue);
        // The band answers with a picture of what it shows.
        Future<void>.microtask(
          () => previews.feed(shotPacket(shown.codeUnits)),
        );
      }

      final n = await previews.captureAll(
        ['a', 'b'],
        restoreId: 'b',
        send: send,
        switchTo: (id) async {
          switches.add(id);
          shown = id;
        },
        settle: Duration.zero,
      );
      expect(n, 2);
      expect(switches, ['a', 'b', 'b']);
      expect(String.fromCharCodes(previews.images['a']!), 'a');
      expect(previews.busy, isFalse);

      final again = make();
      await again.load(['a', 'b', 'c']);
      expect(again.images.keys, unorderedEquals(['a', 'b']));
    },
  );

  test('non-screenshot data is left alone', () {
    expect(make().feed(Uint8List.fromList([3, 0, 1, 0, 1, 2, 3])), isFalse);
  });
}
