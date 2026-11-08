/// Shares the band's readings with Android Health Connect.
///
/// Heart rate is written as one record per minute. The record id is the
/// minute, and its version is the number of samples, so when the band resends
/// a growing file the record is replaced, not duplicated.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:openwear/platform/android_bridge.dart' as bridge;
import 'package:openwear/protocol/health_records.dart';
import 'package:openwear/services/band_log.dart';

enum HealthConnectState {
  unknown,
  unavailable,
  needsUpdate,
  notGranted,

  /// Some kinds are allowed; the rest are listed in [HealthConnectSync.missing].
  partial,
  granted,
}

/// Health Connect write permissions, by the kind names the Android side
/// uses, with how they read in the app.
const healthKinds = {
  'heartRate': 'heart rate',
  'steps': 'steps',
  'activeKcal': 'active calories',
  'totalKcal': 'total calories',
  'spo2': 'SpO₂',
  'restingHr': 'resting heart rate',
  'sleep': 'sleep',
};

class HeartRateBucket {
  const HeartRateBucket(this.minute, this.samples);
  final DateTime minute;
  final List<(DateTime, int)> samples;

  String get id =>
      'openwear-hr-${minute.toUtc().millisecondsSinceEpoch ~/ 60000}';
  int get version => samples.length;

  Map<String, Object> toJson() => {
    'id': id,
    'version': version,
    'samples': [
      for (final (t, bpm) in samples) [t.millisecondsSinceEpoch, bpm],
    ],
  };
}

DateTime minuteOf(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
  t.millisecondsSinceEpoch ~/ 60000 * 60000,
);

/// Every sample of [history] that falls in one of [minutes], grouped per minute.
List<HeartRateBucket> heartRateBuckets(
  SplayTreeMap<DateTime, int> history,
  Iterable<DateTime> minutes,
) {
  final out = <HeartRateBucket>[];
  for (final m in {for (final t in minutes) minuteOf(t)}.toList()..sort()) {
    final end = m.add(const Duration(minutes: 1));
    final samples = [
      for (
        var k = history.firstKeyAfter(
          m.subtract(const Duration(microseconds: 1)),
        );
        k != null && k.isBefore(end);
        k = history.firstKeyAfter(k)
      )
        (k, history[k]!),
    ];
    if (samples.isNotEmpty) out.add(HeartRateBucket(m, samples));
  }
  return out;
}

typedef HealthConnectApi = ({
  Future<String> Function() status,
  Future<bool> Function() request,
  Future<void> Function() openSettings,
  Future<int> Function(List<Map<String, Object>> records) writeHeartRate,
  Future<int> Function(List<Map<String, Object>> records) writeRecords,
});

const HealthConnectApi androidHealthConnect = (
  status: bridge.healthConnectStatus,
  request: bridge.healthConnectRequest,
  openSettings: bridge.healthConnectOpenSettings,
  writeHeartRate: bridge.healthConnectWriteHeartRate,
  writeRecords: bridge.healthConnectWriteRecords,
);

class HealthConnectSync extends ChangeNotifier {
  HealthConnectSync({
    required this.log,
    required this.history,
    this.api = androidHealthConnect,
    this.batchDelay = const Duration(seconds: 30),
  });

  final BandLog log;
  final SplayTreeMap<DateTime, int> history;
  final HealthConnectApi api;
  final Duration batchDelay;

  HealthConnectState state = HealthConnectState.unknown;
  bool enabled = false;
  int written = 0;
  DateTime? lastWrite;
  String? error;

  final _pendingMinutes = <DateTime>{};

  /// Records waiting to be written, by client id (newest wins).
  final _pendingRecords = <String, Map<String, Object>>{};

  /// Version last written per client id, so unchanged data is not resent.
  final _writtenVersions = <String, int>{};

  /// Called when sharing turns on, to queue everything the app has.
  void Function()? onEnabled;
  Timer? _timer;
  StreamSubscription<List<HrSample>>? _sub;

  /// Kinds Health Connect does not let the app write (see [healthKinds]).
  List<String> missing = const [];

  /// [missing] as words, for messages.
  String get missingLabel => missing.map((k) => healthKinds[k] ?? k).join(', ');

  bool get _allowed =>
      state == HealthConnectState.granted ||
      state == HealthConnectState.partial;

  bool get active => enabled && _allowed;

  void listenTo(Stream<List<HrSample>> samples) {
    _sub = samples.listen(_onSamples);
  }

  /// Re-reads which permissions the app holds. When sharing is on and access
  /// came back (granted again in Health Connect), everything is queued again.
  Future<void> refresh() async {
    final wasActive = active;
    final before = missing;
    await _readStatus();
    if (enabled) {
      if (missing.isNotEmpty && !listEquals(before, missing)) {
        log.warn(
          'Health Connect access is off for $missingLabel; that data is not '
          'shared until it is allowed again (Settings → App permissions)',
        );
      }
      final regained = before.any((k) => !missing.contains(k));
      if (active && (!wasActive || regained)) await _start();
    }
    notifyListeners();
  }

  Future<void> _readStatus() async {
    try {
      final status = await api.status();
      if (status.startsWith('missing:')) {
        missing = [
          for (final k in status.substring(8).split(','))
            if (k.isNotEmpty) k,
        ];
        state = missing.isEmpty
            ? HealthConnectState.granted
            : missing.length >= healthKinds.length
            ? HealthConnectState.notGranted
            : HealthConnectState.partial;
        return;
      }
      state = switch (status) {
        'granted' => HealthConnectState.granted,
        'notGranted' => HealthConnectState.notGranted,
        'needsUpdate' => HealthConnectState.needsUpdate,
        _ => HealthConnectState.unavailable,
      };
      missing = switch (state) {
        HealthConnectState.notGranted => healthKinds.keys.toList(),
        _ => const [],
      };
    } on PlatformException catch (e) {
      error = e.message;
      state = HealthConnectState.unavailable;
    } on MissingPluginException {
      state = HealthConnectState.unavailable;
    }
  }

  /// Queues everything the app has, the last day of heart rate included.
  Future<void> _start() async {
    log.app(
      missing.isEmpty
          ? 'Health Connect sharing on'
          : 'Health Connect sharing on (no access to $missingLabel)',
    );
    onEnabled?.call();
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 1));
    _pendingMinutes.addAll(
      history.keys
          .where((t) => t.isAfter(from) && !t.isAfter(now))
          .map(minuteOf),
    );
    await flush();
  }

  /// Asks for any missing access, then turns sharing on and writes today's
  /// data. Android stops showing the request once it has been declined, so
  /// when access is still missing Health Connect's own page is opened.
  Future<void> enable() async {
    await _readStatus();
    if (state == HealthConnectState.notGranted ||
        state == HealthConnectState.partial) {
      try {
        await api.request();
      } on PlatformException catch (e) {
        error = e.message;
      }
      await _readStatus();
      if (missing.isNotEmpty) await _openSettings();
    }
    enabled = _allowed;
    notifyListeners();
    if (enabled) {
      await _start();
    } else {
      log.warn('Health Connect access not granted');
    }
  }

  /// Opens Health Connect on OpenWear's permissions.
  Future<void> _openSettings() async {
    log.app(
      'Opening Health Connect: allow $missingLabel there, then come back',
    );
    try {
      await api.openSettings();
    } on PlatformException catch (e) {
      log.warn('Could not open Health Connect: ${e.message}');
    }
  }

  Future<void> openSettings() => _openSettings();

  void disable() {
    enabled = false;
    _timer?.cancel();
    _pendingMinutes.clear();
    _pendingRecords.clear();
    log.app('Health Connect sharing off');
    notifyListeners();
  }

  void _onSamples(List<HrSample> samples) {
    if (!active) return;
    // Health Connect rejects records that start in the future.
    final now = DateTime.now();
    _pendingMinutes.addAll(
      samples.where((s) => !s.time.isAfter(now)).map((s) => minuteOf(s.time)),
    );
    _timer ??= Timer(batchDelay, () => unawaited(flush()));
  }

  /// Queues steps, calories, SpO₂, resting HR or sleep records (see
  /// health_connect_records.dart); written with the next batch.
  void queue(Iterable<Map<String, Object>> records) {
    if (!active) return;
    for (final r in records) {
      final id = r['id']! as String;
      final version = r['version']! as int;
      if ((_writtenVersions[id] ?? -1) >= version) continue;
      _pendingRecords[id] = r;
    }
    if (_pendingRecords.isNotEmpty) {
      _timer ??= Timer(batchDelay, () => unawaited(flush()));
    }
  }

  /// Writes every pending minute and record now.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (!active) return;
    await _flushRecords();
    if (_pendingMinutes.isEmpty || missing.contains('heartRate')) return;
    final minutes = _pendingMinutes.toList();
    final buckets = heartRateBuckets(history, minutes);
    _pendingMinutes.clear();
    if (buckets.isEmpty) return;
    try {
      final n = await api.writeHeartRate([for (final b in buckets) b.toJson()]);
      written += n;
      lastWrite = DateTime.now();
      error = null;
      final samples = buckets.fold(0, (a, b) => a + b.samples.length);
      log.app('Health Connect: wrote $samples heart-rate samples ($n records)');
    } on PlatformException catch (e) {
      error = e.message;
      log.warn('Health Connect write failed: ${e.message}');
      if (e.code == 'permission') {
        _pendingMinutes.addAll(minutes);
        await refresh();
      }
    }
    notifyListeners();
  }

  /// Health Connect takes at most 1000 records per call.
  static const _maxPerWrite = 500;

  Future<void> _flushRecords() async {
    // Kinds without access stay queued until access comes back.
    final all = [
      for (final r in _pendingRecords.values)
        if (!missing.contains(r['kind'])) r,
    ];
    if (all.isEmpty) return;
    for (final r in all) {
      _pendingRecords.remove(r['id']);
    }
    final kinds = <String, int>{};
    var n = 0;
    var sent = 0;
    try {
      for (var i = 0; i < all.length; i += _maxPerWrite) {
        final chunk = all.sublist(
          i,
          i + _maxPerWrite > all.length ? all.length : i + _maxPerWrite,
        );
        n += await api.writeRecords(chunk);
        sent += chunk.length;
        for (final r in chunk) {
          _writtenVersions[r['id']! as String] = r['version']! as int;
          final k = r['kind']! as String;
          kinds[k] = (kinds[k] ?? 0) + 1;
        }
      }
      written += n;
      lastWrite = DateTime.now();
      error = null;
      log.app(
        'Health Connect: wrote '
        '${kinds.entries.map((e) => '${e.value} ${e.key}').join(', ')}',
      );
    } on PlatformException catch (e) {
      error = e.message;
      log.warn('Health Connect write failed: ${e.message}');
      if (e.code == 'permission') {
        // Keep what was refused so it is written once access is back.
        for (final r in all.skip(sent)) {
          _pendingRecords.putIfAbsent(r['id']! as String, () => r);
        }
        await refresh();
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
