/// Faces 41–45: Almanac, Typewriter, Circuit, Firefly, Charge.
library;

import 'package:openwear/faces/designs/common.dart';

const _white = Color(0xFFF4F1EA), _grey = Color(0xFF6E6A63);

TextStyle _label(Color c) =>
    face(10, c, family: mono, weight: FontWeight.w500, spacing: 1.5);

/// Everything at a glance: date, weather, steps, heart, sleep, stress.
final almanac = CustomFace(
  id: '960000041',
  name: 'Almanac',
  blurb: 'Date, weather, steps, heart, stress and sleep at a glance.',
  kinds: {FaceKind.info},
  accent: const Color(0xFF80CBC4),
  build: (k) async {
    const teal = Color(0xFF80CBC4), card = Color(0xFF15191A);
    await k.background((c, s) {
      fill(c, s, const Color(0xFF000000));
      for (var i = 0; i < 6; i++) {
        final r = Rect.fromLTWH(
          i.isEven ? 8 : 100,
          190 + (i ~/ 2) * 74.0,
          84,
          66,
        );
        c.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(12)),
          Paint()..color = card,
        );
      }
    });
    final time = await k.fontDigits(face(56, _white, weight: FontWeight.w700));
    await k.clock(30, time, face(56, teal, weight: FontWeight.w700));
    await k.weekday(
      20,
      104,
      face(13, teal, weight: FontWeight.w700),
      upper: true,
    );
    final small = await k.fontDigits(face(13, _white, weight: FontWeight.w700));
    k.number(70, 104, FaceData.day, small);
    await k.month(
      96,
      104,
      face(13, _grey, weight: FontWeight.w700),
      upper: true,
    );
    await k.weather(20, 130, 36, _white);
    final temp = await k.fontDigits(face(30, _white, weight: FontWeight.w500));
    k.number(66, 134, FaceData.temperature, temp, zeros: false);
    await k.text(
      66 + two(temp),
      134,
      '°',
      face(30, _grey, weight: FontWeight.w500),
    );
    final n = await k.fontDigits(
      face(22, _white, family: mono, weight: FontWeight.w500),
    );
    const cells = [
      ('STEPS', FaceData.steps, 5, Color(0xFFFFB74D)),
      ('BPM', FaceData.heartRate, 3, Color(0xFFFF5252)),
      ('KCAL', FaceData.calories, 4, Color(0xFFFF8A65)),
      ('STRESS', FaceData.stress, 3, Color(0xFFB39DDB)),
      ('SLEEP', FaceData.sleepScore, 3, Color(0xFF7986CB)),
      ('STAND', FaceData.standCount, 2, Color(0xFF81C784)),
    ];
    for (var i = 0; i < cells.length; i++) {
      final (name, src, count, color) = cells[i];
      final x = i.isEven ? 18 : 110, y = 200 + (i ~/ 2) * 74;
      await k.text(x, y, name, _label(color));
      k.number(x, y + 22, src, n, count: count, zeros: false);
    }
  },
);

/// Typewritten time on a sheet of paper.
final typewriter = CustomFace(
  id: '960000042',
  name: 'Typewriter',
  blurb: 'Typed on paper, with a blinking cursor.',
  kinds: {FaceKind.retro, FaceKind.animated},
  accent: const Color(0xFFEDE3CC),
  build: (k) async {
    const paper = Color(0xFFEDE3CC), ink = Color(0xFF2B2622);
    await k.background((c, s) {
      fill(c, s, const Color(0xFF1C1A17));
      c.drawRect(const Rect.fromLTWH(12, 40, 168, 420), Paint()..color = paper);
      final rule = Paint()..color = const Color(0xFFD6C9AC);
      for (var y = 80.0; y < 460; y += 24) {
        c.drawRect(Rect.fromLTWH(12, y, 168, 1), rule);
      }
      c.drawRect(
        const Rect.fromLTWH(36, 40, 1, 420),
        Paint()..color = const Color(0xFFE57373),
      );
    });
    final type = face(15, ink, family: mono, weight: FontWeight.w500);
    await k.text(44, 62, 'Dear wearer,', type);
    await k.text(44, 110, 'it is now', type);
    final d = await k.fontDigits(
      face(40, ink, family: mono, weight: FontWeight.w700),
    );
    await k.clock(
      140,
      d,
      face(40, ink, family: mono, weight: FontWeight.w700),
      gap: 0,
      x: 40,
    );
    await k.text(44, 214, 'on', type);
    await k.weekday(70, 214, type);
    final n = await k.fontDigits(type);
    await k.text(44, 262, 'You walked', type);
    k.number(44, 286, FaceData.steps, n, count: 5, zeros: false);
    await k.text(100, 286, 'steps.', type);
    await k.text(44, 334, 'Battery is', type);
    k.number(44, 358, FaceData.battery, n, count: 3, zeros: false);
    await k.text(76, 358, '%.', type);
    await k.animation(44, 400, 10, 18, 2, (c, s, t) {
      if (t < 0.5) fill(c, s, ink);
    }, intervalMs: 500);
  },
);

/// Traces on a circuit board, with pulses running along them.
final circuit = CustomFace(
  id: '960000043',
  name: 'Circuit',
  blurb: 'Circuit board traces with signals running along them.',
  kinds: {FaceKind.animated, FaceKind.modern},
  accent: const Color(0xFF00E676),
  build: (k) async {
    const board = Color(0xFF04140B),
        trace = Color(0xFF0E4D2B),
        lit = Color(0xFF00E676);
    final paths = [
      [
        const Offset(0, 40),
        const Offset(60, 40),
        const Offset(80, 60),
        const Offset(192, 60),
      ],
      [
        const Offset(20, 0),
        const Offset(20, 90),
        const Offset(50, 120),
        const Offset(50, 330),
      ],
      [
        const Offset(192, 360),
        const Offset(120, 360),
        const Offset(100, 380),
        const Offset(100, 490),
      ],
      [
        const Offset(0, 440),
        const Offset(70, 440),
        const Offset(90, 420),
        const Offset(170, 420),
        const Offset(170, 340),
      ],
    ];
    Path toPath(List<Offset> pts) {
      final p = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final o in pts.skip(1)) {
        p.lineTo(o.dx, o.dy);
      }
      return p;
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = trace;
    await k.background((c, s) {
      fill(c, s, board);
      for (final pts in paths) {
        c.drawPath(toPath(pts), stroke);
        for (final o in [pts.first, pts.last]) {
          c.drawCircle(o, 5, Paint()..color = trace);
          c.drawCircle(o, 2, Paint()..color = board);
        }
      }
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(56, 130, 132, 190),
          const Radius.circular(6),
        ),
        Paint()..color = const Color(0xFF111111),
      );
    });
    final metrics = [
      for (final pts in paths) toPath(pts).computeMetrics().first,
    ];
    await k.animation(0, 0, 192, 490, 10, (c, s, t) {
      for (var i = 0; i < metrics.length; i++) {
        final m = metrics[i];
        final at = m.length * ((t + i / 4) % 1);
        c.drawPath(
          m.extractPath(at, at + 24),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = lit,
        );
      }
    }, intervalMs: 120);
    final d = await k.fontDigits(
      face(70, lit, family: mono, weight: FontWeight.w700),
    );
    k.number(122 - two(d) ~/ 2, 150, FaceData.hour, d);
    k.number(122 - two(d) ~/ 2, 230, FaceData.minute, d);
  },
);

/// Fireflies drifting over a dusk meadow.
final firefly = CustomFace(
  id: '960000044',
  name: 'Firefly',
  blurb: 'Fireflies drift and glow over a meadow at dusk.',
  kinds: {FaceKind.animated},
  accent: const Color(0xFFFFEB3B),
  build: (k) async {
    await k.background((c, s) {
      gradient(
        c,
        s,
        const [Color(0xFF0B1030), Color(0xFF1B2440), Color(0xFF0A1A0E)],
        const [0, 0.6, 1],
      );
      final grass = Paint()
        ..color = const Color(0xFF0F2A14)
        ..strokeWidth = 2;
      final r = Seeded(44);
      for (var i = 0; i < 90; i++) {
        final x = r.next() * 192;
        c.drawLine(
          Offset(x, 490),
          Offset(x + r.next() * 10 - 5, 400 + r.next() * 50),
          grass,
        );
      }
    });
    final r = Seeded(4);
    final flies = [
      for (var i = 0; i < 9; i++)
        (r.next() * 172 + 10, r.next() * 160 + 280, r.next()),
    ];
    await k.animation(0, 260, 192, 230, 8, (c, s, t) {
      for (final (x, y, phase) in flies) {
        final a = (t + phase) * 2 * pi;
        final glow = 0.5 + 0.5 * sin(a);
        final o = Offset(x + 8 * sin(a / 2), y - 260 + 6 * cos(a));
        c
          ..drawCircle(
            o,
            6,
            Paint()..color = Color.fromARGB((90 * glow).round(), 255, 235, 59),
          )
          ..drawCircle(
            o,
            2,
            Paint()
              ..color = Color.lerp(
                const Color(0xFF5A5320),
                const Color(0xFFFFF59D),
                glow,
              )!,
          );
      }
    }, intervalMs: 200);
    final time = await k.fontDigits(
      face(64, _white, family: serif, weight: FontWeight.w400),
    );
    await k.clock(
      80,
      time,
      face(64, const Color(0xFFFFEB3B), family: serif, weight: FontWeight.w400),
    );
    await k.weekday(
      96,
      166,
      face(
        14,
        const Color(0xFFC5CAE9),
        family: serif,
        weight: FontWeight.w400,
        spacing: 2,
      ),
      center: true,
    );
  },
);

/// A giant battery that shows the band's charge.
final charge = CustomFace(
  id: '960000045',
  name: 'Charge',
  blurb: 'A big battery gauge so you always know the charge.',
  kinds: {FaceKind.info, FaceKind.modern},
  accent: const Color(0xFF69F0AE),
  build: (k) async {
    const green = Color(0xFF69F0AE);
    final time = await k.fontDigits(face(50, _white, weight: FontWeight.w700));
    await k.clock(30, time, face(50, _grey, weight: FontWeight.w700));
    await k.image(
      66,
      128,
      60,
      10,
      (c, s) => c.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(3)),
        Paint()..color = _grey,
      ),
    );
    await k.switcher(
      36,
      138,
      120,
      250,
      FaceData.battery,
      FaceKit.percentSteps(10),
      (c, s, i) {
        final body = RRect.fromRectAndRadius(
          Offset.zero & s,
          const Radius.circular(18),
        );
        c.drawRRect(
          body.deflate(2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = _grey,
        );
        final color = i <= 2
            ? const Color(0xFFFF5252)
            : (i <= 4 ? const Color(0xFFFFD740) : green);
        final h = (s.height - 20) * i / 10;
        if (h > 0) {
          c.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(10, s.height - 10 - h, s.width - 20, h),
              const Radius.circular(10),
            ),
            Paint()..color = color,
          );
        }
      },
    );
    final pct = await k.fontDigits(face(40, _white, weight: FontWeight.w700));
    k.number(
      96 - FaceKit.numberWidth(pct, 3) ~/ 2,
      410,
      FaceData.battery,
      pct,
      count: 3,
      zeros: false,
    );
    await k.text(
      96 + FaceKit.numberWidth(pct, 3) ~/ 2,
      420,
      '%',
      face(24, _grey, weight: FontWeight.w700),
    );
  },
);
