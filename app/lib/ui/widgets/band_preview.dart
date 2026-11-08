/// A live drawing of the paired band: body and straps painted from a shape
/// table, the screen showing the real time, battery, heart rate and the last
/// notification. Original artwork, no vendor assets.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:openwear/protocol/models.dart';
import 'package:openwear/ui/theme.dart';

enum BandShape { capsule, rectangle, round }

/// Shape and proportions per model family; unknown names get the capsule.
class BandModel {
  const BandModel(this.shape, {required this.aspect, required this.bezel});
  final BandShape shape;

  /// Body width / height.
  final double aspect;

  /// Black border around the screen, as a fraction of the body width.
  final double bezel;

  static const capsule = BandModel(
    BandShape.capsule,
    aspect: 0.42,
    bezel: 0.04,
  );
  static const rectangle = BandModel(
    BandShape.rectangle,
    aspect: 0.62,
    bezel: 0.04,
  );
  static const round = BandModel(BandShape.round, aspect: 1, bezel: 0.08);

  /// Best guess from the band's advertised name or model id.
  static BandModel forName(String name, {String? modelId}) {
    final known = wearModelFor(bluetoothName: name, modelId: modelId);
    if (known != null) {
      final w = known.width, h = known.height;
      switch (known.shape) {
        case BandScreenShape.round:
          return round;
        case BandScreenShape.capsule:
          return capsule;
        case BandScreenShape.rectangle when w != null && h != null:
          return BandModel(
            BandShape.rectangle,
            aspect: w / h,
            bezel: rectangle.bezel,
          );
        case BandScreenShape.rectangle:
          return rectangle;
      }
    }
    final n = name.toLowerCase();
    if (n.contains('watch') && !n.contains('miwear.watch.n6')) return round;
    if (n.contains('band 8 pro') ||
        n.contains('band 9 pro') ||
        n.contains('band 10 pro') ||
        n.contains('redmi')) {
      return rectangle;
    }
    return capsule;
  }
}

enum FaceStyle { digital, analog }

FaceStyle faceStyleFor(String? faceName) {
  final n = (faceName ?? '').toLowerCase();
  const analogWords = ['analog', 'classic', 'dial', 'pointer', 'hands'];
  return analogWords.any(n.contains) ? FaceStyle.analog : FaceStyle.digital;
}

class BandScreenData {
  const BandScreenData({
    required this.connected,
    this.battery,
    this.heartRate,
    this.faceName,
    this.notificationApp,
    this.notificationTitle,
    this.notificationTime,
    this.screenshot,
  });

  final bool connected;

  /// A PNG captured from the band for this face; drawn instead of the
  /// built-in sketch when set.
  final Uint8List? screenshot;
  final int? battery;
  final int? heartRate;
  final String? faceName;

  /// Shown as a banner when set (the caller decides how long).
  final String? notificationApp;
  final String? notificationTitle;

  /// When the notification arrived; the preview shows it for
  /// [BandPreview.notificationFor].
  final DateTime? notificationTime;
}

class BandPreview extends StatefulWidget {
  static const notificationFor = Duration(seconds: 8);

  const BandPreview({
    super.key,
    required this.model,
    required this.data,
    this.height = 300,
  });

  final BandModel model;
  final BandScreenData data;
  final double height;

  @override
  State<BandPreview> createState() => _BandPreviewState();
}

class _BandPreviewState extends State<BandPreview>
    with TickerProviderStateMixin {
  late Timer _tick;
  DateTime _now = DateTime.now();

  /// Slides the notification banner in (1) and out (0).
  late final AnimationController _banner = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    reverseDuration: const Duration(milliseconds: 300),
  );

  /// Screen wakes (1) when connected, dims (0) when not.
  late final AnimationController _power = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    value: widget.data.connected ? 1 : 0,
  );
  String? _app, _title;
  DateTime? _shownAt;
  ui.Image? _shot;
  Uint8List? _shotBytes;

  Future<void> _decodeShot() async {
    final bytes = widget.data.screenshot;
    if (identical(bytes, _shotBytes)) return;
    _shotBytes = bytes;
    if (bytes == null) {
      setState(() => _shot = null);
      return;
    }
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted || !identical(bytes, _shotBytes)) return;
      setState(() => _shot = frame.image);
    } on Exception {
      if (mounted) setState(() => _shot = null);
    }
  }

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _syncBanner();
    });
    _syncBanner();
    unawaited(_decodeShot());
  }

  @override
  void didUpdateWidget(BandPreview old) {
    super.didUpdateWidget(old);
    if (old.data.connected != widget.data.connected) {
      widget.data.connected ? _power.forward() : _power.reverse();
    }
    _syncBanner();
    unawaited(_decodeShot());
  }

  void _syncBanner() {
    final d = widget.data;
    final at = d.notificationTime;
    final fresh =
        d.connected &&
        d.notificationApp != null &&
        at != null &&
        DateTime.now().difference(at) < BandPreview.notificationFor;
    if (fresh && at != _shownAt) {
      _shownAt = at;
      _app = d.notificationApp;
      _title = d.notificationTitle;
      _banner.forward(from: 0);
    } else if (!fresh && _banner.status != AnimationStatus.dismissed) {
      if (_banner.status != AnimationStatus.reverse) _banner.reverse();
    }
  }

  @override
  void dispose() {
    _tick.cancel();
    _banner.dispose();
    _power.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final bodyHeight =
        widget.height * (m.shape == BandShape.round ? 0.55 : 0.78);
    final width = bodyHeight * m.aspect;
    return Semantics(
      label: widget.data.connected
          ? 'Band preview, connected'
          : 'Band preview, disconnected',
      child: SizedBox(
        height: widget.height,
        width: math.max(width * 1.25, 110),
        child: AnimatedBuilder(
          animation: Listenable.merge([_banner, _power]),
          builder: (context, _) => CustomPaint(
            painter: BandPainter(
              model: m,
              data: widget.data,
              now: _now,
              dark: MediaQuery.platformBrightnessOf(context) == Brightness.dark,
              fontFamily: fontFamily,
              banner: Curves.easeOutBack.transform(_banner.value).clamp(0, 1.2),
              bannerApp: _app,
              bannerTitle: _title,
              power: Curves.easeInOut.transform(_power.value),
              shot: _shot,
            ),
          ),
        ),
      ),
    );
  }
}

class BandPainter extends CustomPainter {
  BandPainter({
    required this.model,
    required this.data,
    required this.now,
    required this.dark,
    this.fontFamily,
    this.banner = 0,
    this.bannerApp,
    this.bannerTitle,
    this.power = 1,
    this.shot,
  });

  /// The face as captured from the band, if any.
  final ui.Image? shot;

  final String? fontFamily;

  /// 0 hidden … 1 fully in (may overshoot slightly while springing).
  final double banner;
  final String? bannerApp;
  final String? bannerTitle;

  /// 0 asleep (disconnected) … 1 awake.
  final double power;
  final BandModel model;
  final BandScreenData data;
  final DateTime now;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final round = model.shape == BandShape.round;
    final bodyH = size.height * (round ? 0.55 : 0.78);
    final bodyW = bodyH * model.aspect;
    final c = size.center(Offset.zero);
    final body = Rect.fromCenter(center: c, width: bodyW, height: bodyH);

    _straps(canvas, size, body);
    final bodyShape = _bodyShape(body);
    canvas.drawShadow(Path()..addRRect(bodyShape), Colors.black, 10, false);
    canvas.drawRRect(
      bodyShape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [
            Color(0xFF5A5C60),
            Color(0xFF2B2C2F),
            Color(0xFF45474B),
          ],
        ).createShader(body),
    );
    // Glass with a slight sheen.
    final glass = bodyShape.deflate(bodyW * 0.025);
    canvas.drawRRect(glass, Paint()..color = const Color(0xFF050505));
    final screen = glass.deflate(bodyW * model.bezel);
    canvas.save();
    canvas.clipRRect(screen);
    _screen(canvas, screen.outerRect);
    canvas.restore();
    canvas.drawRRect(
      glass,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.center,
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(glass.outerRect),
    );
  }

  RRect _bodyShape(Rect body) => switch (model.shape) {
    BandShape.capsule => RRect.fromRectAndRadius(
      body,
      Radius.circular(body.width / 2),
    ),
    BandShape.rectangle => RRect.fromRectAndRadius(
      body,
      Radius.circular(body.width * 0.22),
    ),
    BandShape.round => RRect.fromRectAndRadius(
      body,
      Radius.circular(body.width / 2),
    ),
  };

  void _straps(Canvas canvas, Size size, Rect body) {
    final strapW = body.width * (model.shape == BandShape.round ? 0.55 : 0.82);
    final colour = dark ? const Color(0xFF2C2C2E) : const Color(0xFF3A3A3C);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [colour, Color.lerp(colour, Colors.white, 0.08)!, colour],
      ).createShader(Rect.fromLTWH(body.center.dx - strapW / 2, 0, strapW, 1));
    final top = RRect.fromLTRBAndCorners(
      body.center.dx - strapW / 2,
      0,
      body.center.dx + strapW / 2,
      body.center.dy,
      topLeft: Radius.circular(strapW * 0.3),
      topRight: Radius.circular(strapW * 0.3),
    );
    final bottom = RRect.fromLTRBAndCorners(
      body.center.dx - strapW / 2,
      body.center.dy,
      body.center.dx + strapW / 2,
      size.height,
      bottomLeft: Radius.circular(strapW * 0.3),
      bottomRight: Radius.circular(strapW * 0.3),
    );
    canvas
      ..drawRRect(top, paint)
      ..drawRRect(bottom, paint);
    // Strap holes on the lower strap.
    final hole = Paint()..color = Colors.black.withValues(alpha: 0.35);
    for (var y = body.bottom + strapW * 0.5; y < size.height - 8; y += 14) {
      canvas.drawCircle(Offset(body.center.dx, y), 2.4, hole);
    }
  }

  void _screen(Canvas canvas, Rect r) {
    canvas.drawRect(r, Paint()..color = Colors.black);
    if (power < 1) {
      canvas.saveLayer(r, Paint()..color = Color.fromRGBO(0, 0, 0, 1 - power));
      _disconnected(canvas, r);
      canvas.restore();
    }
    if (power > 0) {
      canvas.saveLayer(r, Paint()..color = Color.fromRGBO(0, 0, 0, power));
      final image = shot;
      if (image != null) {
        paintImage(
          canvas: canvas,
          rect: r,
          image: image,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        );
      } else {
        switch (faceStyleFor(data.faceName)) {
          case FaceStyle.analog:
            _analog(canvas, r);
          case FaceStyle.digital:
            _digital(canvas, r);
        }
      }
      canvas.restore();
    }
    if (banner > 0.01 && bannerApp != null) _banner(canvas, r);
  }

  void _digital(Canvas canvas, Rect r) {
    final w = r.width;
    final tall = r.height / r.width > 1.4;
    String two(int n) => n.toString().padLeft(2, '0');
    final big = TextStyle(
      color: Colors.white,
      fontSize: w * (tall ? 0.42 : 0.3),
      fontWeight: FontWeight.w700,
      height: 1,
      letterSpacing: -1,
    );
    var y = r.top + r.height * 0.1;
    y += _text(
      canvas,
      _weekdayDate(now),
      r.center.dx,
      y,
      TextStyle(
        color: Metric.steps,
        fontSize: w * 0.1,
        fontWeight: FontWeight.w600,
      ),
    );
    y += r.height * 0.02;
    if (tall) {
      y += _text(canvas, two(now.hour), r.center.dx, y, big);
      y += _text(
        canvas,
        two(now.minute),
        r.center.dx,
        y,
        big.copyWith(color: Metric.stand),
      );
    } else {
      y += _text(
        canvas,
        '${two(now.hour)}:${two(now.minute)}',
        r.center.dx,
        y,
        big,
      );
    }
    y += r.height * 0.05;
    final small = TextStyle(
      color: Colors.white,
      fontSize: w * 0.11,
      fontWeight: FontWeight.w600,
    );
    final hr = data.heartRate;
    _iconText(
      canvas,
      Icons.favorite,
      Metric.heart,
      hr == null || hr == 0 ? '--' : '$hr',
      Offset(r.center.dx, y),
      small,
    );
    y += w * 0.18;
    final battery = data.battery;
    if (battery != null) {
      _batteryBar(
        canvas,
        Rect.fromCenter(
          center: Offset(
            r.center.dx,
            math.min(y + w * 0.06, r.bottom - w * 0.18),
          ),
          width: w * 0.5,
          height: w * 0.08,
        ),
        battery,
      );
    }
  }

  void _analog(Canvas canvas, Rect r) {
    final c = Offset(r.center.dx, r.center.dy - r.height * 0.05);
    final radius = r.width * 0.42;
    final tick = Paint()
      ..color = Colors.white70
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final outer = c + Offset(math.sin(a), -math.cos(a)) * radius;
      final inner =
          c +
          Offset(math.sin(a), -math.cos(a)) *
              radius *
              (i % 3 == 0 ? 0.78 : 0.88);
      canvas.drawLine(inner, outer, tick..strokeWidth = i % 3 == 0 ? 3 : 1.5);
    }
    void hand(double turns, double length, double width, Color colour) {
      final a = turns * 2 * math.pi;
      canvas.drawLine(
        c,
        c + Offset(math.sin(a), -math.cos(a)) * radius * length,
        Paint()
          ..color = colour
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    hand((now.hour % 12 + now.minute / 60) / 12, 0.5, 4, Colors.white);
    hand((now.minute + now.second / 60) / 60, 0.75, 3, Colors.white);
    hand(now.second / 60, 0.85, 1.2, Metric.steps);
    canvas.drawCircle(c, 3.5, Paint()..color = Metric.steps);
    final hr = data.heartRate;
    final small = TextStyle(
      color: Colors.white,
      fontSize: r.width * 0.11,
      fontWeight: FontWeight.w600,
    );
    _iconText(
      canvas,
      Icons.favorite,
      Metric.heart,
      hr == null || hr == 0 ? '--' : '$hr',
      Offset(r.center.dx, c.dy + radius + r.width * 0.12),
      small,
    );
  }

  void _disconnected(Canvas canvas, Rect r) {
    String two(int n) => n.toString().padLeft(2, '0');
    final style = TextStyle(
      color: Colors.white38,
      fontSize: r.width * 0.3,
      fontWeight: FontWeight.w600,
    );
    var y = r.center.dy - r.width * 0.45;
    y += _text(
      canvas,
      '${two(now.hour)}:${two(now.minute)}',
      r.center.dx,
      y,
      style,
    );
    _iconText(
      canvas,
      Icons.bluetooth_disabled,
      Colors.white38,
      'Offline',
      Offset(r.center.dx, y + r.width * 0.1),
      TextStyle(color: Colors.white38, fontSize: r.width * 0.1),
    );
  }

  void _banner(Canvas canvas, Rect r) {
    final h = r.width * 0.62;
    final slide = (1 - banner) * (h + r.height * 0.08);
    canvas.saveLayer(
      r,
      Paint()..color = Color.fromRGBO(0, 0, 0, banner.clamp(0, 1)),
    );
    final card = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        r.left + 4,
        r.top + r.height * 0.08 - slide,
        r.width - 8,
        r.width * 0.62,
      ),
      Radius.circular(r.width * 0.12),
    );
    canvas.drawRRect(card, Paint()..color = const Color(0xF22C2C2E));
    final w = r.width;
    var y = card.top + w * 0.08;
    y += _text(
      canvas,
      bannerApp ?? '',
      r.center.dx,
      y,
      TextStyle(
        color: Metric.weather,
        fontSize: w * 0.09,
        fontWeight: FontWeight.w700,
      ),
      maxWidth: card.width - 8,
    );
    _text(
      canvas,
      bannerTitle ?? '',
      r.center.dx,
      y + 2,
      TextStyle(color: Colors.white, fontSize: w * 0.085),
      maxWidth: card.width - 10,
      maxLines: 3,
    );
    canvas.restore();
  }

  void _batteryBar(Canvas canvas, Rect r, int percent) {
    final colour = percent <= 20 ? const Color(0xFFFF453A) : Metric.battery;
    final shell = RRect.fromRectAndRadius(r, Radius.circular(r.height / 2));
    canvas.drawRRect(shell, Paint()..color = colour.withValues(alpha: 0.25));
    final fill = Rect.fromLTWH(
      r.left,
      r.top,
      r.width * percent.clamp(0, 100) / 100,
      r.height,
    );
    canvas.save();
    canvas.clipRRect(shell);
    canvas.drawRect(fill, Paint()..color = colour);
    canvas.restore();
  }

  /// Draws centred text with its top at [y]; returns its height.
  double _text(
    Canvas canvas,
    String s,
    double cx,
    double y,
    TextStyle style, {
    double? maxWidth,
    int maxLines = 1,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: style.copyWith(fontFamily: style.fontFamily ?? fontFamily),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    tp.paint(canvas, Offset(cx - tp.width / 2, y));
    return tp.height;
  }

  void _iconText(
    Canvas canvas,
    IconData icon,
    Color colour,
    String s,
    Offset topCenter,
    TextStyle style,
  ) {
    final size = style.fontSize ?? 12;
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          color: colour,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final label = TextPainter(
      text: TextSpan(
        text: s,
        style: style.copyWith(fontFamily: style.fontFamily ?? fontFamily),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final total = iconPainter.width + 4 + label.width;
    final x = topCenter.dx - total / 2;
    iconPainter.paint(
      canvas,
      Offset(x, topCenter.dy + (label.height - iconPainter.height) / 2),
    );
    label.paint(canvas, Offset(x + iconPainter.width + 4, topCenter.dy));
  }

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  String _weekdayDate(DateTime t) => '${_days[t.weekday - 1]} ${t.day}';

  @override
  bool shouldRepaint(BandPainter old) =>
      old.now.second != now.second ||
      old.banner != banner ||
      old.power != power ||
      old.shot != shot ||
      old.dark != dark ||
      old.model != model ||
      old.data.connected != data.connected ||
      old.data.battery != data.battery ||
      old.data.heartRate != data.heartRate ||
      old.data.faceName != data.faceName ||
      old.data.notificationApp != data.notificationApp ||
      old.data.notificationTitle != data.notificationTitle;
}
