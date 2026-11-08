import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/faces/catalog.dart';
import 'package:openwear/faces/face_binary.dart';
import 'package:openwear/faces/kit.dart';

/// Values at the edges of what the band can show.
final _extremes = <Map<FaceData, int>>[
  {...sampleValues},
  {
    ...sampleValues,
    FaceData.hour: 23,
    FaceData.minute: 59,
    FaceData.second: 59,
    FaceData.steps: 99999,
    FaceData.stepPercent: 100,
    FaceData.calories: 9999,
    FaceData.heartRate: 199,
    FaceData.battery: 100,
    FaceData.day: 30,
    FaceData.month: 12,
    FaceData.standCount: 12,
    FaceData.stress: 100,
    FaceData.sleepScore: 100,
    FaceData.temperature: 40,
  },
  {
    ...sampleValues,
    FaceData.hour: 0,
    FaceData.minute: 0,
    FaceData.steps: 0,
    FaceData.stepPercent: 0,
    FaceData.calories: 0,
    FaceData.heartRate: 0,
    FaceData.battery: 1,
    FaceData.day: 1,
    FaceData.month: 1,
    FaceData.temperature: 0,
  },
];

/// The faces' own fonts; the test default draws every glyph as a square.
Future<void> _loadFonts() async {
  for (final (family, files) in [
    (
      'SpaceGrotesk',
      ['SpaceGrotesk-Regular', 'SpaceGrotesk-Medium', 'SpaceGrotesk-Bold'],
    ),
    (
      'JetBrainsMono',
      ['JetBrainsMono-Regular', 'JetBrainsMono-Medium', 'JetBrainsMono-Bold'],
    ),
    ('OpenWearCondensed', ['DejaVuSansCondensed', 'DejaVuSansCondensed-Bold']),
    ('OpenWearSerif', ['NotoSerif-Regular', 'NotoSerif-Bold']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);
  for (final f in customFaces) {
    testWidgets('${f.name} stays on screen at every value', (tester) async {
      await tester.runAsync(() async {
        final design = await f.design('en');
        final problems = <String>{};
        for (var v = 0; v < _extremes.length; v++) {
          for (final e in design.elements) {
            for (final (r, x, y) in layoutAt([e], _extremes[v])) {
              if (x < 0 ||
                  y < 0 ||
                  x + r.width > screenW ||
                  y + r.height > screenH) {
                final what = switch (e) {
                  DigitNumber(:final source) => 'digits ${source.name}',
                  ImageSwitch(:final source) => 'switch ${source.name}',
                  Animation() => 'animation',
                  StaticImage() => 'image',
                  LuaApp() => 'lua',
                };
                problems.add(
                  '$what ${r.width}x${r.height} at ($x,$y) off screen (values $v)',
                );
              }
            }
          }
        }
        for (final e in design.elements.whereType<DigitNumber>()) {
          final max = switch (e.source) {
            FaceData.steps => 5,
            FaceData.calories => 4,
            FaceData.heartRate => 3,
            FaceData.battery => 3,
            _ => 0,
          };
          if (max > e.count) {
            problems.add('${e.source.name} shows ${e.count} of $max digits');
          }
        }
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    });
  }
}
