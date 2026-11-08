/// Decoding of reassembled channel-5 health files (`id(7) ‖ body`, CRC already checked).
///
/// Verified so far: the heart-rate sample file the band streams during live HR
/// (data type 6): one header byte, then 6-byte records `ts u32 LE · 0x11 · bpm`.
library;

import 'dart:typed_data';

import 'package:openwear/protocol/fitness.dart';

const _hrSampleType = 6, _hrRecordLength = 6, _hrHeaderLength = 1;

enum HealthFileKind { heartRateSamples, other }

class HrSample {
  const HrSample(this.time, this.bpm);
  final DateTime time;
  final int bpm;
}

class HealthFile {
  const HealthFile(
    this.id,
    this.kind,
    this.body, {
    this.heartRate = const [],
    this.trailingBytes = 0,
  });
  final FitnessId id;
  final HealthFileKind kind;
  final Uint8List body;
  final List<HrSample> heartRate;

  /// Bytes left over that do not form a whole record (0 for a clean file).
  final int trailingBytes;
}

HealthFile parseHealthFile(Uint8List file) {
  if (file.length < idLength) {
    throw const FormatException('health file shorter than its id');
  }
  final id = FitnessId(file.sublist(0, idLength));
  final body = Uint8List.sublistView(file, idLength);
  if (id.isSport || id.dataType != _hrSampleType || body.isEmpty) {
    return HealthFile(id, HealthFileKind.other, body);
  }
  final records = Uint8List.sublistView(body, _hrHeaderLength);
  final view = ByteData.sublistView(records);
  final samples = <HrSample>[];
  var at = 0;
  for (; at + _hrRecordLength <= records.length; at += _hrRecordLength) {
    final ts = view.getUint32(at, Endian.little);
    final bpm = records[at + 5];
    samples.add(HrSample(DateTime.fromMillisecondsSinceEpoch(ts * 1000), bpm));
  }
  return HealthFile(
    id,
    HealthFileKind.heartRateSamples,
    body,
    heartRate: samples,
    trailingBytes: records.length - at,
  );
}

/// One line for the live log.
String describeHealthFile(HealthFile f) {
  if (f.kind == HealthFileKind.other) {
    return 'health file type ${f.id.dataType}, ${f.body.length} bytes';
  }
  final s = f.heartRate;
  if (s.isEmpty) return '0 HR samples';
  String hms(DateTime t) =>
      [t.hour, t.minute, t.second].map((n) => '$n'.padLeft(2, '0')).join(':');
  final shown = s.length > 4 ? s.sublist(s.length - 4) : s;
  final list = shown.map((x) => '${hms(x.time)} ${x.bpm} bpm').join(', ');
  final bpm = s.map((x) => x.bpm);
  final low = bpm.reduce((a, b) => a < b ? a : b);
  final high = bpm.reduce((a, b) => a > b ? a : b);
  return '${s.length} HR samples (${hms(s.first.time)}–${hms(s.last.time)}, '
      '$low–$high bpm): ${s.length > 4 ? '… ' : ''}$list';
}
