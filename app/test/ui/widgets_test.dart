import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/daily_report.dart';
import 'package:openwear/protocol/device.dart';
import 'package:openwear/ui/screens/faces_screen.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/ui/home_screen.dart';
import 'package:openwear/ui/screens/heart_rate_screen.dart';
import 'package:openwear/ui/screens/profile_screen.dart';
import 'package:openwear/services/units.dart';
import 'package:openwear/protocol/profile.dart';
import 'package:openwear/ui/theme.dart';
import 'package:openwear/ui/widgets/gauges.dart';
import 'package:openwear/ui/widgets/band_preview.dart';
import 'package:openwear/ui/widgets/hr_chart.dart';

Widget app(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: openWearTheme(brightness),
      home: Scaffold(body: child),
    );

void main() {
  test('model table picks a shape from the band name', () {
    expect(
      BandModel.forName('Xiaomi Smart Band 9 1A2B').shape,
      BandShape.capsule,
    );
    expect(
      BandModel.forName('Xiaomi Smart Band 9 Pro').shape,
      BandShape.rectangle,
    );
    expect(BandModel.forName('Xiaomi Watch S3').shape, BandShape.round);
  });

  test('face style follows the face name', () {
    expect(faceStyleFor('Classic dial'), FaceStyle.analog);
    expect(faceStyleFor('Big digits'), FaceStyle.digital);
    expect(faceStyleFor(null), FaceStyle.digital);
  });

  test('heart-rate stats', () {
    final now = DateTime.now();
    expect(heartRateStats([]), isNull);
    expect(heartRateStats([(now, 60), (now, 90), (now, 75)]), (60, 75, 90));
  });

  for (final brightness in Brightness.values) {
    testWidgets('band preview draws every state ($brightness)', (tester) async {
      for (final data in const [
        BandScreenData(connected: false),
        BandScreenData(connected: true, battery: 80, heartRate: 72),
        BandScreenData(connected: true, faceName: 'Classic analog'),
        BandScreenData(
          connected: true,
          notificationApp: 'Threads',
          notificationTitle: 'New reply',
        ),
      ]) {
        await tester.pumpWidget(
          app(
            Center(
              child: BandPreview(model: BandModel.capsule, data: data),
            ),
            brightness: brightness,
          ),
        );
        expect(find.byType(BandPreview), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('gauges and chart paint with and without data', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      app(
        Column(
          children: [
            const TickDial(
              progress: 1.3,
              color: Metric.steps,
              track: Color(0xFF333333),
            ),
            const SegmentBar(
              progress: 0.4,
              color: Metric.energy,
              track: Color(0xFF333333),
            ),
            const SegmentBar(
              progress: null,
              color: Metric.stand,
              track: Color(0xFF333333),
            ),
            HeartRateChart(
              samples: const [],
              window: const Duration(minutes: 1),
            ),
            HeartRateChart(
              samples: [
                (now.subtract(const Duration(seconds: 30)), 70),
                (now, 75),
              ],
              window: const Duration(minutes: 1),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('pulse monitor beats only with a reading', (tester) async {
    Widget monitor(int? bpm) => app(
      PulseMonitor(
        bpm: bpm,
        color: Metric.heart,
        track: const Color(0xFF333333),
      ),
    );
    await tester.pumpWidget(monitor(null));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(monitor(60));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('summary shows today\'s totals from the daily report', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'band.address': '08:16:D5:00:12:34',
      'band.name': 'Xiaomi Smart Band 9',
      'band.authKey': '00112233445566778899aabbccddeeff',
    });
    final band = BandService();
    await band.load();
    band.today = DailyReport(
      day: DateTime.now(),
      version: 5,
      steps: 6543,
      activeCalories: 287,
      standingHours: 4,
    );
    band.todayUpdatedAt = DateTime.now();
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: openWearTheme(Brightness.dark),
        home: HomeScreen(band: band),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('6,543'), findsOneWidget);
    expect(find.text('287'), findsOneWidget);
    expect(find.text('GOAL 8,000'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('home shows four tabs and switches between them', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'band.address': '08:16:D5:00:12:34',
      'band.name': 'Xiaomi Smart Band 9',
      'band.authKey': '00112233445566778899aabbccddeeff',
    });
    final band = BandService();
    await band.load();
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: openWearTheme(Brightness.light),
        home: HomeScreen(band: band),
      ),
    );
    await tester.pump();
    expect(find.text('TODAY'), findsWidgets);
    for (final tab in ['HEALTH', 'FACES', 'SETTINGS']) {
      await tester.tap(find.text(tab).last);
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Band settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Software update'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('profile shows saved values in the chosen units', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'settings.units': 'imperial',
      'settings.profile': '{"height":"175","weight":"70","steps":"10000"}',
    });
    final band = BandService();
    await band.load();
    expect(band.units, UnitSystem.imperial);
    expect(band.profile.stepGoal, 10000);
    await tester.pumpWidget(
      MaterialApp(
        theme: openWearTheme(Brightness.light),
        home: ProfileScreen(band: band),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('5′ 9″'), findsOneWidget);
    expect(find.text('154 LB'), findsOneWidget);
    expect(find.text('10,000'), findsOneWidget);
    expect(band.profile.sex, Sex.unspecified);
    expect(tester.takeException(), isNull);
  });

  testWidgets('faces show their names in the phone language', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final band = BandService();
    await band.load();
    band.faces = const [
      WatchFace('1', '星轨', active: true, removable: false),
      WatchFace('2', '多彩线条', active: false, removable: true),
    ];
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: openWearTheme(Brightness.dark),
        home: Scaffold(body: FacesScreen(band: band)),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Star Trails'), findsOneWidget);
    expect(find.text('星轨'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
