/// The band's per-minute activity record: health file with data type 0
/// (daily) and file type 0 (record). It holds what the band measured on
/// its own through the day — all-day heart rate, steps, SpO₂.
///
/// Layout (versions 3–5):
///   id(7) · encryption/compression(1) · validity(6, big-endian 48 bits) ·
///   records until the end of the file, one per minute from the id time.
///
/// The validity mask has four bits per item, from bit 47 down: the first
/// says the item is present in each record, the next three that its first,
/// second and third packed value are valid (steps are the third value of
/// item 0, calories the second of item 1, total calories the first of
/// item 6). Items, in order, with their size in bytes:
///   heart-rate rise + steps 2 · activity type + calories 1 ·
///   strength / sport type 1 · distance 2 · heart rate 1 · battery 1 ·
///   calories + energy 2 · SpO₂ 1 · stress 1 · light 2 (v4+) ·
///   movement 2 (v4+) · floors 1 (v5)
/// After stress, one extra byte (abnormal heart rate) follows when the
/// record's heart-rate-rise bit is set.
library;

import 'dart:typed_data';

import 'package:openwear/protocol/fitness.dart';
import 'package:openwear/protocol/health_records.dart';

const _headerLength = 14; // id 7 + flags 1 + validity 6
const _knownVersions = {3, 4, 5};
const _recordSeconds = 60;

enum _Item {
  riseAndSteps(2),
  activity(1),
  strength(1),
  distance(2),
  heartRate(1),
  battery(1),
  energy(2),
  spo2(1),
  stress(1),
  light(2, since: 4),
  movement(2, since: 4),
  floors(1, since: 5);

  const _Item(this.size, {this.since = 3});
  final int size;
  final int since;
}

/// One minute of the band's own measurements; null when not measured.
class DailyMinute {
  const DailyMinute(
    this.time, {
    this.steps,
    this.heartRate,
    this.spo2,
    this.activeCalories,
    this.totalCalories,
    this.stress,
  });
  final DateTime time;
  final int? steps;
  final int? activeCalories;
  final int? totalCalories;
  final int? heartRate;
  final int? spo2;
  final int? stress;
}

bool isDailyRecord(FitnessId id) =>
    !id.isSport && id.dataType == 0 && id.fileType == 0;

/// Parses a record file (as assembled, CRC already checked); null when the
/// file is not a daily record or its version is unknown.
List<DailyMinute>? parseDailyRecord(Uint8List file) {
  if (file.length < _headerLength) return null;
  final id = FitnessId(file.sublist(0, 7));
  if (!isDailyRecord(id) || !_knownVersions.contains(id.version)) return null;
  var mask = 0;
  for (var i = 8; i < _headerLength; i++) {
    mask = mask << 8 | file[i];
  }
  bool bit(int n) => mask >> n & 1 == 1;
  final items = [
    for (final item in _Item.values)
      if (id.version >= item.since && bit(47 - item.index * 4)) item,
  ];

  /// Whether packed value [part] (0 first, 1 second, 2 third) is valid.
  bool valid(_Item item, [int part = 0]) => bit(46 - item.index * 4 - part);
  final perRecord = items.fold(0, (n, i) => n + i.size);
  if (perRecord == 0) return const [];

  final v = ByteData.sublistView(file);
  final start = id.timestamp ~/ _recordSeconds * _recordSeconds;
  final minutes = <DailyMinute>[];
  var at = _headerLength;
  while (at + perRecord <= file.length) {
    int? steps;
    int? heartRate;
    int? spo2;
    int? active;
    int? total;
    int? stress;
    var rise = false;
    for (final item in items) {
      final value = item.size == 2 ? v.getUint16(at, Endian.little) : file[at];
      at += item.size;
      switch (item) {
        case _Item.riseAndSteps:
          rise = value >> 14 & 1 == 1;
          if (valid(item, 2)) steps = value & 0x3fff;
        case _Item.activity when valid(item, 1):
          active = value & 0x3f;
        case _Item.energy when valid(item):
          total = value >> 10 & 0x3f;
        case _Item.heartRate when valid(item):
          heartRate = _measured(value);
        case _Item.spo2 when valid(item):
          spo2 = _measured(value);
        case _Item.stress:
          if (valid(item)) stress = _measured(value);
          if (rise) at++; // abnormal heart rate
        default:
      }
    }
    if (at > file.length) break;
    minutes.add(
      DailyMinute(
        DateTime.fromMillisecondsSinceEpoch(
          (start + minutes.length * _recordSeconds) * 1000,
        ),
        steps: steps,
        heartRate: heartRate,
        spo2: spo2,
        activeCalories: active,
        totalCalories: total,
        stress: stress,
      ),
    );
  }
  return minutes;
}

int? _measured(int v) => v == 0 || v == 0xff ? null : v;

/// The heart-rate readings in [minutes].
List<HrSample> heartRateOf(List<DailyMinute> minutes) => [
  for (final m in minutes)
    if (m.heartRate case final bpm?) HrSample(m.time, bpm),
];

/// Sum of steps and calories over [minutes] that fall on [day] (local).
({int steps, int activeCalories, int totalCalories}) totalsFor(
  Iterable<DailyMinute> minutes,
  DateTime day,
) {
  var steps = 0, active = 0, total = 0;
  for (final m in minutes) {
    final t = m.time;
    if (t.year != day.year || t.month != day.month || t.day != day.day) {
      continue;
    }
    steps += m.steps ?? 0;
    active += m.activeCalories ?? 0;
    total += m.totalCalories ?? 0;
  }
  return (steps: steps, activeCalories: active, totalCalories: total);
}

/// Minutes with at least this many steps count as moving for the stand goal.
const _standStepsPerMinute = 30;

/// Readings with fewer heart-rate values than this give no resting estimate.
const _restingMinReadings = 10;

/// Daily vitals worked out from the minute records, for when the band's
/// own report has not filled them in yet.
({int? spo2, int? stress, int? restingHeartRate, int standHours}) vitalsFor(
  Iterable<DailyMinute> minutes,
  DateTime day,
) {
  final spo2 = <int>[], stress = <int>[], hr = <int>[];
  final movedHours = <int>{};
  for (final m in minutes) {
    final t = m.time;
    if (t.year != day.year || t.month != day.month || t.day != day.day) {
      continue;
    }
    if (m.spo2 case final v? when v >= 70 && v <= 100) spo2.add(v);
    if (m.stress case final v? when v <= 100) stress.add(v);
    if (m.heartRate case final v? when v >= 30) hr.add(v);
    if ((m.steps ?? 0) >= _standStepsPerMinute) movedHours.add(t.hour);
  }
  int? mean(List<int> xs) =>
      xs.isEmpty ? null : (xs.reduce((a, b) => a + b) / xs.length).round();
  int? resting;
  if (hr.length >= _restingMinReadings) {
    hr.sort();
    // The calmest tenth of the day's readings.
    resting = mean(hr.sublist(0, (hr.length / 10).ceil()));
  }
  return (
    spo2: mean(spo2),
    stress: mean(stress),
    restingHeartRate: resting,
    standHours: movedHours.length,
  );
}

/// All records of a day's record [files], timed between file starts.
///
/// The band writes one record a minute, but also writes one each time the
/// phone syncs and starts a new file after it, so a file's records are not
/// always a minute apart. Steps and calories are increments, so every
/// record counts; times are spread evenly up to the next file (at most a
/// minute apart) and never after [now]. A file the band resent as it grew
/// counts once: the longest copy of each id wins.
List<DailyMinute> recordsOfFiles(Iterable<Uint8List> files, DateTime now) {
  final byId = <String, Uint8List>{};
  for (final f in files) {
    if (f.length < idLength) continue;
    final key = FitnessId(f.sublist(0, idLength)).hex;
    final seen = byId[key];
    if (seen == null || f.length > seen.length) byId[key] = f;
  }
  final parsed = [
    for (final f in byId.values)
      if (parseDailyRecord(f) case final records? when records.isNotEmpty)
        (start: FitnessId(f.sublist(0, idLength)).timestamp, records: records),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
  final out = <DailyMinute>[];
  for (var i = 0; i < parsed.length; i++) {
    final (:start, :records) = parsed[i];
    final end = i + 1 < parsed.length ? parsed[i + 1].start : nowSeconds;
    final span = end - start;
    final step = span <= 0
        ? 1
        : (span ~/ records.length).clamp(1, _recordSeconds);
    for (var k = 0; k < records.length; k++) {
      final m = records[k];
      final at = start + k * step;
      out.add(
        DailyMinute(
          DateTime.fromMillisecondsSinceEpoch(
            (at > nowSeconds && nowSeconds > start ? nowSeconds : at) * 1000,
          ),
          steps: m.steps,
          heartRate: m.heartRate,
          spo2: m.spo2,
          activeCalories: m.activeCalories,
          totalCalories: m.totalCalories,
          stress: m.stress,
        ),
      );
    }
  }
  return out;
}
