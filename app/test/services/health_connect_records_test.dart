import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/daily_record.dart';
import 'package:openwear/protocol/sleep.dart';
import 'package:openwear/services/health_connect_records.dart';

void _u32(BytesBuilder b, int v) =>
    b.add([for (var i = 0; i < 4; i++) v >> (8 * i) & 0xff]);
void _u16(BytesBuilder b, int v) => b.add([v & 0xff, v >> 8 & 0xff]);

const _bed = 1793500000;

/// Unstaged segment (type 8 v5): asleep 2 h, in bed 10 min either side.
SleepSession _segment() {
  final b = BytesBuilder();
  _u32(b, _bed);
  b.add([0, 5, 8 << 2 | 1, 0, 0xff, 0x80, 1]);
  _u32(b, _bed);
  _u32(b, _bed + 7200);
  b.add([90, 93]);
  for (final v in [600, 8400, _bed - 600, _bed + 7800]) {
    _u32(b, v);
  }
  _u16(b, 60);
  _u16(b, 0);
  _u32(b, _bed);
  return parseSleep(b.toBytes())!;
}

void main() {
  final hour = DateTime.utc(2026, 11, 1, 14);

  test('minutes add up to hourly steps and calories', () {
    final minutes = [
      DailyMinute(hour, steps: 100, activeCalories: 3, totalCalories: 5),
      DailyMinute(
        hour.add(const Duration(minutes: 30)),
        steps: 50,
        activeCalories: 1,
        totalCalories: 2,
      ),
      DailyMinute(hour.add(const Duration(hours: 1)), steps: 0),
    ];
    final now = hour.add(const Duration(hours: 1, minutes: 20));
    final r = activityRecords(minutes, now);
    final steps = r.singleWhere((x) => x['kind'] == 'steps');
    expect(steps['value'], 150);
    expect(steps['version'], 150);
    expect(steps['start'], hour.millisecondsSinceEpoch);
    expect(
      steps['end'],
      hour.add(const Duration(hours: 1)).millisecondsSinceEpoch,
    );
    expect(r.singleWhere((x) => x['kind'] == 'activeKcal')['value'], 4);
    expect(r.singleWhere((x) => x['kind'] == 'totalKcal')['value'], 7);
    expect(r, hasLength(3), reason: 'the empty hour is skipped');
  });

  test('the current hour ends now', () {
    final now = hour.add(const Duration(minutes: 10));
    final r = activityRecords([DailyMinute(hour, steps: 10)], now);
    expect(r.single['end'], now.millisecondsSinceEpoch);
  });

  test('SpO₂ readings outside 1–100 or in the future are dropped', () {
    final now = hour;
    final r = spo2Records([
      (hour.subtract(const Duration(minutes: 1)), 97),
      (hour.subtract(const Duration(minutes: 2)), 0),
      (hour.add(const Duration(minutes: 1)), 96),
    ], now);
    expect(r.single['value'], 97);
  });

  test('resting HR is one record per day', () {
    final day = DateTime(2026, 11, 1);
    final a = restingHeartRateRecord(day, 67, hour, version: 1);
    final b = restingHeartRateRecord(day, 65, hour, version: 2);
    expect(a['id'], b['id']);
    expect(a['id'], 'openwear-rhr-20261101');
  });

  test('unstaged sleep becomes in-bed, sleeping, in-bed', () {
    final r = sleepRecord(_segment());
    int ms(int s) => s * 1000;
    expect(r['start'], ms(_bed - 600));
    expect(r['end'], ms(_bed + 7800));
    expect(r['stages'], [
      [ms(_bed - 600), ms(_bed), 'inBed'],
      [ms(_bed), ms(_bed + 7200), 'sleeping'],
      [ms(_bed + 7200), ms(_bed + 7800), 'inBed'],
    ]);
  });
}
