/// Minimal protobuf wire-format codec (enough for the Xiaomi Wear messages).
library;

import 'dart:convert';
import 'dart:typed_data';

const _varint = 0, _fixed64 = 1, _len = 2, _fixed32 = 5;

/// One field to encode. Null values are skipped.
sealed class PbField {
  const PbField(this.number);
  final int number;
}

class PbVarint extends PbField {
  const PbVarint(super.number, this.value);
  final int? value;
}

class PbBool extends PbField {
  const PbBool(super.number, this.value);
  final bool? value;
}

class PbSint extends PbField {
  const PbSint(super.number, this.value);
  final int? value;
}

class PbFloat extends PbField {
  const PbFloat(super.number, this.value);
  final double? value;
}

class PbBytes extends PbField {
  const PbBytes(super.number, this.value);
  final List<int>? value;
}

class PbString extends PbField {
  const PbString(super.number, this.value);
  final String? value;
}

void _writeVarint(BytesBuilder out, int value) {
  // Dart ints are 64-bit; negative values encode as 10-byte two's complement.
  var v = value;
  for (var i = 0; i < 10; i++) {
    final byte = v & 0x7F;
    v = v >>> 7;
    if (v == 0) {
      out.addByte(byte);
      return;
    }
    out.addByte(byte | 0x80);
  }
}

Uint8List pbEncode(List<PbField> fields) {
  final out = BytesBuilder(copy: false);
  for (final field in fields) {
    final n = field.number;
    switch (field) {
      case PbVarint(:final value) when value != null:
        _writeVarint(out, n << 3 | _varint);
        _writeVarint(out, value);
      case PbBool(:final value) when value != null:
        _writeVarint(out, n << 3 | _varint);
        _writeVarint(out, value ? 1 : 0);
      case PbSint(:final value) when value != null:
        _writeVarint(out, n << 3 | _varint);
        _writeVarint(out, (value << 1) ^ (value >> 63));
      case PbFloat(:final value) when value != null:
        _writeVarint(out, n << 3 | _fixed32);
        out.add(
          (ByteData(
            4,
          )..setFloat32(0, value, Endian.little)).buffer.asUint8List(),
        );
      case PbBytes(:final value) when value != null:
        _writeVarint(out, n << 3 | _len);
        _writeVarint(out, value.length);
        out.add(value);
      case PbString(:final value) when value != null:
        final data = utf8.encode(value);
        _writeVarint(out, n << 3 | _len);
        _writeVarint(out, data.length);
        out.add(data);
      default:
        break;
    }
  }
  return out.takeBytes();
}

/// One decoded message level: field number → raw values
/// (varint → int, length-delimited/fixed → Uint8List).
class PbMessage {
  PbMessage(this.fields);
  final Map<int, List<Object>> fields;

  factory PbMessage.decode(List<int> buf) {
    final fields = <int, List<Object>>{};
    var pos = 0;
    (int, int) readVarint(int p) {
      var result = 0, shift = 0;
      while (true) {
        if (p >= buf.length) throw const FormatException('truncated varint');
        final byte = buf[p++];
        result |= (byte & 0x7F) << shift;
        if (byte & 0x80 == 0) return (result, p);
        shift += 7;
      }
    }

    Uint8List take(int length) {
      if (pos + length > buf.length) {
        throw const FormatException('truncated field');
      }
      final value = Uint8List.fromList(buf.sublist(pos, pos + length));
      pos += length;
      return value;
    }

    while (pos < buf.length) {
      final (key, p) = readVarint(pos);
      pos = p;
      final Object value;
      switch (key & 7) {
        case _varint:
          final (v, next) = readVarint(pos);
          pos = next;
          value = v;
        case _len:
          final (length, next) = readVarint(pos);
          pos = next;
          value = take(length);
        case _fixed32:
          value = take(4);
        case _fixed64:
          value = take(8);
        default:
          throw FormatException('unsupported wire type ${key & 7}');
      }
      fields.putIfAbsent(key >> 3, () => []).add(value);
    }
    return PbMessage(fields);
  }

  List<Object> all(int number) => fields[number] ?? const [];
  int int_(int number, [int fallback = 0]) =>
      (fields[number]?.first as int?) ?? fallback;
  Uint8List? bytes(int number) => fields[number]?.first as Uint8List?;
  String string(int number) =>
      utf8.decode(bytes(number) ?? const [], allowMalformed: true);
  PbMessage? message(int number) {
    final b = bytes(number);
    return b == null ? null : PbMessage.decode(b);
  }

  List<PbMessage> messages(int number) =>
      all(number).whereType<Uint8List>().map(PbMessage.decode).toList();
  bool has(int number) => fields.containsKey(number);
}

/// Splits [buf] into its top-level fields, each kept as its exact bytes
/// (key included), so a message can be rewritten without losing fields
/// this codec does not understand.
List<(int, Uint8List)> pbSplit(List<int> buf) {
  final out = <(int, Uint8List)>[];
  var pos = 0;
  int readVarint() {
    var result = 0, shift = 0;
    while (true) {
      if (pos >= buf.length) throw const FormatException('truncated varint');
      final byte = buf[pos++];
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
    }
  }

  while (pos < buf.length) {
    final start = pos;
    final key = readVarint();
    switch (key & 7) {
      case _varint:
        readVarint();
      case _len:
        final length = readVarint(); // read before pos is used
        pos += length;
      case _fixed32:
        pos += 4;
      case _fixed64:
        pos += 8;
      default:
        throw FormatException('unsupported wire type ${key & 7}');
    }
    if (pos > buf.length) throw const FormatException('truncated field');
    out.add((key >> 3, Uint8List.fromList(buf.sublist(start, pos))));
  }
  return out;
}

/// [buf] with every field numbered in [replace] swapped for the new fields
/// (appended at the end); all other fields keep their exact bytes.
Uint8List pbReplace(List<int> buf, List<PbField> replace) {
  final numbers = {for (final f in replace) f.number};
  return Uint8List.fromList([
    for (final (n, bytes) in pbSplit(buf))
      if (!numbers.contains(n)) ...bytes,
    ...pbEncode(replace),
  ]);
}
