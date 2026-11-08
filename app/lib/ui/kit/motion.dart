/// Small looping and entrance animations. Each one stands still when
/// Appearance → Reduce motion is on, and loops stop on hidden tabs
/// (TickerMode), so they cost nothing off screen.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openwear/ui/theme.dart';

/// [duration], or nothing when motion is reduced.
Duration motionFor(Duration duration) =>
    reduceMotion ? Duration.zero : duration;

/// A heart that beats at [bpm]: a quick double thump, then rest.
/// Without a reading (or with reduced motion) it stays still.
class Heartbeat extends StatefulWidget {
  const Heartbeat({
    super.key,
    required this.bpm,
    required this.color,
    this.size = 16,
  });

  final int? bpm;
  final Color color;
  final double size;

  @override
  State<Heartbeat> createState() => _HeartbeatState();
}

class _HeartbeatState extends State<Heartbeat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  static const _minBpm = 30, _maxBpm = 220;

  /// Scale over one beat: "lub" peak, small "dub", then rest.
  static final _beat = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 1.22), weight: 12),
    TweenSequenceItem(tween: Tween(begin: 1.22, end: 1), weight: 12),
    TweenSequenceItem(tween: Tween(begin: 1, end: 1.1), weight: 10),
    TweenSequenceItem(tween: Tween(begin: 1.1, end: 1), weight: 14),
    TweenSequenceItem(tween: ConstantTween(1), weight: 52),
  ]);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(Heartbeat old) {
    super.didUpdateWidget(old);
    if (old.bpm != widget.bpm) _sync();
  }

  void _sync() {
    final bpm = widget.bpm;
    if (bpm == null || bpm <= 0 || reduceMotion) {
      _c
        ..stop()
        ..value = 0;
      return;
    }
    final period = 60000 ~/ bpm.clamp(_minBpm, _maxBpm);
    _c
      ..duration = Duration(milliseconds: period)
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _beat.animate(_c),
    child: Icon(Icons.favorite_rounded, size: widget.size, color: widget.color),
  );
}

/// A dot with a ring that slowly swells and fades, for "live" states.
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key, required this.color, this.size = 6});
  final Color color;
  final double size;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (!reduceMotion) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox.square(
      dimension: s * 2.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _DotPainter(
            widget.color,
            s,
            Curves.easeOut.transform(_c.value),
          ),
        ),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.color, this.dot, this.t);
  final Color color;
  final double dot;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    if (t > 0) {
      canvas.drawCircle(
        c,
        dot / 2 + (size.width / 2 - dot / 2) * t,
        Paint()..color = color.withValues(alpha: 0.45 * (1 - t)),
      );
    }
    canvas.drawCircle(c, dot / 2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.t != t || old.color != color || old.dot != dot;
}

/// Plays a short fade and rise each time [active] turns true, e.g. when
/// its tab is selected.
class ShowOnActivate extends StatefulWidget {
  const ShowOnActivate({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<ShowOnActivate> createState() => _ShowOnActivateState();
}

class _ShowOnActivateState extends State<ShowOnActivate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.slow,
    value: 1,
  );

  @override
  void didUpdateWidget(ShowOnActivate old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !reduceMotion) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    // Always the same widgets around the child, even when finished:
    // swapping the wrapper in and out would remount the whole page.
    builder: (context, child) {
      final t = Motion.ease.transform(_c.value);
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - t)),
          child: child,
        ),
      );
    },
  );
}

/// Briefly pops [child] (a tab icon) when [active] turns true.
class PopOnActivate extends StatefulWidget {
  const PopOnActivate({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<PopOnActivate> createState() => _PopOnActivateState();
}

class _PopOnActivateState extends State<PopOnActivate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  @override
  void didUpdateWidget(PopOnActivate old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !reduceMotion) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) => Transform.scale(
      // Up to 1.18 and back, following half a sine.
      scale: 1 + 0.18 * math.sin(math.pi * _c.value),
      child: child,
    ),
  );
}
