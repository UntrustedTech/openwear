/// Instrument-style gauges: a tick dial for the day's main goal and
/// segmented bars for the others and for battery.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:openwear/ui/kit/basics.dart';
import 'package:openwear/ui/kit/motion.dart';

/// Animates a 0..n value from its previous value (0 on first show).
class _Animated extends StatelessWidget {
  const _Animated({required this.value, required this.builder});
  final double value;
  final Widget Function(double) builder;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    // Fills from empty only while the page opens, not when the card is
    // rebuilt after scrolling back into view.
    tween: Tween(begin: EntranceScope.settled(context) ? value : 0, end: value),
    duration: motionFor(const Duration(milliseconds: 650)),
    curve: const Cubic(0.2, 0, 0, 1),
    builder: (context, v, _) => builder(v),
  );
}

/// A 240° arc of ticks; the first [progress] of them light up in [color].
/// Every tenth tick is longer, like the scale on a gauge.
class TickDial extends StatelessWidget {
  const TickDial({
    super.key,
    required this.progress,
    required this.color,
    required this.track,
    this.size = 220,
    this.child,
  });

  /// 0..n; null draws only the scale.
  final double? progress;
  final Color color;
  final Color track;
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        _Animated(
          value: progress ?? 0,
          builder: (v) => CustomPaint(
            size: Size.square(size),
            painter: TickDialPainter(progress: v, color: color, track: track),
          ),
        ),
        ?child,
      ],
    ),
  );
}

class TickDialPainter extends CustomPainter {
  TickDialPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  static const ticks = 60;
  static const sweep = 240 * math.pi / 180;
  static const start = math.pi / 2 + (2 * math.pi - sweep) / 2;

  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final lit = (progress.clamp(0, 1) * ticks).round();
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2, r * 0.028);
    for (var i = 0; i <= ticks; i++) {
      final a = start + sweep * i / ticks;
      final major = i % 10 == 0;
      final outer = r - paint.strokeWidth;
      final inner = outer - r * (major ? 0.14 : 0.085);
      final dir = Offset(math.cos(a), math.sin(a));
      paint.color = i <= lit && progress > 0
          ? Color.lerp(color.withValues(alpha: 0.45), color, i / ticks) ?? color
          : track;
      canvas.drawLine(c + dir * inner, c + dir * outer, paint);
    }
    // Past the goal: a ring of the metric colour closes the gap.
    if (progress >= 1) {
      final gapStart = start + sweep;
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = paint.strokeWidth
        ..color = color;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - paint.strokeWidth),
        gapStart + 0.12,
        2 * math.pi - sweep - 0.24,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(TickDialPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

/// A bar of [segments] cells; the first [progress] of them fill.
class SegmentBar extends StatelessWidget {
  const SegmentBar({
    super.key,
    required this.progress,
    required this.color,
    required this.track,
    this.segments = 24,
    this.height = 8,
  });

  final double? progress;
  final Color color;
  final Color track;
  final int segments;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: _Animated(
      value: progress ?? 0,
      builder: (v) => CustomPaint(
        size: Size.infinite,
        painter: SegmentPainter(
          progress: v,
          color: color,
          track: track,
          segments: segments,
        ),
      ),
    ),
  );
}

class SegmentPainter extends CustomPainter {
  SegmentPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.segments,
  });

  final double progress;
  final Color color;
  final Color track;
  final int segments;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    final w = (size.width - gap * (segments - 1)) / segments;
    final filled = progress.clamp(0, 1) * segments;
    final radius = Radius.circular(math.min(2, size.height / 2));
    for (var i = 0; i < segments; i++) {
      final rect = Rect.fromLTWH(i * (w + gap), 0, w, size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        Paint()..color = track,
      );
      final f = (filled - i).clamp(0.0, 1.0);
      if (f <= 0) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left, 0, w * f, size.height),
          radius,
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(SegmentPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.track != track ||
      old.segments != segments;
}

/// Ten battery cells coloured by level.
class BatteryCells extends StatelessWidget {
  const BatteryCells({
    super.key,
    required this.percent,
    required this.ok,
    required this.low,
    required this.track,
    this.width = 96,
  });

  final int percent;
  final Color ok;
  final Color low;
  final Color track;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: SegmentBar(
      progress: percent / 100,
      color: percent <= 20 ? low : ok,
      track: track,
      segments: 10,
      height: 10,
    ),
  );
}
