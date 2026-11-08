/// Faces 11–15: Aurora, Terminal, Editorial, Radar, Levels.
library;

import 'package:openwear/faces/designs/common.dart';

const _white = Color(0xFFF4F1EA), _grey = Color(0xFF6E6A63);

/// Slow ribbons of northern light.
final aurora = CustomFace(
  id: '960000011',
  name: 'Aurora',
  blurb: 'Drifting ribbons of northern light.',
  kinds: {FaceKind.animated, FaceKind.modern},
  accent: const Color(0xFF52F2B8),
  build: (k) async {
    const bands = [
      Color(0xFF52F2B8),
      Color(0xFF2BB7A6),
      Color(0xFF7B5CFF),
      Color(0xFFB04DFF),
    ];
    await k.animation(0, 0, 192, 280, 12, (c, s, t) {
      fill(c, s, const Color(0xFF02040A));
      for (var b = 0; b < bands.length; b++) {
        final path = Path()..moveTo(0, s.height);
        for (var x = 0.0; x <= 192; x += 4) {
          final y =
              70 +
              b * 34 +
              18 * sin(x / 34 + t * 2 * pi + b * 0.9) +
              9 * sin(x / 13 - t * 4 * pi + b);
          path.lineTo(x, y);
        }
        path
          ..lineTo(192, s.height)
          ..close();
        c.drawPath(path, Paint()..color = bands[b].withAlpha(150 - b * 20));
      }
      c.drawRect(
        Rect.fromLTWH(0, 230, 192, 50),
        Paint()..color = const Color(0xFF02040A),
      );
    }, intervalMs: 160);
    await k.background(
      (c, s) => c.drawRect(
        const Rect.fromLTWH(0, 280, 192, 210),
        Paint()..color = const Color(0xFF02040A),
      ),
    );
    final time = await k.fontDigits(face(54, _white, weight: FontWeight.w500));
    final (left, total) = await k.clock(
      300,
      time,
      face(54, bands.first, weight: FontWeight.w500),
    );
    await k.weekday(
      left,
      386,
      face(15, bands.first, family: mono, weight: FontWeight.w500, spacing: 2),
      upper: true,
    );
    final d = await k.fontDigits(
      face(15, _white, family: mono, weight: FontWeight.w500),
    );
    k.number(left + total - two(d), 386, FaceData.day, d);
  },
);

/// A shell session that prints your day.
final terminal = CustomFace(
  id: '960000012',
  name: 'Terminal',
  blurb: 'A shell prompt printing your stats, with a blinking cursor.',
  kinds: {FaceKind.info, FaceKind.animated, FaceKind.retro},
  accent: const Color(0xFF8AFF80),
  build: (k) async {
    const green = Color(0xFF8AFF80), dim = Color(0xFF4C7A48);
    final prompt = face(13, dim, family: mono, weight: FontWeight.w500);
    final text = face(13, green, family: mono, weight: FontWeight.w500);
    await k.text(12, 40, r'~ $ date', prompt);
    final big = await k.fontDigits(
      face(56, green, family: mono, weight: FontWeight.w700),
    );
    k.number(10, 62, FaceData.hour, big);
    await k.text(10 + two(big) - 4, 58, ':', face(56, dim, family: mono));
    k.number(10 + two(big) + 26, 62, FaceData.minute, big);
    await k.weekday(12, 128, text, upper: true);
    final n = await k.fontDigits(text);
    k.number(52, 128, FaceData.day, n);
    await k.month(52 + two(n) + 8, 128, text, upper: true);

    await k.text(12, 168, r'~ $ stats', prompt);
    const rows = [
      ('steps', FaceData.steps, 5),
      ('pulse', FaceData.heartRate, 3),
      ('kcal', FaceData.calories, 4),
      ('stress', FaceData.stress, 3),
      ('batt%', FaceData.battery, 3),
      ('temp°', FaceData.temperature, 2),
    ];
    for (var i = 0; i < rows.length; i++) {
      final y = 192 + i * 24;
      await k.text(
        12,
        y,
        rows[i].$1.padRight(8, '.'),
        face(13, dim, family: mono, weight: FontWeight.w500),
      );
      k.number(100, y, rows[i].$2, n, count: rows[i].$3, zeros: false);
    }
    await k.text(12, 348, r'~ $ goal', prompt);
    await k.switcher(
      12,
      370,
      168,
      14,
      FaceData.stepPercent,
      FaceKit.percentSteps(5),
      (c, s, i) {
        final tp = TextPainter(
          text: TextSpan(
            text: '[${'#' * (i * 16 ~/ 20)}${'-' * (16 - i * 16 ~/ 20)}]',
            style: text,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, Offset.zero);
      },
    );
    await k.text(12, 404, r'~ $', prompt);
    await k.animation(44, 402, 9, 16, 2, (c, s, t) {
      if (t < 0.5) fill(c, s, green);
    }, intervalMs: 530);
  },
);

/// Magazine typography on warm paper.
final editorial = CustomFace(
  id: '960000013',
  name: 'Editorial',
  blurb: 'Serif numerals on paper, with the date in words.',
  kinds: {FaceKind.modern},
  accent: const Color(0xFFC8361F),
  build: (k) async {
    const ink = Color(0xFF1B1A17), red = Color(0xFFC8361F);
    await k.background((c, s) {
      fill(c, s, const Color(0xFFF2EBDD));
      c
        ..drawRect(const Rect.fromLTWH(16, 64, 160, 2), Paint()..color = ink)
        ..drawRect(const Rect.fromLTWH(16, 70, 160, 0.8), Paint()..color = ink)
        ..drawRect(
          const Rect.fromLTWH(16, 392, 160, 0.8),
          Paint()..color = ink,
        );
    });
    await k.weekday(
      16,
      38,
      face(
        18,
        ink,
        family: serif,
        weight: FontWeight.w400,
        style: FontStyle.italic,
      ),
    );
    await k.month(
      124,
      40,
      face(13, red, family: mono, weight: FontWeight.w500, spacing: 2),
      upper: true,
    );
    final hour = await k.fontDigits(
      face(132, ink, family: serif, weight: FontWeight.w400),
    );
    k.number((192 - two(hour)) ~/ 2, 92, FaceData.hour, hour);
    final minute = await k.fontDigits(
      face(
        96,
        red,
        family: serif,
        weight: FontWeight.w400,
        style: FontStyle.italic,
      ),
    );
    k.number((192 - two(minute)) ~/ 2, 250, FaceData.minute, minute);
    await k.text(
      16,
      408,
      'No.',
      face(
        16,
        ink,
        family: serif,
        weight: FontWeight.w400,
        style: FontStyle.italic,
      ),
    );
    final day = await k.fontDigits(
      face(30, ink, family: serif, weight: FontWeight.w400),
    );
    k.number(46, 402, FaceData.day, day);
    final steps = await k.fontDigits(
      face(12, ink, family: mono, weight: FontWeight.w500),
    );
    k.number(
      176 - FaceKit.numberWidth(steps, 5),
      414,
      FaceData.steps,
      steps,
      count: 5,
      zeros: false,
    );
  },
);

/// A sweeping radar scope.
final radar = CustomFace(
  id: '960000014',
  name: 'Radar',
  blurb: 'A rotating sweep over a phosphor scope.',
  kinds: {FaceKind.animated, FaceKind.retro},
  accent: const Color(0xFF39FF9E),
  build: (k) async {
    const phosphor = Color(0xFF39FF9E);
    const centre = Offset(96, 96);
    await k.background((c, s) {
      fill(c, s, const Color(0xFF010805));
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = phosphor.withAlpha(70);
      for (final r in [30.0, 60.0, 90.0]) {
        c.drawCircle(const Offset(96, 136), r, ringPaint);
      }
      c
        ..drawLine(const Offset(6, 136), const Offset(186, 136), ringPaint)
        ..drawLine(const Offset(96, 46), const Offset(96, 226), ringPaint);
    });
    final blips = [
      const Offset(60, 70),
      const Offset(140, 120),
      const Offset(110, 40),
      const Offset(50, 140),
    ];
    await k.animation(0, 40, 192, 192, 24, (c, s, t) {
      final angle = t * 2 * pi;
      for (var w = 0; w < 14; w++) {
        final a = angle - w * 0.07;
        c.drawArc(
          Rect.fromCircle(center: centre, radius: 90),
          a - pi / 2,
          0.07,
          true,
          Paint()..color = phosphor.withAlpha(150 - w * 10),
        );
      }
      for (final b in blips) {
        final ba =
            (atan2(b.dy - centre.dy, b.dx - centre.dx) + pi / 2) % (2 * pi);
        final since = (angle - ba) % (2 * pi);
        final alpha = (255 * (1 - since / (2 * pi))).toInt();
        c.drawCircle(b, 3.5, Paint()..color = phosphor.withAlpha(alpha));
      }
    }, intervalMs: 90);
    final time = await k.fontDigits(
      face(46, phosphor, family: mono, weight: FontWeight.w500),
    );
    final (left, total) = await k.clock(
      262,
      time,
      face(46, phosphor.withAlpha(140), family: mono),
    );
    final label = face(
      11,
      phosphor.withAlpha(140),
      family: mono,
      weight: FontWeight.w500,
      spacing: 1,
    );
    final n = await k.fontDigits(
      face(16, phosphor, family: mono, weight: FontWeight.w500),
    );
    await k.text(left, 350, 'BRG', label);
    k.number(left + 40, 348, FaceData.heartRate, n, count: 3, zeros: false);
    await k.text(left, 378, 'RNG', label);
    k.number(left + 40, 376, FaceData.steps, n, count: 5, zeros: false);
    await k.weekday(left, 410, label, upper: true);
    k.number(left + 40, 408, FaceData.day, n);
  },
);

/// Three tall meters for steps, calories and battery.
final levels = CustomFace(
  id: '960000015',
  name: 'Levels',
  blurb: 'Tall meters for steps, calories and battery.',
  kinds: {FaceKind.info, FaceKind.modern},
  accent: const Color(0xFFFFD23F),
  build: (k) async {
    const meters = [
      ('STEP', FaceData.stepPercent, Color(0xFFB8F24A), FaceData.steps, 5),
      (
        'KCAL',
        FaceData.caloriePercent,
        Color(0xFFFFD23F),
        FaceData.calories,
        4,
      ),
      ('BATT', FaceData.battery, Color(0xFF4FD1FF), FaceData.battery, 3),
    ];
    final time = await k.fontDigits(face(52, _white, weight: FontWeight.w500));
    final (left, total) = await k.clock(
      40,
      time,
      face(52, _grey, weight: FontWeight.w500),
    );
    await k.weekday(
      left,
      102,
      face(13, _grey, family: mono, weight: FontWeight.w500, spacing: 2),
      upper: true,
    );
    final d = await k.fontDigits(
      face(13, _white, family: mono, weight: FontWeight.w500),
    );
    k.number(left + total - two(d), 102, FaceData.day, d);
    final label = face(
      10,
      _grey,
      family: mono,
      weight: FontWeight.w500,
      spacing: 1,
    );
    final n = await k.fontDigits(
      face(12, _white, family: mono, weight: FontWeight.w500),
    );
    for (var m = 0; m < meters.length; m++) {
      final (name, source, color, numberSource, count) = meters[m];
      final x = 16 + m * 58;
      await k.switcher(x, 136, 44, 230, source, FaceKit.percentSteps(5), (
        c,
        s,
        i,
      ) {
        for (var seg = 0; seg < 20; seg++) {
          final lit = seg < i;
          c.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(0, s.height - (seg + 1) * 11.5, s.width, 9),
              const Radius.circular(2),
            ),
            Paint()
              ..color = lit
                  ? color.withAlpha(140 + seg * 5)
                  : const Color(0xFF1A1A1A),
          );
        }
      });
      await k.text(
        x + 22,
        376,
        name,
        label.copyWith(color: color),
        centerX: true,
      );
      k.number(
        x + 22 - FaceKit.numberWidth(n, count) ~/ 2,
        394,
        numberSource,
        n,
        count: count,
        zeros: false,
      );
    }
  },
);
