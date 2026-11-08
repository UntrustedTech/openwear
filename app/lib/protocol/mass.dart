/// Mass (bulk file) transfer phone → watch: 22/0 prepare, then slices on L2
/// channel 2 (plaintext), one per L1 ACK. Used for app icons and watch faces.
library;

import 'dart:typed_data';

import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/crc32.dart';
import 'package:openwear/protocol/link.dart';
import 'package:openwear/protocol/l1.dart';
import 'package:openwear/protocol/pb.dart';
import 'package:pointycastle/digests/md5.dart';

const _subPrepare = 0;
const _statusAlreadyHave = 1;
const _defaultSlice = 4096;
const _sliceHeader = 4;

/// (type, detail) of the file kinds we send.
const dataAppIcon = (3, 2);

class MassException implements Exception {
  const MassException(this.message);
  final String message;
  @override
  String toString() => 'MassException: $message';
}

Uint8List md5(List<int> data) => MD5Digest().process(Uint8List.fromList(data));

int typeByte((int, int) kind) => (kind.$1 << 4) | kind.$2;

Command prepareRequest((int, int) kind, Uint8List data) =>
    Command.of(typeMass, _subPrepare, [
      PbBytes(
        1,
        pbEncode([
          PbVarint(1, typeByte(kind)),
          PbBytes(2, md5(data)),
          PbVarint(3, data.length),
          const PbVarint(4, 0),
        ]),
      ),
    ]);

/// Slice length the watch asked for, or null when it already has the file.
int? parsePrepareResponse(Command rsp) {
  if (rsp.status == _statusAlreadyHave) return null;
  if ((rsp.status ?? 0) != 0) {
    throw MassException('prepare refused, status ${rsp.status}');
  }
  final body = rsp.body.message(2);
  if (body == null) throw const MassException('empty prepare response');
  final status = body.int_(2);
  if (status != 0) {
    throw MassException(
      status == 1 ? 'watch is busy' : 'prepare status $status',
    );
  }
  if (body.int_(4) != 0) {
    throw const MassException('resuming a partial upload is not supported');
  }
  final slice = body.int_(5);
  return slice == 0 ? _defaultSlice : slice;
}

/// header(22) ‖ data ‖ CRC32(header ‖ data), split into `[total][index]` slices.
List<Uint8List> buildPackets((int, int) kind, Uint8List data, int sliceLength) {
  final header = ByteData(22)
    ..setUint8(0, 0)
    ..setUint8(1, typeByte(kind))
    ..setUint32(18, data.length, Endian.little);
  final h = header.buffer.asUint8List()..setRange(2, 18, md5(data));
  final blob = BytesBuilder(copy: false)
    ..add(h)
    ..add(data);
  final withoutCrc = blob.takeBytes();
  final crc = ByteData(4)..setUint32(0, crc32(withoutCrc), Endian.little);
  final all = Uint8List.fromList([...withoutCrc, ...crc.buffer.asUint8List()]);
  final chunk = sliceLength - _sliceHeader;
  if (chunk <= 0) throw MassException('slice length $sliceLength too small');
  final count = (all.length + chunk - 1) ~/ chunk;
  return [
    for (var n = 0; n < count; n++)
      Uint8List.fromList([
        count & 0xFF,
        count >> 8,
        (n + 1) & 0xFF,
        (n + 1) >> 8,
        ...all.sublist(n * chunk, ((n + 1) * chunk).clamp(0, all.length)),
      ]),
  ];
}

/// Sends one file. Returns false when the watch already had it.
Future<bool> upload(
  Link link,
  (int, int) kind,
  Uint8List data, {
  void Function(double)? onProgress,
}) async {
  final slice = parsePrepareResponse(
    await link.request(
      prepareRequest(kind, data),
      timeout: const Duration(seconds: 15),
    ),
  );
  if (slice == null) return false;
  final packets = buildPackets(kind, data, slice);
  for (var i = 0; i < packets.length; i++) {
    await link.sendChannel(channelMass, opcodePlain, packets[i]);
    onProgress?.call((i + 1) / packets.length);
  }
  return true;
}
