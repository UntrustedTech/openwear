/// Hand-drawn glyphs for faces: weather icons, seven-segment and dot-matrix
/// digits.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';

// --- weather ---------------------------------------------------------------------

enum WeatherKind {
  clear,
  cloudy,
  overcast,
  rain,
  storm,
  snow,
  fog,
  dust,
  unknown,
}

/// Every condition code the band reports, ascending.
final weatherCodes = List<int>.unmodifiable([
  for (var c = 0; c <= 33; c++) c,
  49, 53, 54, 55, 56, 57, 58, 99, //
]);

WeatherKind weatherKind(int code) => switch (code) {
  0 => WeatherKind.clear,
  1 => WeatherKind.cloudy,
  2 => WeatherKind.overcast,
  4 || 5 || 10 || 11 || 12 || 24 || 25 => WeatherKind.storm,
  3 || 6 || 7 || 8 || 9 || 19 || 21 || 22 || 23 => WeatherKind.rain,
  13 || 14 || 15 || 16 || 17 || 26 || 27 || 28 || 33 => WeatherKind.snow,
  18 || 32 || 49 || 57 || 58 => WeatherKind.fog,
  20 || 29 || 30 || 31 || 53 || 54 || 55 || 56 => WeatherKind.dust,
  _ => WeatherKind.unknown,
};

void _cloud(Canvas c, double u, Offset o, Paint p) {
  final path = Path()
    ..addOval(
      Rect.fromCircle(center: o + Offset(-0.18 * u, 0.04 * u), radius: 0.2 * u),
    )
    ..addOval(
      Rect.fromCircle(
        center: o + Offset(0.06 * u, -0.08 * u),
        radius: 0.26 * u,
      ),
    )
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(o.dx - 0.36 * u, o.dy, o.dx + 0.36 * u, o.dy + 0.22 * u),
        Radius.circular(0.11 * u),
      ),
    );
  c.drawPath(path, p);
}

void paintWeather(Canvas c, Size s, WeatherKind kind, Color color) {
  final u = s.shortestSide;
  final fill = Paint()..color = color;
  final stroke = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = u * 0.07
    ..strokeCap = StrokeCap.round;
  final mid = s.center(Offset.zero);
  switch (kind) {
    case WeatherKind.clear:
      c.drawCircle(mid, u * 0.2, fill);
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final d = Offset(math.cos(a), math.sin(a));
        c.drawLine(mid + d * u * 0.3, mid + d * u * 0.42, stroke);
      }
    case WeatherKind.cloudy:
      c.drawCircle(mid + Offset(u * 0.16, -u * 0.16), u * 0.15, fill);
      _cloud(
        c,
        u,
        mid + Offset(-u * 0.04, u * 0.06),
        Paint()..color = const Color(0xFF000000),
      );
      _cloud(c, u * 0.9, mid + Offset(-u * 0.04, u * 0.08), fill);
    case WeatherKind.overcast:
      _cloud(c, u, mid, fill);
    case WeatherKind.rain || WeatherKind.storm || WeatherKind.snow:
      _cloud(c, u * 0.9, mid + Offset(0, -u * 0.12), fill);
      for (var i = -1; i <= 1; i++) {
        final x = mid.dx + i * u * 0.2;
        final y = mid.dy + u * 0.24;
        if (kind == WeatherKind.snow) {
          c.drawCircle(Offset(x, y + u * 0.06), u * 0.05, fill);
        } else if (kind == WeatherKind.storm && i == 0) {
          c.drawPath(
            Path()
              ..moveTo(x + u * 0.04, y - u * 0.04)
              ..lineTo(x - u * 0.06, y + u * 0.1)
              ..lineTo(x + u * 0.02, y + u * 0.1)
              ..lineTo(x - u * 0.04, y + u * 0.22),
            stroke..strokeWidth = u * 0.06,
          );
        } else {
          c.drawLine(
            Offset(x + u * 0.03, y),
            Offset(x - u * 0.03, y + u * 0.13),
            stroke,
          );
        }
      }
    case WeatherKind.fog || WeatherKind.dust:
      for (var i = 0; i < 3; i++) {
        final y = mid.dy + (i - 1) * u * 0.2;
        final inset = kind == WeatherKind.dust && i.isOdd ? u * 0.18 : u * 0.1;
        c.drawLine(Offset(inset, y), Offset(s.width - inset, y), stroke);
      }
    case WeatherKind.unknown:
      c.drawCircle(mid, u * 0.06, fill);
  }
}

// --- seven-segment -----------------------------------------------------------------

/// Segments a–g lit for each digit.
const _segments = [
  0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F, //
];

/// A slanted seven-segment digit; unlit segments drawn in [ghost].
void paintSevenSegment(
  Canvas c,
  Size s,
  int digit,
  Color on,
  Color ghost, {
  double slant = 0.1,
}) {
  final h = s.height;
  final w = s.width - slant * h;
  final k = w * 0.09; // half thickness
  const g = 1.0; // gap between segments
  Path horizontal(double x0, double x1, double y) => Path()
    ..moveTo(x0 + g, y)
    ..lineTo(x0 + g + k, y - k)
    ..lineTo(x1 - g - k, y - k)
    ..lineTo(x1 - g, y)
    ..lineTo(x1 - g - k, y + k)
    ..lineTo(x0 + g + k, y + k)
    ..close();
  Path vertical(double x, double y0, double y1) => Path()
    ..moveTo(x, y0 + g)
    ..lineTo(x + k, y0 + g + k)
    ..lineTo(x + k, y1 - g - k)
    ..lineTo(x, y1 - g)
    ..lineTo(x - k, y1 - g - k)
    ..lineTo(x - k, y0 + g + k)
    ..close();

  final x0 = k, x1 = w - k, y0 = k, y1 = h / 2, y2 = h - k;
  final paths = [
    horizontal(x0, x1, y0), // a
    vertical(x1, y0, y1), // b
    vertical(x1, y1, y2), // c
    horizontal(x0, x1, y2), // d
    vertical(x0, y1, y2), // e
    vertical(x0, y0, y1), // f
    horizontal(x0, x1, y1), // g
  ];
  c
    ..save()
    ..transform(
      Float64List.fromList([
        1, 0, 0, 0, -slant, 1, 0, 0, 0, 0, 1, 0, slant * h, 0, 0, 1, //
      ]),
    );
  for (var i = 0; i < 7; i++) {
    final lit = _segments[digit] >> i & 1 == 1;
    c.drawPath(paths[i], Paint()..color = lit ? on : ghost);
  }
  c.restore();
}

// --- dot matrix --------------------------------------------------------------------

/// 5×7 dot-matrix digits, one string of five bits per row.
const _dots = [
  ['01110', '10001', '10011', '10101', '11001', '10001', '01110'],
  ['00100', '01100', '00100', '00100', '00100', '00100', '01110'],
  ['01110', '10001', '00001', '00010', '00100', '01000', '11111'],
  ['11111', '00010', '00100', '00010', '00001', '10001', '01110'],
  ['00010', '00110', '01010', '10010', '11111', '00010', '00010'],
  ['11111', '10000', '11110', '00001', '00001', '10001', '01110'],
  ['00110', '01000', '10000', '11110', '10001', '10001', '01110'],
  ['11111', '00001', '00010', '00100', '01000', '01000', '01000'],
  ['01110', '10001', '10001', '01110', '10001', '10001', '01110'],
  ['01110', '10001', '10001', '01111', '00001', '00010', '01100'],
];

void paintDotMatrix(
  Canvas c,
  Size s,
  int digit,
  Color on,
  Color off, {
  bool square = false,
}) {
  final pitch = math.min(s.width / 5, s.height / 7);
  final r = pitch * 0.4;
  for (var row = 0; row < 7; row++) {
    for (var col = 0; col < 5; col++) {
      final lit = _dots[digit][row][col] == '1';
      final centre = Offset((col + 0.5) * pitch, (row + 0.5) * pitch);
      final p = Paint()..color = lit ? on : off;
      if (square) {
        c.drawRect(Rect.fromCircle(center: centre, radius: r), p);
      } else {
        c.drawCircle(centre, r, p);
      }
    }
  }
}
