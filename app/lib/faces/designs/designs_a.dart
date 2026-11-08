/// Faces 1–5: Signal, Pulse, Meridian, Orbit, Cascade.
library;

import 'package:openwear/faces/designs/common.dart';

const _orange = Color(0xFFFF5A1F),
    _white = Color(0xFFF4F1EA),
    _grey = Color(0xFF6E6A63);

/// Big stacked numerals in OpenWear's own orange.
final signal = CustomFace(
  id: '960000001',
  name: 'Signal',
  blurb: 'Stacked numerals, live dot, battery and steps.',
  kinds: {FaceKind.modern, FaceKind.animated},
  accent: _orange,
  build: (k) async {
    await k.image(16, 36, 22, 4, (c, s) => fill(c, s, _orange));
    await k.weekday(
      16,
      50,
      face(15, _orange, family: mono, weight: FontWeight.w500),
      upper: true,
    );
    final small = await k.fontDigits(
      face(15, _white, family: mono, weight: FontWeight.w500),
    );
    k.number(16, 72, FaceData.day, small);
    await k.month(
      16 + two(small) + 6,
      72,
      face(15, _grey, family: mono, weight: FontWeight.w500),
      upper: true,
    );

    final big = await k.fontDigits(face(104, _white));
    k.number(10, 112, FaceData.hour, big);
    final big2 = await k.fontDigits(face(104, _orange));
    k.number(10, 222, FaceData.minute, big2);
    await k.animation(170, 300, 10, 10, 2, (c, s, t) {
      if (t < 0.5) {
        c.drawCircle(s.center(Offset.zero), 4, Paint()..color = _orange);
      }
    }, intervalMs: 500);

    await k.image(
      16,
      372,
      160,
      1,
      (c, s) => fill(c, s, const Color(0xFF2A2724)),
    );
    final label = face(
      11,
      _grey,
      family: mono,
      weight: FontWeight.w500,
      spacing: 1,
    );
    await k.text(16, 388, 'BATTERY', label);
    await k.text(104, 388, 'STEPS', label);
    final info = await k.fontDigits(
      face(22, _white, family: mono, weight: FontWeight.w500),
    );
    k.number(16, 406, FaceData.battery, info, count: 3, zeros: false);
    k.number(104, 406, FaceData.steps, info, count: 5, zeros: false);
  },
);

/// A live ECG trace with heart rate front and centre.
final pulse = CustomFace(
  id: '960000002',
  name: 'Pulse',
  blurb: 'Moving heartbeat trace with live heart rate.',
  kinds: {FaceKind.animated, FaceKind.info},
  accent: const Color(0xFFFF3B4E),
  build: (k) async {
    const red = Color(0xFFFF3B4E);
    await k.background(
      (c, s) => gradient(
        c,
        s,
        const [Color(0xFF1A0508), Color(0xFF000000)],
        const [0, 0.6],
      ),
    );
    final time = await k.fontDigits(face(60, _white, weight: FontWeight.w500));
    await k.clock(44, time, face(60, red, weight: FontWeight.w500));
    await k.weekday(
      96,
      116,
      face(14, _grey, family: mono, weight: FontWeight.w500),
      upper: true,
      center: true,
    );

    // ECG: a fixed trace with a bright head sweeping left to right.
    double ecg(double x) {
      final p = (x % 96) / 96;
      if (p > 0.42 && p < 0.46) return -(p - 0.42) * 900;
      if (p >= 0.46 && p < 0.52) return -36 + (p - 0.46) * 1250;
      if (p >= 0.52 && p < 0.56) return 39 - (p - 0.52) * 975;
      if (p > 0.66 && p < 0.78) return -9 * sin((p - 0.66) / 0.12 * pi);
      return 0;
    }

    await k.animation(0, 160, 192, 100, 16, (c, s, t) {
      final head = t * 192;
      for (var x = 0.0; x < 192; x += 1) {
        final age = (head - x) % 192;
        final alpha = (255 * (1 - age / 192)).clamp(30, 255).toInt();
        c.drawLine(
          Offset(x, 50 + ecg(x)),
          Offset(x + 1, 50 + ecg(x + 1)),
          Paint()
            ..color = red.withAlpha(alpha)
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round,
        );
      }
      c.drawCircle(Offset(head, 50 + ecg(head)), 4, Paint()..color = _white);
    }, intervalMs: 80);

    await k.text(
      96,
      280,
      'HEART RATE',
      face(11, _grey, family: mono, weight: FontWeight.w500, spacing: 1.5),
      centerX: true,
    );
    final hr = await k.fontDigits(face(72, _white));
    k.number(
      (192 - FaceKit.numberWidth(hr, 3)) ~/ 2,
      300,
      FaceData.heartRate,
      hr,
      count: 3,
      zeros: false,
    );
    await k.text(
      96,
      378,
      'BPM',
      face(14, red, family: mono, weight: FontWeight.w700, spacing: 2),
      centerX: true,
    );

    final info = await k.fontDigits(
      face(18, _white, family: mono, weight: FontWeight.w500),
    );
    final label = face(
      10,
      _grey,
      family: mono,
      weight: FontWeight.w500,
      spacing: 1,
    );
    await k.text(20, 418, 'KCAL', label);
    k.number(20, 432, FaceData.calories, info, count: 4, zeros: false);
    await k.text(112, 418, 'STRESS', label);
    k.number(112, 432, FaceData.stress, info, count: 3, zeros: false);
  },
);

/// A real dial, drawn as one image per hand position.
final meridian = CustomFace(
  id: '960000003',
  name: 'Meridian',
  blurb: 'Analogue dial with hour and minute hands.',
  kinds: {FaceKind.modern},
  accent: const Color(0xFFD9B26F),
  build: (k) async {
    const gold = Color(0xFFD9B26F), navy = Color(0xFF0D1B2E);
    const centre = Offset(96, 96);
    await k.background((c, s) {
      fill(c, s, const Color(0xFF050A12));
      c.drawCircle(const Offset(96, 220), 92, Paint()..color = navy);
      for (var i = 0; i < 60; i++) {
        final a = i * pi / 30;
        final d = Offset(cos(a), sin(a));
        final major = i % 5 == 0;
        c.drawLine(
          const Offset(96, 220) + d * (major ? 74 : 80),
          const Offset(96, 220) + d * 86,
          Paint()
            ..color = major ? gold : const Color(0xFF55607A)
            ..strokeWidth = major ? 2.5 : 1,
        );
      }
    });
    final numeral = face(20, gold, family: serif, weight: FontWeight.w400);
    await k.text(96, 146, '12', numeral, centerX: true);
    await k.text(96, 274, '6', numeral, centerX: true);
    await k.text(30, 210, '9', numeral);
    await k.text(152, 210, '3', numeral);

    void hand(
      Canvas c,
      double angle,
      double length,
      double width,
      Color color,
    ) {
      final d = Offset(sin(angle), -cos(angle));
      c.drawLine(
        centre - d * 12,
        centre + d * length,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    await k.switcher(
      0,
      124,
      192,
      192,
      FaceData.hour,
      List.generate(24, (i) => i),
      (c, s, i) {
        hand(c, (i % 12) / 12 * 2 * pi, 48, 6, _white);
      },
    );
    await k.switcher(
      0,
      124,
      192,
      192,
      FaceData.minute,
      List.generate(60, (i) => i),
      (c, s, i) {
        hand(c, i / 60 * 2 * pi, 72, 3, gold);
      },
    );
    await k.image(90, 214, 12, 12, (c, s) {
      c
        ..drawCircle(s.center(Offset.zero), 5.5, Paint()..color = gold)
        ..drawCircle(s.center(Offset.zero), 2, Paint()..color = navy);
    });

    await k.weekday(
      96,
      340,
      face(16, gold, family: serif, weight: FontWeight.w400),
      center: true,
    );
    final day = await k.fontDigits(
      face(34, _white, family: serif, weight: FontWeight.w400),
    );
    k.number((192 - two(day)) ~/ 2, 362, FaceData.day, day);
    await k.image(66, 414, 60, 1, (c, s) => fill(c, s, gold.withAlpha(120)));
    final steps = await k.fontDigits(
      face(14, _grey, family: mono, weight: FontWeight.w500),
    );
    k.number(
      96 - FaceKit.numberWidth(steps, 5) ~/ 2,
      426,
      FaceData.steps,
      steps,
      count: 5,
      zeros: false,
    );
  },
);

/// A small planet with a moon in orbit.
final orbit = CustomFace(
  id: '960000004',
  name: 'Orbit',
  blurb: 'A moon circling its planet above the time.',
  kinds: {FaceKind.animated, FaceKind.modern},
  accent: const Color(0xFF7C8CFF),
  build: (k) async {
    const violet = Color(0xFF7C8CFF), cyan = Color(0xFF5CE1E6);
    await k.background((c, s) {
      fill(c, s, const Color(0xFF04040C));
      final r = Seeded(4);
      for (var i = 0; i < 70; i++) {
        c.drawCircle(
          Offset(r.next() * 192, r.next() * 490),
          r.next() * 1.1 + 0.3,
          Paint()..color = _white.withAlpha(60 + r.below(120)),
        );
      }
    });
    await k.animation(0, 36, 192, 192, 24, (c, s, t) {
      const mid = Offset(96, 96);
      final a = t * 2 * pi;
      final moon = mid + Offset(cos(a) * 78, sin(a) * 26);
      final behind = sin(a) < 0;
      final orbitPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = violet.withAlpha(90);
      c.drawOval(
        Rect.fromCenter(center: mid, width: 156, height: 52),
        orbitPaint,
      );
      if (behind) c.drawCircle(moon, 9, Paint()..color = cyan);
      c
        ..drawCircle(mid, 46, Paint()..color = const Color(0xFF2B2F7A))
        ..save()
        ..clipPath(Path()..addOval(Rect.fromCircle(center: mid, radius: 46)))
        ..drawCircle(
          mid + const Offset(-14, -14),
          46,
          Paint()..color = const Color(0xFF4752C4),
        )
        ..drawCircle(mid + const Offset(-26, -26), 30, Paint()..color = violet)
        ..restore();
      if (!behind) c.drawCircle(moon, 9, Paint()..color = cyan);
    }, intervalMs: 90);
    final time = await k.fontDigits(face(78, _white, weight: FontWeight.w400));
    k.number((192 - two(time)) ~/ 2, 252, FaceData.hour, time);
    k.number((192 - two(time)) ~/ 2, 334, FaceData.minute, time);
    await k.weekday(
      96,
      430,
      face(14, cyan, family: mono, weight: FontWeight.w500, spacing: 2),
      upper: true,
      center: true,
    );
  },
);

/// Falling code behind a clean terminal-green clock.
final cascade = CustomFace(
  id: '960000005',
  name: 'Cascade',
  blurb: 'Columns of falling code behind the time.',
  kinds: {FaceKind.animated, FaceKind.retro},
  accent: const Color(0xFF3DFF7A),
  build: (k) async {
    const green = Color(0xFF3DFF7A);
    const chars = '0123456789ABCDEF';
    final glyphs = {
      for (var level = 0; level < 4; level++)
        for (var i = 0; i < chars.length; i++)
          (level, i): TextPainter(
            text: TextSpan(
              text: chars[i],
              style: face(
                11,
                level == 3
                    ? const Color(0xFFD8FFE4)
                    : green.withAlpha(60 + level * 60),
                family: mono,
                weight: FontWeight.w500,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(),
    };
    final columns = Seeded(5);
    final speeds = [for (var i = 0; i < 16; i++) 1 + columns.below(2)];
    final offsets = [for (var i = 0; i < 16; i++) columns.below(40)];
    final symbols = [
      for (var i = 0; i < 16 * 40; i++) columns.below(chars.length),
    ];
    await k.animation(0, 0, 192, 490, 10, (c, s, t) {
      final frame = (t * 10).round();
      for (var col = 0; col < 16; col++) {
        final head = (offsets[col] + frame * speeds[col] * 4) % 40;
        for (var back = 0; back < 10; back++) {
          final row = (head - back) % 40;
          final level = back == 0
              ? 3
              : back < 3
              ? 2
              : back < 6
              ? 1
              : 0;
          glyphs[(level, symbols[col * 40 + row])]!.paint(
            c,
            Offset(col * 12.0 + 2, row * 12.25),
          );
        }
      }
    }, intervalMs: 120);
    await k.image(16, 170, 160, 150, (c, s) {
      c.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(10)),
        Paint()..color = const Color(0xF0000000),
      );
      c.drawRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & s).deflate(0.5),
          const Radius.circular(10),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = green.withAlpha(120),
      );
    });
    final time = await k.fontDigits(
      face(54, green, family: mono, weight: FontWeight.w700),
    );
    final w = two(time);
    k.number(96 - w ~/ 2, 186, FaceData.hour, time);
    k.number(96 - w ~/ 2, 246, FaceData.minute, time);
  },
);
