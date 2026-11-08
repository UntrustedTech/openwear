/// Faces 36–40: Pixel, Tide, Lava, Prism, Enso.
library;

import 'package:openwear/faces/designs/common.dart';

const _white = Color(0xFFF4F1EA), _grey = Color(0xFF6E6A63);

TextStyle _label(Color c) =>
    face(10, c, family: mono, weight: FontWeight.w500, spacing: 1.5);

/// Chunky square-pixel digits and a walking sprite.
final pixel = CustomFace(
  id: '960000036',
  name: 'Pixel',
  blurb: 'Chunky pixel digits and a little walking sprite.',
  kinds: {FaceKind.retro, FaceKind.animated},
  accent: const Color(0xFF7CFC00),
  build: (k) async {
    const green = Color(0xFF7CFC00), dim = Color(0xFF14240A);
    await k.background((c, s) {
      fill(c, s, const Color(0xFF050805));
      final p = Paint()..color = const Color(0xFF0E160B);
      for (var y = 0.0; y < 490; y += 4) {
        c.drawRect(Rect.fromLTWH(0, y, 192, 1), p);
      }
      c.drawRect(const Rect.fromLTWH(0, 330, 192, 4), Paint()..color = green);
    });
    final d = await k.paintedDigits(
      40,
      56,
      (c, s, i) => paintDotMatrix(c, s, i, green, dim, square: true),
    );
    k.number((192 - two(d, spacing: 8)) ~/ 2, 90, FaceData.hour, d, spacing: 8);
    k.number(
      (192 - two(d, spacing: 8)) ~/ 2,
      170,
      FaceData.minute,
      d,
      spacing: 8,
    );
    const sprite = [
      ['00110', '00110', '01111', '10110', '00110', '01001', '10001'],
      ['00110', '00110', '01110', '01111', '00110', '00110', '01010'],
    ];
    await k.animation(0, 290, 192, 40, 12, (c, s, t) {
      final frame = sprite[(t * 12).floor() % 2];
      final x0 = t * 172;
      for (var r = 0; r < 7; r++) {
        for (var col = 0; col < 5; col++) {
          if (frame[r][col] == '1') {
            c.drawRect(
              Rect.fromLTWH(x0 + col * 4, 10 + r * 4.0, 4, 4),
              Paint()..color = green,
            );
          }
        }
      }
    }, intervalMs: 200);
    final n = await k.paintedDigits(
      15,
      21,
      (c, s, i) => paintDotMatrix(c, s, i, green, dim, square: true),
    );
    await k.text(20, 356, 'STEPS', _label(green));
    k.number(20, 372, FaceData.steps, n, count: 5, zeros: false, spacing: 2);
    await k.text(20, 410, 'BATT', _label(green));
    k.number(20, 426, FaceData.battery, n, count: 3, zeros: false, spacing: 2);
  },
);

/// Waves rolling in under a moonlit sky.
final tide = CustomFace(
  id: '960000037',
  name: 'Tide',
  blurb: 'Waves rolling in under a calm night sky.',
  kinds: {FaceKind.animated, FaceKind.modern},
  accent: const Color(0xFF4DD0E1),
  build: (k) async {
    await k.background((c, s) {
      gradient(c, s, const [Color(0xFF020814), Color(0xFF0B2740)]);
      c.drawCircle(
        const Offset(146, 74),
        16,
        Paint()..color = const Color(0xFFE8F1F2),
      );
      final r = Seeded(37);
      for (var i = 0; i < 30; i++) {
        c.drawCircle(
          Offset(r.next() * 192, r.next() * 250),
          r.next() < 0.2 ? 1.2 : 0.7,
          Paint()..color = const Color(0xFFBFD8E6),
        );
      }
    });
    await k.animation(0, 360, 192, 130, 8, (c, s, t) {
      const colors = [Color(0xFF0E4C6E), Color(0xFF136A8A), Color(0xFF1A8BA8)];
      for (var layer = 0; layer < 3; layer++) {
        final base = 20.0 + layer * 34;
        final path = Path()..moveTo(0, s.height);
        for (var x = 0.0; x <= 192; x += 4) {
          path.lineTo(
            x,
            base +
                8 *
                    sin(
                      x / 26 +
                          (t + layer / 3) * 2 * pi * (layer.isEven ? 1 : -1),
                    ),
          );
        }
        path
          ..lineTo(192, s.height)
          ..close();
        c.drawPath(path, Paint()..color = colors[layer]);
      }
    }, intervalMs: 220);
    final time = await k.fontDigits(face(64, _white, weight: FontWeight.w400));
    await k.clock(
      150,
      time,
      face(64, const Color(0xFF4DD0E1), weight: FontWeight.w400),
    );
    await k.weekday(
      96,
      236,
      _label(const Color(0xFF9FC5D6)),
      upper: true,
      center: true,
    );
    final n = await k.fontDigits(
      face(16, _white, family: mono, weight: FontWeight.w500),
    );
    k.number(84, 260, FaceData.day, n);
  },
);

/// Molten blobs rise and fall like a lava lamp.
final lava = CustomFace(
  id: '960000038',
  name: 'Lava',
  blurb: 'Molten blobs drifting like a lava lamp.',
  kinds: {FaceKind.animated, FaceKind.retro},
  accent: const Color(0xFFFF6D00),
  build: (k) async {
    await k.background(
      (c, s) => gradient(c, s, const [Color(0xFF1A0500), Color(0xFF3A0B00)]),
    );
    await k.animation(20, 250, 152, 220, 10, (c, s, t) {
      final glass = RRect.fromRectAndRadius(
        Offset.zero & s,
        const Radius.circular(60),
      );
      c
        ..save()
        ..clipRRect(glass)
        ..drawRRect(glass, Paint()..color = const Color(0xFF4A0F00));
      const blobs = [
        (40.0, 30.0, 0.0),
        (100.0, 22.0, 0.33),
        (70.0, 26.0, 0.66),
      ];
      for (final (x, r, phase) in blobs) {
        final y = s.height / 2 + (s.height / 2 - r) * sin((t + phase) * 2 * pi);
        c.drawCircle(Offset(x, y), r, Paint()..color = const Color(0xFFFF6D00));
        c.drawCircle(
          Offset(x - r * 0.3, y - r * 0.3),
          r * 0.35,
          Paint()..color = const Color(0xFFFFA040),
        );
      }
      c.restore();
    }, intervalMs: 260);
    final time = await k.fontDigits(
      face(66, const Color(0xFFFFE0C2), weight: FontWeight.w700),
    );
    await k.clock(
      70,
      time,
      face(66, const Color(0xFFFF6D00), weight: FontWeight.w700),
    );
    await k.weekday(
      96,
      156,
      _label(const Color(0xFFFFA040)),
      upper: true,
      center: true,
    );
    final n = await k.fontDigits(
      face(16, const Color(0xFFFFE0C2), family: mono, weight: FontWeight.w500),
    );
    await k.text(40, 186, 'BPM', _label(_grey));
    k.number(40, 202, FaceData.heartRate, n, count: 3, zeros: false);
    await k.text(110, 186, 'BATT', _label(_grey));
    k.number(110, 202, FaceData.battery, n, count: 3, zeros: false);
  },
);

/// A light spectrum split across the hours and minutes.
final prism = CustomFace(
  id: '960000039',
  name: 'Prism',
  blurb: 'A spectrum of colour behind bold, clean numerals.',
  kinds: {FaceKind.modern},
  accent: const Color(0xFFB39DDB),
  build: (k) async {
    await k.background((c, s) {
      fill(c, s, const Color(0xFF000000));
      c.drawRect(
        const Rect.fromLTWH(0, 70, 192, 250),
        Paint()
          ..shader = linear(const Offset(0, 70), const Offset(192, 320), const [
            Color(0xFFFF5F6D),
            Color(0xFFFFC371),
            Color(0xFF47E5BC),
            Color(0xFF4A90E2),
            Color(0xFFB06AB3),
          ]),
      );
    });
    final d = await k.fontDigits(
      face(110, const Color(0xFF000000), weight: FontWeight.w700),
    );
    k.number((192 - two(d)) ~/ 2, 82, FaceData.hour, d);
    k.number((192 - two(d)) ~/ 2, 196, FaceData.minute, d);
    await k.weekday(
      20,
      350,
      face(14, _white, weight: FontWeight.w700),
      upper: true,
    );
    final n = await k.fontDigits(face(14, _white, weight: FontWeight.w700));
    k.number(150, 350, FaceData.day, n);
    await k.text(20, 390, 'STEPS', _label(_grey));
    k.number(20, 406, FaceData.steps, n, count: 5, zeros: false);
  },
);

/// A single brush-stroke circle, Zen style.
final enso = CustomFace(
  id: '960000040',
  name: 'Enso',
  blurb: 'A single brush-stroke circle and quiet numerals.',
  kinds: {FaceKind.modern},
  accent: const Color(0xFFD32F2F),
  build: (k) async {
    const paper = Color(0xFFF1EBDD), sumi = Color(0xFF1B1A17);
    await k.background((c, s) {
      fill(c, s, paper);
      const centre = Offset(96, 200);
      for (var i = 0; i < 300; i++) {
        final a = -pi / 2 + i / 300 * 2 * pi * 0.9;
        final w = 10 * sin(i / 300 * pi) + 3;
        c.drawCircle(
          centre + Offset(cos(a), sin(a)) * (76 + 2 * sin(i / 17)),
          w / 2,
          Paint()..color = sumi,
        );
      }
      c.drawRect(
        const Rect.fromLTWH(150, 420, 18, 18),
        Paint()..color = const Color(0xFFD32F2F),
      );
    });
    final d = await k.fontDigits(
      face(46, sumi, family: serif, weight: FontWeight.w400),
    );
    await k.clock(
      176,
      d,
      face(46, sumi, family: serif, weight: FontWeight.w400),
    );
    await k.weekday(
      96,
      320,
      face(14, sumi, family: serif, weight: FontWeight.w400, spacing: 3),
      center: true,
    );
  },
);
