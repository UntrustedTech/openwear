/// Turns the band's data into Health Connect records (as maps for the
/// Android bridge). Each record has a stable client id, and a version that
/// grows when the data grows, so a resend replaces instead of doubling.
library;

import 'package:openwear/protocol/daily_record.dart';
import 'package:openwear/protocol/sleep.dart';

typedef HcRecord = Map<String, Object>;

int _ms(DateTime t) => t.millisecondsSinceEpoch;

/// Steps, active and total calories per hour, from the minute records.
/// Hours still in progress end at [now]; empty hours are skipped.
List<HcRecord> activityRecords(Iterable<DailyMinute> minutes, DateTime now) {
  final hours = <int, List<int>>{}; // hour (epoch h) → steps, active, total
  for (final m in minutes) {
    if (m.time.isAfter(now)) continue;
    final h = _ms(m.time) ~/ Duration.millisecondsPerHour;
    final sums = hours.putIfAbsent(h, () => [0, 0, 0]);
    sums[0] += m.steps ?? 0;
    sums[1] += m.activeCalories ?? 0;
    sums[2] += m.totalCalories ?? 0;
  }
  final out = <HcRecord>[];
  for (final MapEntry(key: h, value: sums) in hours.entries) {
    final start = h * Duration.millisecondsPerHour;
    final end = start + Duration.millisecondsPerHour;
    final until = end < _ms(now) ? end : _ms(now);
    if (until <= start) continue;
    for (final (kind, value) in [
      ('steps', sums[0]),
      ('activeKcal', sums[1]),
      ('totalKcal', sums[2]),
    ]) {
      if (value <= 0) continue;
      out.add({
        'kind': kind,
        'id': 'openwear-$kind-$h',
        'version': value,
        'start': start,
        'end': until,
        'value': value,
      });
    }
  }
  return out;
}

/// One SpO₂ reading per measured minute (or spot check).
List<HcRecord> spo2Records(Iterable<(DateTime, int)> readings, DateTime now) =>
    [
      for (final (t, v) in readings)
        if (v > 0 && v <= 100 && !t.isAfter(now))
          {
            'kind': 'spo2',
            'id': 'openwear-spo2-${_ms(t) ~/ 60000}',
            'version': 1,
            'start': _ms(t),
            'end': _ms(t),
            'value': v,
          },
    ];

/// The day's resting heart rate, at the end of [day] (or [now] if earlier);
/// [version] should grow each time the value is resent.
HcRecord restingHeartRateRecord(
  DateTime day,
  int bpm,
  DateTime now, {
  required int version,
}) {
  final endOfDay = DateTime(day.year, day.month, day.day, 23, 59);
  final at = endOfDay.isAfter(now) ? now : endOfDay;
  final key = day.year * 10000 + day.month * 100 + day.day;
  return {
    'kind': 'restingHr',
    'id': 'openwear-rhr-$key',
    'version': version,
    'start': _ms(at),
    'end': _ms(at),
    'value': bpm,
  };
}

String _stageName(SleepStage s) => switch (s) {
  SleepStage.deep => 'deep',
  SleepStage.light => 'light',
  SleepStage.rem => 'rem',
  SleepStage.awake => 'awake',
  SleepStage.unknown => 'sleeping',
};

/// A sleep session with its stages; sleep the band did not stage becomes
/// one "sleeping" stage, with time in bed before and after it.
HcRecord sleepRecord(SleepSession s) {
  final bed = s.wentToBed != null && s.wentToBed!.isBefore(s.start)
      ? s.wentToBed!
      : s.start;
  final up = s.leftBed != null && s.leftBed!.isAfter(s.end)
      ? s.leftBed!
      : s.end;
  final stages = <List<Object>>[
    if (bed.isBefore(s.start)) [_ms(bed), _ms(s.start), 'inBed'],
    if (s.hasStages) ...[
      for (final x in s.stages)
        if (x.end.isAfter(x.start))
          [_ms(x.start), _ms(x.end), _stageName(x.stage)],
    ] else if (s.end.isAfter(s.start))
      [_ms(s.start), _ms(s.end), 'sleeping'],
    if (up.isAfter(s.end)) [_ms(s.end), _ms(up), 'inBed'],
  ];
  return {
    'kind': 'sleep',
    'id': 'openwear-sleep-${s.id.hex}',
    // Grows as the band adds to the file, and once more when it finishes.
    'version':
        (_ms(up) ~/ 1000) * 4 + (s.finished ? 2 : 0) + (s.hasStages ? 1 : 0),
    'start': _ms(bed),
    'end': _ms(up),
    'title': s.kind == SleepKind.nap ? 'Nap' : 'Sleep',
    'stages': stages,
  };
}
