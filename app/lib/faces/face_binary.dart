/// Packs a watch face into the band's runtime binary (`5A A5 34 12`).
///
/// Layout follows band10-toolkit (MIT, © utsabfdahal,
/// https://github.com/utsabfdahal/band10-toolkit), builder/native.ts:
/// main header, one face header, 16-byte definitions, properties, the
/// preview, then image resources. Only the subset that toolkit verified on
/// hardware is emitted: static images, animations, digit numbers and
/// value-to-image switches. Lua faces (a [LuaApp] plus its files) follow
/// the layout of the Lua samples in github.com/m0tral/MiWatchLuaWatchfaces
/// (read as a format reference only; no code taken).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:openwear/faces/image_codec.dart';

const mainHeaderSize = 0xA8, faceHeaderSize = 0x58, _definitionSize = 16;
const faceMagic = [0x5A, 0xA5, 0x34, 0x12];

/// Values the band can draw (2-byte data-source ids).
enum FaceData {
  hour(0x0811),
  hourHigh(0x0A11),
  hourLow(0x0911),
  minuteHigh(0x1211),
  minuteLow(0x1111),
  minute(0x1011),
  second(0x1811),
  year(0x0812),
  month(0x1012),
  day(0x1812),
  weekday(0x2012), // Sunday = 0
  battery(0x0841),
  steps(0x0821),
  stepPercent(0x1021),
  calories(0x0823),
  caloriePercent(0x1023),
  heartRate(0x0822),
  heartRateZone(0x1022), // 1–5
  standCount(0x0824),
  sleepScore(0x0828),
  stress(0x0826),
  temperature(0x2031), // °C
  weather(0x3031);

  const FaceData(this.id);
  final int id;
}

sealed class FaceElement {
  const FaceElement(this.x, this.y);
  final int x;
  final int y;
}

class StaticImage extends FaceElement {
  const StaticImage(super.x, super.y, this.image);
  final Raster image;
}

/// Frames that loop forever ([repeat] 0) at [intervalMs].
class Animation extends FaceElement {
  const Animation(
    super.x,
    super.y,
    this.frames, {
    this.intervalMs = 100,
    this.repeat = 0,
  });
  final List<Raster> frames;
  final int intervalMs;
  final int repeat;
}

/// Digit alignment. The band anchors a number at its x: 0 draws it ending
/// there (seen on a Smart Band 9), 1 starting there (band10-toolkit).
const alignRight = 0, alignLeft = 1;

/// A number drawn with ten digit images ([digits] 0–9).
class DigitNumber extends FaceElement {
  const DigitNumber(
    super.x,
    super.y,
    this.source,
    this.digits, {
    required this.count,
    this.leadingZeros = true,
    this.align = alignLeft,
    this.spacing = 0,
  });
  final FaceData source;
  final List<Raster> digits;
  final int count;
  final bool leadingZeros;
  final int align;
  final int spacing;
}

/// Shows `images[i]` once the value reaches `values[i]`.
class ImageSwitch extends FaceElement {
  const ImageSwitch(super.x, super.y, this.source, this.images, this.values)
    : assert(images.length == values.length);
  final FaceData source;
  final List<Raster> images;
  final List<int> values;
}

/// A file stored inside the face for its scripts, e.g. "lua/main.lua".
class FaceFile {
  const FaceFile(this.path, this.bytes);
  final String path;
  final List<int> bytes;
}

/// A Lua program the band runs as (part of) the face, with the band's
/// LVGL bindings (`require("lvgl")`, `require("dataman")`). [entry] is the
/// path of the script to run, one of [files].
class LuaApp extends FaceElement {
  LuaApp(this.entry, this.files) : super(0, 0) {
    if (!files.any((f) => f.path == entry)) {
      throw ArgumentError('entry $entry is not one of the files');
    }
  }
  final String entry;
  final List<FaceFile> files;
}

/// One stored file: u24 size, path length, 16 zero bytes, path, contents.
Uint8List encodeFaceFile(FaceFile f) {
  final path = utf8.encode(f.path);
  if (path.isEmpty || path.length > 255) {
    throw ArgumentError('file path must be 1–255 bytes: ${f.path}');
  }
  if (f.bytes.length > 0xffffff) throw ArgumentError('${f.path} too large');
  final out = Uint8List(20 + path.length + f.bytes.length);
  _u24(ByteData.sublistView(out), 0, f.bytes.length);
  out
    ..[3] = path.length
    ..setRange(20, 20 + path.length, path)
    ..setRange(20 + path.length, out.length, f.bytes);
  return out;
}

class FaceDesign {
  const FaceDesign({
    required this.id,
    required this.name,
    required this.elements,
    required this.preview,
  });

  /// Nine ASCII digits.
  final String id;
  final String name;
  final List<FaceElement> elements;
  final Raster preview;
}

// --- packing -------------------------------------------------------------------

class _Prepared {
  final singles = <Raster>[];
  final lists = <List<Raster>>[];
  final animations = <Animation>[];
  final widgets = <FaceElement>[];
  final files = <FaceFile>[];
  final refs = <(int type, int index, FaceElement)>[];

  int single(Raster r) {
    final i = singles.indexWhere((s) => identical(s, r));
    if (i >= 0) return i;
    singles.add(r);
    return singles.length - 1;
  }

  int list(List<Raster> l) {
    final i = lists.indexWhere((s) => identical(s, l));
    if (i >= 0) return i;
    lists.add(l);
    return lists.length - 1;
  }
}

int _widgetSize(FaceElement w) =>
    w is ImageSwitch ? 16 + w.values.length * 4 : 20;

void _u16(ByteData d, int o, int v) => d.setUint16(o, v, Endian.little);
void _u24(ByteData d, int o, int v) {
  d
    ..setUint16(o, v & 0xffff, Endian.little)
    ..setUint8(o + 2, v >> 16 & 0xff);
}

void _u32(ByteData d, int o, int v) => d.setUint32(o, v, Endian.little);

Uint8List _widget(FaceElement e, _Prepared p) {
  final out = Uint8List(_widgetSize(e));
  final d = ByteData.sublistView(out);
  switch (e) {
    case DigitNumber():
      out
        ..[0] = e.source.id >> 8
        ..[1] = e.source.id & 0xff
        ..[2] = e.count.clamp(1, 255)
        ..[3] = 0x10 | (e.leadingZeros ? 1 : 0) << 2 | e.align & 3;
      _u24(d, 8, p.list(e.digits));
      out
        ..[11] = 3
        ..[13] = e.spacing & 0xff;
    case ImageSwitch():
      out
        ..[0] = e.source.id >> 8
        ..[1] = e.source.id & 0xff
        ..[3] = 0x20;
      _u24(d, 8, p.list(e.images));
      out[11] = 3;
      _u24(d, 12, 0x200);
      for (var i = 0; i < e.values.length; i++) {
        _u16(d, 16 + i * 4, e.values[i]);
      }
    case StaticImage() || Animation() || LuaApp():
      throw StateError('not a widget');
  }
  return out;
}

Uint8List _concat(List<Uint8List> parts) {
  final b = BytesBuilder(copy: false);
  parts.forEach(b.add);
  return b.takeBytes();
}

/// The installable binary for [design].
Uint8List packFace(FaceDesign design) {
  if (!RegExp(r'^\d{9}$').hasMatch(design.id)) {
    throw ArgumentError('face id must be 9 digits');
  }
  final p = _Prepared();
  for (final e in design.elements) {
    switch (e) {
      case StaticImage():
        p.refs.add((2, p.single(e.image), e));
      case Animation():
        p.list(e.frames);
        p.animations.add(e);
        p.refs.add((4, p.animations.length - 1, e));
      case DigitNumber() || ImageSwitch():
        p.widgets.add(e);
        p.refs.add((7, p.widgets.length - 1, e));
      case LuaApp():
        final first = p.files.length;
        p.files.addAll(e.files);
        p.refs.add((
          5,
          first + e.files.indexWhere((f) => f.path == e.entry),
          e,
        ));
    }
  }
  final paths = p.files.map((f) => f.path).toList();
  if (paths.toSet().length != paths.length) {
    throw ArgumentError('face files must have distinct paths');
  }
  final files = [for (final f in p.files) encodeFaceFile(f)];
  final widgetBytes = [for (final w in p.widgets) _widget(w, p)];
  final singles = [for (final r in p.singles) encodeImage(r)];
  final lists = [for (final l in p.lists) encodeImageList(l)];
  final preview = encodeImage(design.preview);

  final defCount =
      p.refs.length +
      singles.length +
      lists.length +
      p.animations.length +
      files.length +
      p.widgets.length;
  final defStart = mainHeaderSize + faceHeaderSize;
  final propStart = defStart + defCount * _definitionSize;
  final propSize =
      p.refs.length * 16 +
      p.animations.length * 12 +
      widgetBytes.fold<int>(0, (n, w) => n + w.length);
  final previewOffset = propStart + propSize;
  var resourceAt = previewOffset + preview.length;

  // Main header.
  final main = Uint8List(mainHeaderSize)..setRange(0, 4, faceMagic);
  final md = ByteData.sublistView(main);
  _u32(md, 0x10, 0x800);
  _u16(md, 0x1C, 1);
  _u16(md, 0x1E, 1);
  _u32(md, 0x20, previewOffset);
  main.setRange(0x28, 0x31, ascii.encode(design.id));
  final name = utf8.encode(design.name);
  main.setRange(0x68, 0x68 + name.length.clamp(0, 59), name);

  // Face header: (count, offset) per definition type.
  final face = Uint8List(faceHeaderSize);
  final fd = ByteData.sublistView(face);
  _u32(fd, 4, previewOffset);
  var at = defStart;
  void section(int o, int count) {
    _u32(fd, o, count);
    _u32(fd, o + 4, at);
    at += count * _definitionSize;
  }

  section(0x08, p.refs.length);
  section(0x10, 0);
  section(0x18, singles.length);
  section(0x20, lists.length);
  section(0x28, p.animations.length);
  section(0x30, files.length);
  section(0x38, 0);
  section(0x40, p.widgets.length);
  section(0x48, 0);
  section(0x50, 0);

  // Definitions, then properties.
  final defs = Uint8List(defCount * _definitionSize);
  final dd = ByteData.sublistView(defs);
  var di = 0;
  void def(int index, int type, int offset, int length) {
    final o = di++ * _definitionSize;
    _u16(dd, o, index);
    defs[o + 3] = type;
    _u32(dd, o + 8, offset);
    _u32(dd, o + 12, length);
  }

  final props = BytesBuilder(copy: false);
  var propAt = propStart;
  for (var i = 0; i < p.refs.length; i++) {
    def(i, 0, propAt, 16);
    propAt += 16;
  }
  for (var i = 0; i < singles.length; i++) {
    def(i, 2, resourceAt, singles[i].length);
    resourceAt += singles[i].length;
  }
  for (var i = 0; i < lists.length; i++) {
    def(i, 3, resourceAt, lists[i].length);
    resourceAt += lists[i].length;
  }
  for (var i = 0; i < p.animations.length; i++) {
    def(i, 4, propAt, 12);
    propAt += 12;
  }
  for (var i = 0; i < files.length; i++) {
    def(i, 5, resourceAt, files[i].length);
    resourceAt += files[i].length;
  }
  for (var i = 0; i < p.widgets.length; i++) {
    def(i, 7, propAt, widgetBytes[i].length);
    propAt += widgetBytes[i].length;
  }

  for (final (type, index, e) in p.refs) {
    final b = Uint8List(16);
    final bd = ByteData.sublistView(b);
    _u24(bd, 0, index);
    b[3] = type;
    // The band skips anything at a negative position (it reads 65535).
    _u16(bd, 4, e.x.clamp(0, 0xffff));
    _u16(bd, 6, e.y.clamp(0, 0xffff));
    props.add(b);
  }
  for (final a in p.animations) {
    final b = Uint8List(12);
    final bd = ByteData.sublistView(b);
    _u24(bd, 0, p.list(a.frames));
    b[3] = 3;
    _u16(bd, 6, a.intervalMs);
    _u16(bd, 8, a.repeat);
    props.add(b);
  }
  widgetBytes.forEach(props.add);

  return _concat([
    main,
    face,
    defs,
    props.takeBytes(),
    preview,
    ...singles,
    ...lists,
    ...files,
  ]);
}
