/// Talks to OpenWear's own band app (band-app/ in the repo): answers its
/// "is the phone app there?", sends it today's numbers and recent phone
/// notifications, and carries out what it asks for (find phone, sync,
/// weather, quick replies).
///
/// Messages are JSON objects with a type `t`:
/// - band → phone: `hello`, `cmd` {c: findPhone|stopFindPhone|sync|weather},
///   `reply` {k: notification key, x: text}
/// - phone → band: `state` (see [BandAppSnapshot]), `ack` {c, ok, m?}
library;

import 'dart:async';

import 'package:openwear/protocol/band_app_messages.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/services/band_log.dart';

/// OpenWear's band app.
const openWearBandApp = 'org.openwear.band';

/// Most recent notifications kept for the band app.
const _maxNotes = 8;
const _maxNoteText = 160;

/// One phone notification as the band app shows it.
class BandAppNote {
  const BandAppNote({
    required this.key,
    required this.app,
    required this.title,
    required this.text,
    required this.time,
    required this.canReply,
  });
  final String key;
  final String app;
  final String title;
  final String text;
  final DateTime time;
  final bool canReply;

  Map<String, Object?> toJson() => {
    'k': key,
    'a': app,
    'ti': title,
    'tx': text.length > _maxNoteText
        ? '${text.substring(0, _maxNoteText)}…'
        : text,
    'at': time.millisecondsSinceEpoch ~/ 1000,
    'r': canReply,
  };
}

/// Today's numbers for the band app; null fields are unknown.
class BandAppSnapshot {
  const BandAppSnapshot({
    this.steps,
    this.stepGoal,
    this.activeKcal,
    this.kcalGoal,
    this.standHours,
    this.standGoal,
    this.heartRate,
    this.restingHr,
    this.spo2,
    this.sleepMinutes,
    this.sleepStart,
    this.sleepEnd,
    this.battery,
  });
  final int? steps, stepGoal, activeKcal, kcalGoal, standHours, standGoal;
  final int? heartRate, restingHr, spo2, sleepMinutes, battery;
  final DateTime? sleepStart, sleepEnd;

  Map<String, Object?> toJson() => {
    'steps': steps,
    'goal': stepGoal,
    'kcal': activeKcal,
    'kcalGoal': kcalGoal,
    'stand': standHours,
    'standGoal': standGoal,
    'hr': heartRate,
    'rest': restingHr,
    'spo2': spo2,
    'sleep': sleepMinutes,
    'sleepFrom': _hm(sleepStart),
    'sleepTo': _hm(sleepEnd),
    'batt': battery,
  };

  static String? _hm(DateTime? t) => t == null
      ? null
      : '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}';
}

/// What the band app can make the phone do.
class BandAppActions {
  const BandAppActions({
    required this.findPhone,
    required this.sync,
    required this.sendWeather,
    required this.reply,
  });

  /// Rings the phone (true) or stops it (false).
  final Future<void> Function(bool ring) findPhone;
  final Future<void> Function() sync;
  final Future<void> Function() sendWeather;

  /// Answers notification [key] with [text]; false when it can't be answered.
  final Future<bool> Function(String key, String text) reply;
}

class BandAppLink {
  BandAppLink({
    required this.log,
    required this.send,
    required this.snapshot,
    required this.actions,
    this.minInterval = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final BandLog log;
  final Future<void> Function(Command) send;
  final BandAppSnapshot Function() snapshot;
  final BandAppActions actions;

  /// Least time between two pushed states.
  final Duration minInterval;
  final DateTime Function() _clock;

  /// The band app, once it has spoken to us.
  BandAppId? app;
  final _notes = <BandAppNote>[];
  DateTime? _lastPush;
  Timer? _pending;

  List<BandAppNote> get notes => List.unmodifiable(_notes);

  /// Handles [cmd] when it is for our band app; true when it was.
  bool handle(Command cmd) {
    final ask = bandAppStatusAsk(cmd);
    if (ask != null) {
      if (ask.package != openWearBandApp) return false;
      app = ask;
      log.app('Band app asked for the phone → connected');
      unawaited(send(bandAppStatus(ask)));
      return true;
    }
    final msg = bandAppMessage(cmd);
    if (msg == null || msg.app.package != openWearBandApp) return false;
    app = msg.app;
    final json = msg.json;
    if (json == null) {
      log.warn('Band app sent something unreadable');
      return true;
    }
    unawaited(_onMessage(json));
    return true;
  }

  Future<void> _onMessage(Map<String, dynamic> json) async {
    switch (json['t']) {
      case 'hello':
        log.app('Band app opened');
        await pushState(force: true);
      case 'cmd':
        await _run('${json['c']}');
      case 'reply':
        final key = '${json['k'] ?? ''}';
        final text = '${json['x'] ?? ''}'.trim();
        final ok =
            key.isNotEmpty && text.isNotEmpty && await actions.reply(key, text);
        log.app(ok ? 'Band app replied: "$text"' : 'Band app reply failed');
        await _ack('reply', ok, ok ? 'Sent' : 'Could not reply');
      default:
        log.warn('Band app sent an unknown message: ${json['t']}');
    }
  }

  Future<void> _run(String c) async {
    log.app('Band app asked: $c');
    try {
      switch (c) {
        case 'findPhone':
          await actions.findPhone(true);
        case 'stopFindPhone':
          await actions.findPhone(false);
        case 'sync':
          await actions.sync();
          await pushState(force: true);
        case 'weather':
          await actions.sendWeather();
        default:
          await _ack(c, false, 'Unknown');
          return;
      }
      await _ack(c, true);
    } on Exception catch (e) {
      log.warn('Band app request $c failed: $e');
      await _ack(c, false, 'Failed');
    }
  }

  Future<void> _ack(String c, bool ok, [String? message]) =>
      _send({'t': 'ack', 'c': c, 'ok': ok, 'm': ?message});

  /// Sends today's numbers and notifications, at most every [minInterval]
  /// unless [force]d.
  Future<void> pushState({bool force = false}) async {
    if (app == null) return;
    final now = _clock();
    final last = _lastPush;
    if (!force && last != null && now.difference(last) < minInterval) {
      _pending ??= Timer(minInterval - now.difference(last), () {
        _pending = null;
        unawaited(pushState());
      });
      return;
    }
    _pending?.cancel();
    _pending = null;
    _lastPush = now;
    await _send({
      't': 'state',
      'now': now.millisecondsSinceEpoch ~/ 1000,
      ...snapshot().toJson(),
      'notes': [for (final n in _notes) n.toJson()],
    });
  }

  Future<void> _send(Map<String, Object?> json) async {
    final to = app;
    if (to == null) return;
    try {
      await send(phoneToBandApp(to, json));
    } on Exception catch (e) {
      log.warn('Could not reach the band app: $e');
    }
  }

  /// A phone notification arrived.
  void addNote(BandAppNote note) {
    _notes
      ..removeWhere((n) => n.key == note.key)
      ..insert(0, note);
    if (_notes.length > _maxNotes) _notes.removeRange(_maxNotes, _notes.length);
    unawaited(pushState());
  }

  /// A phone notification was dismissed.
  void removeNote(String key) {
    final before = _notes.length;
    _notes.removeWhere((n) => n.key == key);
    if (_notes.length != before) unawaited(pushState());
  }

  /// The band disconnected: the app must ask again.
  void reset() {
    app = null;
    _pending?.cancel();
    _pending = null;
  }
}
