/// Everything OpenWear holds about the wearer's health, as a ZIP of CSV
/// files that a spreadsheet opens, plus the live log.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:openwear/protocol/daily_record.dart';
import 'package:openwear/protocol/manual_measurement.dart';
import 'package:openwear/protocol/sleep.dart';

/// Where exports land, under the phone's Download folder.
const exportFolder = 'OpenWear/Exports';

class ExportData {
  const ExportData({
    required this.created,
    required this.heartRate,
    required this.minutes,
    required this.spotChecks,
    required this.sleep,
    required this.log,
  });
  final DateTime created;
  final Map<DateTime, int> heartRate;
  final List<DailyMinute> minutes;
  final List<Measurement> spotChecks;
  final List<SleepSession> sleep;
  final String log;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Local time without fractions, e.g. 2026-11-02T09:30:00.
String _time(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)}'
    'T${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

String _cell(Object? v) => switch (v) {
  null => '',
  DateTime t => _time(t),
  _ => '$v',
};

String _csv(List<String> header, Iterable<List<Object?>> rows) {
  final b = StringBuffer()..writeln(header.join(','));
  for (final r in rows) {
    b.writeln(r.map(_cell).join(','));
  }
  return b.toString();
}

String exportFileName(DateTime t) =>
    'openwear-export-${t.year}${_two(t.month)}${_two(t.day)}'
    '-${_two(t.hour)}${_two(t.minute)}.zip';

String _readme(ExportData d) =>
    '''
OpenWear data export, made ${_time(d.created)} (phone's local time).

heart_rate.csv        every heart-rate reading the app has received
activity_minutes.csv  today's minute-by-minute record from the band
spot_checks.csv       measurements started on the band (heart rate, SpO2, stress)
sleep_sessions.csv    nights and naps with their totals and score
sleep_stages.csv      the stages (deep, light, REM, awake) inside each session
live_log.txt          what the band and app exchanged, for bug reports

Empty cells mean the band did not report that value.
''';

/// Shortest password accepted for a protected export.
const exportPasswordMinLength = 6;

/// Builds the ZIP for [d]. With a [password], every file in it is
/// encrypted with AES-256 (WinZip AE-2), which 7-Zip, WinRAR, macOS
/// Archive Utility and most Android file managers open.
Uint8List buildExport(ExportData d, {String? password}) {
  if (password != null && password.length < exportPasswordMinLength) {
    throw ArgumentError('password too short');
  }
  final files = {
    'README.txt': _readme(d),
    'heart_rate.csv': _csv(
      ['time', 'bpm'],
      [
        for (final e
            in (d.heartRate.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key))))
          [e.key, e.value],
      ],
    ),
    'activity_minutes.csv': _csv(
      [
        'time',
        'steps',
        'heart_rate',
        'spo2',
        'active_kcal',
        'total_kcal',
        'stress',
      ],
      [
        for (final m in d.minutes)
          [
            m.time,
            m.steps,
            m.heartRate,
            m.spo2,
            m.activeCalories,
            m.totalCalories,
            m.stress,
          ],
      ],
    ),
    'spot_checks.csv': _csv(
      ['time', 'kind', 'value'],
      [
        for (final c in d.spotChecks) [c.time, c.kind.name, c.value],
      ],
    ),
    'sleep_sessions.csv': _csv(
      [
        'start',
        'end',
        'kind',
        'finished',
        'asleep_min',
        'deep_min',
        'light_min',
        'rem_min',
        'awake_min',
        'awake_count',
        'score',
        'efficiency',
      ],
      [
        for (final s in d.sleep)
          [
            s.start,
            s.end,
            s.kind.name,
            s.finished,
            s.reportedAsleepMinutes,
            s.deepMinutes,
            s.lightMinutes,
            s.remMinutes,
            s.awakeMinutes,
            s.awakeCount,
            s.score,
            s.efficiency,
          ],
      ],
    ),
    'sleep_stages.csv': _csv(
      ['session_start', 'start', 'end', 'stage'],
      [
        for (final s in d.sleep)
          for (final st in s.stages) [s.start, st.start, st.end, st.stage.name],
      ],
    ),
    'live_log.txt': d.log,
  };
  final archive = Archive();
  for (final MapEntry(key: name, value: text) in files.entries) {
    archive.addFile(ArchiveFile.string(name, text));
  }
  return Uint8List.fromList(ZipEncoder(password: password).encode(archive));
}
