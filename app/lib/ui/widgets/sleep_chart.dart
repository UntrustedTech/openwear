/// A night drawn as stages (awake, REM, light, deep from top to bottom), or
/// as one asleep band when the band did not stage it.
library;

import 'package:flutter/material.dart';
import 'package:openwear/protocol/sleep.dart';
import 'package:openwear/ui/theme.dart';

abstract final class StageColors {
  static const deep = Color(0xFF5B4BDB);
  static const light = Metric.sleep;
  static const rem = Color(0xFF4FC9F0);
  static const awake = Color(0xFFF5C445);

  static Color of(SleepStage s) => switch (s) {
    SleepStage.deep => deep,
    SleepStage.light => light,
    SleepStage.rem => rem,
    SleepStage.awake => awake,
    SleepStage.unknown => light,
  };
}

String stageName(SleepStage s) => switch (s) {
  SleepStage.deep => 'Deep',
  SleepStage.light => 'Light',
  SleepStage.rem => 'REM',
  SleepStage.awake => 'Awake',
  SleepStage.unknown => 'Asleep',
};

/// Lanes from the top.
const _lanes = [
  SleepStage.awake,
  SleepStage.rem,
  SleepStage.light,
  SleepStage.deep,
];

String clockTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class SleepChart extends StatelessWidget {
  const SleepChart({super.key, required this.session, this.height = 120});
  final SleepSession session;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = session;
    final from = s.wentToBed != null && s.wentToBed!.isBefore(s.start)
        ? s.wentToBed!
        : s.start;
    final to = s.leftBed != null && s.leftBed!.isAfter(s.end)
        ? s.leftBed!
        : s.end;
    return Column(
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            size: Size.infinite,
            painter: _SleepPainter(
              session: s,
              from: from,
              to: to,
              colors: {
                for (final x in _lanes) x: sys(context, StageColors.of(x)),
              },
              track: p.raised,
            ),
          ),
        ),
        const SizedBox(height: Space.s),
        Row(
          children: [
            Text(clockTime(from), style: T.unit.copyWith(color: p.muted)),
            const Spacer(),
            Text(clockTime(to), style: T.unit.copyWith(color: p.muted)),
          ],
        ),
      ],
    );
  }
}

class _SleepPainter extends CustomPainter {
  _SleepPainter({
    required this.session,
    required this.from,
    required this.to,
    required this.colors,
    required this.track,
  });

  final SleepSession session;
  final DateTime from;
  final DateTime to;
  final Map<SleepStage, Color> colors;
  final Color track;

  double _x(DateTime t, Size size) {
    final span = to.difference(from).inSeconds;
    if (span <= 0) return 0;
    return (t.difference(from).inSeconds / span).clamp(0.0, 1.0) * size.width;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (session.hasStages) {
      _paintStages(canvas, size);
    } else {
      _paintAsleep(canvas, size);
    }
  }

  void _paintStages(Canvas canvas, Size size) {
    final laneHeight = size.height / _lanes.length;
    const gap = 3.0;
    for (var i = 0; i < _lanes.length; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            0,
            i * laneHeight + gap,
            size.width,
            laneHeight - 2 * gap,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = track.withValues(alpha: 0.5),
      );
    }
    for (final span in session.stages) {
      final lane = _lanes.indexOf(
        span.stage == SleepStage.unknown ? SleepStage.light : span.stage,
      );
      final left = _x(span.start, size), right = _x(span.end, size);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            left,
            lane * laneHeight + gap,
            (right - left) < 1.5 ? left + 1.5 : right,
            (lane + 1) * laneHeight - gap,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = colors[_lanes[lane]]!,
      );
    }
  }

  void _paintAsleep(Canvas canvas, Size size) {
    final band = Rect.fromLTWH(
      0,
      size.height * 0.3,
      size.width,
      size.height * 0.4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(band, const Radius.circular(6)),
      Paint()..color = track,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          _x(session.start, size),
          band.top,
          _x(session.end, size),
          band.bottom,
        ),
        const Radius.circular(6),
      ),
      Paint()..color = colors[SleepStage.light]!,
    );
  }

  @override
  bool shouldRepaint(_SleepPainter old) =>
      old.session != session || old.colors != colors || old.track != track;
}

/// Each stage's share of the night as one stacked bar.
class StageBar extends StatelessWidget {
  const StageBar({super.key, required this.totals});
  final Map<SleepStage, Duration> totals;

  @override
  Widget build(BuildContext context) {
    final parts = [
      for (final s in _lanes.reversed)
        if ((totals[s] ?? Duration.zero) > Duration.zero) (s, totals[s]!),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            for (final (s, d) in parts)
              Expanded(
                flex: d.inMinutes.clamp(1, 1 << 20),
                child: ColoredBox(color: sys(context, StageColors.of(s))),
              ),
          ],
        ),
      ),
    );
  }
}
