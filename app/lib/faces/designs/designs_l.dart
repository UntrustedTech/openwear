/// Faces 56–60: Aquarium, Codefall, Moodring, Hourglass, Stack.
library;

import 'package:openwear/faces/designs/common.dart';

const _white = Color(0xFFF4F1EA), _grey = Color(0xFF6E6A63);

TextStyle _label(Color c) =>
    face(10, c, family: mono, weight: FontWeight.w500, spacing: 1.5);

/// Fish swim past behind the glass.
final aquarium = CustomFace(
  id: '960000056',
  name: 'Aquarium',
  blurb: 'Fish swim and bubbles rise behind the time.',
  kinds: {FaceKind.animated},
  accent: const Color(0xFFFF8A3D),
  build: (k) async {
    await k.background((c, s) {
      gradient(
        c,
        s,
        const [Color(0xFF03263F), Color(0xFF0A4F6E), Color(0xFF0C3B2A)],
        const [0, 0.7, 1],
      );
      final weed = Paint()
        ..color = const Color(0xFF1F7A4A)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (final x in [20.0, 44.0, 150.0, 176.0]) {
        c.drawPath(
          Path()
            ..moveTo(x, 490)
            ..quadraticBezierTo(x + 14, 440, x - 4, 400)
            ..quadraticBezierTo(x - 14, 370, x + 4, 340),
          weed,
        );
      }
      c.drawRect(
        const Rect.fromLTWH(0, 470, 192, 20),
        Paint()..color = const Color(0xFFC2A36B),
      );
    });
    void fish(Canvas c, Offset at, double size, Color color, bool right) {
      final d = right ? 1.0 : -1.0;
      c
        ..drawOval(
          Rect.fromCenter(center: at, width: size * 2, height: size * 1.1),
          Paint()..color = color,
        )
        ..drawPath(
          Path()
            ..moveTo(at.dx - d * size, at.dy)
            ..lineTo(at.dx - d * size * 1.7, at.dy - size * 0.6)
            ..lineTo(at.dx - d * size * 1.7, at.dy + size * 0.6)
            ..close(),
          Paint()..color = color,
        )
        ..drawCircle(
          at + Offset(d * size * 0.5, -size * 0.15),
          size * 0.15,
          Paint()..color = const Color(0xFF111111),
        );
    }

    await k.animation(0, 280, 192, 190, 16, (c, s, t) {
      fish(
        c,
        Offset(-30 + t * 252, 50 + 6 * sin(t * 4 * pi)),
        14,
        const Color(0xFFFF8A3D),
        true,
      );
      fish(
        c,
        Offset(222 - ((t + 0.4) % 1) * 252, 120),
        10,
        const Color(0xFFFFD54F),
        false,
      );
      fish(
        c,
        Offset(-20 + ((t + 0.7) % 1) * 232, 160),
        7,
        const Color(0xFF4FC3F7),
        true,
      );
      for (var b = 0; b < 6; b++) {
        final p = (t + b / 6) % 1;
        c.drawCircle(
          Offset(60 + b * 14.0 + 4 * sin(p * 6 * pi), s.height - p * s.height),
          2 + b % 3,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xAACFF4FF),
        );
      }
    }, intervalMs: 150);
    final time = await k.fontDigits(face(64, _white, weight: FontWeight.w700));
    await k.clock(
      80,
      time,
      face(64, const Color(0xFF80DEEA), weight: FontWeight.w700),
    );
    await k.weekday(
      96,
      160,
      _label(const Color(0xFF80DEEA)),
      upper: true,
      center: true,
    );
    final n = await k.fontDigits(face(16, _white, family: mono));
    k.number(84, 184, FaceData.day, n);
  },
);

/// Columns of glyphs pour down the screen.
final codefall = CustomFace(
  id: '960000057',
  name: 'Codefall',
  blurb: 'Streams of glowing code pour down behind the time.',
  kinds: {FaceKind.animated, FaceKind.retro},
  accent: const Color(0xFF39FF6A),
  build: (k) async {
    const green = Color(0xFF39FF6A);
    await k.background((c, s) => fill(c, s, const Color(0xFF000400)));
    final r = Seeded(57);
    final columns = [
      for (var i = 0; i < 12; i++) (i * 16.0 + 4, r.next(), 6 + r.below(8)),
    ];
    const glyphs = '01アイウエオカキク23456789';
    final style = face(12, green, family: mono, weight: FontWeight.w500);
    final painters = [
      for (var g = 0; g < glyphs.length; g++)
        TextPainter(
          text: TextSpan(text: glyphs[g], style: style),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    await k.animation(0, 0, 192, 490, 10, (c, s, t) {
      for (final (x, phase, length) in columns) {
        final head = ((t + phase) % 1) * (490 + length * 14);
        for (var j = 0; j < length; j++) {
          final y = head - j * 14;
          if (y < 0 || y > 490) continue;
          final tp =
              painters[(x ~/ 16 + j * 3 + (t * 10).round()) % painters.length];
          c
            ..saveLayer(
              null,
              Paint()
                ..color = Color.fromARGB(j == 0 ? 255 : 200 - j * 18, 0, 0, 0),
            )
            ..translate(x, y);
          tp.paint(c, Offset.zero);
          c.restore();
        }
      }
    }, intervalMs: 120);
    await k.image(
      10,
      168,
      172,
      130,
      (c, s) => c.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(10)),
        Paint()..color = const Color(0xE6000400),
      ),
    );
    final time = await k.fontDigits(
      face(
        56,
        green,
        family: mono,
        weight: FontWeight.w700,
        shadows: const [Shadow(color: green, blurRadius: 10)],
      ),
    );
    await k.clock(
      186,
      time,
      face(56, green, family: mono, weight: FontWeight.w700),
      gap: 0,
    );
    await k.weekday(96, 256, _label(green), upper: true, center: true);
  },
);

/// The background colour follows your stress level, like a mood ring.
final moodring = CustomFace(
  id: '960000058',
  name: 'Moodring',
  blurb: 'A glowing orb that shifts colour with your stress level.',
  kinds: {FaceKind.info, FaceKind.modern},
  accent: const Color(0xFFB388FF),
  build: (k) async {
    const steps = [0, 20, 40, 60, 80];
    const moods = [
      (Color(0xFF26C6DA), 'CALM'),
      (Color(0xFF66BB6A), 'RELAXED'),
      (Color(0xFFFFCA28), 'NORMAL'),
      (Color(0xFFFF7043), 'TENSE'),
      (Color(0xFFE53935), 'HIGH'),
    ];
    await k.background((c, s) => fill(c, s, const Color(0xFF000000)));
    await k.switcher(0, 90, 192, 260, FaceData.stress, steps, (c, s, i) {
      final (color, word) = moods[i];
      c.drawCircle(
        s.center(Offset.zero),
        96,
        Paint()
          ..shader = radial(
            s.center(Offset.zero),
            96,
            [color, color.withAlpha(120), const Color(0x00000000)],
            const [0, 0.55, 1],
          ),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: word,
          style: face(
            14,
            _white,
            family: mono,
            weight: FontWeight.w700,
            spacing: 4,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset((s.width - tp.width) / 2, s.height - 34));
    });
    final time = await k.fontDigits(face(60, _white, weight: FontWeight.w700));
    await k.clock(186, time, face(60, _white, weight: FontWeight.w700));
    await k.weekday(96, 40, _label(_grey), upper: true, center: true);
    final n = await k.fontDigits(face(22, _white, family: mono));
    await k.text(30, 380, 'STRESS', _label(_grey));
    k.number(30, 396, FaceData.stress, n, count: 3, zeros: false);
    await k.text(118, 380, 'BPM', _label(_grey));
    k.number(118, 396, FaceData.heartRate, n, count: 3, zeros: false);
  },
);

/// Sand runs out over each hour.
final hourglass = CustomFace(
  id: '960000059',
  name: 'Hourglass',
  blurb: 'Sand runs from top to bottom over every hour.',
  kinds: {FaceKind.animated, FaceKind.retro},
  accent: const Color(0xFFE8B86B),
  build: (k) async {
    const sand = Color(0xFFE8B86B),
        glass = Color(0xFF8FB3C7),
        wood = Color(0xFF6D4C33);
    await k.background((c, s) {
      gradient(c, s, const [Color(0xFF1A120B), Color(0xFF0B0805)]);
      c
        ..drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(36, 120, 120, 12),
            const Radius.circular(4),
          ),
          Paint()..color = wood,
        )
        ..drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(36, 428, 120, 12),
            const Radius.circular(4),
          ),
          Paint()..color = wood,
        );
    });
    Path bulb(bool top) {
      const l = 50.0, r = 142.0, neck = 96.0;
      final y0 = top ? 132.0 : 428.0, y1 = 280.0;
      return Path()
        ..moveTo(l, y0)
        ..lineTo(r, y0)
        ..quadraticBezierTo(r, (y0 + y1) / 2, neck + 4, y1)
        ..lineTo(neck - 4, y1)
        ..quadraticBezierTo(l, (y0 + y1) / 2, l, y0)
        ..close();
    }

    // Every 5 minutes the sand moves down a step.
    final marks = [for (var m = 0; m < 60; m += 5) m];
    await k.switcher(0, 0, 192, 440, FaceData.minute, marks, (c, s, i) {
      final done = (i + 1) / 13;
      for (final top in [true, false]) {
        final shape = bulb(top);
        c
          ..save()
          ..clipPath(shape);
        if (top) {
          final y = 140 + 140 * done;
          c.drawRect(Rect.fromLTRB(0, y, 192, 280), Paint()..color = sand);
        } else {
          final y = 428 - 140 * done;
          c.drawPath(
            Path()
              ..moveTo(40, 428)
              ..lineTo(96, y)
              ..lineTo(152, 428)
              ..close(),
            Paint()..color = sand,
          );
        }
        c
          ..restore()
          ..drawPath(
            shape,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = glass,
          );
      }
    });
    await k.animation(93, 280, 6, 140, 6, (c, s, t) {
      for (var y = -20.0 + t * 20; y < s.height; y += 20) {
        c.drawRect(Rect.fromLTWH(2, y, 2, 10), Paint()..color = sand);
      }
    }, intervalMs: 120);
    final time = await k.fontDigits(
      face(44, _white, family: serif, weight: FontWeight.w700),
    );
    await k.clock(
      40,
      time,
      face(44, sand, family: serif, weight: FontWeight.w700),
    );
    await k.weekday(
      96,
      456,
      face(12, sand, family: serif, weight: FontWeight.w400, spacing: 3),
      upper: true,
      center: true,
    );
  },
);

/// Falling blocks pile up as you near your step goal.
final stack = CustomFace(
  id: '960000060',
  name: 'Stack',
  blurb: 'Colourful blocks pile up as you get closer to your step goal.',
  kinds: {FaceKind.sport, FaceKind.retro, FaceKind.animated},
  accent: const Color(0xFF7C4DFF),
  build: (k) async {
    const palette = [
      Color(0xFF00BCD4),
      Color(0xFFFFEB3B),
      Color(0xFF7C4DFF),
      Color(0xFF4CAF50),
      Color(0xFFFF5252),
      Color(0xFFFF9800),
    ];
    const cell = 16.0, cols = 10, rows = 14;
    await k.background((c, s) {
      fill(c, s, const Color(0xFF0B0B14));
      c.drawRect(
        const Rect.fromLTWH(14, 186, 164, 228),
        Paint()..color = const Color(0xFF14142A),
      );
      final grid = Paint()..color = const Color(0xFF1B1B33);
      for (var x = 0; x <= cols; x++) {
        c.drawRect(Rect.fromLTWH(16 + x * cell, 188, 1, rows * cell), grid);
      }
    });
    final r = Seeded(60);
    final cells = [
      for (var i = 0; i < cols * rows; i++) palette[r.below(palette.length)],
    ];
    void block(Canvas c, Offset at, Color color) {
      c
        ..drawRect(
          Rect.fromLTWH(at.dx, at.dy, cell - 1, cell - 1),
          Paint()..color = color,
        )
        ..drawRect(
          Rect.fromLTWH(at.dx, at.dy, cell - 1, 3),
          Paint()..color = const Color(0x55FFFFFF),
        );
    }

    await k.switcher(
      16,
      188,
      160,
      224,
      FaceData.stepPercent,
      FaceKit.percentSteps(10),
      (c, s, i) {
        final filledRows = (i / 10 * (rows - 2)).round();
        for (var row = 0; row < filledRows; row++) {
          for (var col = 0; col < cols; col++) {
            // Leave a gap in each row so it looks like a game in progress.
            if ((col + row * 3) % 7 == 6) continue;
            block(
              c,
              Offset(col * cell, s.height - (row + 1) * cell),
              cells[row * cols + col],
            );
          }
        }
      },
    );
    await k.animation(16, 188, 160, 64, 8, (c, s, t) {
      final y = t * 48;
      final x = 4 * cell;
      for (final (dx, dy) in [(0, 0), (1, 0), (2, 0), (1, 1)]) {
        block(c, Offset(x + dx * cell, y + dy * cell), const Color(0xFFFF4081));
      }
    }, intervalMs: 250);
    final time = await k.paintedDigits(
      20,
      28,
      (c, s, d) => paintDotMatrix(
        c,
        s,
        d,
        _white,
        const Color(0xFF1B1B33),
        square: true,
      ),
    );
    k.number(
      96 - (4 * 20 + 3 * 4 + 12) ~/ 2,
      60,
      FaceData.hour,
      time,
      spacing: 4,
    );
    k.number(96 + 6 + 2, 60, FaceData.minute, time, spacing: 4);
    await k.weekday(96, 118, _label(_grey), upper: true, center: true);
    final n = await k.fontDigits(
      face(18, _white, family: mono, weight: FontWeight.w700),
    );
    await k.text(16, 428, 'STEPS', _label(const Color(0xFF7C4DFF)));
    k.number(16, 444, FaceData.steps, n, count: 5, zeros: false);
    await k.text(118, 428, 'GOAL %', _label(const Color(0xFF7C4DFF)));
    k.number(118, 444, FaceData.stepPercent, n, count: 3, zeros: false);
  },
);
