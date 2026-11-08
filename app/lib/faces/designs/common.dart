/// Shared pieces for the built-in OpenWear face designs.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:openwear/faces/face_binary.dart';
import 'package:openwear/faces/kit.dart';

export 'dart:math' show pi, sin, cos, atan2, sqrt;

export 'package:flutter/painting.dart';
export 'package:openwear/faces/face_binary.dart' show FaceData;
export 'package:openwear/faces/glyphs.dart';
export 'package:openwear/faces/kit.dart';

enum FaceKind { modern, animated, info, retro, sport }

/// One of OpenWear's own faces.
class CustomFace {
  const CustomFace({
    required this.id,
    required this.name,
    required this.blurb,
    required this.kinds,
    required this.accent,
    required this.build,
    this.lua = false,
  });

  /// Nine digits; the band lists the face under this id.
  final String id;
  final String name;
  final String blurb;
  final Set<FaceKind> kinds;
  final Color accent;
  final Future<void> Function(FaceKit k) build;

  /// Runs as a Lua script on the band (fits any screen of a Lua model);
  /// otherwise it is drawn for a 192×490 screen.
  final bool lua;

  Future<FaceDesign> design(String language) async {
    final k = FaceKit(language);
    await build(k);
    return k.finish(id, name);
  }
}

const grotesk = 'SpaceGrotesk', mono = 'JetBrainsMono';

/// Bundled, so a face looks the same on every phone (system fonts differ
/// between makers and would shift the layouts).
const serif = 'OpenWearSerif', condensed = 'OpenWearCondensed';

TextStyle face(
  double size,
  Color color, {
  String family = grotesk,
  FontWeight weight = FontWeight.w700,
  double spacing = 0,
  List<Shadow>? shadows,
  FontStyle? style,
}) => TextStyle(
  fontFamily: family,
  fontSize: size,
  color: color,
  fontWeight: weight,
  letterSpacing: spacing,
  height: 1,
  shadows: shadows,
  fontStyle: style,
  leadingDistribution: TextLeadingDistribution.even,
);

/// Outlined text.
TextStyle outline(
  double size,
  Color color, {
  String family = grotesk,
  double width = 2,
}) => TextStyle(
  fontFamily: family,
  fontSize: size,
  fontWeight: FontWeight.w700,
  height: 1,
  foreground: Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..color = color,
);

void fill(Canvas c, Size s, Color color) =>
    c.drawRect(Offset.zero & s, Paint()..color = color);

/// Vertical gradient filling [s].
void gradient(Canvas c, Size s, List<Color> colors, [List<double>? stops]) =>
    c.drawRect(
      Offset.zero & s,
      Paint()..shader = linear(Offset.zero, Offset(0, s.height), colors, stops),
    );

/// A horizontal bar filled to [fraction].
void bar(
  Canvas c,
  Size s,
  double fraction,
  Color on,
  Color track, {
  double radius = 3,
}) {
  final r = Radius.circular(radius);
  c.drawRRect(
    RRect.fromRectAndRadius(Offset.zero & s, r),
    Paint()..color = track,
  );
  if (fraction <= 0) return;
  c.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, s.width * fraction.clamp(0, 1), s.height),
      r,
    ),
    Paint()..color = on,
  );
}

/// A ring arc filled to [fraction], starting at 12 o'clock.
void ring(
  Canvas c,
  Offset centre,
  double radius,
  double width,
  double fraction,
  Color on,
  Color track,
) {
  final rect = Rect.fromCircle(center: centre, radius: radius);
  final p = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;
  c.drawArc(rect, 0, 2 * math.pi, false, p..color = track);
  if (fraction > 0) {
    c.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0, 1),
      false,
      p..color = on,
    );
  }
}

/// Deterministic pseudo-random numbers so a face renders the same each time.
class Seeded {
  Seeded(int seed) : _r = math.Random(seed);
  final math.Random _r;
  double next() => _r.nextDouble();
  int below(int n) => _r.nextInt(n);
}

/// The face's step-percent thresholds as fractions.
List<double> fractions(List<int> percents) => [
  for (final p in percents) p / 100,
];

/// Width of a two-digit number in [d].
int two(Digits d, {int spacing = 0}) =>
    FaceKit.numberWidth(d, 2, spacing: spacing);

/// Stops spread evenly over [colors] when none are given.
List<double>? _even(List<Color> colors, List<double>? stops) =>
    stops ??
    (colors.length <= 2
        ? null
        : [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)]);

Shader linear(Offset a, Offset b, List<Color> colors, [List<double>? stops]) =>
    ui.Gradient.linear(a, b, colors, _even(colors, stops));

Shader radial(
  Offset centre,
  double radius,
  List<Color> colors, [
  List<double>? stops,
]) => ui.Gradient.radial(centre, radius, colors, _even(colors, stops));
