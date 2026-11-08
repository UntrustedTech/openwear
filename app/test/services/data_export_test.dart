import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/daily_record.dart';
import 'package:openwear/protocol/manual_measurement.dart';
import 'package:openwear/services/data_export.dart';

String fileText(Archive a, String name) =>
    utf8.decode(a.findFile(name)!.content as List<int>);

void main() {
  final at = DateTime(2026, 11, 2, 9, 30);

  ExportData sample() => ExportData(
    created: at,
    heartRate: {at: 72, at.add(const Duration(minutes: 1)): 75},
    minutes: [
      DailyMinute(at, steps: 40, heartRate: 72, spo2: 98, activeCalories: 2),
    ],
    spotChecks: [Measurement(at, MeasurementKind.spo2, 97)],
    sleep: const [],
    log: 'line one',
  );

  test('the zip holds one CSV per kind of data, a log and a readme', () {
    final zip = ZipDecoder().decodeBytes(buildExport(sample()));
    expect(zip.files.map((f) => f.name).toSet(), {
      'README.txt',
      'heart_rate.csv',
      'activity_minutes.csv',
      'spot_checks.csv',
      'sleep_sessions.csv',
      'sleep_stages.csv',
      'live_log.txt',
    });
  });

  test('heart rate rows carry a local ISO time and the bpm', () {
    final zip = ZipDecoder().decodeBytes(buildExport(sample()));
    final lines = const LineSplitter().convert(fileText(zip, 'heart_rate.csv'));
    expect(lines.first, 'time,bpm');
    expect(lines[1], '2026-11-02T09:30:00,72');
    expect(lines, hasLength(3));
  });

  test('missing values are left empty, not zero', () {
    final zip = ZipDecoder().decodeBytes(buildExport(sample()));
    final lines = const LineSplitter().convert(
      fileText(zip, 'activity_minutes.csv'),
    );
    expect(
      lines.first,
      'time,steps,heart_rate,spo2,active_kcal,total_kcal,stress',
    );
    expect(lines[1], '2026-11-02T09:30:00,40,72,98,2,,');
  });

  test('spot checks name their kind', () {
    final zip = ZipDecoder().decodeBytes(buildExport(sample()));
    expect(fileText(zip, 'spot_checks.csv'), contains(',spo2,97'));
  });

  test('the file name carries the date and time', () {
    expect(exportFileName(at), 'openwear-export-20261102-0930.zip');
  });

  group('password', () {
    test('a protected export is AES encrypted and opens with the password', () {
      final bytes = buildExport(sample(), password: 'hunter22');
      expect(
        utf8.decode(bytes, allowMalformed: true),
        isNot(contains('time,bpm')),
        reason: 'no CSV text in the clear',
      );
      final zip = ZipDecoder().decodeBytes(bytes, password: 'hunter22');
      expect(fileText(zip, 'heart_rate.csv'), startsWith('time,bpm'));
    });

    test('short passwords are refused', () {
      expect(() => buildExport(sample(), password: '123'), throwsArgumentError);
    });
  });
}
