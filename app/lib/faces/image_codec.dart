/// Image blocks inside a watch-face binary.
///
/// Layout follows band10-toolkit (MIT, © utsabfdahal), parser/imageCodec.ts.
/// Smart Band 9 ("n66") differs from Band 10 only for images with more than
/// 256 colours: those use sign 6, RGB565 little-endian plus an alpha byte.
library;

import 'dart:typed_data';

import 'package:openwear/faces/rle.dart';

const imageHeaderSize = 12;
const _paletteBytes = 256 * 4;
const _magic = [0xE0, 0x21, 0xA5, 0x5A];

/// Pixel encodings ("sign" byte).
const signIndexed = 0x10, signRgb565Alpha = 6;

/// Straight (not premultiplied) RGBA pixels.
class Raster {
  Raster(this.width, this.height, this.rgba)
    : assert(rgba.length == width * height * 4);
  final int width;
  final int height;
  final Uint8List rgba;
}

/// Palette (BGRA, 256 entries) + one index per pixel, or null when the
/// raster has more than 256 colours.
Uint8List? _indexed(Uint8List rgba) {
  final palette = <int, int>{};
  final indices = Uint8List(rgba.length ~/ 4);
  for (var o = 0, p = 0; o < rgba.length; o += 4, p++) {
    final key =
        rgba[o + 3] << 24 | rgba[o] << 16 | rgba[o + 1] << 8 | rgba[o + 2];
    var index = palette[key];
    if (index == null) {
      if (palette.length == 256) return null;
      index = palette[key] = palette.length;
    }
    indices[p] = index;
  }
  final out = Uint8List(_paletteBytes + indices.length);
  for (final MapEntry(:key, value: i) in palette.entries) {
    out
      ..[i * 4] = key & 0xff
      ..[i * 4 + 1] = key >> 8 & 0xff
      ..[i * 4 + 2] = key >> 16 & 0xff
      ..[i * 4 + 3] = key >> 24 & 0xff;
  }
  out.setRange(_paletteBytes, out.length, indices);
  return out;
}

Uint8List _rgb565Alpha(Uint8List rgba) {
  final out = Uint8List(rgba.length ~/ 4 * 3);
  for (var i = 0, o = 0; i < rgba.length; i += 4, o += 3) {
    final v =
        (rgba[i] & 0xf8) << 8 | (rgba[i + 1] & 0xfc) << 3 | rgba[i + 2] >> 3;
    out
      ..[o] = v & 0xff
      ..[o + 1] = v >> 8
      ..[o + 2] = rgba[i + 3];
  }
  return out;
}

Uint8List _compressed(Uint8List raw, int bpp, bool indexed) {
  final enc = indexed ? encodeRleV2(raw) : encodeRleV1(raw, bpp);
  final out = Uint8List(8 + enc.length)..setRange(0, 4, _magic);
  ByteData.sublistView(out).setUint32(4, raw.length << 4 | bpp, Endian.little);
  return out..setRange(8, out.length, enc);
}

/// Pixels of [r] in [sign]'s encoding, compressed.
Uint8List _payload(Raster r, int sign) {
  if (sign == signIndexed) {
    final raw = _indexed(r.rgba);
    if (raw == null) throw StateError('more than 256 colours');
    return _compressed(raw, 1, true);
  }
  return _compressed(_rgb565Alpha(r.rgba), 3, false);
}

int _signFor(Iterable<Raster> rasters) =>
    rasters.every((r) => _indexed(r.rgba) != null)
    ? signIndexed
    : signRgb565Alpha;

/// One image: 12-byte header + compressed pixels.
Uint8List encodeImage(Raster r) {
  final sign = _signFor([r]);
  final payload = _payload(r, sign);
  final out = Uint8List(imageHeaderSize + payload.length);
  ByteData.sublistView(out)
    ..setUint8(0, sign)
    ..setUint8(1, 4) // compressed
    ..setUint16(4, r.width, Endian.little)
    ..setUint16(6, r.height, Endian.little)
    ..setUint32(8, payload.length, Endian.little);
  return out..setRange(imageHeaderSize, out.length, payload);
}

/// Same-sized images: header, a length table, then each compressed image.
Uint8List encodeImageList(List<Raster> rasters) {
  if (rasters.isEmpty || rasters.length > 255) {
    throw ArgumentError('image lists hold 1–255 images');
  }
  final first = rasters.first;
  if (rasters.any((r) => r.width != first.width || r.height != first.height)) {
    throw ArgumentError('image list frames differ in size');
  }
  final sign = _signFor(rasters);
  final payloads = [for (final r in rasters) _payload(r, sign)];
  final table = rasters.length * 4;
  final total = payloads.fold<int>(table, (n, p) => n + p.length);
  final out = Uint8List(imageHeaderSize + total);
  final bd = ByteData.sublistView(out)
    ..setUint8(0, sign)
    ..setUint8(1, rasters.length)
    ..setUint8(2, 4)
    ..setUint16(4, first.width, Endian.little)
    ..setUint16(6, first.height, Endian.little)
    ..setUint32(8, total, Endian.little);
  var at = imageHeaderSize + table;
  for (var i = 0; i < payloads.length; i++) {
    bd.setUint32(imageHeaderSize + i * 4, payloads[i].length, Endian.little);
    out.setRange(at, at + payloads[i].length, payloads[i]);
    at += payloads[i].length;
  }
  return out;
}

// --- decoding (for checks and previews) ----------------------------------------

Raster _decodePixels(Uint8List b, int off, int len, int sign, int w, int h) {
  final view = ByteData.sublistView(b);
  for (var i = 0; i < 4; i++) {
    if (len < 8 || b[off + i] != _magic[i]) {
      throw const FormatException('uncompressed image');
    }
  }
  final info = view.getUint32(off + 4, Endian.little);
  final bpp = info & 0xf, rawLen = info >> 4;
  final enc = Uint8List.sublistView(b, off + 8, off + len);
  final raw = sign == signIndexed || bpp == 1
      ? decodeRleV2(enc, rawLen)
      : decodeRleV1(enc, rawLen, bpp);
  final rgba = Uint8List(w * h * 4);
  for (var p = 0; p < w * h; p++) {
    final o = p * 4;
    if (sign == signIndexed || bpp == 1) {
      final q = raw[_paletteBytes + p] * 4;
      rgba
        ..[o] = raw[q + 2]
        ..[o + 1] = raw[q + 1]
        ..[o + 2] = raw[q]
        ..[o + 3] = raw[q + 3];
    } else {
      final lo = raw[p * 3], hi = raw[p * 3 + 1];
      rgba
        ..[o] = hi & 0xf8
        ..[o + 1] = ((hi & 7) << 5 | (lo & 0xe0) >> 3) & 0xfc
        ..[o + 2] = (lo & 0x1f) << 3
        ..[o + 3] = raw[p * 3 + 2];
    }
  }
  return Raster(w, h, rgba);
}

Raster decodeImage(Uint8List b, int off) {
  final v = ByteData.sublistView(b);
  return _decodePixels(
    b,
    off + imageHeaderSize,
    v.getUint32(off + 8, Endian.little),
    b[off],
    v.getUint16(off + 4, Endian.little),
    v.getUint16(off + 6, Endian.little),
  );
}

List<Raster> decodeImageList(Uint8List b, int off) {
  final v = ByteData.sublistView(b);
  final count = b[off + 1];
  final w = v.getUint16(off + 4, Endian.little);
  final h = v.getUint16(off + 6, Endian.little);
  var at = off + imageHeaderSize + count * 4;
  return [
    for (var i = 0; i < count; i++)
      () {
        final len = v.getUint32(off + imageHeaderSize + i * 4, Endian.little);
        final r = _decodePixels(b, at, len, b[off], w, h);
        at += len;
        return r;
      }(),
  ];
}
