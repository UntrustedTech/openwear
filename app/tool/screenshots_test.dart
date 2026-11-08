// Renders the app's real screens with sample data, for the README and
// promo images. Not part of the normal test run:
//
//   flutter test tool/screenshots_test.dart
//
// Writes PNGs to ../brand/screens/. Every value shown is made up; nothing
// comes from a real band, account or location.

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/daily_report.dart';
import 'package:openwear/protocol/device.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/ui/home_screen.dart';
import 'package:openwear/ui/screens/heart_rate_screen.dart';
import 'package:openwear/ui/screens/sleep_screen.dart';
import 'package:openwear/ui/theme.dart';

const _out = '../brand/screens';
const _logical = Size(393, 852);
const _ratio = 3.0;

Future<void> _loadFonts() async {
  final families = {
    'SpaceGrotesk': [
      'SpaceGrotesk-Regular',
      'SpaceGrotesk-Medium',
      'SpaceGrotesk-Bold',
    ],
    'JetBrainsMono': [
      'JetBrainsMono-Regular',
      'JetBrainsMono-Medium',
      'JetBrainsMono-Bold',
    ],
    'OpenWearCondensed': ['DejaVuSansCondensed', 'DejaVuSansCondensed-Bold'],
    'OpenWearSerif': ['NotoSerif-Regular', 'NotoSerif-Bold'],
  };
  for (final MapEntry(key: family, value: files) in families.entries) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(File('assets/fonts/$f.ttf').readAsBytesSync()),
        ),
      );
    }
    await loader.load();
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  await (FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
      .load();
}

void _u32(BytesBuilder b, int v) =>
    b.add([for (var i = 0; i < 4; i++) v >> (8 * i) & 0xff]);
void _u16(BytesBuilder b, int v) => b.add([v & 0xff, v >> 8 & 0xff]);

/// A staged night (sleep file type 3 v2) from [bed], 7 h 40 min long.
Uint8List _night(int bed) {
  const length = 7 * 3600 + 2400;
  final b = BytesBuilder();
  _u32(b, bed);
  b.add([0, 2, 3 << 2, 0, 0xff, 0xff]);
  b.add([86, 0, 0, 0, 0]);
  _u16(b, 460);
  _u32(b, bed);
  _u32(b, bed + length);
  b.add([0, 0, 1]);
  for (final m in [92, 268, 84, 16]) {
    _u16(b, m);
  }
  b.addByte(0);
  for (final (o, stage) in [
    (0, 3),
    (1500, 2),
    (5400, 3),
    (7800, 4),
    (9600, 3),
    (12600, 2),
    (15000, 3),
    (18600, 4),
    (21000, 5),
    (21600, 3),
    (24600, 4),
    (length, 5),
  ]) {
    _u32(b, bed + o);
    b.addByte(stage);
  }
  return b.toBytes();
}

Future<BandService> _sampleBand() async {
  FlutterSecureStorage.setMockInitialValues({
    'band.address': '00:11:22:33:44:55',
    'band.name': 'Xiaomi Smart Band 9',
    'band.authKey': '00112233445566778899aabbccddeeff',
  });
  final band = BandService();
  await band.load();
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  band
    ..state = BandState.connected
    ..battery = 82
    ..heartRate = 74
    ..today = DailyReport(
      day: day,
      version: 5,
      steps: 8432,
      activeCalories: 412,
      totalCalories: 1980,
      standingHours: 9,
      restingHeartRate: 58,
      averageHeartRate: 71,
      minHeartRate: 54,
      maxHeartRate: 128,
      averageStress: 27,
      averageSpo2: 97,
    )
    ..todayUpdatedAt = now
    ..faces = const [
      WatchFace('960000001', 'Almanac', active: true, removable: true),
      WatchFace('2', 'Classic dial', active: false, removable: false),
    ];
  // A day of heart rate: low overnight, a walk mid-morning, a workout.
  final hr = SplayTreeMap<DateTime, int>();
  for (var m = 0; m < 18 * 60; m += 5) {
    final t = now.subtract(Duration(minutes: 18 * 60 - m));
    final h = t.hour + t.minute / 60;
    var bpm = h < 7 ? 56 : 68 + 6 * math.sin(m / 37);
    if (h > 10 && h < 11) bpm += 30;
    if (h > 17.5 && h < 18.3) bpm += 52;
    hr[t] = bpm.round();
  }
  band.hrHistory.addAll(hr);
  final bed = day.subtract(const Duration(hours: 1, minutes: 10));
  band.sleepLog.add(_night(bed.millisecondsSinceEpoch ~/ 1000), now);
  return band;
}

Future<void> _shoot(WidgetTester tester, GlobalKey key, String name) async {
  // Many short frames, so entrance animations and page transitions finish
  // (a looping heartbeat means pumpAndSettle would never return).
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _ratio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_out/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFonts);

  for (final brightness in Brightness.values) {
    final tag = brightness.name;
    testWidgets('screens ($tag)', (tester) async {
      tester.view.physicalSize = _logical * _ratio;
      tester.view.devicePixelRatio = _ratio;
      addTearDown(tester.view.reset);
      final band = await _sampleBand();
      final key = GlobalKey();
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            navigatorKey: nav,
            debugShowCheckedModeBanner: false,
            theme: openWearTheme(brightness),
            home: HomeScreen(band: band),
          ),
        ),
      );
      await _shoot(tester, key, 'today-$tag');
      for (final (tab, label) in [
        ('HEALTH', 'health'),
        ('FACES', 'faces'),
        ('SETTINGS', 'settings'),
      ]) {
        await tester.tap(find.text(tab).last);
        await _shoot(tester, key, '$label-$tag');
      }
      unawaited(
        nav.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => HeartRateScreen(band: band)),
        ),
      );
      await _shoot(tester, key, 'heart-rate-$tag');
      nav.currentState!.pop();
      unawaited(
        nav.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => SleepScreen(band: band)),
        ),
      );
      await _shoot(tester, key, 'sleep-$tag');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
