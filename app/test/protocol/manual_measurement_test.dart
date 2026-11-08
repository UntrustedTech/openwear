import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/daily_record.dart';
import 'package:openwear/protocol/manual_measurement.dart';

void main() {
  test('reads spot checks of each kind', () {
    final file = Uint8List.fromList([
      0x00, 0x10, 0x00, 0x6b, 0xf0, 0x02, 0x18, 0x00, // id: type 6, v2
      0x10, 0x10, 0x00, 0x6b, 0x22, 97, // SpO₂ 97
      0x20, 0x10, 0x00, 0x6b, 0x13, 41, // stress 41
      0x30, 0x10, 0x00, 0x6b, 0x14, 1, 2, 3, 4, // temperature (skipped value)
      0x40, 0x10, 0x00, 0x6b, 0x01, 64, // heart rate 64
    ]);
    final m = parseManualMeasurements(file)!;
    expect(
      [for (final x in m) x.kind],
      [
        MeasurementKind.spo2,
        MeasurementKind.stress,
        MeasurementKind.temperature,
        MeasurementKind.heartRate,
      ],
    );
    expect([for (final x in m) x.value], [97, 41, 0, 64]);
  });

  test('other files are not measurements', () {
    expect(
      parseManualMeasurements(Uint8List.fromList([0, 0, 0, 0, 0, 4, 0, 0])),
      isNull,
    );
  });

  test('vitals come from the minute records', () {
    final day = DateTime(2026, 10, 31);
    final minutes = [
      for (var i = 0; i < 20; i++)
        DailyMinute(
          day.add(Duration(hours: 9, minutes: i * 6)),
          heartRate: 60 + i,
          spo2: i.isEven ? 96 : null,
          stress: i < 4 ? 30 : null,
          steps: i == 0 || i == 15 ? 80 : 0,
        ),
    ];
    final v = vitalsFor(minutes, day);
    expect(v.spo2, 96);
    expect(v.stress, 30);
    expect(v.restingHeartRate, 61); // lowest tenth: 60, 61 → 61 (rounded)
    expect(v.standHours, 2); // 9:00 and 10:30
  });
}
