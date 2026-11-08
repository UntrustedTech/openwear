/// The band's daily activity report: health file with data type 0
/// (daily) and file type 1 (report). The band rewrites it through the day,
/// so today's copy holds the running totals.
///
/// Layout (versions 5 and 6, all little-endian):
///   id(7) · encryption/compression(1) · validity flags(4, MSB first; bit
///   31 − n marks body field n as valid) · body:
///   0 steps u32 · 1 active kcal u16 · 2 current HR u8 · 3 resting HR u8 ·
///   4 max HR u8 · 5 its time u32 · 6 min HR u8 · 7 its time u32 · 8 avg HR u8 ·
///   9 avg stress u8 · 10 max stress u8 · 11 min stress u8 ·
///   12 standing hours (24-bit mask) · 13 total kcal u16 · 14 recovery u16 ·
///   15 SpO₂ u8 · 16 max SpO₂ u8 · 17 its time u32 · 18 min SpO₂ u8 ·
///   19 its time u32 · 20 avg SpO₂ u8 · …
library;

import 'dart:typed_data';

import 'package:openwear/protocol/fitness.dart';

const _headerLength = 12; // id 7 + flags 1 + validity 4
const _knownVersions = {5, 6};

class DailyReport {
  const DailyReport({
    required this.day,
    required this.version,
    this.steps,
    this.activeCalories,
    this.totalCalories,
    this.standingHours,
    this.restingHeartRate,
    this.averageHeartRate,
    this.minHeartRate,
    this.maxHeartRate,
    this.averageStress,
    this.averageSpo2,
  });

  /// Local midnight the report belongs to.
  final DateTime day;
  final int version;
  final int? steps;
  final int? activeCalories;
  final int? totalCalories;
  final int? standingHours;
  final int? restingHeartRate;
  final int? averageHeartRate;
  final int? minHeartRate;
  final int? maxHeartRate;
  final int? averageStress;
  final int? averageSpo2;

  /// This report with steps and calories raised to [steps] etc. when the
  /// per-minute records are further along than the band's report.
  DailyReport atLeast({
    required int steps,
    required int activeCalories,
    required int totalCalories,
  }) => DailyReport(
    day: day,
    version: version,
    steps: _max(this.steps, steps),
    activeCalories: _max(this.activeCalories, activeCalories),
    totalCalories: _max(this.totalCalories, totalCalories),
    standingHours: standingHours,
    restingHeartRate: restingHeartRate,
    averageHeartRate: averageHeartRate,
    minHeartRate: minHeartRate,
    maxHeartRate: maxHeartRate,
    averageStress: averageStress,
    averageSpo2: averageSpo2,
  );

  /// This report with any missing vitals taken from the arguments.
  DailyReport withFallbacks({
    int? restingHeartRate,
    int? averageSpo2,
    int? averageStress,
    int? standingHours,
  }) => DailyReport(
    day: day,
    version: version,
    steps: steps,
    activeCalories: activeCalories,
    totalCalories: totalCalories,
    standingHours: _orElse(this.standingHours, standingHours),
    restingHeartRate: _orElse(this.restingHeartRate, restingHeartRate),
    averageHeartRate: averageHeartRate,
    minHeartRate: minHeartRate,
    maxHeartRate: maxHeartRate,
    averageStress: _orElse(this.averageStress, averageStress),
    averageSpo2: _orElse(this.averageSpo2, averageSpo2),
  );

  /// [own] unless it is missing or 0 (the band's "not measured"); a 0
  /// fallback counts as missing too.
  static int? _orElse(int? own, int? fallback) {
    if (own != null && own > 0) return own;
    if (fallback != null && fallback > 0) return fallback;
    return own;
  }

  static int? _max(int? a, int b) =>
      a == null ? (b > 0 ? b : null) : (a > b ? a : b);

  bool isFor(DateTime t) =>
      t.year == day.year && t.month == day.month && t.day == day.day;

  @override
  String toString() =>
      'steps ${steps ?? '–'}, ${activeCalories ?? '–'} active kcal, '
      'stood ${standingHours ?? '–'} h, resting HR ${restingHeartRate ?? '–'}, '
      'SpO₂ ${averageSpo2 ?? '–'}, stress ${averageStress ?? '–'}';
}

bool isDailyReport(FitnessId id) =>
    !id.isSport && id.dataType == 0 && id.fileType == 1;

/// Parses a report file (as assembled, CRC already checked); null when the
/// file is not a daily report or its version is unknown.
DailyReport? parseDailyReport(Uint8List file) {
  if (file.length < 7) return null;
  final id = FitnessId(file.sublist(0, 7));
  if (!isDailyReport(id) || !_knownVersions.contains(id.version)) return null;
  if (file.length < _headerLength + 42) return null;
  final v = ByteData.sublistView(file);
  final validity = v.getUint32(8, Endian.big);
  bool valid(int field) => validity >> (31 - field) & 1 == 1;

  // Body offsets for fields 0–20.
  const offsets = [
    0,
    4,
    6,
    7,
    8,
    9,
    13,
    14,
    18,
    19,
    20,
    21,
    22,
    25,
    27,
    29,
    30,
    31,
    35,
    36,
    40,
  ];
  int at(int field) => _headerLength + offsets[field];
  int? u8(int field) {
    if (!valid(field)) return null;
    final x = v.getUint8(at(field));
    return x == 0xff || x == 0 ? null : x;
  }

  int? u16(int field) =>
      valid(field) ? v.getUint16(at(field), Endian.little) : null;
  int? u32(int field) =>
      valid(field) ? v.getUint32(at(field), Endian.little) : null;

  int? standing() {
    if (!valid(12)) return null;
    final o = at(12);
    final mask =
        v.getUint8(o) | v.getUint8(o + 1) << 8 | v.getUint8(o + 2) << 16;
    var hours = 0;
    for (var m = mask; m != 0; m >>= 1) {
      hours += m & 1;
    }
    return hours;
  }

  final tz = Duration(minutes: id.tzQuarters * 15);
  final utc = DateTime.fromMillisecondsSinceEpoch(
    id.timestamp * 1000,
    isUtc: true,
  );
  final local = utc.add(tz);
  return DailyReport(
    day: DateTime(local.year, local.month, local.day),
    version: id.version,
    steps: u32(0),
    activeCalories: u16(1),
    restingHeartRate: u8(3),
    maxHeartRate: u8(4),
    minHeartRate: u8(6),
    averageHeartRate: u8(8),
    averageStress: u8(9),
    standingHours: standing(),
    totalCalories: u16(13),
    averageSpo2: u8(20),
  );
}
