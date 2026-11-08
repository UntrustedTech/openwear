/// Faces 6–10: Quartz, Ember, Nixie, Cockpit, Monolith.
library;

import 'package:openwear/faces/designs/common.dart';

const _white = Color(0xFFF4F1EA), _grey = Color(0xFF6E6A63);

/// A segment LCD with seconds and everything else at a glance.
final quartz = CustomFace(
  id: '960000006',
  name: 'Quartz',
  blurb: 'Segment LCD with seconds, date, steps and pulse.',
  kinds: {FaceKind.retro, FaceKind.info},
  accent: const Color(0xFFB8C49A),
  build: (k) async {
    const lcd = Color(0xFFB8C49A),
        ink = Color(0xFF1C2416),
        ghost = Color(0x1C1C2416);
    await k.background((c, s) {
      fill(c, s, const Color(0xFF0B0C0A));
      final panel = RRect.fromRectAndRadius(
        const Rect.fromLTWH(10, 70, 172, 350),
        const Radius.circular(14),
      );
      c
        ..drawRRect(panel.inflate(4), Paint()..color = const Color(0xFF3A3D36))
        ..drawRRect(panel, Paint()..color = lcd);
    });
    final label = face(
      10,
      ink,
      family: mono,
      weight: FontWeight.w700,
      spacing: 1,
    );
    await k.weekday(22, 84, label, upper: true);
    final small = await k.paintedDigits(
      13,
      22,
      (c, s, d) => paintSevenSegment(c, s, d, ink, ghost),
    );
    k.number(108, 82, FaceData.month, small, spacing: 2);
    await k.image(137, 99, 4, 4, (c, s) => fill(c, s, ink));
    k.number(144, 82, FaceData.day, small, spacing: 2);

    final big = await k.paintedDigits(
      32,
      60,
      (c, s, d) => paintSevenSegment(c, s, d, ink, ghost),
    );
    k.number(20, 126, FaceData.hour, big, spacing: 4);
    await k.animation(90, 134, 8, 44, 2, (c, s, t) {
      if (t >= 0.5) return;
      c
        ..drawRect(const Rect.fromLTWH(1, 8, 6, 6), Paint()..color = ink)
        ..drawRect(const Rect.fromLTWH(-1, 32, 6, 6), Paint()..color = ink);
    }, intervalMs: 500);
    k.number(104, 126, FaceData.minute, big, spacing: 4);
    final secs = await k.paintedDigits(
      18,
      32,
      (c, s, d) => paintSevenSegment(c, s, d, ink, ghost),
    );
    k.number(130, 200, FaceData.second, secs, spacing: 3);

    await k.image(22, 246, 148, 2, (c, s) => fill(c, s, ink.withAlpha(90)));
    await k.text(22, 260, 'STEP', label);
    final mid = await k.paintedDigits(
      16,
      28,
      (c, s, d) => paintSevenSegment(c, s, d, ink, ghost),
    );
    k.number(76, 256, FaceData.steps, mid, count: 5, spacing: 3);
    await k.text(22, 306, 'PULSE', label);
    k.number(112, 302, FaceData.heartRate, mid, count: 3, spacing: 3);
    await k.text(22, 352, 'BATT', label);
    k.number(112, 348, FaceData.battery, mid, count: 3, spacing: 3);
    await k.switcher(
      22,
      392,
      148,
      12,
      FaceData.battery,
      FaceKit.percentSteps(10),
      (c, s, i) {
        for (var b = 0; b < 10; b++) {
          c.drawRect(
            Rect.fromLTWH(b * 15.0, 0, 12, 12),
            Paint()..color = b < i ? ink : ghost,
          );
        }
      },
    );
  },
);

/// Amber dot-matrix numerals, like a departures board at night.
final ember = CustomFace(
  id: '960000007',
  name: 'Ember',
  blurb: 'Glowing amber dot-matrix numerals.',
  kinds: {FaceKind.retro},
  accent: const Color(0xFFFFB13B),
  build: (k) async {
    const amber = Color(0xFFFFB13B), off = Color(0xFF261A0A);
    final big = await k.paintedDigits(
      45,
      63,
      (c, s, d) => paintDotMatrix(c, s, d, amber, off),
    );
    final x = (192 - two(big, spacing: 12)) ~/ 2;
    k.number(x, 120, FaceData.hour, big, spacing: 12);
    k.number(x, 210, FaceData.minute, big, spacing: 12);
    final small = await k.paintedDigits(
      15,
      21,
      (c, s, d) => paintDotMatrix(c, s, d, amber, off),
    );
    await k.weekday(
      x,
      66,
      face(16, amber, family: mono, weight: FontWeight.w700, spacing: 2),
      upper: true,
    );
    k.number(
      192 - x - two(small, spacing: 4),
      64,
      FaceData.day,
      small,
      spacing: 4,
    );
    await k.text(
      x,
      316,
      'BATTERY',
      face(
        11,
        amber.withAlpha(150),
        family: mono,
        weight: FontWeight.w500,
        spacing: 2,
      ),
    );
    await k.switcher(
      x,
      336,
      192 - 2 * x,
      10,
      FaceData.battery,
      FaceKit.percentSteps(5),
      (c, s, i) {
        for (var b = 0; b < 20; b++) {
          c.drawCircle(
            Offset(b * s.width / 20 + 3, 5),
            3,
            Paint()..color = b < i ? amber : off,
          );
        }
      },
    );
    await k.text(
      x,
      366,
      'STEPS',
      face(
        11,
        amber.withAlpha(150),
        family: mono,
        weight: FontWeight.w500,
        spacing: 2,
      ),
    );
    k.number(x, 386, FaceData.steps, small, count: 5, zeros: false, spacing: 4);
  },
);

/// Four glowing tubes.
final nixie = CustomFace(
  id: '960000008',
  name: 'Nixie',
  blurb: 'Warm glowing tube numerals in glass.',
  kinds: {FaceKind.retro, FaceKind.animated},
  accent: const Color(0xFFFF7A2E),
  build: (k) async {
    const glow = Color(0xFFFF7A2E);
    const tubes = [
      Rect.fromLTWH(14, 92, 78, 140),
      Rect.fromLTWH(100, 92, 78, 140),
      Rect.fromLTWH(14, 258, 78, 140),
      Rect.fromLTWH(100, 258, 78, 140),
    ];
    await k.background((c, s) {
      gradient(c, s, const [Color(0xFF120A06), Color(0xFF050302)]);
      for (final t in tubes) {
        final r = RRect.fromRectAndCorners(
          t,
          topLeft: const Radius.circular(36),
          topRight: const Radius.circular(36),
          bottomLeft: const Radius.circular(8),
          bottomRight: const Radius.circular(8),
        );
        c
          ..drawRRect(r, Paint()..color = const Color(0xFF1C130C))
          ..drawRRect(
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = const Color(0xFF4A3A2C),
          );
        // Mesh behind the numerals.
        for (var y = t.top + 24; y < t.bottom - 10; y += 7) {
          c.drawLine(
            Offset(t.left + 10, y),
            Offset(t.right - 10, y),
            Paint()..color = const Color(0xFF2A1E14),
          );
        }
      }
    });
    final digit = await k.fontDigits(
      face(
        96,
        glow,
        family: condensed,
        weight: FontWeight.w400,
        shadows: const [Shadow(color: Color(0xCCFF5A00), blurRadius: 10)],
      ),
      extraWidth: 8,
    );
    final dx = (78 - digit.width) ~/ 2;
    k.number(14 + dx, 112, FaceData.hour, digit, spacing: 86 - digit.width);
    k.number(14 + dx, 278, FaceData.minute, digit, spacing: 86 - digit.width);
    await k.animation(90, 238, 12, 16, 2, (c, s, t) {
      final p = Paint()..color = t < 0.5 ? glow : const Color(0xFF3A2516);
      c
        ..drawCircle(const Offset(6, 4), 3, p)
        ..drawCircle(const Offset(6, 13), 3, p);
    }, intervalMs: 500);
    await k.weekday(
      96,
      420,
      face(
        14,
        glow.withAlpha(200),
        family: mono,
        weight: FontWeight.w500,
        spacing: 3,
      ),
      upper: true,
      center: true,
    );
  },
);

/// Everything the band knows, in one screen.
final cockpit = CustomFace(
  id: '960000009',
  name: 'Cockpit',
  blurb: 'Time, date, weather, steps, pulse, calories and battery.',
  kinds: {FaceKind.info, FaceKind.modern},
  accent: const Color(0xFF4FD1FF),
  build: (k) async {
    const cyan = Color(0xFF4FD1FF),
        panel = Color(0xFF12161C),
        lime = Color(0xFFB8F24A),
        pink = Color(0xFFFF4F8B),
        amber = Color(0xFFFFC145);
    const tiles = [
      Rect.fromLTWH(10, 196, 84, 84),
      Rect.fromLTWH(98, 196, 84, 84),
      Rect.fromLTWH(10, 284, 84, 84),
      Rect.fromLTWH(98, 284, 84, 84),
    ];
    await k.background((c, s) {
      fill(c, s, const Color(0xFF000000));
      for (final t in [...tiles, const Rect.fromLTWH(10, 372, 172, 56)]) {
        c.drawRRect(
          RRect.fromRectAndRadius(t, const Radius.circular(12)),
          Paint()..color = panel,
        );
      }
    });
    final time = await k.fontDigits(face(62, _white));
    final w = two(time);
    final (left, total) = await k.clock(52, time, face(62, cyan));
    final dateStyle = face(
      14,
      _grey,
      family: mono,
      weight: FontWeight.w500,
      spacing: 1,
    );
    await k.weekday(left, 128, dateStyle.copyWith(color: cyan), upper: true);
    final date = await k.fontDigits(dateStyle.copyWith(color: _white));
    k.number(left + 48, 128, FaceData.day, date);
    await k.month(left + 48 + two(date) + 6, 128, dateStyle, upper: true);
    await k.weather(left + 2 * w - 14, 150, 30, amber);
    final temp = await k.fontDigits(
      face(18, _white, family: mono, weight: FontWeight.w500),
    );
    k.number(left, 158, FaceData.temperature, temp, count: 2, zeros: false);
    await k.text(
      left + two(temp) + 1,
      158,
      '°',
      face(18, _grey, family: mono, weight: FontWeight.w500),
    );

    final label = face(
      10,
      _grey,
      family: mono,
      weight: FontWeight.w500,
      spacing: 1,
    );
    final value = await k.fontDigits(
      face(24, _white, family: mono, weight: FontWeight.w500),
    );
    final values = await k.fontDigits(
      face(20, _white, family: mono, weight: FontWeight.w500),
    );
    Future<void> tile(
      Rect t,
      String name,
      Color color,
      FaceData src,
      int count,
      Digits d,
    ) async {
      await k.image(
        t.left.toInt() + 10,
        t.top.toInt() + 12,
        6,
        6,
        (c, s) =>
            c.drawCircle(s.center(Offset.zero), 3, Paint()..color = color),
      );
      await k.text(t.left.toInt() + 20, t.top.toInt() + 10, name, label);
      k.number(
        t.left.toInt() + 10,
        t.top.toInt() + 34,
        src,
        d,
        count: count,
        zeros: false,
      );
    }

    await tile(tiles[0], 'STEPS', lime, FaceData.steps, 5, values);
    await k.switcher(
      20,
      262,
      64,
      6,
      FaceData.stepPercent,
      FaceKit.percentSteps(10),
      (c, s, i) => bar(c, s, i / 10, lime, const Color(0xFF263018)),
    );
    await tile(tiles[1], 'BPM', pink, FaceData.heartRate, 3, value);
    await tile(tiles[2], 'KCAL', amber, FaceData.calories, 4, value);
    await tile(tiles[3], 'BATTERY', cyan, FaceData.battery, 3, value);
    await k.switcher(
      108,
      350,
      64,
      6,
      FaceData.battery,
      FaceKit.percentSteps(10),
      (c, s, i) => bar(c, s, i / 10, cyan, const Color(0xFF13303B)),
    );
    await k.text(22, 384, 'STRESS', label);
    k.number(22, 400, FaceData.stress, values, count: 3, zeros: false);
    await k.switcher(
      84,
      402,
      86,
      10,
      FaceData.stress,
      const [0, 20, 40, 60, 80],
      (c, s, i) {
        for (var b = 0; b < 5; b++) {
          c.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(b * 18.0, 0, 14, 10),
              const Radius.circular(2),
            ),
            Paint()
              ..color = b <= i
                  ? Color.lerp(lime, pink, b / 4)!
                  : const Color(0xFF22262C),
          );
        }
      },
    );
  },
);

/// Two enormous numerals and nothing else.
final monolith = CustomFace(
  id: '960000010',
  name: 'Monolith',
  blurb: 'Huge condensed numerals, solid over outline.',
  kinds: {FaceKind.modern},
  accent: _white,
  build: (k) async {
    final solid = await k.fontDigits(face(150, _white, family: condensed));
    final hollow = await k.fontDigits(
      outline(150, const Color(0xFF8C877E), family: condensed, width: 2.5),
    );
    k.number(
      (192 - two(solid, spacing: 0)) ~/ 2,
      24,
      FaceData.hour,
      solid,
      spacing: 0,
    );
    k.number(
      (192 - two(hollow, spacing: 0)) ~/ 2,
      214,
      FaceData.minute,
      hollow,
      spacing: 0,
    );
    await k.weekday(
      16,
      434,
      face(14, _grey, family: mono, weight: FontWeight.w500, spacing: 2),
      upper: true,
    );
    final d = await k.fontDigits(
      face(14, _white, family: mono, weight: FontWeight.w500),
    );
    k.number(176 - two(d), 434, FaceData.day, d);
  },
);
