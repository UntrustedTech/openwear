/// Faces 21–25 (sport): Tempo, Stride, Zone, Trackside, Split.
library;

import 'package:openwear/faces/designs/common.dart';

const _white = Color(0xFFF4F1EA), _grey = Color(0xFF6E6A63);

/// Heart-rate zone colours, zone 1 (easy) to 5 (max).
const zoneColors = [
  Color(0xFF8E9AAF),
  Color(0xFF4FC3F7),
  Color(0xFF7CE38B),
  Color(0xFFFFB74D),
  Color(0xFFFF5252),
];
const zoneNames = ['WARM UP', 'FAT BURN', 'AEROBIC', 'ANAEROBIC', 'MAX'];

TextStyle _label(Color c) =>
    face(10, c, family: mono, weight: FontWeight.w500, spacing: 1.5);

/// Pulse first: big heart rate with its training zone.
final tempo = CustomFace(
  id: '960000021',
  name: 'Tempo',
  blurb: 'Heart rate and training zone for your workout.',
  kinds: {FaceKind.sport, FaceKind.info},
  accent: const Color(0xFFFF5252),
  build: (k) async {
    final time = await k.fontDigits(face(34, _white, weight: FontWeight.w500));
    await k.clock(36, time, face(34, _grey, weight: FontWeight.w500));
    await k.text(96, 104, 'HEART RATE', _label(_grey), centerX: true);
    final hr = await k.fontDigits(face(96, _white));
    k.number(
      (192 - FaceKit.numberWidth(hr, 3)) ~/ 2,
      124,
      FaceData.heartRate,
      hr,
      count: 3,
      zeros: false,
    );
    await k.switcher(
      16,
      236,
      160,
      52,
      FaceData.heartRateZone,
      const [0, 1, 2, 3, 4, 5],
      (c, s, z) {
        for (var i = 0; i < 5; i++) {
          final lit = i < z;
          c.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(i * 32.0 + 1, 0, 30, 10),
              const Radius.circular(3),
            ),
            Paint()..color = lit ? zoneColors[i] : const Color(0xFF1E1E1E),
          );
        }
        final tp = TextPainter(
          text: TextSpan(
            text: z == 0 ? 'RESTING' : 'ZONE $z · ${zoneNames[z - 1]}',
            style: face(
              13,
              z == 0 ? _grey : zoneColors[z - 1],
              family: mono,
              weight: FontWeight.w700,
              spacing: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: s.width);
        tp.paint(c, Offset((s.width - tp.width) / 2, 24));
      },
    );
    final n = await k.fontDigits(
      face(24, _white, family: mono, weight: FontWeight.w500),
    );
    await k.text(20, 330, 'KCAL', _label(const Color(0xFFFFB74D)));
    k.number(20, 348, FaceData.calories, n, count: 4, zeros: false);
    await k.text(110, 330, 'STEPS', _label(const Color(0xFF7CE38B)));
    k.number(
      110,
      348,
      FaceData.steps,
      await k.fontDigits(
        face(18, _white, family: mono, weight: FontWeight.w500),
      ),
      count: 5,
      zeros: false,
    );
    await k.animation(88, 410, 16, 16, 2, (c, s, t) {
      final p = Paint()
        ..color = t < 0.5 ? const Color(0xFFFF5252) : const Color(0xFF5A1C1C);
      final path = Path()
        ..moveTo(8, 14)
        ..cubicTo(-4, 6, 2, -2, 8, 4)
        ..cubicTo(14, -2, 20, 6, 8, 14);
      c.drawPath(path, p);
    }, intervalMs: 420);
  },
);

/// Steps inside a ring that fills towards the goal.
final stride = CustomFace(
  id: '960000022',
  name: 'Stride',
  blurb: 'Steps in a ring that fills towards your goal.',
  kinds: {FaceKind.sport, FaceKind.modern},
  accent: const Color(0xFFC6EE4A),
  build: (k) async {
    const lime = Color(0xFFC6EE4A);
    final time = await k.fontDigits(face(46, _white, weight: FontWeight.w500));
    await k.clock(40, time, face(46, lime, weight: FontWeight.w500));
    await k.weekday(96, 96, _label(_grey), upper: true, center: true);
    await k.switcher(
      6,
      140,
      180,
      180,
      FaceData.stepPercent,
      FaceKit.percentSteps(5),
      (c, s, i) {
        ring(
          c,
          s.center(Offset.zero),
          80,
          12,
          i / 20,
          lime,
          const Color(0xFF1F2610),
        );
      },
    );
    await k.text(96, 196, 'STEPS', _label(_grey), centerX: true);
    final steps = await k.fontDigits(face(36, _white, weight: FontWeight.w700));
    k.number(
      96 - FaceKit.numberWidth(steps, 5) ~/ 2,
      214,
      FaceData.steps,
      steps,
      count: 5,
      zeros: false,
    );
    final pct = await k.fontDigits(
      face(14, lime, family: mono, weight: FontWeight.w700),
    );
    k.number(78, 262, FaceData.stepPercent, pct, count: 3, zeros: false);
    await k.text(
      78 + FaceKit.numberWidth(pct, 3),
      262,
      '%',
      face(14, lime, family: mono, weight: FontWeight.w700),
    );
    final n = await k.fontDigits(
      face(20, _white, family: mono, weight: FontWeight.w500),
    );
    await k.text(24, 356, 'KCAL', _label(_grey));
    k.number(24, 374, FaceData.calories, n, count: 4, zeros: false);
    await k.text(118, 356, 'BPM', _label(_grey));
    k.number(118, 374, FaceData.heartRate, n, count: 3, zeros: false);
  },
);

/// The whole screen takes the colour of your heart-rate zone.
final zone = CustomFace(
  id: '960000023',
  name: 'Zone',
  blurb: 'The screen glows in your current heart-rate zone colour.',
  kinds: {FaceKind.sport},
  accent: const Color(0xFF7CE38B),
  build: (k) async {
    await k.switcher(
      0,
      0,
      192,
      490,
      FaceData.heartRateZone,
      const [0, 1, 2, 3, 4, 5],
      (c, s, z) {
        final color = z == 0 ? const Color(0xFF2A2A2A) : zoneColors[z - 1];
        c.drawRect(
          Offset.zero & s,
          Paint()
            ..shader = linear(Offset.zero, Offset(0, s.height), [
              color.withAlpha(110),
              const Color(0xFF000000),
            ]),
        );
        final tp = TextPainter(
          text: TextSpan(
            text: z == 0 ? 'RESTING' : 'ZONE $z',
            style: face(
              16,
              color,
              family: mono,
              weight: FontWeight.w700,
              spacing: 3,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, Offset((s.width - tp.width) / 2, 36));
      },
    );
    final hr = await k.fontDigits(face(82, _white));
    k.number(
      (192 - FaceKit.numberWidth(hr, 3)) ~/ 2,
      150,
      FaceData.heartRate,
      hr,
      count: 3,
      zeros: false,
    );
    await k.text(
      96,
      270,
      'BPM',
      face(16, _white, family: mono, weight: FontWeight.w700, spacing: 4),
      centerX: true,
    );
    final time = await k.fontDigits(face(40, _white, weight: FontWeight.w500));
    await k.clock(350, time, face(40, _grey, weight: FontWeight.w500));
    await k.weekday(96, 408, _label(_grey), upper: true, center: true);
  },
);

/// A runner laps an athletics track.
final trackside = CustomFace(
  id: '960000024',
  name: 'Trackside',
  blurb: 'A runner laps the track while your steps count up.',
  kinds: {FaceKind.sport, FaceKind.animated},
  accent: const Color(0xFFE86A3A),
  build: (k) async {
    const clay = Color(0xFFC4502A), field = Color(0xFF1F6B3A);
    final track = RRect.fromRectAndRadius(
      const Rect.fromLTWH(26, 40, 140, 230),
      const Radius.circular(70),
    );
    await k.background((c, s) {
      fill(c, s, const Color(0xFF07130B));
      c
        ..drawRRect(track, Paint()..color = clay)
        ..drawRRect(track.deflate(22), Paint()..color = field);
      for (var lane = 1; lane < 4; lane++) {
        c.drawRRect(
          track.deflate(lane * 5.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = const Color(0xAAFFFFFF),
        );
      }
    });
    final metric = (Path()..addRRect(track.deflate(11))).computeMetrics().first;
    await k.animation(0, 0, 192, 300, 24, (c, s, t) {
      final pos = metric.getTangentForOffset(metric.length * t)!.position;
      c
        ..drawCircle(pos, 7, Paint()..color = const Color(0x55FFFFFF))
        ..drawCircle(pos, 4.5, Paint()..color = _white);
    }, intervalMs: 110);
    final time = await k.fontDigits(face(34, _white, weight: FontWeight.w700));
    await k.clock(
      136,
      time,
      face(34, const Color(0xFFB8E0C4), weight: FontWeight.w700),
    );
    final label = _label(const Color(0xFFE86A3A));
    final n = await k.fontDigits(
      face(26, _white, family: mono, weight: FontWeight.w700),
    );
    await k.text(20, 300, 'STEPS', label);
    k.number(20, 318, FaceData.steps, n, count: 5, zeros: false);
    await k.text(20, 364, 'KCAL', label);
    k.number(20, 382, FaceData.calories, n, count: 4, zeros: false);
    await k.switcher(
      20,
      428,
      152,
      6,
      FaceData.stepPercent,
      FaceKit.percentSteps(10),
      (c, s, i) => bar(c, s, i / 10, clay, const Color(0xFF2A1A12)),
    );
  },
);

/// A stopwatch layout: running seconds and lap-style stats.
final split = CustomFace(
  id: '960000025',
  name: 'Split',
  blurb: 'Stopwatch style with running seconds and lap-like stats.',
  kinds: {FaceKind.sport, FaceKind.info},
  accent: const Color(0xFFFFD60A),
  build: (k) async {
    const yellow = Color(0xFFFFD60A);
    await k.background((c, s) {
      fill(c, s, const Color(0xFF000000));
      final p = Paint()..color = const Color(0xFF2A2A2A);
      for (final y in [176.0, 236.0, 296.0, 356.0]) {
        c.drawRect(Rect.fromLTWH(16, y, 160, 1), p);
      }
    });
    final time = await k.fontDigits(
      face(58, _white, family: mono, weight: FontWeight.w700),
    );
    await k.clock(
      46,
      time,
      face(58, _grey, family: mono, weight: FontWeight.w700),
      gap: 0,
    );
    final secs = await k.fontDigits(
      face(28, yellow, family: mono, weight: FontWeight.w700),
    );
    k.number(96 - two(secs) ~/ 2, 118, FaceData.second, secs);
    final row = await k.fontDigits(
      face(22, _white, family: mono, weight: FontWeight.w500),
    );
    const rows = [
      ('LAP 1  STEPS', FaceData.steps, 5),
      ('LAP 2  KCAL', FaceData.calories, 4),
      ('LAP 3  BPM', FaceData.heartRate, 3),
      ('LAP 4  BATT', FaceData.battery, 3),
    ];
    for (var i = 0; i < rows.length; i++) {
      final y = 190 + i * 60;
      await k.text(16, y, rows[i].$1, _label(i == 0 ? yellow : _grey));
      k.number(
        176 - FaceKit.numberWidth(row, rows[i].$3),
        y + 18,
        rows[i].$2,
        row,
        count: rows[i].$3,
        zeros: false,
      );
    }
    await k.weekday(16, 420, _label(yellow), upper: true);
    final d = await k.fontDigits(_label(_white).copyWith(fontSize: 12));
    k.number(60, 419, FaceData.day, d);
  },
);
