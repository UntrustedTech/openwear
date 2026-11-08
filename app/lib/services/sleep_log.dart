/// Sleep sessions received from the band, and which one is "last night".
library;

import 'dart:typed_data';

import 'package:openwear/protocol/fitness.dart';
import 'package:openwear/protocol/sleep.dart';

/// How far back sleep is kept and shown.
const sleepKeptFor = Duration(days: 8);

/// A sleep that ended this long ago is no longer "last night".
const _lastNightWithin = Duration(hours: 20);

/// Files older than this are confirmed even when the band never marked
/// them finished, so they do not pile up on the band.
const _confirmUnfinishedAfter = Duration(days: 2);

class SleepLog {
  /// Sessions by file id; the band may resend a file as it grows.
  final _sessions = <String, SleepSession>{};

  List<SleepSession> get sessions => List.unmodifiable(
    _sessions.values.toList()..sort((a, b) => a.start.compareTo(b.start)),
  );

  /// Keeps [file] when it is a sleep file; returns the session, or null
  /// when it is not sleep or did not change anything.
  SleepSession? add(Uint8List file, DateTime now) {
    final s = parseSleep(file);
    if (s == null) return null;
    _sessions.removeWhere((_, x) => now.difference(x.end) > sleepKeptFor);
    if (now.difference(s.end) > sleepKeptFor) return null;
    final seen = _sessions[s.id.hex];
    if (seen != null && _sameSession(seen, s)) return null;
    _sessions[s.id.hex] = s;
    return s;
  }

  /// The main sleep that ended most recently, within the past day: the
  /// night file when the band staged one, else the longest segment.
  SleepSession? lastNight(DateTime now) {
    final recent = [
      for (final s in _sessions.values)
        if (s.kind != SleepKind.nap &&
            !s.end.isAfter(now.add(const Duration(minutes: 5))) &&
            now.difference(s.end) <= _lastNightWithin)
          s,
    ];
    if (recent.isEmpty) return null;
    final nights = recent.where((s) => s.kind == SleepKind.night).toList();
    final pool = nights.isNotEmpty ? nights : recent;
    pool.sort((a, b) => b.asleep.compareTo(a.asleep));
    return pool.first;
  }

  /// Naps (and short segments) of the past day, besides [main].
  List<SleepSession> napsSince(DateTime now, SleepSession? main) => [
    for (final s in sessions)
      if (s != main &&
          now.difference(s.end) <= const Duration(hours: 24) &&
          (s.kind == SleepKind.nap || (main == null || !_overlaps(s, main))))
        s,
  ];

  /// Whether file [id] was received and the band has closed it.
  bool isFinished(FitnessId id) => _sessions[id.hex]?.finished ?? false;

  /// Whether the band may drop file [id]: sleep files once finished, or
  /// once old enough that the band will not add to them.
  bool mayConfirm(FitnessId id, DateTime now) {
    final s = _sessions[id.hex];
    if (s == null) return false;
    return s.finished || now.difference(s.end) > _confirmUnfinishedAfter;
  }
}

bool _sameSession(SleepSession a, SleepSession b) =>
    a.end == b.end &&
    a.finished == b.finished &&
    a.stages.length == b.stages.length &&
    a.heartRate.length == b.heartRate.length;

bool _overlaps(SleepSession a, SleepSession b) =>
    a.start.isBefore(b.end) && b.start.isBefore(a.end);
