/// Faces 16–20: Synthwave, Bauhaus, Breathe, Binary, Constellation.
library;

import 'package:openwear/faces/designs/common.dart';

const _white = Color(0xFFF4F1EA), _grey = Color(0xFF6E6A63);

/// A striped sun over a scrolling neon grid.
final synthwave = CustomFace(
  id: '960000016',
  name: 'Synthwave',
  blurb: 'Striped sun over a neon grid rolling towards you.',
  kinds: {FaceKind.animated, FaceKind.retro},
  accent: const Color(0xFFFF4FD8),
  build: (k) async {
    const magenta = Color(0xFFFF4FD8), horizon = 320.0;
    await k.background((c, s) {
      gradient(
        c,
        s,
        const [Color(0xFF0B0221), Color(0xFF3A0B4F), Color(0xFF8C1E5E)],
        const [0, 0.5, 0.65],
      );
      c.drawRect(
        const Rect.fromLTWH(0, horizon, 192, 170),
        Paint()..color = const Color(0xFF0A0118),
      );
      final sun = Rect.fromCircle(
        center: const Offset(96, horizon - 6),
        radius: 62,
      );
      c
        ..save()
        ..clipRect(const Rect.fromLTWH(0, 0, 192, horizon))
        ..drawCircle(
          sun.center,
          62,
          Paint()
            ..shader = linear(sun.topCenter, sun.bottomCenter, const [
              Color(0xFFFFE45E),
              Color(0xFFFF4F7B),
            ]),
        );
      for (var i = 0; i < 6; i++) {
        final y = horizon - 44 + i * 9.0;
        c.drawRect(
          Rect.fromLTWH(0, y, 192, 2.0 + i),
          Paint()..color = const Color(0xFF6E1559),
        );
      }
      c.restore();
    });
    await k.animation(0, horizon.toInt(), 192, 170, 8, (c, s, t) {
      final p = Paint()
        ..color = magenta
        ..strokeWidth = 1.4;
      for (var i = -8; i <= 8; i++) {
        c.drawLine(Offset(96 + i * 6.0, 0), Offset(96 + i * 60.0, s.height), p);
      }
      for (var i = 0; i < 8; i++) {
        final z = (i + t) / 8;
        final y = s.height * z * z;
        c.drawLine(
          Offset(0, y),
          Offset(192, y),
          p..color = magenta.withAlpha((80 + 175 * z).toInt()),
        );
      }
    }, intervalMs: 90);
    final chrome = TextStyle(
      fontFamily: grotesk,
      fontSize: 58,
      fontWeight: FontWeight.w700,
      height: 1,
      foreground: Paint()
        ..shader = linear(
          Offset.zero,
          const Offset(0, 58),
          const [
            Color(0xFFE8F6FF),
            Color(0xFF7FD3FF),
            Color(0xFF2B2E83),
            Color(0xFFFF9FE8),
          ],
          const [0, 0.48, 0.52, 1],
        ),
    );
    final time = await k.fontDigits(chrome);
    await k.clock(74, time, face(58, magenta));
    await k.weekday(
      96,
      156,
      face(14, magenta, family: mono, weight: FontWeight.w700, spacing: 4),
      upper: true,
      center: true,
    );
  },
);

/// Primary shapes and a condensed grotesque.
final bauhaus = CustomFace(
  id: '960000017',
  name: 'Bauhaus',
  blurb: 'Primary shapes and bold condensed numerals.',
  kinds: {FaceKind.modern},
  accent: const Color(0xFFE63B2E),
  build: (k) async {
    const red = Color(0xFFE63B2E),
        blue = Color(0xFF1F4CC9),
        yellow = Color(0xFFF2B630),
        ink = Color(0xFF141414),
        paper = Color(0xFFEFE8DA);
    await k.background((c, s) {
      fill(c, s, paper);
      c
        ..drawCircle(const Offset(150, 92), 54, Paint()..color = red)
        ..drawRect(const Rect.fromLTWH(118, 262, 74, 74), Paint()..color = blue)
        ..drawArc(
          const Rect.fromLTWH(92, 342, 200, 200),
          pi,
          pi / 2,
          true,
          Paint()..color = yellow,
        )
        ..drawRect(const Rect.fromLTWH(16, 230, 160, 6), Paint()..color = ink);
    });
    final big = await k.fontDigits(face(118, ink, family: condensed));
    k.number(14, 96, FaceData.hour, big);
    final big2 = await k.fontDigits(face(118, ink, family: condensed));
    k.number(14, 246, FaceData.minute, big2);
    await k.weekday(
      16,
      40,
      face(16, ink, family: condensed, spacing: 1),
      upper: true,
    );
    final d = await k.fontDigits(face(16, ink, family: condensed));
    k.number(16, 60, FaceData.day, d);
    await k.month(
      16 + two(d) + 4,
      60,
      face(16, ink, family: condensed),
      upper: true,
    );
    final steps = await k.fontDigits(
      face(14, ink, family: mono, weight: FontWeight.w700),
    );
    k.number(16, 420, FaceData.steps, steps, count: 5, zeros: false);
  },
);

/// Rings that grow and fade at a calm breathing pace.
final breathe = CustomFace(
  id: '960000018',
  name: 'Breathe',
  blurb: 'Slow expanding rings to breathe along with.',
  kinds: {FaceKind.animated, FaceKind.modern},
  accent: const Color(0xFF7FE0D0),
  build: (k) async {
    const teal = Color(0xFF7FE0D0);
    final time = await k.fontDigits(face(40, _white, weight: FontWeight.w400));
    await k.clock(44, time, face(40, teal, weight: FontWeight.w400));
    await k.animation(0, 130, 192, 192, 20, (c, s, t) {
      final mid = s.center(Offset.zero);
      for (var r = 0; r < 3; r++) {
        final phase = (t + r / 3) % 1;
        c.drawCircle(
          mid,
          16 + phase * 76,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 + 6 * (1 - phase)
            ..color = teal.withAlpha((220 * (1 - phase)).toInt()),
        );
      }
      final core = 18 + 8 * sin(t * 2 * pi);
      c.drawCircle(mid, core, Paint()..color = teal);
    }, intervalMs: 200);
    final label = face(
      10,
      _grey,
      family: mono,
      weight: FontWeight.w500,
      spacing: 1.5,
    );
    final n = await k.fontDigits(face(26, _white, weight: FontWeight.w500));
    await k.text(48, 360, 'PULSE', label, centerX: true);
    k.number(
      48 - FaceKit.numberWidth(n, 3) ~/ 2,
      378,
      FaceData.heartRate,
      n,
      count: 3,
      zeros: false,
    );
    await k.text(144, 360, 'STRESS', label, centerX: true);
    k.number(
      144 - FaceKit.numberWidth(n, 3) ~/ 2,
      378,
      FaceData.stress,
      n,
      count: 3,
      zeros: false,
    );
    await k.weekday(
      96,
      432,
      label.copyWith(color: teal),
      upper: true,
      center: true,
    );
  },
);

/// Hours and minutes as lit bits.
final binary = CustomFace(
  id: '960000019',
  name: 'Binary',
  blurb: 'Read the time in bits: 8, 4, 2, 1.',
  kinds: {FaceKind.modern, FaceKind.retro},
  accent: const Color(0xFF34C6FF),
  build: (k) async {
    const blue = Color(0xFF34C6FF), off = Color(0xFF14232B);
    const cols = [
      (FaceData.hourHigh, 2),
      (FaceData.hourLow, 4),
      (FaceData.minuteHigh, 3),
      (FaceData.minuteLow, 4),
    ];
    final label = face(11, _grey, family: mono, weight: FontWeight.w500);
    for (var b = 0; b < 4; b++) {
      await k.text(14, 108 + b * 44 + 12, '${8 >> b}', label);
    }
    for (var col = 0; col < cols.length; col++) {
      final (source, bits) = cols[col];
      final x = 40 + col * 38 + (col >= 2 ? 6 : 0);
      await k.switcher(
        x,
        104,
        32,
        4 * 44,
        source,
        List.generate(
          bits == 2
              ? 3
              : bits == 3
              ? 6
              : 10,
          (i) => i,
        ),
        (c, s, v) {
          for (var b = 0; b < 4; b++) {
            final bit = 3 - b;
            if (bit >= bits) continue;
            final lit = v >> bit & 1 == 1;
            c.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(2, b * 44.0 + 6, 28, 28),
                const Radius.circular(8),
              ),
              Paint()..color = lit ? blue : off,
            );
          }
        },
      );
    }
    await k.text(59, 290, 'H', label, centerX: true);
    await k.text(141, 290, 'M', label, centerX: true);
    final time = await k.fontDigits(
      face(18, _grey, family: mono, weight: FontWeight.w500),
    );
    final w = two(time);
    k.number(96 - w - 6, 340, FaceData.hour, time);
    await k.text(
      96,
      340,
      ':',
      face(18, _grey, family: mono, weight: FontWeight.w500),
      centerX: true,
    );
    k.number(96 + 6, 340, FaceData.minute, time);
    await k.weekday(
      96,
      400,
      face(13, blue, family: mono, weight: FontWeight.w500, spacing: 3),
      upper: true,
      center: true,
    );
  },
);

/// Twinkling stars joined into a constellation.
final constellation = CustomFace(
  id: '960000020',
  name: 'Constellation',
  blurb: 'Twinkling stars joined by faint lines.',
  kinds: {FaceKind.animated, FaceKind.modern},
  accent: const Color(0xFFB9C7FF),
  build: (k) async {
    const star = Color(0xFFDDE4FF);
    final r = Seeded(20);
    final stars = [
      for (var i = 0; i < 60; i++) Offset(r.next() * 192, r.next() * 300),
    ];
    final sizes = [for (var i = 0; i < 60; i++) 0.4 + r.next() * 1.2];
    const shape = [
      Offset(30, 60),
      Offset(70, 40),
      Offset(112, 74),
      Offset(150, 52),
      Offset(132, 130),
      Offset(84, 150),
      Offset(112, 74),
    ];
    await k.background((c, s) {
      gradient(
        c,
        s,
        const [Color(0xFF0A0F26), Color(0xFF000000)],
        const [0, 0.7],
      );
      final line = Paint()
        ..color = star.withAlpha(70)
        ..strokeWidth = 1;
      for (var i = 0; i + 1 < shape.length; i++) {
        c.drawLine(
          shape[i] + const Offset(0, 40),
          shape[i + 1] + const Offset(0, 40),
          line,
        );
      }
      for (final p in shape) {
        c.drawCircle(p + const Offset(0, 40), 3, Paint()..color = star);
      }
    });
    await k.animation(0, 0, 192, 300, 8, (c, s, t) {
      for (var i = 0; i < stars.length; i++) {
        final twinkle = 0.5 + 0.5 * sin(t * 2 * pi + i * 1.7);
        c.drawCircle(
          stars[i],
          sizes[i] * (0.7 + 0.6 * twinkle),
          Paint()..color = star.withAlpha((60 + 195 * twinkle).toInt()),
        );
      }
    }, intervalMs: 180);
    final time = await k.fontDigits(face(56, _white, weight: FontWeight.w400));
    final (left, total) = await k.clock(
      300,
      time,
      face(56, _grey, weight: FontWeight.w400),
    );
    await k.weekday(
      left,
      392,
      face(
        14,
        const Color(0xFFB9C7FF),
        family: mono,
        weight: FontWeight.w500,
        spacing: 2,
      ),
      upper: true,
    );
    final d = await k.fontDigits(
      face(14, _white, family: mono, weight: FontWeight.w500),
    );
    k.number(left + total - two(d), 392, FaceData.day, d);
  },
);
