/// Heart-rate line with a soft area fill, drawn from (time, bpm) samples.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openwear/ui/theme.dart';

class HeartRateChart extends StatelessWidget {
  const HeartRateChart({
    super.key,
    required this.samples,
    required this.window,
    this.height = 120,
    this.now,
  });

  /// Samples in time order.
  final List<(DateTime, int)> samples;

  /// How far back from [now] the x axis reaches.
  final Duration window;
  final double height;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: HeartRatePainter(
          samples: samples,
          end: now ?? DateTime.now(),
          window: window,
          grid: separator(context),
          label: secondaryLabel(context),
          lineColor: sys(context, Metric.heart),
          fontFamily: fontFamily,
        ),
      ),
    );
  }
}

class HeartRatePainter extends CustomPainter {
  HeartRatePainter({
    required this.samples,
    required this.end,
    required this.window,
    required this.grid,
    required this.label,
    required this.lineColor,
    this.fontFamily,
  });

  final Color lineColor;

  final String? fontFamily;

  final List<(DateTime, int)> samples;
  final DateTime end;
  final Duration window;
  final Color grid;
  final Color label;

  @override
  void paint(Canvas canvas, Size size) {
    final start = end.subtract(window);
    final shown = [
      for (final s in samples)
        if (!s.$1.isBefore(start) && !s.$1.isAfter(end)) s,
    ];
    final lo = shown.isEmpty ? 50 : shown.map((s) => s.$2).reduce(math.min);
    final hi = shown.isEmpty ? 120 : shown.map((s) => s.$2).reduce(math.max);
    final floor = ((lo - 10) ~/ 10) * 10.0;
    final ceil = ((hi + 19) ~/ 10) * 10.0;
    const labelWidth = 30.0;
    final plot = Rect.fromLTWH(0, 6, size.width - labelWidth, size.height - 12);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.5;
    for (final v in [floor, (floor + ceil) / 2, ceil]) {
      final y = plot.bottom - (v - floor) / (ceil - floor) * plot.height;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: v.round().toString(),
          style: TextStyle(color: label, fontSize: 10, fontFamily: fontFamily),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(plot.right + 6, y - tp.height / 2));
    }
    if (shown.isEmpty) return;

    Offset at((DateTime, int) s) {
      final x =
          plot.left +
          s.$1.difference(start).inMilliseconds /
              window.inMilliseconds *
              plot.width;
      final y = plot.bottom - (s.$2 - floor) / (ceil - floor) * plot.height;
      return Offset(x, y);
    }

    final line = Path();
    final area = Path();
    // A long gap splits the line (band off the wrist or not measuring);
    // all-day readings can be several minutes apart.
    const gap = Duration(minutes: 15);
    for (var i = 0; i < shown.length; i++) {
      final p = at(shown[i]);
      final newSegment =
          i == 0 || shown[i].$1.difference(shown[i - 1].$1) > gap;
      if (newSegment) {
        if (i > 0) area.lineTo(at(shown[i - 1]).dx, plot.bottom);
        line.moveTo(p.dx, p.dy);
        area
          ..moveTo(p.dx, plot.bottom)
          ..lineTo(p.dx, p.dy);
      } else {
        line.lineTo(p.dx, p.dy);
        area.lineTo(p.dx, p.dy);
      }
    }
    area
      ..lineTo(at(shown.last).dx, plot.bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.35),
            lineColor.withValues(alpha: 0),
          ],
        ).createShader(plot),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = lineColor,
    );
    canvas.drawCircle(at(shown.last), 4, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(HeartRatePainter old) =>
      old.samples.length != samples.length ||
      old.end != end ||
      old.window != window ||
      old.grid != grid ||
      old.lineColor != lineColor;
}

/// Samples from a time-sorted map, newest [window] only.
List<(DateTime, int)> recentSamples(
  Map<DateTime, int> history,
  Duration window, {
  DateTime? now,
}) {
  final from = (now ?? DateTime.now()).subtract(window);
  return [
    for (final e in history.entries)
      if (!e.key.isBefore(from)) (e.key, e.value),
  ];
}

/// A chart window that fits [samples]: at least [min], at most [max].
Duration fittedWindow(
  List<(DateTime, int)> samples, {
  Duration min = const Duration(hours: 1),
  Duration max = const Duration(hours: 24),
  DateTime? now,
}) {
  if (samples.isEmpty) return min;
  final span = (now ?? DateTime.now()).difference(samples.first.$1);
  final hours = (span.inMinutes / 60).ceil().clamp(min.inHours, max.inHours);
  return Duration(hours: hours);
}

/// (min, average, max) bpm, or null when there are no samples.
(int, int, int)? heartRateStats(List<(DateTime, int)> samples) {
  if (samples.isEmpty) return null;
  final bpm = samples.map((s) => s.$2);
  final sum = bpm.fold(0, (a, b) => a + b);
  return (
    bpm.reduce(math.min),
    (sum / samples.length).round(),
    bpm.reduce(math.max),
  );
}
