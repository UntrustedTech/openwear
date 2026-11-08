/// Faces 51–55: Bezel, Sweep, Daylight, Buddy, Bloom.
/// Each one changes with the time or your day, not just its numbers.
library;

import 'package:openwear/faces/designs/common.dart';

const _white = Color(0xFFF4F1EA), _grey = Color(0xFF6E6A63);

TextStyle _label(Color c) =>
    face(10, c, family: mono, weight: FontWeight.w500, spacing: 1.5);

List<int> _range(int from, int to, [int step = 1]) => [
  for (var v = from; v <= to; v += step) v,
];

void _centred(Canvas c, Offset at, String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
}

/// A minute ring that turns under a fixed pointer; the hour sits inside.
final bezel = CustomFace(
  id: '960000051',
  name: 'Bezel',
  blurb: 'A dive-watch bezel that turns with every minute.',
  kinds: {FaceKind.modern, FaceKind.sport},
  accent: const Color(0xFFFF7A1A),
  build: (k) async {
    const orange = Color(0xFFFF7A1A), steel = Color(0xFF9AA3AD);
    await k.background((c, s) {
      fill(c, s, const Color(0xFF05080B));
      c.drawCircle(
        const Offset(96, 200),
        92,
        Paint()..color = const Color(0xFF151B22),
      );
      // Fixed pointer at 12 o'clock.
      c.drawPath(
        Path()
          ..moveTo(88, 98)
          ..lineTo(104, 98)
          ..lineTo(96, 112)
          ..close(),
        Paint()..color = orange,
      );
    });
    const r = 78.0, size = 184;
    await k.switcher(4, 108, size, size, FaceData.minute, _range(0, 59), (
      c,
      s,
      m,
    ) {
      final centre = s.center(Offset.zero);
      for (var i = 0; i < 60; i++) {
        // Minute m sits under the pointer at the top.
        final a = -pi / 2 + (i - m) * 2 * pi / 60;
        final dir = Offset(cos(a), sin(a));
        final major = i % 5 == 0;
        c.drawLine(
          centre + dir * (r - (major ? 12 : 6)),
          centre + dir * r,
          Paint()
            ..color = i == m ? orange : (major ? _white : steel)
            ..strokeWidth = major ? 3 : 1.5,
        );
        if (i % 15 == 0) {
          _centred(
            c,
            centre + dir * (r - 24),
            '$i',
            face(13, i == m ? orange : _white, family: mono),
          );
        }
      }
    });
    final hour = await k.fontDigits(face(64, _white, weight: FontWeight.w700));
    k.number((192 - two(hour)) ~/ 2, 168, FaceData.hour, hour);
    final small = await k.fontDigits(face(26, orange, family: mono));
    k.number(96 - two(small) ~/ 2, 300, FaceData.minute, small);
    await k.text(96, 330, 'MIN', _label(steel), centerX: true);
    await k.weekday(96, 352, _label(steel), upper: true, center: true);
    final n = await k.fontDigits(face(22, _white, family: mono));
    await k.text(24, 386, 'STEPS', _label(orange));
    k.number(24, 402, FaceData.steps, n, count: 5, zeros: false);
    await k.text(122, 386, 'BPM', _label(orange));
    k.number(122, 402, FaceData.heartRate, n, count: 3, zeros: false);
  },
);

/// A seconds hand of light runs round the time, tick by tick.
final sweep = CustomFace(
  id: '960000052',
  name: 'Sweep',
  blurb: 'A ring of sixty lights ticks round with the seconds.',
  kinds: {FaceKind.animated, FaceKind.modern},
  accent: const Color(0xFF00E5FF),
  build: (k) async {
    const cyan = Color(0xFF00E5FF);
    await k.background((c, s) {
      fill(c, s, const Color(0xFF000000));
      for (var i = 0; i < 60; i++) {
        final a = -pi / 2 + i * 2 * pi / 60;
        c.drawCircle(
          const Offset(96, 200) + Offset(cos(a), sin(a)) * 84,
          i % 5 == 0 ? 2.6 : 1.6,
          Paint()..color = const Color(0xFF1E2A2E),
        );
      }
    });
    await k.switcher(4, 108, 184, 184, FaceData.second, _range(0, 59), (
      c,
      s,
      sec,
    ) {
      final centre = s.center(Offset.zero);
      // The current second and a fading tail behind it.
      for (var back = 0; back < 8; back++) {
        final i = sec - back;
        final a = -pi / 2 + i * 2 * pi / 60;
        c.drawCircle(
          centre + Offset(cos(a), sin(a)) * 84,
          back == 0 ? 4.5 : 3.0 - back * 0.25,
          Paint()..color = cyan.withAlpha(255 - back * 30),
        );
      }
    });
    final time = await k.fontDigits(face(52, _white, weight: FontWeight.w500));
    await k.clock(172, time, face(52, cyan, weight: FontWeight.w500));
    await k.weekday(96, 238, _label(_grey), upper: true, center: true);
    final n = await k.fontDigits(face(18, _white, family: mono));
    await k.text(30, 340, 'STEPS', _label(cyan));
    k.number(30, 356, FaceData.steps, n, count: 5, zeros: false);
    await k.text(118, 340, 'BATT', _label(cyan));
    k.number(118, 356, FaceData.battery, n, count: 3, zeros: false);
  },
);

/// Sky colours for each hour: night, dawn, day, dusk.
Color _skyTop(int h) => switch (h) {
  < 5 || >= 21 => const Color(0xFF02040F),
  < 7 => const Color(0xFF2B2F6B),
  < 17 => const Color(0xFF1E88E5),
  < 19 => const Color(0xFF6A3BA0),
  _ => const Color(0xFF16163A),
};

Color _skyBottom(int h) => switch (h) {
  < 5 || >= 21 => const Color(0xFF0B1030),
  < 7 => const Color(0xFFFF9E6B),
  < 17 => const Color(0xFFBDE3FF),
  < 19 => const Color(0xFFFF7A45),
  _ => const Color(0xFF3B2C5A),
};

/// The sky follows the clock: sunrise, noon, sunset and stars.
final daylight = CustomFace(
  id: '960000053',
  name: 'Daylight',
  blurb: 'The sky changes through the day, with the sun and moon on their arc.',
  kinds: {FaceKind.modern, FaceKind.info},
  accent: const Color(0xFFFFC94D),
  build: (k) async {
    await k.background((c, s) => fill(c, s, const Color(0xFF0B0F0C)));
    await k.switcher(0, 0, 192, 300, FaceData.hour, _range(0, 22, 2), (
      c,
      s,
      i,
    ) {
      final h = i * 2 + 1; // midpoint of the two-hour slot
      gradient(c, s, [_skyTop(h), _skyBottom(h)]);
      final night = h < 6 || h >= 19;
      if (night) {
        final r = Seeded(53);
        for (var i = 0; i < 40; i++) {
          c.drawCircle(
            Offset(r.next() * 192, r.next() * 240),
            r.next() < 0.2 ? 1.2 : 0.7,
            Paint()..color = const Color(0xFFDDE6FF),
          );
        }
      }
      // Sun from 6 to 18, moon otherwise, along an arc.
      final t = night ? ((h + 6) % 24) / 12 : (h - 6) / 12;
      final pos = Offset(16 + 160 * t, 230 - 170 * sin(pi * t));
      if (night) {
        c
          ..drawCircle(pos, 14, Paint()..color = const Color(0xFFEDEFF5))
          ..drawCircle(
            pos + const Offset(6, -4),
            12,
            Paint()..color = _skyTop(h),
          );
      } else {
        c
          ..drawCircle(pos, 24, Paint()..color = const Color(0x55FFE29A))
          ..drawCircle(pos, 15, Paint()..color = const Color(0xFFFFD54F));
      }
      // Hills.
      c.drawPath(
        Path()
          ..moveTo(0, 270)
          ..quadraticBezierTo(60, 230, 120, 262)
          ..quadraticBezierTo(160, 240, 192, 258)
          ..lineTo(192, 300)
          ..lineTo(0, 300)
          ..close(),
        Paint()
          ..color = night ? const Color(0xFF0A1410) : const Color(0xFF2E7D32),
      );
    });
    final time = await k.fontDigits(face(58, _white, weight: FontWeight.w700));
    await k.clock(
      316,
      time,
      face(58, const Color(0xFFFFC94D), weight: FontWeight.w700),
    );
    await k.weekday(96, 386, _label(_grey), upper: true, center: true);
    await k.weather(24, 412, 32, _white);
    final n = await k.fontDigits(face(22, _white, weight: FontWeight.w500));
    k.number(64, 416, FaceData.temperature, n, zeros: false);
    await k.text(64 + two(n), 416, '°', face(22, _grey));
    await k.text(118, 410, 'STEPS', _label(_grey));
    final small = await k.fontDigits(face(16, _white, family: mono));
    k.number(118, 426, FaceData.steps, small, count: 5, zeros: false);
  },
);

/// Draws the buddy with a mood from 0 (sleepy) to 4 (thrilled).
void _buddy(Canvas c, Size s, int mood, {bool blink = false}) {
  final centre = Offset(s.width / 2, s.height / 2 + 6);
  const colors = [
    Color(0xFF7E8AA2),
    Color(0xFF64B5F6),
    Color(0xFF4DD0A1),
    Color(0xFFFFC94D),
    Color(0xFFFF7A9A),
  ];
  final body = colors[mood];
  // Bounce a little higher when happier.
  final lift = mood * 3.0;
  final o = centre - Offset(0, lift);
  c
    ..drawOval(
      Rect.fromCenter(
        center: centre + const Offset(0, 52),
        width: 70,
        height: 10,
      ),
      Paint()..color = const Color(0x33000000),
    )
    ..drawOval(
      Rect.fromCenter(center: o, width: 104, height: 92),
      Paint()..color = body,
    )
    ..drawOval(
      Rect.fromCenter(
        center: o + const Offset(-22, -24),
        width: 26,
        height: 14,
      ),
      Paint()..color = const Color(0x44FFFFFF),
    );
  final ink = Paint()
    ..color = const Color(0xFF1B1A22)
    ..strokeWidth = 3.5
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  for (final dx in [-18.0, 18.0]) {
    final eye = o + Offset(dx, -6);
    if (blink || mood == 0) {
      c.drawLine(eye - const Offset(6, 0), eye + const Offset(6, 0), ink);
    } else {
      c.drawCircle(eye, 6, Paint()..color = const Color(0xFF1B1A22));
      c.drawCircle(eye + const Offset(-2, -2), 2, Paint()..color = _white);
    }
  }
  // Mouth: flat when sleepy, a wider smile as the day goes on.
  final mouth = o + const Offset(0, 16);
  final curve = (mood - 1) * 5.0;
  c.drawPath(
    Path()
      ..moveTo(mouth.dx - 14, mouth.dy)
      ..quadraticBezierTo(mouth.dx, mouth.dy + curve, mouth.dx + 14, mouth.dy),
    ink,
  );
  if (mood >= 3) {
    for (final dx in [-34.0, 34.0]) {
      c.drawCircle(
        o + Offset(dx, 8),
        6,
        Paint()..color = const Color(0x55FF4D6D),
      );
    }
  }
}

/// A little friend that gets happier the more you walk.
final buddy = CustomFace(
  id: '960000054',
  name: 'Buddy',
  blurb: 'A little friend who cheers up as you reach your step goal.',
  kinds: {FaceKind.animated, FaceKind.sport},
  accent: const Color(0xFF4DD0A1),
  build: (k) async {
    await k.background(
      (c, s) => gradient(c, s, const [Color(0xFF14121F), Color(0xFF231F35)]),
    );
    final time = await k.fontDigits(face(50, _white, weight: FontWeight.w700));
    await k.clock(
      40,
      time,
      face(50, const Color(0xFF4DD0A1), weight: FontWeight.w700),
    );
    await k.weekday(96, 104, _label(_grey), upper: true, center: true);
    const moods = [0, 25, 50, 75, 100];
    await k.switcher(
      26,
      150,
      140,
      140,
      FaceData.stepPercent,
      moods,
      (c, s, i) => _buddy(c, s, i),
    );
    // Blinks now and then (drawn over the eyes only).
    await k.animation(66, 176, 60, 30, 12, (c, s, t) {
      if ((t * 12).round() != 11) return;
      final ink = Paint()
        ..color = const Color(0xFF1B1A22)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;
      for (final x in [12.0, 48.0]) {
        c.drawLine(Offset(x - 6, 14), Offset(x + 6, 14), ink);
      }
    }, intervalMs: 300);
    const words = [
      'ZZZ… LET’S MOVE',
      'WARMING UP',
      'HALFWAY THERE',
      'ALMOST!',
      'GOAL! YAY',
    ];
    await k.switcher(16, 300, 160, 16, FaceData.stepPercent, moods, (c, s, i) {
      _centred(
        c,
        s.center(Offset.zero),
        words[i],
        _label(_white).copyWith(fontSize: 11),
      );
    });
    final n = await k.fontDigits(face(30, _white, weight: FontWeight.w700));
    k.number(
      96 - FaceKit.numberWidth(n, 5) ~/ 2,
      340,
      FaceData.steps,
      n,
      count: 5,
      zeros: false,
    );
    await k.text(96, 378, 'STEPS', _label(_grey), centerX: true);
    await k.switcher(
      36,
      404,
      120,
      6,
      FaceData.stepPercent,
      FaceKit.percentSteps(10),
      (c, s, i) =>
          bar(c, s, i / 10, const Color(0xFF4DD0A1), const Color(0xFF2C2840)),
    );
  },
);

/// A plant that grows through the day with your steps.
final bloom = CustomFace(
  id: '960000055',
  name: 'Bloom',
  blurb: 'A seedling that grows and flowers as you walk.',
  kinds: {FaceKind.sport, FaceKind.modern},
  accent: const Color(0xFFF48FB1),
  build: (k) async {
    const soil = Color(0xFF3E2A1E),
        leaf = Color(0xFF66BB6A),
        pot = Color(0xFFC8693E);
    await k.background((c, s) {
      gradient(c, s, const [Color(0xFF0E1A12), Color(0xFF060A07)]);
      c
        ..drawPath(
          Path()
            ..moveTo(56, 380)
            ..lineTo(136, 380)
            ..lineTo(126, 440)
            ..lineTo(66, 440)
            ..close(),
          Paint()..color = pot,
        )
        ..drawRect(
          const Rect.fromLTWH(52, 372, 88, 12),
          Paint()..color = const Color(0xFFD9824F),
        )
        ..drawRect(const Rect.fromLTWH(60, 378, 72, 6), Paint()..color = soil);
    });
    await k.switcher(
      16,
      160,
      160,
      214,
      FaceData.stepPercent,
      FaceKit.percentSteps(10),
      (c, s, i) {
        final base = Offset(s.width / 2, s.height);
        final height = 20 + i * 17.0;
        final stem = Paint()
          ..color = leaf
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        final top = base - Offset(0, height);
        c.drawPath(
          Path()
            ..moveTo(base.dx, base.dy)
            ..quadraticBezierTo(
              base.dx + 14,
              base.dy - height / 2,
              top.dx,
              top.dy,
            ),
          stem,
        );
        for (var l = 0; l < i; l++) {
          final y = base.dy - 16 - l * 16.0;
          final side = l.isEven ? 1.0 : -1.0;
          c.drawOval(
            Rect.fromCenter(
              center: Offset(base.dx + side * 16, y),
              width: 28,
              height: 12,
            ),
            Paint()..color = l.isEven ? leaf : const Color(0xFF81C784),
          );
        }
        if (i >= 10) {
          for (var p = 0; p < 6; p++) {
            final a = p * pi / 3;
            c.drawCircle(
              top + Offset(cos(a), sin(a)) * 12,
              9,
              Paint()..color = const Color(0xFFF48FB1),
            );
          }
          c.drawCircle(top, 7, Paint()..color = const Color(0xFFFFD54F));
        } else if (i >= 7) {
          c.drawOval(
            Rect.fromCenter(center: top, width: 14, height: 20),
            Paint()..color = const Color(0xFFEC407A),
          );
        }
      },
    );
    final time = await k.fontDigits(
      face(52, _white, family: serif, weight: FontWeight.w400),
    );
    await k.clock(
      40,
      time,
      face(52, const Color(0xFFF48FB1), family: serif, weight: FontWeight.w400),
    );
    await k.weekday(
      96,
      102,
      face(
        13,
        const Color(0xFFA5D6A7),
        family: serif,
        weight: FontWeight.w400,
        spacing: 2,
      ),
      center: true,
    );
    final n = await k.fontDigits(face(16, _white, family: mono));
    k.number(
      96 - FaceKit.numberWidth(n, 5) ~/ 2,
      450,
      FaceData.steps,
      n,
      count: 5,
      zeros: false,
    );
  },
);
