/// L1 SAR framing, L2 channel packets and the SPP-v1 version probe
/// (docs/protocol/01-transport, 06-capture-findings).
library;

import 'dart:typed_data';

const frameNak = 0, frameAck = 1, frameCmd = 2, frameData = 3;
const cmdStartReq = 1, cmdStartRsp = 2;
const channelPb = 1, channelMass = 2, channelFitness = 5;
const opcodePlain = 1, opcodeEncrypted = 2;

const _headerLen = 8;
const _mps = 0xFC00, _txWindow = 32, _sendTimeoutMs = 10000;

final List<int> _crcTable = List.generate(256, (byte) {
  var crc = byte;
  for (var i = 0; i < 8; i++) {
    crc = crc & 1 != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
  }
  return crc;
});

int crc16Arc(List<int> data) {
  var crc = 0;
  for (final byte in data) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return crc;
}

class Frame {
  const Frame(this.type, this.seq, this.payload, {this.frx = 0});
  final int type;
  final int seq;
  final Uint8List payload;
  final int frx;

  Uint8List encode() {
    final header = ByteData(_headerLen)
      ..setUint8(0, 0xA5)
      ..setUint8(1, 0xA5)
      ..setUint8(2, (frx << 4) | type)
      ..setUint8(3, seq & 0xFF)
      ..setUint16(4, payload.length, Endian.little)
      ..setUint16(6, crc16Arc(payload), Endian.little);
    return Uint8List.fromList([...header.buffer.asUint8List(), ...payload]);
  }
}

Uint8List _tlv16(int kind, int value) =>
    (ByteData(5)
          ..setUint8(0, kind)
          ..setUint16(1, 2, Endian.little)
          ..setUint16(3, value, Endian.little))
        .buffer
        .asUint8List();

Frame startRequest() => Frame(
  frameCmd,
  0,
  Uint8List.fromList([
    cmdStartReq,
    1, 3, 0, 1, 0, 0, // version 1.0.0
    ..._tlv16(2, _mps),
    ..._tlv16(3, _txWindow),
    ..._tlv16(4, _sendTimeoutMs),
  ]),
);

Map<int, Uint8List> parseTlv(List<int> data) {
  final out = <int, Uint8List>{};
  var pos = 0;
  while (pos + 3 <= data.length) {
    final kind = data[pos];
    final length = data[pos + 1] | (data[pos + 2] << 8);
    final end = (pos + 3 + length).clamp(0, data.length);
    out[kind] = Uint8List.fromList(data.sublist(pos + 3, end));
    pos += 3 + length;
  }
  return out;
}

/// Reassembles L1 frames from arbitrary stream chunks.
class FrameReader {
  final _buf = <int>[];

  List<Frame> feed(List<int> chunk) {
    _buf.addAll(chunk);
    final frames = <Frame>[];
    while (true) {
      final start = _findMagic();
      if (start < 0) {
        _buf.clear();
        return frames;
      }
      _buf.removeRange(0, start);
      if (_buf.length < _headerLen) return frames;
      final flags = _buf[2], seq = _buf[3];
      final length = _buf[4] | (_buf[5] << 8);
      final crc = _buf[6] | (_buf[7] << 8);
      if (_buf.length < _headerLen + length) return frames;
      final payload = Uint8List.fromList(
        _buf.sublist(_headerLen, _headerLen + length),
      );
      _buf.removeRange(0, _headerLen + length);
      if (crc16Arc(payload) != crc) {
        throw FormatException('L1 CRC mismatch seq=$seq len=$length');
      }
      frames.add(Frame(flags & 0x0F, seq, payload, frx: (flags >> 4) & 1));
    }
  }

  int _findMagic() {
    for (var i = 0; i + 1 < _buf.length; i++) {
      if (_buf[i] == 0xA5 && _buf[i + 1] == 0xA5) return i;
    }
    return _buf.isNotEmpty && _buf.last == 0xA5 ? _buf.length - 1 : -1;
  }
}

Uint8List l2Encode(int channel, int opcode, List<int> payload) =>
    Uint8List.fromList([channel, opcode, ...payload]);

(int channel, int opcode, Uint8List payload) l2Decode(Uint8List data) {
  if (data.length < 2) throw const FormatException('L2 packet too short');
  return (data[0], data[1], Uint8List.sublistView(data, 2));
}

// --- SPP v1 probe: tells us the band's protocol version before V2 framing ---

Uint8List sppVersionProbe([int seq = 1]) {
  const header = (1 << 14) | (1 << 15);
  return Uint8List.fromList([
    0xBA,
    0xDC,
    0xFE,
    header & 0xFF,
    header >> 8,
    3,
    0, // magic, header, body length
    0, seq & 0xFF, 0, // opcode, seq, flags
    0xEF,
  ]);
}

/// "major.minor.patch" from the band's reply to [sppVersionProbe].
String sppVersion(List<int> packet) {
  if (packet.length < 10 ||
      packet[0] != 0xBA ||
      packet[1] != 0xDC ||
      packet[2] != 0xFE) {
    throw FormatException('not an SPP v1 packet');
  }
  final length = packet[5] | (packet[6] << 8);
  final payload = [
    ...packet.sublist(10, (7 + length).clamp(10, packet.length)),
    0,
    0,
    0,
  ];
  return '${payload[0]}.${payload[1]}.${payload[2]}';
}
