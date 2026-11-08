/// Faces 31–35: Lanes, Cadence (sport), Flip, Neon, Blueprint.
library;

import 'package:openwear/faces/designs/common.dart';

const _white = Color(0xFFF4F1EA), _grey = Color(0xFF6E6A63);

TextStyle _label(Color c) =>
    face(10, c, family: mono, weight: FontWeight.w500, spacing: 1.5);

/// Pool lanes with rippling water.
final lanes = CustomFace(
  id: '960000031',
  name: 'Lanes',
  blurb: 'Pool lanes with rippling water and your effort.',
  kinds: {FaceKind.sport, FaceKind.animated},
  accent: const Color(0xFF29B6F6),
  build: (k) async {
    const water0 = Color(0xFF0277BD), light = Color(0xFF4FC3F7);
    void ropes(Canvas c, double top, double h) {
      for (final x in [48.0, 96.0, 144.0]) {
        for (var y = 0.0; y < h; y += 12) {
          final odd = ((y + top) ~/ 12).isOdd;
          c.drawRect(
            Rect.fromLTWH(x - 2, y, 4, 8),
            Paint()..color = odd ? _white : const Color(0xFFE53935),
          );
        }
      }
    }

    void water(Canvas c, Size s, double top, double t) {
      fill(c, s, water0);
      for (var y = 0.0; y < s.height; y += 14) {
        final path = Path()..moveTo(0, y);
        for (var x = 0.0; x <= 192; x += 8) {
          path.lineTo(x, y + 3 * sin(x / 18 + t * 2 * pi + (y + top) / 30));
        }
        c.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = light,
        );
      }
      ropes(c, top, s.height);
    }

    await k.background((c, s) => water(c, s, 0, 0));
    await k.animation(
      0,
      364,
      192,
      126,
      6,
      (c, s, t) => water(c, s, 364, t),
      intervalMs: 180,
    );
    await k.image(
      14,
      150,
      164,
      190,
      (c, s) => c.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(16)),
        Paint()..color = const Color(0xE6001A2E),
      ),
    );
    final time = await k.fontDigits(face(58, _white, weight: FontWeight.w700));
    await k.clock(168, time, face(58, light, weight: FontWeight.w700));
    final n = await k.fontDigits(
      face(18, _white, family: mono, weight: FontWeight.w500),
    );
    await k.text(30, 248, 'KCAL', _label(light));
    k.number(30, 264, FaceData.calories, n, count: 4, zeros: false);
    await k.text(110, 248, 'BPM', _label(light));
    k.number(110, 264, FaceData.heartRate, n, count: 3, zeros: false);
    await k.weekday(30, 304, _label(_white), upper: true);
    k.number(110, 300, FaceData.day, n);
  },
);

/// A metronome bar that keeps the beat of a steady run.
final cadence = CustomFace(
  id: '960000032',
  name: 'Cadence',
  blurb: 'Bouncing beat bars, steps and heart rate for runners.',
  kinds: {FaceKind.sport, FaceKind.animated},
  accent: const Color(0xFFB388FF),
  build: (k) async {
    const violet = Color(0xFFB388FF), pink = Color(0xFFFF80AB);
    final time = await k.fontDigits(face(60, _white, weight: FontWeight.w700));
    await k.clock(40, time, face(60, violet, weight: FontWeight.w700));
    await k.animation(16, 128, 160, 90, 10, (c, s, t) {
      for (var i = 0; i < 10; i++) {
        final h = 12 + 70 * (0.5 + 0.5 * sin(t * 2 * pi + i * 0.7)).abs();
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(i * 16.0 + 2, s.height - h, 10, h),
            const Radius.circular(5),
          ),
          Paint()..color = Color.lerp(violet, pink, i / 9)!,
        );
      }
    }, intervalMs: 90);
    final big = await k.fontDigits(face(52, _white, weight: FontWeight.w700));
    await k.text(20, 250, 'STEPS', _label(violet));
    k.number(20, 266, FaceData.steps, big, count: 5, zeros: false);
    final n = await k.fontDigits(
      face(24, _white, family: mono, weight: FontWeight.w500),
    );
    await k.text(20, 344, 'BPM', _label(pink));
    k.number(20, 360, FaceData.heartRate, n, count: 3, zeros: false);
    await k.text(110, 344, 'KCAL', _label(pink));
    k.number(110, 360, FaceData.calories, n, count: 4, zeros: false);
    await k.switcher(
      20,
      412,
      152,
      6,
      FaceData.stepPercent,
      FaceKit.percentSteps(10),
      (c, s, i) => bar(c, s, i / 10, violet, const Color(0xFF231A33)),
    );
  },
);

/// Split-flap cards like an old station clock.
final flip = CustomFace(
  id: '960000033',
  name: 'Flip',
  blurb: 'Split-flap cards like a railway station clock.',
  kinds: {FaceKind.retro, FaceKind.modern},
  accent: const Color(0xFFE0E0E0),
  build: (k) async {
    const cards = [
      Rect.fromLTWH(14, 100, 78, 120),
      Rect.fromLTWH(100, 100, 78, 120),
      Rect.fromLTWH(14, 232, 78, 120),
      Rect.fromLTWH(100, 232, 78, 120),
    ];
    await k.background((c, s) {
      fill(c, s, const Color(0xFF0C0C0C));
      for (final r in cards) {
        final rr = RRect.fromRectAndRadius(r, const Radius.circular(8));
        c
          ..drawRRect(rr, Paint()..color = const Color(0xFF242424))
          ..drawRRect(
            RRect.fromRectAndCorners(
              Rect.fromLTWH(r.left, r.top, r.width, r.height / 2),
              topLeft: const Radius.circular(8),
              topRight: const Radius.circular(8),
            ),
            Paint()..color = const Color(0xFF2C2C2C),
          );
      }
    });
    final d = await k.fontDigits(
      face(
        96,
        const Color(0xFFEDEDED),
        family: condensed,
        weight: FontWeight.w700,
      ),
    );
    final dx = (78 - d.width) ~/ 2;
    final dy = (120 - d.height) ~/ 2;
    k.number(14 + dx, 100 + dy, FaceData.hour, d, spacing: 86 - d.width);
    k.number(14 + dx, 232 + dy, FaceData.minute, d, spacing: 86 - d.width);
    await k.image(
      14,
      159,
      164,
      2,
      (c, s) => fill(c, s, const Color(0xFF0C0C0C)),
    );
    await k.image(
      14,
      291,
      164,
      2,
      (c, s) => fill(c, s, const Color(0xFF0C0C0C)),
    );
    await k.weekday(
      96,
      50,
      _label(_white).copyWith(fontSize: 14),
      upper: true,
      center: true,
    );
    final n = await k.fontDigits(
      face(14, _grey, family: mono, weight: FontWeight.w500),
    );
    await k.month(
      80,
      392,
      _label(_grey).copyWith(fontSize: 14),
      upper: true,
      center: true,
    );
    k.number(112, 392, FaceData.day, n);
  },
);

/// Neon tubes on a brick wall, with a flicker.
final neon = CustomFace(
  id: '960000034',
  name: 'Neon',
  blurb: 'Glowing neon tubes on a dark brick wall, with a flicker.',
  kinds: {FaceKind.animated, FaceKind.retro},
  accent: const Color(0xFFFF2BD6),
  build: (k) async {
    const pink = Color(0xFFFF2BD6), cyan = Color(0xFF2BF0FF);
    await k.background((c, s) {
      fill(c, s, const Color(0xFF120A10));
      final brick = Paint()..color = const Color(0xFF1C1018);
      for (var row = 0; row < 25; row++) {
        for (var col = -1; col < 5; col++) {
          final x = col * 48.0 + (row.isOdd ? 24 : 0);
          c.drawRect(Rect.fromLTWH(x + 1, row * 20.0 + 1, 46, 18), brick);
        }
      }
    });
    List<Shadow> glow(Color c) => [
      Shadow(color: c, blurRadius: 8),
      Shadow(color: c.withAlpha(160), blurRadius: 18),
    ];
    final hour = await k.fontDigits(
      face(
        92,
        const Color(0xFFFFE0F8),
        family: grotesk,
        weight: FontWeight.w400,
        shadows: glow(pink),
      ),
      extraWidth: 10,
    );
    final minute = await k.fontDigits(
      face(
        92,
        const Color(0xFFE0FDFF),
        family: grotesk,
        weight: FontWeight.w400,
        shadows: glow(cyan),
      ),
      extraWidth: 10,
    );
    k.number((192 - two(hour)) ~/ 2, 110, FaceData.hour, hour);
    k.number((192 - two(minute)) ~/ 2, 226, FaceData.minute, minute);
    await k.animation(20, 360, 152, 40, 6, (c, s, t) {
      final on = t < 0.5 || (t > 0.66 && t < 0.83);
      final tp = TextPainter(
        text: TextSpan(
          text: 'OPEN',
          style: face(
            30,
            on ? const Color(0xFFFFF4B0) : const Color(0xFF3A3320),
            weight: FontWeight.w700,
            spacing: 6,
            shadows: on ? glow(const Color(0xFFFFC233)) : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset((s.width - tp.width) / 2, 2));
    }, intervalMs: 300);
    await k.weekday(
      96,
      60,
      face(
        14,
        pink,
        family: mono,
        weight: FontWeight.w700,
        spacing: 4,
        shadows: glow(pink),
      ),
      upper: true,
      center: true,
    );
  },
);

/// A technical drawing of the time.
final blueprint = CustomFace(
  id: '960000035',
  name: 'Blueprint',
  blurb: 'The time as a technical drawing, dimensions and all.',
  kinds: {FaceKind.modern},
  accent: const Color(0xFF5AB4FF),
  build: (k) async {
    const ink = Color(0xFFDDEBFF), paper = Color(0xFF0D3B78);
    await k.background((c, s) {
      fill(c, s, paper);
      final fine = Paint()..color = const Color(0xFF1C4E8F);
      for (var x = 0.0; x < 192; x += 12) {
        c.drawLine(Offset(x, 0), Offset(x, 490), fine);
      }
      for (var y = 0.0; y < 490; y += 12) {
        c.drawLine(Offset(0, y), Offset(192, y), fine);
      }
      final line = Paint()
        ..color = ink
        ..strokeWidth = 1;
      c
        ..drawLine(const Offset(14, 96), const Offset(178, 96), line)
        ..drawLine(const Offset(14, 90), const Offset(14, 102), line)
        ..drawLine(const Offset(178, 90), const Offset(178, 102), line)
        ..drawLine(const Offset(186, 110), const Offset(186, 340), line)
        ..drawRect(
          const Rect.fromLTWH(10, 404, 172, 60),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = ink,
        );
    });
    final d = await k.fontDigits(outline(104, ink, width: 1.6));
    k.number((192 - two(d)) ~/ 2, 110, FaceData.hour, d);
    k.number((192 - two(d)) ~/ 2, 226, FaceData.minute, d);
    final note = face(
      9,
      ink,
      family: mono,
      weight: FontWeight.w500,
      spacing: 1,
    );
    await k.text(70, 82, 'W 164.0', note);
    await k.text(16, 412, 'DRAWN', note);
    await k.text(16, 440, 'SHEET', note);
    await k.weekday(
      70,
      410,
      face(12, ink, family: mono, weight: FontWeight.w700),
      upper: true,
    );
    final n = await k.fontDigits(
      face(12, ink, family: mono, weight: FontWeight.w700),
    );
    k.number(110, 410, FaceData.day, n);
    k.number(70, 438, FaceData.steps, n, count: 5, zeros: false);
  },
);
