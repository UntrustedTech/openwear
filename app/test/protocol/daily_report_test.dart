import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/daily_report.dart';

Uint8List hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

/// Today's report from the Band 9 (not worn yet), synced with the PC tool.
final idle = hex(
  'c067e56af00501000000000c00000000000000000000000000ff00000000000000ff00'
  '000000000000000000000000ff000000000000000000000000000000011c',
);

Uint8List withValues() {
  final f = Uint8List.fromList(idle);
  final v = ByteData.sublistView(f);
  // steps, active kcal, resting HR, avg HR, standing, total kcal, avg SpO2
  const fields = [0, 1, 3, 8, 12, 13, 20];
  var flags = 0;
  for (final n in fields) {
    flags |= 1 << (31 - n);
  }
  v.setUint32(8, flags, Endian.big);
  v.setUint32(12, 6543, Endian.little);
  v.setUint16(16, 287, Endian.little);
  v.setUint8(19, 58);
  v.setUint8(30, 74);
  // stood in hours 8, 9, 13 and 17
  final mask = 1 << 8 | 1 << 9 | 1 << 13 | 1 << 17;
  v
    ..setUint8(34, mask & 0xff)
    ..setUint8(35, mask >> 8 & 0xff)
    ..setUint8(36, mask >> 16);
  v.setUint16(37, 1890, Endian.little);
  v.setUint8(52, 97);
  return f;
}

void main() {
  test('the idle report belongs to local midnight and has no totals', () {
    final r = parseDailyReport(idle)!;
    expect(r.day, DateTime(2026, 10, 31));
    expect(r.version, 5);
    expect(r.steps, isNull, reason: 'steps not flagged valid');
    expect(r.standingHours, isNull);
    expect(r.minHeartRate, isNull);
  });

  test('flagged fields are read at their offsets', () {
    final r = parseDailyReport(withValues())!;
    expect(r.steps, 6543);
    expect(r.activeCalories, 287);
    expect(r.restingHeartRate, 58);
    expect(r.averageHeartRate, 74);
    expect(r.standingHours, 4);
    expect(r.totalCalories, 1890);
    expect(r.averageSpo2, 97);
    expect(r.maxHeartRate, isNull, reason: 'not flagged');
  });

  test('other files and unknown versions are not reports', () {
    final hr = hex('c067e56af00218');
    expect(
      parseDailyReport(Uint8List.fromList([...hr, ...List.filled(60, 0)])),
      isNull,
    );
    final v9 = Uint8List.fromList(idle)..[5] = 9;
    expect(parseDailyReport(v9), isNull);
    expect(parseDailyReport(Uint8List.fromList(idle.sublist(0, 30))), isNull);
  });

  test('fallbacks fill missing or zero vitals but never hide real ones', () {
    final day = DateTime(2026, 10, 31);
    final empty = DailyReport(
      day: day,
      version: 5,
      standingHours: 0,
      averageSpo2: 0,
    );
    final filled = empty.withFallbacks(
      restingHeartRate: 58,
      averageSpo2: 97,
      averageStress: 31,
      standingHours: 6,
    );
    expect(filled.restingHeartRate, 58);
    expect(filled.averageSpo2, 97);
    expect(filled.averageStress, 31);
    expect(filled.standingHours, 6);

    final real = DailyReport(day: day, version: 5, averageSpo2: 95);
    expect(real.withFallbacks(averageSpo2: 97).averageSpo2, 95);
    expect(empty.withFallbacks(standingHours: 0).standingHours, 0);
  });
}
