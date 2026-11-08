/// Health sync (8/x file IDs + channel-5 files) and live heart rate (8/45–47).
library;

import 'dart:typed_data';

import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/crc32.dart';
import 'package:openwear/protocol/pb.dart';

const idLength = 7;
const _subTodayIds = 1, _subHistoryIds = 2, _subRequestOne = 4, _subConfirm = 5;
const _subRealtimeStart = 45, _subRealtimeStop = 46, _subRealtimeData = 47;
const _fIds = 2, _fId = 3, _fTodayReq = 5, _fRealtime = 39, _fRealtimeHr = 4;

class FitnessId {
  FitnessId(List<int> raw) : raw = Uint8List.fromList(raw);
  final Uint8List raw;

  ByteData get _view => ByteData.sublistView(raw);
  int get timestamp => _view.getUint32(0, Endian.little);
  int get tzQuarters => _view.getInt8(4);
  int get version => raw[5];
  bool get isSport => raw[6] >> 7 == 1;
  int get dataType => (raw[6] >> 2) & 0x1F;
  int get fileType => raw[6] & 0x03;
  String get hex => raw.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  bool operator ==(Object other) => other is FitnessId && other.hex == hex;
  @override
  int get hashCode => hex.hashCode;
}

List<FitnessId> splitIds(List<int> blob) => [
  for (var i = 0; i + idLength <= blob.length; i += idLength)
    FitnessId(blob.sublist(i, i + idLength)),
];

Command todayIdsRequest() => Command.of(typeFitness, _subTodayIds, [
  PbBytes(_fTodayReq, pbEncode([const PbVarint(1, 0)])),
]);

Command historyIdsRequest() => const Command(typeFitness, _subHistoryIds);

List<FitnessId> idsFromResponse(Command rsp) =>
    splitIds(rsp.body.bytes(_fIds) ?? rsp.body.bytes(_fId) ?? Uint8List(0));

Command requestFile(FitnessId id) =>
    Command.of(typeFitness, _subRequestOne, [PbBytes(_fId, id.raw)]);

/// Tells the band the file is saved; it may then delete it.
Command confirmFile(FitnessId id) =>
    Command.of(typeFitness, _subConfirm, [PbBytes(_fId, id.raw)]);

/// Reassembles channel-5 packets `[total u16][seq u16, 1-based][bytes]` into
/// `id(7) ‖ body`, checking the trailing CRC32 (little-endian).
class FileAssembler {
  final _parts = <Uint8List>[];
  int _total = 0;

  /// Returns the complete file once the last packet arrives, else null.
  Uint8List? feed(Uint8List packet) {
    final view = ByteData.sublistView(packet);
    final total = view.getUint16(0, Endian.little),
        seq = view.getUint16(2, Endian.little);
    if (seq == 1 || total != _total || seq != _parts.length + 1) {
      _parts.clear();
      _total = total;
      if (seq != 1) {
        throw FormatException('fitness packet $seq/$total out of order');
      }
    }
    _parts.add(Uint8List.sublistView(packet, 4));
    if (seq < total) return null;
    final data = Uint8List.fromList(_parts.expand((p) => p).toList());
    _parts.clear();
    _total = 0;
    if (data.length < 4) throw const FormatException('fitness file too short');
    final body = Uint8List.sublistView(data, 0, data.length - 4);
    final crc = ByteData.sublistView(
      data,
      data.length - 4,
    ).getUint32(0, Endian.little);
    if (crc32(body) != crc) {
      throw const FormatException('fitness file CRC32 mismatch');
    }
    return Uint8List.fromList(body);
  }
}

// --- live heart rate ---------------------------------------------------------------

Command realtimeStart() => const Command(typeFitness, _subRealtimeStart);
Command realtimeStop() => const Command(typeFitness, _subRealtimeStop);

/// BPM from an 8/47 push (~1/s while streaming); 0 = no reading yet (not worn).
/// Returns null for any other command.
int? realtimeHeartRate(Command cmd) {
  if (!cmd.isA(typeFitness, _subRealtimeData)) return null;
  return cmd.body.message(_fRealtime)?.int_(_fRealtimeHr);
}
