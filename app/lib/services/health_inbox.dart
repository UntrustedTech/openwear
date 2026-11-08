/// Today's health files as the band sends them, and which ones may be
/// confirmed (8/5) so the band can drop them and stop resending.
library;

import 'dart:typed_data';

import 'package:openwear/protocol/daily_record.dart';
import 'package:openwear/protocol/fitness.dart';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _timeOf(FitnessId id) =>
    DateTime.fromMillisecondsSinceEpoch(id.timestamp * 1000);

class HealthInbox {
  /// Today's minute-record files by id (longest copy).
  final _dayFiles = <String, Uint8List>{};

  /// Start of the newest minute-record file seen; the band still appends
  /// to it, so it is never confirmed.
  int _newestRecordStart = 0;

  int get todayFileCount => _dayFiles.length;

  /// Keeps [file] when it is one of [now]'s minute-record files; true when
  /// that changed what [recordsFor] returns.
  bool add(Uint8List file, DateTime now) {
    if (file.length < idLength) return false;
    final id = FitnessId(file.sublist(0, idLength));
    if (!isDailyRecord(id)) return false;
    if (id.timestamp > _newestRecordStart) _newestRecordStart = id.timestamp;
    _dayFiles.removeWhere(
      (_, f) => !_sameDay(_timeOf(FitnessId(f.sublist(0, idLength))), now),
    );
    if (!_sameDay(_timeOf(id), now)) return false;
    final seen = _dayFiles[id.hex];
    if (seen != null && seen.length >= file.length) return false;
    _dayFiles[id.hex] = file;
    return true;
  }

  /// Every record of [now]'s day, oldest first.
  List<DailyMinute> recordsFor(DateTime now) =>
      recordsOfFiles(_dayFiles.values, now);

  /// Whether the band may drop file [id] once it is saved on the phone.
  /// Files of earlier days are finished; today's report and heart-rate
  /// file keep growing, so only closed minute-record files are confirmed.
  bool mayConfirm(FitnessId id, DateTime now) {
    if (!_sameDay(_timeOf(id), now)) return _timeOf(id).isBefore(now);
    return isDailyRecord(id) && id.timestamp < _newestRecordStart;
  }
}
