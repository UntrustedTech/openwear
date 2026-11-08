import 'package:flutter/material.dart';
import 'package:openwear/ui/theme.dart' show reduceMotion;

/// The OpenWear mark (see brand/make_icons.py): a band outline with an
/// orange pulse running through it, on the app background.
///
/// With [animate], the pulse traces itself across the band once when the
/// logo appears (skipped under Reduce motion).
class OpenWearLogo extends StatelessWidget {
  const OpenWearLogo({super.key, this.size = 56, this.animate = false});
  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: animate && !reduceMotion
        ? TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeInOutCubic,
            builder: (context, t, _) =>
                CustomPaint(painter: _MarkPainter(trace: t)),
          )
        : CustomPaint(painter: _MarkPainter()),
  );
}

const _background = Color(0xFF0C0C0E),
    _band = Color(0xFFF2F0E9),
    _pulse = Color(0xFFFF5B1F);

/// Same geometry as the launcher icon, in its 108-unit space; the tile
/// shows units 18–90.
const _pulsePoints = [
  Offset(23, 54),
  Offset(45.5, 54),
  Offset(49.5, 42),
  Offset(54.5, 66),
  Offset(59, 46),
  Offset(62.5, 54),
  Offset(85, 54),
];

class _MarkPainter extends CustomPainter {
  _MarkPainter({this.trace = 1});

  /// How much of the pulse is drawn, 0..1.
  final double trace;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 72;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(16 * k)),
        Paint()..color = _background,
      )
      ..save()
      ..scale(k)
      ..translate(-18, -18);
    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(
      RRect.fromLTRBR(38, 26, 70, 82, const Radius.circular(16)),
      stroke(_band, 4.5),
    );
    var pulse = Path()..addPolygon(_pulsePoints, false);
    if (trace < 1) {
      final metric = pulse.computeMetrics().first;
      pulse = metric.extractPath(0, metric.length * trace);
    }
    canvas
      ..drawPath(pulse, stroke(_background, 11))
      ..drawPath(pulse, stroke(_pulse, 4.6))
      ..restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.trace != trace;
}
