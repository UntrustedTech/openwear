/// Faces 26–30 (sport): Podium, Velocity, Summit, Triad, Matchday.
library;

import 'package:openwear/faces/designs/common.dart';

const _white = Color(0xFFF4F1EA), _grey = Color(0xFF6E6A63);

TextStyle _label(Color c) =>
    face(10, c, family: mono, weight: FontWeight.w500, spacing: 1.5);

/// A medal that upgrades as you close in on the step goal.
final podium = CustomFace(
  id: '960000026',
  name: 'Podium',
  blurb: 'Earn bronze, silver and gold as you near your step goal.',
  kinds: {FaceKind.sport},
  accent: const Color(0xFFE8C15A),
  build: (k) async {
    const medals = [
      (Color(0xFF2A2A2A), Color(0xFF3A3A3A), 'KEEP GOING'),
      (Color(0xFFB0703C), Color(0xFF7A4520), 'BRONZE'),
      (Color(0xFFC9CED6), Color(0xFF7D838C), 'SILVER'),
      (Color(0xFFE8C15A), Color(0xFF9C7420), 'GOLD'),
    ];
    final time = await k.fontDigits(face(44, _white, weight: FontWeight.w700));
    await k.clock(40, time, face(44, _grey, weight: FontWeight.w700));
    await k.switcher(
      36,
      120,
      120,
      200,
      FaceData.stepPercent,
      const [0, 50, 75, 100],
      (c, s, i) {
        final (face1, edge, _) = medals[i];
        final ribbon = Paint()
          ..color = i == 0 ? const Color(0xFF222222) : const Color(0xFF2E5BD9);
        c
          ..drawPath(
            Path()
              ..moveTo(30, 0)
              ..lineTo(50, 0)
              ..lineTo(70, 70)
              ..lineTo(50, 70)
              ..close(),
            ribbon,
          )
          ..drawPath(
            Path()
              ..moveTo(90, 0)
              ..lineTo(70, 0)
              ..lineTo(50, 70)
              ..lineTo(70, 70)
              ..close(),
            ribbon
              ..color = i == 0
                  ? const Color(0xFF1A1A1A)
                  : const Color(0xFFD93A3A),
          )
          ..drawCircle(const Offset(60, 130), 56, Paint()..color = edge)
          ..drawCircle(const Offset(60, 130), 46, Paint()..color = face1);
        final star = Path();
        for (var p = 0; p < 10; p++) {
          final r = p.isEven ? 22.0 : 9.0;
          final a = -pi / 2 + p * pi / 5;
          final pt = Offset(60 + r * cos(a), 130 + r * sin(a));
          p == 0 ? star.moveTo(pt.dx, pt.dy) : star.lineTo(pt.dx, pt.dy);
        }
        c.drawPath(star..close(), Paint()..color = edge);
      },
    );
    await k.switcher(
      16,
      330,
      160,
      16,
      FaceData.stepPercent,
      const [0, 50, 75, 100],
      (c, s, i) {
        final tp = TextPainter(
          text: TextSpan(
            text: medals[i].$3,
            style: face(
              13,
              i == 0 ? _grey : medals[i].$1,
              family: mono,
              weight: FontWeight.w700,
              spacing: 3,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, Offset((s.width - tp.width) / 2, 0));
      },
    );
    final n = await k.fontDigits(face(30, _white, weight: FontWeight.w700));
    k.number(
      96 - FaceKit.numberWidth(n, 5) ~/ 2,
      362,
      FaceData.steps,
      n,
      count: 5,
      zeros: false,
    );
    await k.text(96, 400, 'STEPS', _label(_grey), centerX: true);
  },
);

/// A speedometer whose needle follows your step goal.
final velocity = CustomFace(
  id: '960000027',
  name: 'Velocity',
  blurb: 'A speedometer needle that climbs with your steps.',
  kinds: {FaceKind.sport, FaceKind.modern},
  accent: const Color(0xFFFF3B30),
  build: (k) async {
    const red = Color(0xFFFF3B30);
    const centre = Offset(96, 110);
    double angleFor(double f) => pi * 0.75 + f * pi * 1.5;
    await k.background((c, s) {
      fill(c, s, const Color(0xFF050505));
      final arc = Rect.fromCircle(
        center: centre + const Offset(0, 60),
        radius: 84,
      );
      c.drawArc(
        arc,
        pi * 0.75,
        pi * 1.5,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..shader = linear(arc.centerLeft, arc.centerRight, const [
            Color(0xFF2B2B2B),
            Color(0xFF5A1410),
            red,
          ]),
      );
      for (var i = 0; i <= 10; i++) {
        final a = angleFor(i / 10);
        final d = Offset(cos(a), sin(a));
        c.drawLine(
          centre + const Offset(0, 60) + d * 66,
          centre + const Offset(0, 60) + d * (i.isEven ? 56 : 61),
          Paint()
            ..color = _white
            ..strokeWidth = i.isEven ? 2.5 : 1,
        );
      }
    });
    await k.switcher(
      0,
      76,
      192,
      192,
      FaceData.stepPercent,
      FaceKit.percentSteps(5),
      (c, s, i) {
        final a = angleFor(i / 20);
        final o = s.center(Offset.zero);
        c
          ..drawLine(
            o,
            o + Offset(cos(a), sin(a)) * 70,
            Paint()
              ..color = red
              ..strokeWidth = 3.5
              ..strokeCap = StrokeCap.round,
          )
          ..drawCircle(o, 8, Paint()..color = _white)
          ..drawCircle(o, 3, Paint()..color = red);
      },
    );
    final pct = await k.fontDigits(
      face(16, red, family: mono, weight: FontWeight.w700),
    );
    k.number(
      96 - FaceKit.numberWidth(pct, 3) ~/ 2,
      230,
      FaceData.stepPercent,
      pct,
      count: 3,
      zeros: false,
    );
    await k.text(96, 250, 'GOAL %', _label(_grey), centerX: true);
    final time = await k.fontDigits(
      face(64, _white, weight: FontWeight.w700, style: FontStyle.italic),
    );
    await k.clock(290, time, face(64, red, weight: FontWeight.w700));
    final n = await k.fontDigits(
      face(18, _white, family: mono, weight: FontWeight.w500),
    );
    await k.text(20, 390, 'STEPS', _label(_grey));
    k.number(20, 406, FaceData.steps, n, count: 5, zeros: false);
    await k.text(120, 390, 'BPM', _label(_grey));
    k.number(120, 406, FaceData.heartRate, n, count: 3, zeros: false);
  },
);

/// Climb the mountain: a marker rises along the ridge with your steps.
final summit = CustomFace(
  id: '960000028',
  name: 'Summit',
  blurb: 'Climb the ridge to the peak as you reach your step goal.',
  kinds: {FaceKind.sport, FaceKind.modern},
  accent: const Color(0xFF9AD0EC),
  build: (k) async {
    const ridge = [
      Offset(0, 300),
      Offset(36, 250),
      Offset(58, 266),
      Offset(96, 170),
      Offset(118, 196),
      Offset(150, 120),
      Offset(192, 210),
    ];
    final path = Path()..moveTo(ridge.first.dx, ridge.first.dy);
    for (final p in ridge.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final toPeak = Path()..moveTo(ridge.first.dx, ridge.first.dy);
    for (final p in ridge.skip(1).take(5)) {
      toPeak.lineTo(p.dx, p.dy);
    }
    final metric = toPeak.computeMetrics().first;
    await k.background((c, s) {
      gradient(
        c,
        s,
        const [Color(0xFF0B1E33), Color(0xFF243B55), Color(0xFF0B0F14)],
        const [0, 0.5, 0.7],
      );
      final land = Path.from(path)
        ..lineTo(192, 490)
        ..lineTo(0, 490)
        ..close();
      c
        ..drawPath(land, Paint()..color = const Color(0xFF15202B))
        ..drawPath(
          Path()
            ..moveTo(132, 146)
            ..lineTo(150, 120)
            ..lineTo(166, 144)
            ..lineTo(156, 140)
            ..lineTo(148, 150)
            ..lineTo(140, 141)
            ..close(),
          Paint()..color = const Color(0xFFE6F2FA),
        )
        ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0xFF9AD0EC),
        );
    });
    await k.switcher(
      0,
      0,
      192,
      310,
      FaceData.stepPercent,
      FaceKit.percentSteps(10),
      (c, s, i) {
        final along = metric.extractPath(0, metric.length * i / 10);
        c.drawPath(
          along,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFFFFB13B),
        );
        final tip = metric
            .getTangentForOffset(metric.length * i / 10)!
            .position;
        c
          ..drawCircle(tip, 6, Paint()..color = const Color(0xFFFFB13B))
          ..drawLine(
            tip,
            tip + const Offset(0, -16),
            Paint()
              ..color = _white
              ..strokeWidth = 1.5,
          )
          ..drawRect(
            Rect.fromLTWH(tip.dx, tip.dy - 16, 9, 6),
            Paint()..color = const Color(0xFFFF5A1F),
          );
      },
    );
    final time = await k.fontDigits(face(56, _white, weight: FontWeight.w500));
    await k.clock(
      330,
      time,
      face(56, const Color(0xFF9AD0EC), weight: FontWeight.w500),
    );
    final n = await k.fontDigits(
      face(16, _white, family: mono, weight: FontWeight.w500),
    );
    await k.text(20, 406, 'STEPS', _label(const Color(0xFF9AD0EC)));
    k.number(20, 422, FaceData.steps, n, count: 5, zeros: false);
    await k.text(120, 406, 'GOAL %', _label(const Color(0xFF9AD0EC)));
    k.number(120, 422, FaceData.stepPercent, n, count: 3, zeros: false);
    await k.weekday(20, 40, _label(_white), upper: true);
  },
);

/// Three segmented arcs: steps, calories and battery.
final triad = CustomFace(
  id: '960000029',
  name: 'Triad',
  blurb: 'Three segmented arcs for steps, calories and battery.',
  kinds: {FaceKind.sport, FaceKind.info},
  accent: const Color(0xFF00E5A0),
  build: (k) async {
    const arcs = [
      (FaceData.stepPercent, Color(0xFF00E5A0), 84.0, 'STEPS'),
      (FaceData.caloriePercent, Color(0xFFFF7A45), 66.0, 'KCAL'),
      (FaceData.battery, Color(0xFF5AA9FF), 48.0, 'BATT'),
    ];
    for (final (source, color, r, _) in arcs) {
      await k.switcher(0, 24, 192, 192, source, FaceKit.percentSteps(5), (
        c,
        s,
        i,
      ) {
        final o = s.center(Offset.zero);
        for (var seg = 0; seg < 20; seg++) {
          final a0 = -pi / 2 + seg * 2 * pi / 20 + 0.04;
          c.drawArc(
            Rect.fromCircle(center: o, radius: r),
            a0,
            2 * pi / 20 - 0.08,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 12
              ..color = seg < i ? color : color.withAlpha(40),
          );
        }
      });
    }
    final small = await k.fontDigits(face(22, _white, weight: FontWeight.w700));
    k.number(96 - two(small) - 2, 108, FaceData.hour, small);
    k.number(96 + 2, 108, FaceData.minute, small);
    final n = await k.fontDigits(
      face(18, _white, family: mono, weight: FontWeight.w500),
    );
    for (var i = 0; i < arcs.length; i++) {
      final (_, color, _, name) = arcs[i];
      final y = 250 + i * 56;
      await k.image(
        20,
        y + 6,
        8,
        8,
        (c, s) =>
            c.drawCircle(s.center(Offset.zero), 4, Paint()..color = color),
      );
      await k.text(36, y + 2, name, _label(_grey));
      k.number(
        36,
        y + 18,
        [FaceData.steps, FaceData.calories, FaceData.battery][i],
        n,
        count: i == 0 ? 5 : 4,
        zeros: false,
      );
    }
  },
);

/// A stadium scoreboard: the time is the score.
final matchday = CustomFace(
  id: '960000030',
  name: 'Matchday',
  blurb: 'Stadium scoreboard with the time as the score.',
  kinds: {FaceKind.sport, FaceKind.retro},
  accent: const Color(0xFF3DDC84),
  build: (k) async {
    const grass = Color(0xFF1E7B3C), amber = Color(0xFFFFC233);
    await k.background((c, s) {
      fill(c, s, grass);
      for (var y = 0.0; y < 490; y += 40) {
        c.drawRect(
          Rect.fromLTWH(0, y, 192, 20),
          Paint()..color = const Color(0xFF238845),
        );
      }
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xCCFFFFFF);
      c
        ..drawRect(const Rect.fromLTWH(10, 10, 172, 470), line)
        ..drawLine(const Offset(10, 245), const Offset(182, 245), line)
        ..drawCircle(const Offset(96, 245), 34, line)
        ..drawRect(const Rect.fromLTWH(50, 10, 92, 50), line)
        ..drawRect(const Rect.fromLTWH(50, 430, 92, 50), line)
        ..drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(18, 120, 156, 92),
            const Radius.circular(8),
          ),
          Paint()..color = const Color(0xF0101010),
        );
    });
    await k.text(40, 128, 'HOME', _label(amber));
    await k.text(124, 128, 'AWAY', _label(amber));
    final score = await k.paintedDigits(
      26,
      46,
      (c, s, d) => paintDotMatrix(c, s, d, amber, const Color(0xFF2A2310)),
    );
    k.number(28, 150, FaceData.hour, score, spacing: 4);
    await k.text(
      96,
      160,
      '–',
      face(24, amber, family: mono, weight: FontWeight.w700),
      centerX: true,
    );
    k.number(112, 150, FaceData.minute, score, spacing: 4);
    await k.image(
      18,
      290,
      156,
      60,
      (c, s) => c.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(8)),
        Paint()..color = const Color(0xF0101010),
      ),
    );
    final n = await k.fontDigits(
      face(18, _white, family: mono, weight: FontWeight.w700),
    );
    await k.text(30, 298, 'STEPS', _label(amber));
    k.number(30, 316, FaceData.steps, n, count: 5, zeros: false);
    await k.text(120, 298, 'BPM', _label(amber));
    k.number(120, 316, FaceData.heartRate, n, count: 3, zeros: false);
  },
);
