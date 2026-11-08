/// SPP v1 framing, spoken by older Xiaomi Wear models whose answer to the
/// version probe is below 2.0 (docs/protocol/01-transport.md, "SPP v1").
///
/// Packet: `BA DC FE`, channel (low nibble), flags (0x80 always, 0x40 wants
/// a reply), u16 LE length of opcode+serial+type+payload, opcode, frame
/// serial, data type, payload, `EF`. Commands are sealed with AES-CCM
/// (4-byte tag) under the session's 4-byte IVs. Gadgetbridge's
/// XiaomiSppPacketV1 was read as a description of the format.
library;

import 'dart:typed_data';

import 'package:openwear/protocol/crypto.dart';
import 'package:openwear/protocol/l1.dart';

const _preamble = [0xBA, 0xDC, 0xFE], _epilogue = 0xEF;
const _headerBytes = 10, _minPacket = 11;

/// Raw v1 channel numbers.
const v1Version = 0, v1PbRx = 1, v1PbTx = 2, v1Fitness = 3, v1Mass = 5;

/// What the payload is: plain, CCM-sealed, or an auth step (plain).
const v1Plain = 0, v1Encrypted = 1, v1Auth = 2;

const v1OpSend = 2;

/// Auth commands (type 1, subtype 17 and up) go out as [v1Auth].
bool isAuthCommand(int type, int subtype) => type == 1 && subtype >= 17;

/// The v2 channel id OpenWear uses for a v1 raw channel, and back.
int? v2ChannelOf(int raw) => switch (raw) {
  v1PbRx || v1PbTx => channelPb,
  v1Fitness => channelFitness,
  v1Mass => channelMass,
  _ => null,
};

int v1ChannelOf(int v2) => switch (v2) {
  channelPb => v1PbTx,
  channelFitness => v1Fitness,
  channelMass => v1Mass,
  _ => throw ArgumentError('no SPP v1 channel for $v2'),
};

class V1Packet {
  const V1Packet({
    required this.channel,
    required this.dataType,
    required this.payload,
    this.serial = 0,
    this.opcode = v1OpSend,
    this.needsReply = false,
  });

  final int channel;
  final int dataType;
  final Uint8List payload;
  final int serial;
  final int opcode;
  final bool needsReply;

  Uint8List encode() {
    final out = Uint8List(_minPacket + payload.length)
      ..setRange(0, 3, _preamble);
    out
      ..[3] = channel & 0x0F
      ..[4] = 0x80 | (needsReply ? 0x40 : 0)
      ..[5] = (payload.length + 3) & 0xFF
      ..[6] = (payload.length + 3) >> 8
      ..[7] = opcode
      ..[8] = serial & 0xFF
      ..[9] = dataType
      ..setRange(_headerBytes, _headerBytes + payload.length, payload)
      ..[out.length - 1] = _epilogue;
    return out;
  }
}

/// Splits the byte stream into packets; junk before a preamble is dropped.
class V1Reader {
  final _buffer = BytesBuilder();

  List<V1Packet> feed(List<int> data) {
    _buffer.add(data);
    var bytes = _buffer.takeBytes();
    final out = <V1Packet>[];
    while (true) {
      final start = _find(bytes);
      if (start < 0) {
        bytes = Uint8List(0);
        break;
      }
      if (start > 0) bytes = Uint8List.sublistView(bytes, start);
      if (bytes.length < _minPacket) break;
      final length = bytes[5] | bytes[6] << 8;
      final total = length + 8;
      if (length < 3) {
        bytes = Uint8List.sublistView(bytes, 1);
        continue;
      }
      if (bytes.length < total) break;
      if (bytes[total - 1] != _epilogue) {
        bytes = Uint8List.sublistView(bytes, 1);
        continue;
      }
      out.add(
        V1Packet(
          channel: bytes[3] & 0x0F,
          needsReply: bytes[4] & 0x40 != 0,
          opcode: bytes[7],
          serial: bytes[8],
          dataType: bytes[9],
          payload: Uint8List.fromList(bytes.sublist(_headerBytes, total - 1)),
        ),
      );
      bytes = Uint8List.sublistView(bytes, total);
    }
    _buffer.add(bytes);
    return out;
  }

  static int _find(Uint8List b) {
    for (var i = 0; i + 2 < b.length; i++) {
      if (b[i] == _preamble[0] &&
          b[i + 1] == _preamble[1] &&
          b[i + 2] == _preamble[2]) {
        return i;
      }
    }
    // Keep a possible preamble split across reads.
    if (b.isNotEmpty && b.last == _preamble[0]) return b.length - 1;
    if (b.length >= 2 &&
        b[b.length - 2] == _preamble[0] &&
        b.last == _preamble[1]) {
      return b.length - 2;
    }
    return -1;
  }
}

/// 12-byte CCM nonce: the 4-byte session IV, 4 zero bytes, u32 LE counter.
Uint8List v1Nonce(List<int> iv, int counter) {
  final n = Uint8List(12)..setRange(0, 4, iv);
  ByteData.sublistView(n).setUint32(8, counter, Endian.little);
  return n;
}

/// An outgoing command: u16 LE counter, then the sealed command.
Uint8List v1SealCommand(
  List<int> key,
  List<int> iv,
  int counter,
  List<int> plain,
) {
  final sealed = ccmEncrypt(key, v1Nonce(iv, counter), plain);
  return Uint8List(2 + sealed.length)
    ..[0] = counter & 0xFF
    ..[1] = counter >> 8 & 0xFF
    ..setRange(2, 2 + sealed.length, sealed);
}

/// Other outgoing channels are sealed with counter 0 and no prefix.
Uint8List v1Seal(List<int> key, List<int> iv, List<int> plain) =>
    ccmEncrypt(key, v1Nonce(iv, 0), plain);

/// Everything the band sends is sealed with counter 0. A failed tag check
/// (wrong key, corrupted packet) is a [FormatException].
Uint8List v1Open(List<int> key, List<int> iv, List<int> sealed) {
  try {
    return ccmDecrypt(key, v1Nonce(iv, 0), sealed);
    // pointycastle reports a bad CCM tag as a StateError.
    // ignore: avoid_catching_errors
  } on StateError catch (e) {
    throw FormatException('SPP v1 packet failed its check: ${e.message}');
  }
}
