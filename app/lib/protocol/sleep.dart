/// Sleep health files. Every file is `id(7) · encryption/compression(1) ·
/// validity bits · body`, numbers little-endian. The validity bits are read
/// from the high bit of the first byte down, one per field, in field order.
///
/// **Night sleep** (data type 3, versions 1–2, 2 validity bytes): the band
/// staged the night itself. Report fields, sizes in bytes:
///   total score 1 · quality score 1 · duration score 1 · summary 1 ·
///   advice 1 · asleep minutes 2 · fell asleep u32 · woke up u32 ·
///   recovery score 1 · nervous score 1 · awake count 1 · deep minutes 2 ·
///   light minutes 2 · REM minutes 2 · awake minutes 2 · (v2) friendly
///   score 1
/// then stage records `time u32 · stage u8` to the end of the file; each
/// stage lasts until the next record's time.
///
/// **Nap** (data type 2, version 2, 1 validity byte): asleep minutes 2, then
/// stage records as above.
///
/// **Full-day sleep** (data types 7 and 8, versions 1–6; 1, 1, 1, 1, 2, 3
/// validity bytes): one sleep segment found by the band. The band does not
/// stage these; it sends raw features that Mi Fitness stages with a closed
/// Xiaomi model, which this app does not have. Fields:
///   finished u8 (no validity bit) · fell asleep u32 · woke up u32 ·
///   (v4) breathing quality u8 · (v5) efficiency u8 · latency u32 ·
///   in-bed u32 · went to bed u32 · left bed u32 · (v6) HRV average,
///   SD, median, low/high/mid percentile u16 ×6 · HRV time u32 · HRV max,
///   min, baseline max, baseline min u16 ×4
/// then series, each present only when its validity bit is set:
///   heart rate (u8), SpO₂ (u8), (v6) HRV (u16), (v3) snoring (u32), each as
///   `interval u16 (seconds) · count u16` and, when count > 0,
///   `(v2) first time u32 · values`. Version 1 has no first time; its
///   series start when sleep did.
/// The rest is the raw features.
///
/// Stage codes: 2 deep, 3 light, 4 REM, 5 awake.
library;

import 'dart:typed_data';

import 'package:openwear/protocol/fitness.dart';

const _napType = 2, _nightType = 3, _fullDayTypes = {7, 8};
const _flagsLength = 1;

enum SleepKind { night, nap, segment }

enum SleepStage { deep, light, rem, awake, unknown }

SleepStage stageOf(int code) => switch (code) {
  2 => SleepStage.deep,
  3 => SleepStage.light,
  4 => SleepStage.rem,
  5 => SleepStage.awake,
  _ => SleepStage.unknown,
};

class StageSpan {
  const StageSpan(this.start, this.end, this.stage);
  final DateTime start;
  final DateTime end;
  final SleepStage stage;
  Duration get length => end.difference(start);
}

/// One night, nap or segment as the band recorded it; null fields were not
/// measured.
class SleepSession {
  const SleepSession({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
    this.finished = true,
    this.wentToBed,
    this.leftBed,
    this.reportedAsleepMinutes,
    this.deepMinutes,
    this.lightMinutes,
    this.remMinutes,
    this.awakeMinutes,
    this.awakeCount,
    this.score,
    this.efficiency,
    this.breathingQuality,
    this.hrvAverage,
    this.stages = const [],
    this.heartRate = const [],
    this.spo2 = const [],
  });

  final FitnessId id;
  final SleepKind kind;

  /// Fell asleep / woke up.
  final DateTime start;
  final DateTime end;

  /// False while the band is still recording this segment.
  final bool finished;
  final DateTime? wentToBed;
  final DateTime? leftBed;
  final int? reportedAsleepMinutes;
  final int? deepMinutes;
  final int? lightMinutes;
  final int? remMinutes;
  final int? awakeMinutes;
  final int? awakeCount;

  /// Sleep score 0–100 (night sleep only).
  final int? score;

  /// Percent of time in bed spent asleep.
  final int? efficiency;

  /// Breathing quality 40–100.
  final int? breathingQuality;
  final int? hrvAverage;
  final List<StageSpan> stages;
  final List<(DateTime, int)> heartRate;
  final List<(DateTime, int)> spo2;

  bool get hasStages => stages.any((s) => s.stage != SleepStage.unknown);

  /// Time asleep: the stages without awake time when the band staged it,
  /// else what it reported, else fell asleep → woke up.
  Duration get asleep {
    if (hasStages) {
      return stages
          .where((s) => s.stage != SleepStage.awake)
          .fold(Duration.zero, (sum, s) => sum + s.length);
    }
    final m = reportedAsleepMinutes;
    if (m != null && m > 0) return Duration(minutes: m);
    return end.difference(start);
  }

  /// Time spent in each stage, from the stage list when there is one, else
  /// from the reported minutes.
  Map<SleepStage, Duration> get stageTotals {
    if (hasStages) {
      final out = <SleepStage, Duration>{};
      for (final s in stages) {
        out[s.stage] = (out[s.stage] ?? Duration.zero) + s.length;
      }
      return out;
    }
    return {
      for (final (stage, m) in [
        (SleepStage.deep, deepMinutes),
        (SleepStage.light, lightMinutes),
        (SleepStage.rem, remMinutes),
        (SleepStage.awake, awakeMinutes),
      ])
        if (m != null) stage: Duration(minutes: m),
    };
  }

  int? get averageHeartRate => _average(heartRate);
  int? get lowestHeartRate => heartRate.isEmpty
      ? null
      : heartRate.map((x) => x.$2).reduce((a, b) => a < b ? a : b);
  int? get averageSpo2 => _average(spo2);

  @override
  String toString() {
    String hm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final a = asleep;
    return '${kind.name} ${hm(start)}–${hm(end)}, asleep ${a.inHours} h '
        '${a.inMinutes % 60} min'
        '${hasStages ? ', ${stages.length} stages' : ''}'
        '${score == null ? '' : ', score $score'}'
        '${efficiency == null ? '' : ', efficiency $efficiency%'}'
        '${heartRate.isEmpty ? '' : ', HR ${heartRate.length} points'}'
        '${spo2.isEmpty ? '' : ', SpO₂ ${spo2.length} points'}'
        '${finished ? '' : ' (still recording)'}';
  }
}

int? _average(List<(DateTime, int)> xs) {
  final valid = [
    for (final x in xs)
      if (x.$2 > 0) x.$2,
  ];
  if (valid.isEmpty) return null;
  return (valid.reduce((a, b) => a + b) / valid.length).round();
}

bool isSleepFile(FitnessId id) =>
    !id.isSport &&
    (id.dataType == _napType ||
        id.dataType == _nightType ||
        _fullDayTypes.contains(id.dataType));

/// Parses a sleep file (as assembled, CRC already checked); null when the
/// file is not a sleep file, its version is unknown or it is cut short.
SleepSession? parseSleep(Uint8List file) {
  if (file.length < idLength + _flagsLength) return null;
  final id = FitnessId(file.sublist(0, idLength));
  if (!isSleepFile(id)) return null;
  try {
    return switch (id.dataType) {
      _nightType => _parseStaged(file, id, SleepKind.night),
      _napType => _parseStaged(file, id, SleepKind.nap),
      _ => _parseSegment(file, id),
    };
  } on RangeError {
    return null;
  }
}

/// Reads fields in order; a field is set only when its validity bit is.
class _Reader {
  _Reader(this.file, this.at, this.validity);
  final Uint8List file;
  int at;
  final Uint8List validity;
  int _bit = 0;
  late final _view = ByteData.sublistView(file);

  bool get atEnd => at >= file.length;

  /// The next validity bit.
  bool nextValid() {
    final byte = _bit ~/ 8, shift = 7 - _bit % 8;
    _bit++;
    if (byte >= validity.length) throw RangeError('validity bit $_bit');
    return (validity[byte] >> shift) & 1 == 1;
  }

  int read(int size) {
    if (at + size > file.length) throw RangeError('field at $at');
    final v = switch (size) {
      1 => file[at],
      2 => _view.getUint16(at, Endian.little),
      4 => _view.getUint32(at, Endian.little),
      _ => throw ArgumentError(size),
    };
    at += size;
    return v;
  }

  /// A field with a validity bit: always read, kept only when valid.
  int? field(int size) {
    final valid = nextValid();
    final v = read(size);
    return valid ? v : null;
  }
}

DateTime _time(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

SleepSession? _parseStaged(Uint8List file, FitnessId id, SleepKind kind) {
  final night = kind == SleepKind.night;
  final validityLength = night ? 2 : 1;
  if (night ? id.version > 2 : id.version != 2) return null;
  final header = idLength + _flagsLength + validityLength;
  if (file.length < header) return null;
  final r = _Reader(
    file,
    header,
    Uint8List.sublistView(file, idLength + _flagsLength, header),
  );
  int? score, asleep, start, end, awakeCount;
  int? deep, light, rem, awake;
  if (night) {
    score = r.field(1);
    for (var i = 0; i < 4; i++) {
      r.field(1); // quality, duration score, summary, advice
    }
    asleep = r.field(2);
    start = r.field(4);
    end = r.field(4);
    r.field(1); // recovery score
    r.field(1); // nervous score
    awakeCount = r.field(1);
    deep = r.field(2);
    light = r.field(2);
    rem = r.field(2);
    awake = r.field(2);
    if (id.version >= 2) r.field(1); // friendly score
  } else {
    asleep = r.field(2);
  }
  final records = <(int, int)>[];
  while (r.at + 5 <= file.length) {
    records.add((r.read(4), r.read(1)));
  }
  final stages = [
    for (var i = 0; i + 1 < records.length; i++)
      if (records[i + 1].$1 > records[i].$1)
        StageSpan(
          _time(records[i].$1),
          _time(records[i + 1].$1),
          stageOf(records[i].$2),
        ),
  ];
  final first = start ?? (records.isEmpty ? null : records.first.$1);
  final last = end ?? (records.isEmpty ? null : records.last.$1);
  if (first == null || last == null) return null;
  return SleepSession(
    id: id,
    kind: kind,
    start: _time(first),
    end: _time(last),
    reportedAsleepMinutes: asleep,
    deepMinutes: deep,
    lightMinutes: light,
    remMinutes: rem,
    awakeMinutes: awake,
    awakeCount: awakeCount,
    score: score,
    stages: stages,
  );
}

const _segmentValidityLength = {1: 1, 2: 1, 3: 1, 4: 1, 5: 2, 6: 3};

SleepSession? _parseSegment(Uint8List file, FitnessId id) {
  final v = id.version;
  final validityLength = _segmentValidityLength[v];
  if (validityLength == null) return null;
  final header = idLength + _flagsLength + validityLength;
  if (file.length < header) return null;
  final r = _Reader(
    file,
    header,
    Uint8List.sublistView(file, idLength + _flagsLength, header),
  );
  final finished = r.read(1) == 1;
  final start = r.field(4), end = r.field(4);
  final quality = v >= 4 ? r.field(1) : null;
  int? efficiency, wentToBed, leftBed, hrv;
  if (v >= 5) {
    efficiency = r.field(1);
    r.field(4); // latency
    r.field(4); // in bed
    wentToBed = r.field(4);
    leftBed = r.field(4);
  }
  if (v >= 6) {
    hrv = r.field(2);
    for (final size in [2, 2, 2, 2, 2, 4, 2, 2, 2, 2]) {
      r.field(size);
    }
  }
  final hasHr = r.nextValid(), hasSpo2 = r.nextValid();
  final hasHrv = v >= 6 && r.nextValid();
  final hasSnore = v >= 3 && r.nextValid();
  if (start == null || end == null) return null;
  List<(DateTime, int)> series(bool present, int size) {
    if (!present || r.at + 4 > file.length) return const [];
    final interval = r.read(2); // seconds
    final count = r.read(2);
    if (count == 0) return const [];
    final first = v >= 2 ? r.read(4) : start;
    return [
      for (var i = 0; i < count; i++)
        (_time(first + i * interval), r.read(size)),
    ];
  }

  final hr = series(hasHr, 1);
  final spo2 = series(hasSpo2, 1);
  series(hasHrv, 2);
  series(hasSnore, 4);
  return SleepSession(
    id: id,
    kind: SleepKind.segment,
    start: _time(start),
    end: _time(end),
    finished: finished,
    wentToBed: wentToBed == null || wentToBed == 0 ? null : _time(wentToBed),
    leftBed: leftBed == null || leftBed == 0 ? null : _time(leftBed),
    efficiency: efficiency,
    breathingQuality: quality == 0 ? null : quality,
    hrvAverage: hrv == 0 ? null : hrv,
    heartRate: [
      for (final x in hr)
        if (x.$2 > 0 && x.$2 < 255) x,
    ],
    spo2: [
      for (final x in spo2)
        if (x.$2 > 0 && x.$2 <= 100) x,
    ],
  );
}
