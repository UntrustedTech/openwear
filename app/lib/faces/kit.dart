/// Drawing kit for generated faces: paints rasters with Flutter's canvas and
/// collects them as face elements, and composes a preview from them.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:openwear/faces/calendar_names.dart';
import 'package:openwear/faces/face_binary.dart';
import 'package:openwear/faces/glyphs.dart';
import 'package:openwear/faces/image_codec.dart';

/// Smart Band 9 screen.
const screenW = 192, screenH = 490;

typedef Painter = void Function(Canvas c, Size s);
typedef IndexedPainter = void Function(Canvas c, Size s, int i);

/// Paints [w]×[h] straight-alpha RGBA pixels.
Future<Raster> render(int w, int h, Painter paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder), Size(w.toDouble(), h.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  if (data == null) throw StateError('could not read face pixels');
  return Raster(w, h, data.buffer.asUint8List());
}

TextPainter _layout(String text, TextStyle style) => TextPainter(
  text: TextSpan(text: text, style: style),
  textDirection: TextDirection.ltr,
)..layout();

/// Ten same-sized digit images, 0–9.
class Digits {
  const Digits(this.images);
  final List<Raster> images;
  int get width => images.first.width;
  int get height => images.first.height;
}

/// Values shown in previews.
const sampleValues = <FaceData, int>{
  FaceData.hour: 10,
  FaceData.minute: 9,
  FaceData.second: 36,
  FaceData.year: 2026,
  FaceData.month: 10,
  FaceData.day: 31,
  FaceData.weekday: 6,
  FaceData.battery: 76,
  FaceData.steps: 6842,
  FaceData.stepPercent: 68,
  FaceData.calories: 286,
  FaceData.heartRate: 72,
  FaceData.heartRateZone: 2,
  FaceData.standCount: 7,
  FaceData.sleepScore: 84,
  FaceData.stress: 32,
  FaceData.temperature: 16,
  FaceData.weather: 1,
  FaceData.hourHigh: 1,
  FaceData.hourLow: 0,
  FaceData.minuteHigh: 0,
  FaceData.minuteLow: 9,
};

class FaceKit {
  FaceKit(this.language);

  /// Phone language tag, for weekday and month names.
  final String language;
  final elements = <FaceElement>[];

  Future<void> background(Painter p) async =>
      elements.add(StaticImage(0, 0, await render(screenW, screenH, p)));

  Future<void> image(int x, int y, int w, int h, Painter p) async =>
      elements.add(StaticImage(x, y, await render(w, h, p)));

  /// Static text whose left edge (or centre, when [centerX]) is at [x].
  Future<void> text(
    int x,
    int y,
    String text,
    TextStyle style, {
    bool centerX = false,
  }) async {
    final tp = _layout(text, style);
    final w = tp.width.ceil() + 2, h = tp.height.ceil();
    elements.add(
      StaticImage(
        centerX ? x - w ~/ 2 : x,
        y,
        await render(w, h, (c, _) => tp.paint(c, const Offset(1, 0))),
      ),
    );
  }

  /// Digits set in [style], each centred in a cell as wide as the widest.
  Future<Digits> fontDigits(TextStyle style, {int extraWidth = 0}) async {
    final painters = [for (var d = 0; d < 10; d++) _layout('$d', style)];
    final w = painters.map((p) => p.width).reduce(math.max).ceil() + extraWidth;
    final h = painters.first.height.ceil();
    return Digits([
      for (final tp in painters)
        await render(
          w,
          h,
          (c, s) => tp.paint(c, Offset((w - tp.width) / 2, 0)),
        ),
    ]);
  }

  Future<Digits> paintedDigits(int w, int h, IndexedPainter p) async => Digits([
    for (var d = 0; d < 10; d++) await render(w, h, (c, s) => p(c, s, d)),
  ]);

  /// Width of [count] digits laid out with [spacing].
  static int numberWidth(Digits d, int count, {int spacing = 0}) =>
      count * d.width + (count - 1) * spacing;

  void number(
    int x,
    int y,
    FaceData source,
    Digits digits, {
    int count = 2,
    bool zeros = true,
    int spacing = 0,
  }) => elements.add(
    DigitNumber(
      x,
      y,
      source,
      digits.images,
      count: count,
      leadingZeros: zeros,
      spacing: spacing.clamp(0, 255),
    ),
  );

  /// hour:minute, centred unless [x] is given. Returns the left edge and
  /// the total width.
  Future<(int, int)> clock(
    int y,
    Digits d,
    TextStyle colon, {
    int gap = 2,
    int? x,
  }) async {
    final tp = _layout(':', colon);
    var cw = tp.width.ceil() + 2;
    int width() => 2 * numberWidth(d, 2) + 2 * gap + cw;
    // Too wide for the screen: tighten, then trim the digits' empty sides.
    // A number starting left of the screen is not drawn by the band.
    if (width() > screenW) {
      gap = 0;
      cw = tp.width.ceil();
    }
    if (width() > screenW) d = trimDigits(d);
    final w = numberWidth(d, 2);
    final total = width();
    final left = x ?? math.max(0, (screenW - total) ~/ 2);
    number(left, y, FaceData.hour, d);
    elements.add(
      StaticImage(
        left + w + gap,
        y,
        await render(
          cw,
          tp.height.ceil(),
          (c, _) => tp.paint(c, const Offset(1, 0)),
        ),
      ),
    );
    number(left + w + 2 * gap + cw, y, FaceData.minute, d);
    return (left, total);
  }

  /// [d] without the transparent columns all ten digits share on each side.
  static Digits trimDigits(Digits d) {
    final w = d.width, h = d.height;
    bool inked(Raster r, int x) {
      for (var y = 0; y < h; y++) {
        if (r.rgba[(y * w + x) * 4 + 3] != 0) return true;
      }
      return false;
    }

    var left = 0, right = w - 1;
    while (left < right && !d.images.any((r) => inked(r, left))) {
      left++;
    }
    while (right > left && !d.images.any((r) => inked(r, right))) {
      right--;
    }
    final nw = right - left + 1;
    if (nw == w) return d;
    return Digits([
      for (final r in d.images)
        Raster(
          nw,
          h,
          Uint8List.fromList([
            for (var y = 0; y < h; y++)
              ...r.rgba.sublist((y * w + left) * 4, (y * w + right + 1) * 4),
          ]),
        ),
    ]);
  }

  /// One image per entry of [values]; the band shows the last one reached.
  Future<void> switcher(
    int x,
    int y,
    int w,
    int h,
    FaceData source,
    List<int> values,
    IndexedPainter p,
  ) async => elements.add(
    ImageSwitch(x, y, source, [
      for (var i = 0; i < values.length; i++)
        await render(w, h, (c, s) => p(c, s, i)),
    ], values),
  );

  /// Percent thresholds 0, step, 2·step … 100.
  static List<int> percentSteps(int step) => [
    for (var v = 0; v <= 100; v += step) v,
  ];

  Future<void> _names(
    int x,
    int y,
    List<String> names,
    List<int> values,
    FaceData src,
    TextStyle style,
    bool center,
  ) async {
    final painters = [for (final n in names) _layout(n, style)];
    final w = painters.map((p) => p.width).reduce(math.max).ceil() + 2;
    final h = painters.map((p) => p.height).reduce(math.max).ceil();
    await switcher(center ? x - w ~/ 2 : x, y, w, h, src, values, (c, s, i) {
      final tp = painters[i];
      tp.paint(c, Offset(center ? (w - tp.width) / 2 : 1, 0));
    });
  }

  Future<void> weekday(
    int x,
    int y,
    TextStyle style, {
    bool upper = false,
    bool center = false,
  }) => _names(
    x,
    y,
    [for (final n in weekdayNames(language)) upper ? n.toUpperCase() : n],
    List.generate(7, (i) => i),
    FaceData.weekday,
    style,
    center,
  );

  Future<void> month(
    int x,
    int y,
    TextStyle style, {
    bool upper = false,
    bool center = false,
  }) => _names(
    x,
    y,
    [for (final n in monthNames(language)) upper ? n.toUpperCase() : n],
    List.generate(12, (i) => i + 1),
    FaceData.month,
    style,
    center,
  );

  /// Weather icon for every condition code the band sends.
  Future<void> weather(int x, int y, int size, Color color) => switcher(
    x,
    y,
    size,
    size,
    FaceData.weather,
    weatherCodes,
    (c, s, i) => paintWeather(c, s, weatherKind(weatherCodes[i]), color),
  );

  /// [frames] images played in a loop; `t` runs from 0 to just under 1.
  Future<void> animation(
    int x,
    int y,
    int w,
    int h,
    int frames,
    void Function(Canvas c, Size s, double t) p, {
    int intervalMs = 100,
  }) async => elements.add(
    Animation(x, y, [
      for (var i = 0; i < frames; i++)
        await render(w, h, (c, s) => p(c, s, i / frames)),
    ], intervalMs: intervalMs),
  );

  /// A Lua script the band runs over everything added before it.
  void lua(String entry, List<FaceFile> files) =>
      elements.add(LuaApp(entry, files));

  /// Builds the design with a preview composed from the sample values.
  Future<FaceDesign> finish(String id, String name) async => FaceDesign(
    id: id,
    name: name,
    elements: List.unmodifiable(elements),
    preview: await composePreview(elements, scale: 0.5),
  );
}

// --- previews --------------------------------------------------------------------

/// [r] as a drawable image.
Future<ui.Image> rasterImage(Raster r) {
  final premul = Uint8List(r.rgba.length);
  for (var i = 0; i < premul.length; i += 4) {
    final a = r.rgba[i + 3];
    premul
      ..[i] = r.rgba[i] * a ~/ 255
      ..[i + 1] = r.rgba[i + 1] * a ~/ 255
      ..[i + 2] = r.rgba[i + 2] * a ~/ 255
      ..[i + 3] = a;
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    premul,
    r.width,
    r.height,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}

/// What the band would draw at [values], as a list of (raster, x, y).
List<(Raster, int, int)> layoutAt(
  List<FaceElement> elements,
  Map<FaceData, int> values,
) {
  final out = <(Raster, int, int)>[];
  for (final e in elements) {
    switch (e) {
      case StaticImage():
        out.add((e.image, e.x, e.y));
      case LuaApp():
        // Drawn by the band at run time; the preview shows what lies under it.
        break;
      case Animation():
        out.add((e.frames[e.frames.length ~/ 3], e.x, e.y));
      case ImageSwitch():
        final v = values[e.source] ?? 0;
        var pick = 0;
        for (var i = 0; i < e.values.length; i++) {
          if (v >= e.values[i]) pick = i;
        }
        out.add((e.images[pick], e.x, e.y));
      case DigitNumber():
        final v = values[e.source] ?? 0;
        var s = '$v';
        if (e.leadingZeros) s = s.padLeft(e.count, '0');
        if (s.length > e.count) s = s.substring(s.length - e.count);
        final w = e.digits.first.width + e.spacing;
        // Right-aligned numbers end at x; left-aligned ones start there.
        final left = e.align == alignRight ? e.x - s.length * w : e.x;
        for (var i = 0; i < s.length; i++) {
          out.add((e.digits[s.codeUnitAt(i) - 0x30], left + i * w, e.y));
        }
    }
  }
  return out;
}

Future<Raster> composePreview(
  List<FaceElement> elements, {
  Map<FaceData, int> values = sampleValues,
  double scale = 1,
}) async {
  final parts = layoutAt(elements, values);
  final images = [for (final (r, _, _) in parts) await rasterImage(r)];
  final w = (screenW * scale).round(), h = (screenH * scale).round();
  final result = await render(w, h, (c, s) {
    c
      ..drawRect(Offset.zero & s, Paint()..color = const Color(0xFF000000))
      ..scale(scale);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (var i = 0; i < parts.length; i++) {
      c.drawImage(
        images[i],
        Offset(parts[i].$2.toDouble(), parts[i].$3.toDouble()),
        paint,
      );
    }
  });
  for (final i in images) {
    i.dispose();
  }
  return result;
}
