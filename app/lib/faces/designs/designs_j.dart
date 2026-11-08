/// Faces 46–50: Glitch, Pendulum, Forecast, Ticker, Hairline.
library;

import 'package:openwear/faces/designs/common.dart';

const _white = Color(0xFFF4F1EA), _grey = Color(0xFF6E6A63);

TextStyle _label(Color c) =>
    face(10, c, family: mono, weight: FontWeight.w500, spacing: 1.5);

/// Digital glitch bars sweep across the screen.
final glitch = CustomFace(
  id: '960000046',
  name: 'Glitch',
  blurb: 'Split-colour numerals with digital glitches.',
  kinds: {FaceKind.animated, FaceKind.modern},
  accent: const Color(0xFFFF1744),
  build: (k) async {
    final hour = await k.fontDigits(
      face(
        100,
        _white,
        weight: FontWeight.w700,
        shadows: const [
          Shadow(color: Color(0xFFFF1744), offset: Offset(-3, 0)),
          Shadow(color: Color(0xFF00E5FF), offset: Offset(3, 0)),
        ],
      ),
      extraWidth: 6,
    );
    k.number((192 - two(hour)) ~/ 2, 100, FaceData.hour, hour);
    k.number((192 - two(hour)) ~/ 2, 214, FaceData.minute, hour);
    await k.animation(0, 340, 192, 60, 8, (c, s, t) {
      final r = Seeded((t * 8).round() + 1);
      for (var i = 0; i < 5; i++) {
        final y = r.next() * s.height;
        c.drawRect(
          Rect.fromLTWH(
            r.next() * 120,
            y,
            20 + r.next() * 80,
            2 + r.next() * 4,
          ),
          Paint()
            ..color = i.isEven
                ? const Color(0xFFFF1744)
                : const Color(0xFF00E5FF),
        );
      }
    }, intervalMs: 140);
    await k.weekday(20, 420, _label(const Color(0xFF00E5FF)), upper: true);
    final n = await k.fontDigits(_label(_white).copyWith(fontSize: 12));
    k.number(130, 419, FaceData.battery, n, count: 3, zeros: false);
    await k.text(160, 420, '%', _label(_grey));
  },
);

/// A brass pendulum swings under the time.
final pendulum = CustomFace(
  id: '960000047',
  name: 'Pendulum',
  blurb: 'A brass pendulum swings beneath the time.',
  kinds: {FaceKind.animated, FaceKind.retro},
  accent: const Color(0xFFD4A04C),
  build: (k) async {
    const brass = Color(0xFFD4A04C), wood = Color(0xFF2A1A10);
    await k.background((c, s) {
      gradient(c, s, const [Color(0xFF3B2416), wood]);
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(14, 210, 164, 260),
          const Radius.circular(80),
        ),
        Paint()..color = const Color(0xFF140C07),
      );
    });
    final time = await k.fontDigits(
      face(56, const Color(0xFFF3E2C0), family: serif, weight: FontWeight.w700),
    );
    await k.clock(
      60,
      time,
      face(56, brass, family: serif, weight: FontWeight.w700),
    );
    await k.weekday(
      96,
      140,
      face(14, brass, family: serif, weight: FontWeight.w400, spacing: 2),
      center: true,
    );
    await k.animation(14, 210, 164, 260, 12, (c, s, t) {
      final a = 0.35 * sin(t * 2 * pi);
      const pivot = Offset(82, 10);
      final bob = pivot + Offset(sin(a), cos(a)) * 200;
      c
        ..drawLine(
          pivot,
          bob,
          Paint()
            ..color = brass
            ..strokeWidth = 3,
        )
        ..drawCircle(bob, 22, Paint()..color = brass)
        ..drawCircle(
          bob - const Offset(6, 6),
          7,
          Paint()..color = const Color(0xFFF1D08A),
        )
        ..drawCircle(pivot, 5, Paint()..color = brass);
    }, intervalMs: 90);
  },
);

/// Weather first: a big icon and temperature.
final forecast = CustomFace(
  id: '960000048',
  name: 'Forecast',
  blurb: 'A big weather icon and temperature, then the time.',
  kinds: {FaceKind.info},
  accent: const Color(0xFF64B5F6),
  build: (k) async {
    await k.background(
      (c, s) => gradient(
        c,
        s,
        const [Color(0xFF0D47A1), Color(0xFF000000)],
        const [0, 0.6],
      ),
    );
    await k.weather(46, 40, 100, _white);
    final temp = await k.fontDigits(face(80, _white, weight: FontWeight.w400));
    final w = FaceKit.numberWidth(temp, 2);
    k.number(
      (192 - w) ~/ 2 - 10,
      156,
      FaceData.temperature,
      temp,
      zeros: false,
    );
    await k.text(
      (192 + w) ~/ 2 - 8,
      160,
      '°',
      face(48, _white, weight: FontWeight.w400),
    );
    final time = await k.fontDigits(face(48, _white, weight: FontWeight.w700));
    await k.clock(
      290,
      time,
      face(48, const Color(0xFF64B5F6), weight: FontWeight.w700),
    );
    await k.weekday(
      96,
      360,
      _label(const Color(0xFF90CAF9)),
      upper: true,
      center: true,
    );
    final n = await k.fontDigits(
      face(16, _white, family: mono, weight: FontWeight.w500),
    );
    await k.text(30, 400, 'STEPS', _label(_grey));
    k.number(30, 416, FaceData.steps, n, count: 5, zeros: false);
    await k.text(118, 400, 'BPM', _label(_grey));
    k.number(118, 416, FaceData.heartRate, n, count: 3, zeros: false);
  },
);

/// A stock-ticker board of your day.
final ticker = CustomFace(
  id: '960000049',
  name: 'Ticker',
  blurb: 'Your day as a market board, with a scrolling ticker.',
  kinds: {FaceKind.info, FaceKind.animated},
  accent: const Color(0xFF00C853),
  build: (k) async {
    const up = Color(0xFF00C853), amber = Color(0xFFFFC400);
    await k.background((c, s) {
      fill(c, s, const Color(0xFF050505));
      final line = Paint()..color = const Color(0xFF1E1E1E);
      for (var y = 160.0; y <= 400; y += 48) {
        c.drawRect(Rect.fromLTWH(10, y, 172, 1), line);
      }
    });
    final time = await k.fontDigits(
      face(48, amber, family: mono, weight: FontWeight.w700),
    );
    await k.clock(
      40,
      time,
      face(48, amber, family: mono, weight: FontWeight.w700),
      gap: 0,
    );
    await k.weekday(96, 104, _label(_grey), upper: true, center: true);
    final n = await k.fontDigits(
      face(20, _white, family: mono, weight: FontWeight.w700),
    );
    const rows = [
      ('STP', FaceData.steps, 5),
      ('CAL', FaceData.calories, 4),
      ('BPM', FaceData.heartRate, 3),
      ('STR', FaceData.stress, 3),
      ('BAT', FaceData.battery, 3),
    ];
    for (var i = 0; i < rows.length; i++) {
      final (name, src, count) = rows[i];
      final y = 128 + i * 48;
      await k.text(
        14,
        y + 4,
        name,
        face(16, up, family: mono, weight: FontWeight.w700),
      );
      await k.text(
        58,
        y + 6,
        '▲',
        face(12, up, family: mono, weight: FontWeight.w700),
      );
      k.number(
        178 - FaceKit.numberWidth(n, count),
        y + 2,
        src,
        n,
        count: count,
        zeros: false,
      );
    }
    const tape = 'OPENWEAR  ▲ STEPS  ▲ HEART  ▲ SLEEP  ▲ ';
    final tp = TextPainter(
      text: TextSpan(
        text: tape * 2,
        style: face(12, amber, family: mono, weight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final period = tp.width / 2;
    await k.animation(0, 440, 192, 18, 12, (c, s, t) {
      tp.paint(c, Offset(-t * period, 2));
    }, intervalMs: 160);
  },
);

/// Thin numerals and a single line, nothing else.
final hairline = CustomFace(
  id: '960000050',
  name: 'Hairline',
  blurb: 'Thin numerals and one line that tracks your steps.',
  kinds: {FaceKind.modern},
  accent: const Color(0xFFFFFFFF),
  build: (k) async {
    final d = await k.fontDigits(face(120, _white, weight: FontWeight.w300));
    k.number((192 - two(d)) ~/ 2, 90, FaceData.hour, d);
    k.number((192 - two(d)) ~/ 2, 220, FaceData.minute, d);
    await k.switcher(
      20,
      380,
      152,
      2,
      FaceData.stepPercent,
      FaceKit.percentSteps(5),
      (c, s, i) =>
          bar(c, s, i / 20, _white, const Color(0xFF2A2A2A), radius: 1),
    );
    await k.weekday(20, 396, _label(_grey), upper: true);
    final n = await k.fontDigits(_label(_grey).copyWith(fontSize: 12));
    k.number(172 - two(n), 395, FaceData.day, n);
  },
);
