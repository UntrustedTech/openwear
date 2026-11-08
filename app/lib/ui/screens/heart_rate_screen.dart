import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/ui/common.dart';
import 'package:openwear/ui/kit/kit.dart';
import 'package:openwear/ui/widgets/hr_chart.dart';

/// Live heart rate: a monitor that pulses at the measured pace, the last
/// minute as a chart and min/avg/max for the past hour.
class HeartRateScreen extends StatelessWidget {
  const HeartRateScreen({super.key, required this.band});
  final BandService band;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: subPageBar(context, 'Heart rate'),
    body: ListenableBuilder(
      listenable: band,
      builder: (context, _) => _body(context),
    ),
  );

  Widget _body(BuildContext context) {
    final p = Palette.of(context);
    final hr = band.heartRate;
    final live = hr != null;
    final minute = recentSamples(band.hrHistory, const Duration(minutes: 1));
    final hour = recentSamples(band.hrHistory, const Duration(hours: 1));
    final stats = heartRateStats(hour);
    final status = switch (hr) {
      null => 'Start a reading to see your pulse live.',
      0 => 'Measuring… keep the band snug on your wrist.',
      _ => 'Live from your band',
    };
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.xl,
        Space.gutter,
        Space.xxl,
      ),
      children: [
        Center(
          child: PulseMonitor(
            bpm: live && hr > 0 ? hr : null,
            color: Metric.heart,
            track: p.line,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedNumber(
                  value: hr == null || hr == 0 ? null : hr,
                  placeholder: hr == 0 ? '…' : '—',
                  style: T
                      .numeral(72)
                      .copyWith(color: live && hr > 0 ? p.text : p.faint),
                ),
                const SizedBox(height: Space.s),
                Text(
                  'BPM',
                  style: T.unit.copyWith(color: p.tone(Metric.heart)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.l),
        AnimatedSwitcher(
          duration: Motion.base,
          child: Text(
            status,
            key: ValueKey(status),
            textAlign: TextAlign.center,
            style: T.small.copyWith(color: p.muted),
          ),
        ),
        const SizedBox(height: Space.xl),
        if (!band.connected)
          ConnectPrompt(band: band, what: 'measure your heart rate')
        else
          ActionButton(
            label: live ? 'Stop reading' : 'Start live reading',
            icon: live ? Icons.stop_rounded : Icons.play_arrow_rounded,
            kind: live ? ButtonKind.secondary : ButtonKind.primary,
            color: Metric.heart,
            onPressed: () {
              HapticFeedback.mediumImpact();
              runAction(
                context,
                live ? band.stopHeartRate : band.startHeartRate,
              );
            },
          ),
        const SectionLabel('Last minute'),
        Panel(
          child: HeartRateChart(
            samples: minute,
            window: const Duration(minutes: 1),
          ),
        ),
        const SectionLabel('Past hour'),
        Row(
          children: [
            for (final (label, value) in [
              ('Min', stats?.$1),
              ('Avg', stats?.$2),
              ('Max', stats?.$3),
            ]) ...[
              if (label != 'Min') const SizedBox(width: Space.m),
              Expanded(
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow(label),
                      const SizedBox(height: Space.m),
                      Readout(value: value, size: 28),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A ring that sends out a ripple on every beat at [bpm]; still without a
/// reading.
class PulseMonitor extends StatefulWidget {
  const PulseMonitor({
    super.key,
    required this.bpm,
    required this.color,
    required this.track,
    this.size = 240,
    this.child,
  });

  final int? bpm;
  final Color color;
  final Color track;
  final double size;
  final Widget? child;

  @override
  State<PulseMonitor> createState() => _PulseMonitorState();
}

class _PulseMonitorState extends State<PulseMonitor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PulseMonitor old) {
    super.didUpdateWidget(old);
    if (old.bpm != widget.bpm) _sync();
  }

  void _sync() {
    final bpm = widget.bpm;
    if (bpm == null || bpm <= 0) {
      _beat
        ..stop()
        ..value = 0;
      return;
    }
    _beat
      ..duration = Duration(milliseconds: (60000 / bpm.clamp(30, 220)).round())
      ..repeat();
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _PulsePainter(
              beat: _beat,
              active: widget.bpm != null,
              color: widget.color,
              track: widget.track,
            ),
          ),
        ),
        ?widget.child,
      ],
    ),
  );
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.beat,
    required this.active,
    required this.color,
    required this.track,
  }) : super(repaint: beat);

  final Animation<double> beat;
  final bool active;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final base = r * 0.72;
    final t = beat.value;
    // Scale ticks around the ring, like a bezel.
    final tick = Paint()
      ..color = track
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 72; i++) {
      final a = 2 * math.pi * i / 72;
      final d = Offset(math.cos(a), math.sin(a));
      final len = i % 6 == 0 ? 8.0 : 4.0;
      canvas.drawLine(c + d * (r - len), c + d * r, tick);
    }
    canvas.drawCircle(
      c,
      base,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = active ? color : track,
    );
    if (!active) return;
    // Ripple travelling out to the bezel, fading as it goes.
    final ease = Curves.easeOut.transform(t);
    canvas.drawCircle(
      c,
      base + (r - 10 - base) * ease,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * (1 - ease) + 0.5
        ..color = color.withValues(alpha: 0.7 * (1 - ease)),
    );
    // Soft fill that swells on the beat.
    final swell = t < 0.15 ? t / 0.15 : 1 - (t - 0.15) / 0.85;
    canvas.drawCircle(
      c,
      base - 1,
      Paint()..color = color.withValues(alpha: 0.05 + 0.07 * swell),
    );
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.active != active || old.color != color || old.track != track;
}
