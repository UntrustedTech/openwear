/// Run-length codecs used inside watch-face image blocks.
///
/// Ported from band10-toolkit (MIT, © utsabfdahal,
/// https://github.com/utsabfdahal/band10-toolkit), parser/rle.ts.
library;

import 'dart:typed_data';

const _maxRun = 0x7f;

class RleException implements Exception {
  const RleException(this.message);
  final String message;
  @override
  String toString() => 'RleException: $message';
}

bool _samePixel(Uint8List d, int a, int b, int bpp) {
  for (var i = 0; i < bpp; i++) {
    if (d[a + i] != d[b + i]) return false;
  }
  return true;
}

/// Pixel RLE ("v1"): `count` (1–127) followed by one whole pixel.
Uint8List encodeRleV1(Uint8List data, int bpp) {
  if (bpp < 1 || data.length % bpp != 0) {
    throw RleException('length ${data.length} is not a multiple of $bpp');
  }
  final out = BytesBuilder(copy: false);
  var offset = 0;
  while (offset < data.length) {
    var count = 1;
    while (count < _maxRun &&
        offset + (count + 1) * bpp <= data.length &&
        _samePixel(data, offset, offset + count * bpp, bpp)) {
      count++;
    }
    out
      ..addByte(count)
      ..add(Uint8List.sublistView(data, offset, offset + bpp));
    offset += count * bpp;
  }
  return out.takeBytes();
}

Uint8List decodeRleV1(Uint8List enc, int length, int bpp) {
  final out = Uint8List(length);
  var i = 0, o = 0;
  while (i < enc.length && o < length) {
    final control = enc[i++];
    final count = control & _maxRun;
    if (count == 0) throw const RleException('zero-length v1 packet');
    if (control & 0x80 == 0) {
      if (i + bpp > enc.length) throw const RleException('truncated v1 run');
      for (var r = 0; r < count; r++) {
        if (o + bpp > length) throw const RleException('v1 overflows');
        out.setRange(o, o + bpp, enc, i);
        o += bpp;
      }
      i += bpp;
    } else {
      final n = count * bpp;
      if (i + n > enc.length || o + n > length) {
        throw const RleException('truncated v1 literal');
      }
      out.setRange(o, o + n, enc, i);
      i += n;
      o += n;
    }
  }
  if (o != length) throw RleException('v1 produced $o of $length bytes');
  return out;
}

/// Byte RLE ("v2") for palette indices: runs `n, byte`; literals
/// `0x80|n, bytes…`.
Uint8List encodeRleV2(Uint8List data) {
  final out = BytesBuilder(copy: false);
  var offset = 0;
  while (offset < data.length) {
    var repeat = 1;
    while (repeat < _maxRun &&
        offset + repeat < data.length &&
        data[offset + repeat] == data[offset]) {
      repeat++;
    }
    if (repeat >= 3) {
      out
        ..addByte(repeat)
        ..addByte(data[offset]);
      offset += repeat;
      continue;
    }
    final start = offset;
    offset += repeat;
    while (offset < data.length && offset - start < _maxRun) {
      var next = 1;
      while (next < 3 &&
          offset + next < data.length &&
          data[offset + next] == data[offset]) {
        next++;
      }
      if (next >= 3) break;
      final room = _maxRun - (offset - start);
      offset += next < room ? next : room;
    }
    out
      ..addByte(0x80 | (offset - start))
      ..add(Uint8List.sublistView(data, start, offset));
  }
  return out.takeBytes();
}

Uint8List decodeRleV2(Uint8List enc, int length) {
  final out = Uint8List(length);
  var i = 0, o = 0;
  while (i < enc.length && o < length) {
    final control = enc[i++];
    final count = control & _maxRun;
    if (count == 0) throw const RleException('zero-length v2 packet');
    if (o + count > length) throw const RleException('v2 overflows');
    if (control & 0x80 != 0) {
      if (i + count > enc.length) throw const RleException('truncated v2');
      out.setRange(o, o + count, enc, i);
      i += count;
    } else {
      if (i >= enc.length) throw const RleException('truncated v2 run');
      out.fillRange(o, o + count, enc[i++]);
    }
    o += count;
  }
  if (o != length) throw RleException('v2 produced $o of $length bytes');
  return out;
}
