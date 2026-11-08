import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/daily_record.dart';
import 'package:openwear/protocol/fitness.dart';

Uint8List hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

// A real v4 file from the Smart Band 9: three idle minutes.
const idle =
    'b87ee56af0040000fffff8cfffff'
    '000000e000000064e400000000000000000000e000000064e400000000000000000000e000000064e400000000000000';

void main() {
  test('the real v4 file holds three minutes without heart rate', () {
    final file = hex(idle.replaceAll(' ', ''));
    final minutes = parseDailyRecord(file)!;
    expect(minutes, hasLength(3));
    final start = FitnessId(file.sublist(0, 7)).timestamp ~/ 60 * 60;
    expect(minutes.first.time.millisecondsSinceEpoch, start * 1000);
    expect(minutes[1].time.difference(minutes[0].time).inSeconds, 60);
    expect(minutes.every((m) => m.heartRate == null && m.steps == 0), isTrue);
  });

  test('heart rate, steps and the abnormal byte are read', () {
    final file = hex(idle).sublist(0, 14);
    final record = [
      0x2a, 0x40, // rise set, 42 steps
      0, 0xe0, 0, 0, // activity, strength, distance
      72, 100, 0xe4, 0, 97, 20, // HR, battery, energy, SpO₂, stress
      130, // abnormal HR (rise)
      0, 0, 0, 0, // light, movement
    ];
    final minutes = parseDailyRecord(Uint8List.fromList([...file, ...record]))!;
    expect(minutes, hasLength(1));
    expect(minutes.single.heartRate, 72);
    expect(minutes.single.steps, 42);
    expect(minutes.single.spo2, 97);
    expect(heartRateOf(minutes).single.bpm, 72);
  });

  test('today\'s totals add up steps and calories per minute', () {
    final header = hex(idle).sublist(0, 14);
    List<int> minute(int steps, int kcal) => [
      steps & 0xff, steps >> 8, // no rise
      kcal, 0xe0, 0, 0, // activity: calories in bits 5–0
      70, 100, 0, kcal << 2, 0, 0, // HR, battery, total kcal bits 15–10
      0, 0, 0, 0,
    ];
    final file = Uint8List.fromList([
      ...header,
      ...minute(100, 3),
      ...minute(250, 5),
    ]);
    final minutes = parseDailyRecord(file)!;
    final day = minutes.first.time;
    final t = totalsFor(minutes, day);
    expect(t.steps, 350);
    expect(t.activeCalories, 8);
    expect(t.totalCalories, 8);
    expect(totalsFor(minutes, day.add(const Duration(days: 1))).steps, 0);
  });

  test('other files are ignored', () {
    final file = hex(idle);
    file[6] = 0x01; // file type 1: the daily report
    expect(parseDailyRecord(file), isNull);
  });
}
