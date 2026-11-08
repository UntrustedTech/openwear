import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/ui/screens/sleep_screen.dart';
import 'package:openwear/ui/theme.dart';

void _u32(BytesBuilder b, int v) =>
    b.add([for (var i = 0; i < 4; i++) v >> (8 * i) & 0xff]);
void _u16(BytesBuilder b, int v) => b.add([v & 0xff, v >> 8 & 0xff]);

/// A staged night (type 3 v2) from [bed], 7 h long.
Uint8List _night(int bed) {
  final b = BytesBuilder();
  _u32(b, bed);
  b.add([0, 2, 3 << 2, 0, 0xff, 0xff]);
  b.add([84, 0, 0, 0, 0]);
  _u16(b, 400);
  _u32(b, bed);
  _u32(b, bed + 7 * 3600);
  b.add([0, 0, 1]);
  for (final m in [80, 250, 70, 20]) {
    _u16(b, m);
  }
  b.addByte(0);
  for (final (o, stage) in [
    (0, 3),
    (5400, 2),
    (3 * 3600, 4),
    (4 * 3600, 5),
    (4 * 3600 + 1200, 3),
    (7 * 3600, 5),
  ]) {
    _u32(b, bed + o);
    b.addByte(stage);
  }
  return b.toBytes();
}

/// An unstaged full-day segment (type 8 v5) from [start], 2 h long.
Uint8List _segment(int start) {
  final b = BytesBuilder();
  _u32(b, start);
  b.add([0, 5, 8 << 2 | 1, 0, 0xff, 0x80, 1]);
  _u32(b, start);
  _u32(b, start + 7200);
  b.add([90, 93]);
  for (final v in [300, 7500, start - 300, start + 7300]) {
    _u32(b, v);
  }
  _u16(b, 60);
  _u16(b, 3);
  _u32(b, start);
  b.add([60, 55, 57]);
  return b.toBytes();
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('sleep page shows stages and the week ($brightness)', (
      tester,
    ) async {
      final now = DateTime.now();
      final s = now.millisecondsSinceEpoch ~/ 1000;
      final band = BandService();
      band.sleepLog
        ..add(_night(s - 8 * 3600), now)
        ..add(_segment(s - 30 * 3600), now);
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: openWearTheme(brightness),
          home: SleepScreen(band: band),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('DEEP'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('SCORE'), 200);
      await tester.scrollUntilVisible(find.text('PAST WEEK'), 200);
      expect(tester.takeException(), isNull);

      // The older, unstaged segment explains why it has no stages.
      await tester.scrollUntilVisible(find.text('2 H'), 200);
      await tester.tap(find.text('2 H'));
      await tester.pumpAndSettle();
      expect(find.textContaining('without stages'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sleep card asks to wear the band when there is no sleep', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: openWearTheme(Brightness.dark),
        home: Scaffold(body: SleepPanel(band: BandService())),
      ),
    );
    expect(find.textContaining('Wear the band to bed'), findsOneWidget);
  });
}
