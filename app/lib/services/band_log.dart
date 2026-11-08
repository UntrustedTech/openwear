/// Live log of everything the band and the app exchange.
library;

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/daily_record.dart';
import 'package:openwear/protocol/describe.dart';
import 'package:openwear/protocol/fitness.dart';
import 'package:openwear/protocol/health_records.dart';
import 'package:openwear/protocol/l1.dart' show channelFitness;
import 'package:openwear/protocol/link_events.dart';

enum LogDirection { fromBand, toBand, app, warning }

@immutable
class LogEntry {
  const LogEntry(
    this.time,
    this.direction,
    this.title, {
    this.summary,
    this.detail,
    this.replaceKey,
  });
  final DateTime time;
  final LogDirection direction;
  final String title;
  final String? summary;
  final String? detail; // decoded payload tree, shown when expanded

  /// A newer entry with the same key replaces this one (e.g. a file the band
  /// resends as it grows), so the log keeps only the latest copy.
  final String? replaceKey;
}

class BandLog extends ChangeNotifier {
  static const capacity = 2000;
  final _entries = ListQueue<LogEntry>();
  bool paused = false;

  /// App version, phone, Android version, band — printed at the top of exports.
  final sessionInfo = <String, String>{};

  /// Newest first.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// How far back a [LogEntry.replaceKey] looks for the copy it replaces.
  static const replaceWindow = 200;

  void add(LogEntry entry) {
    if (paused) return;
    final key = entry.replaceKey;
    if (key != null) {
      final stale = _entries
          .take(replaceWindow)
          .where((e) => e.replaceKey == key)
          .toList();
      stale.forEach(_entries.remove);
    }
    _entries.addFirst(entry);
    while (_entries.length > capacity) {
      _entries.removeLast();
    }
    notifyListeners();
  }

  void app(String message, {String? detail, String? replaceKey}) => add(
    LogEntry(
      DateTime.now(),
      LogDirection.app,
      message,
      detail: detail,
      replaceKey: replaceKey,
    ),
  );
  void warn(String message, {String? detail}) => add(
    LogEntry(DateTime.now(), LogDirection.warning, message, detail: detail),
  );

  /// Logs a failure with its type and the top of the stack, for bug reports.
  void error(String context, Object error, [StackTrace? stack]) {
    final frames = stack?.toString().trim().split('\n').take(12).join('\n');
    warn(
      '$context: $error',
      detail: ['type ${error.runtimeType}', ?frames].join('\n'),
    );
  }

  void togglePause() {
    paused = !paused;
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  void onLinkEvent(LinkEvent event) {
    switch (event) {
      case CommandSent(
        :final command,
        :final encrypted,
        :final seq,
        :final bytes,
      ):
        add(
          _commandEntry(event.time, LogDirection.toBand, command, encrypted, [
            _frame(seq),
            '$bytes B',
          ]),
        );
      case CommandReceived(
        :final command,
        :final encrypted,
        :final seq,
        :final bytes,
        :final latency,
      ):
        add(
          _commandEntry(event.time, LogDirection.fromBand, command, encrypted, [
            _frame(seq),
            '$bytes B',
            latency == null
                ? 'pushed by band'
                : 'reply in ${latency.inMilliseconds} ms',
          ]),
        );
      case ChannelData(
        :final channel,
        :final payload,
        :final outgoing,
        :final seq,
      ):
        final name = channelNames[channel] ?? 'Channel $channel';
        final health = !outgoing && channel == channelFitness
            ? _singlePacketHealthFile(payload)
            : null;
        add(
          LogEntry(
            event.time,
            outgoing ? LogDirection.toBand : LogDirection.fromBand,
            health == null ? '$name data' : 'Health file ${health.id.hex}',
            summary: [
              if (health != null) describeHealthFile(health),
              _frame(seq),
              '${payload.length} bytes',
            ].whereType<String>().join(' · '),
            detail: _hexPreview(payload),
            // The band sends hundreds of minute files at once; keep one line.
            replaceKey: health == null
                ? null
                : isDailyRecord(health.id)
                ? 'health:minute-files'
                : 'health:${health.id.hex}',
          ),
        );
      case LinkStatus(:final message, :final warning, :final detail):
        add(
          LogEntry(
            event.time,
            warning ? LogDirection.warning : LogDirection.app,
            message,
            detail: detail,
          ),
        );
    }
  }

  LogEntry _commandEntry(
    DateTime time,
    LogDirection dir,
    Command c,
    bool encrypted,
    List<String?> meta,
  ) {
    final hidden = c.type == typeAuth;
    final status = c.status == null ? '' : ' · status ${c.status}';
    final transport = [
      ...meta,
      encrypted ? '🔒' : 'plain',
    ].whereType<String>().join(' · ');
    return LogEntry(
      time,
      dir,
      '${c.type}/${c.subtype}  ${commandName(c)}',
      summary:
          [summarize(c), '($transport)'].whereType<String>().join('  ') +
          status,
      detail: hidden
          ? '(auth handshake — hidden, it is derived from your band key)'
          : (c.payload == null || c.payload!.isEmpty
                ? '(no payload)'
                : pbTree(c.payload!)),
    );
  }

  /// Plain-text export (newest last) for sharing a bug report.
  String export() {
    final header = [
      '# OpenWear log, exported ${DateTime.now().toIso8601String()}',
      for (final e in sessionInfo.entries) '# ${e.key}: ${e.value}',
    ].join('\n');
    final body = _entries
        .toList()
        .reversed
        .map((e) {
          final arrow = switch (e.direction) {
            LogDirection.fromBand => 'band → phone',
            LogDirection.toBand => 'phone → band',
            LogDirection.app => 'app',
            LogDirection.warning => 'warning',
          };
          final detail = e.detail == null
              ? ''
              : '\n${e.detail!.split('\n').map((l) => '    $l').join('\n')}';
          return '${e.time.toIso8601String()}  $arrow  ${e.title}  ${e.summary ?? ''}$detail';
        })
        .join('\n');
    return '$header\n$body';
  }
}

String? _frame(int? seq) => seq == null ? null : '#$seq';

String _hexPreview(List<int> b) {
  final shown = b.length > 64 ? b.sublist(0, 64) : b;
  final hex = shown.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');
  return b.length > 64 ? '$hex … (${b.length} bytes)' : hex;
}

/// Decodes a channel-5 file that fits in one packet (the live HR file does);
/// longer files are decoded by the health sync instead.
HealthFile? _singlePacketHealthFile(Uint8List packet) {
  if (packet.length < 4 || packet[0] != 1 || packet[1] != 0) return null;
  try {
    final file = FileAssembler().feed(packet);
    return file == null ? null : parseHealthFile(file);
  } on FormatException {
    return null;
  }
}
