/// Human-readable names and summaries for the live log.
library;

import 'dart:convert';

import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/device.dart';
import 'package:openwear/protocol/fitness.dart';
import 'package:openwear/protocol/music.dart';
import 'package:openwear/protocol/pb.dart';
import 'package:openwear/protocol/settings.dart';

const Map<int, String> familyNames = {
  1: 'Auth', 2: 'System', 4: 'Watch face', 5: 'Mi Pay', 7: 'Notifications', //
  8: 'Health', 9: 'Weather', 10: 'Weather', 11: 'Alarms', 12: 'Calendar',
  13: 'Workout',
  17: 'Alarms & reminders',
  18: 'Music',
  20: 'Apps',
  22: 'File transfer',
};

/// Names of (type, subtype) pairs seen in Mi Fitness and on the Band 9.
const Map<(int, int), String> commandNames = {
  (1, 17): 'Bind info',
  (1, 18): 'Bind hello',
  (1, 19): 'Bind confirm',
  (1, 25): 'Bind result',
  (1, 26): 'Session verify', (1, 27): 'Session confirm', //
  (2, 1): 'Battery',
  (2, 2): 'Device info',
  (2, 3): 'Set time',
  (2, 18): 'Find band',
  (2, 23): 'Do Not Disturb',
  (2, 24): 'Raise-to-wake settings', (2, 25): 'Set raise-to-wake',
  (2, 42): 'Wear mode', //
  (4, 0): 'List faces',
  (4, 1): 'Set face',
  (4, 2): 'Delete face',
  (4, 4): 'Install face',
  (4, 7): 'Current face', //
  (7, 0): 'Notification',
  (7, 1): 'Remove notification',
  (7, 2): 'End call (pressed on band)',
  (7, 5): 'Mute ringer (pressed on band)',
  (7, 8): 'Open on phone',
  (7, 13): 'Quick reply',
  (7, 15): 'Prepare app icon', (7, 16): 'Band asks for app icon', //
  (8, 1): 'Today\'s health files',
  (8, 2): 'Older health files',
  (8, 3): 'Request files',
  (8, 4): 'Request file',
  (8, 5): 'Confirm file saved',
  (8, 45): 'Start live heart rate',
  (8, 46): 'Stop live heart rate', (8, 47): 'Live stats', //
  (10, 0): 'Weather now', (10, 1): 'Daily forecast', //
  (10, 2): 'Hourly forecast', (10, 3): 'Band asks for weather', //
  (18, 0): 'Band asks for music info', (18, 1): 'Music player state', //
  (22, 0): 'Prepare file upload', (22, 1): 'File upload control',
};

const Map<int, String> channelNames = {2: 'File upload', 5: 'Health file'};

String commandName(Command c) =>
    commandNames[(c.type, c.subtype)] ??
    '${familyNames[c.type] ?? 'Type ${c.type}'} ${c.subtype}';

/// One-line meaning of payloads we understand, or null.
String? summarize(Command c) {
  if (c.type == typeAuth) return null;
  if (c.isA(typeSystem, 1)) {
    final p = batteryPercent(c);
    return p == null ? null : 'battery $p%';
  }
  final bpm = realtimeHeartRate(c);
  if (bpm != null) {
    return bpm == 0 ? 'heart rate: no reading yet' : 'heart rate $bpm bpm';
  }
  final icon = iconRequestPackage(c);
  if (icon != null) return icon;
  if (c.isA(typeFace, 0)) return '${parseFaces(c).length} faces';
  if (c.isA(typeFitness, 1) || c.isA(typeFitness, 2)) {
    return '${idsFromResponse(c).length} file(s)';
  }
  final music = _musicSummary(c);
  if (music != null) return music;
  if (c.isA(typeSystem, 23)) {
    final dnd = dndMode(c);
    if (dnd != null) return 'DND ${dnd.name}';
  }
  if (c.isA(typeSystem, 18)) {
    return c.body.int_(5) == 1 ? 'stop' : 'start ringing';
  }
  final wake = c.isA(typeSystem, 24) || c.isA(typeSystem, 25)
      ? parseRaiseToWake(c)
      : null;
  if (wake != null) {
    return 'raise to wake ${wake.mode.name} ${wake.start}–${wake.end}';
  }
  if (c.isA(typeSystem, 42)) {
    final mode = c.body.message(35)?.message(3)?.int_(1);
    if (mode != null) return 'wear mode $mode';
  }
  if (c.isA(typeNotify, 0)) {
    final item = c.body.message(3)?.message(1);
    if (item != null) return '${item.string(2)}: ${item.string(3)}';
  }
  return null;
}

String? _musicSummary(Command c) {
  if (c.isA(typeMusic, 1)) {
    final p = c.body.message(1);
    if (p == null) return null;
    final state = PlayerState.fromCode(p.int_(1)).name;
    final title = p.string(4);
    return title.isEmpty ? state : '$state: $title';
  }
  final control = musicControl(c);
  if (control != null) {
    final (kind, volume) = control;
    return kind == MusicControl.volume ? 'volume $volume%' : kind.name;
  }
  return null;
}

/// Indented tree of a protobuf payload (best effort; strings shown quoted).
String pbTree(List<int> bytes, {int depth = 0, int maxDepth = 6}) {
  final PbMessage msg;
  try {
    msg = PbMessage.decode(bytes);
  } on FormatException {
    return '${'  ' * depth}${_hex(bytes)}';
  }
  final lines = <String>[];
  final pad = '  ' * depth;
  for (final entry in msg.fields.entries) {
    for (final value in entry.value) {
      if (value is int) {
        lines.add('$pad${entry.key}: $value');
        continue;
      }
      final b = value as List<int>;
      final text = _printable(b);
      if (text == null && depth < maxDepth && _looksNested(b)) {
        lines.add('$pad${entry.key} {');
        lines.add(pbTree(b, depth: depth + 1, maxDepth: maxDepth));
        lines.add('$pad}');
      } else {
        lines.add('$pad${entry.key}: ${text ?? _hex(b)}');
      }
    }
  }
  return lines.join('\n');
}

bool _looksNested(List<int> b) {
  if (b.isEmpty) return false;
  try {
    return PbMessage.decode(b).fields.isNotEmpty;
  } on FormatException {
    return false;
  }
}

String? _printable(List<int> b) {
  try {
    final s = utf8.decode(b);
    const whitespace = {0x09, 0x0a, 0x0d};
    if (s.runes.every(
      (r) => (r >= 0x20 && r != 0x7f) || whitespace.contains(r),
    )) {
      final shown = s
          .replaceAll('\\', r'\\')
          .replaceAll('\n', r'\n')
          .replaceAll('\r', r'\r')
          .replaceAll('\t', r'\t');
      return "'$shown'";
    }
  } on FormatException {
    return null;
  }
  return null;
}

String _hex(List<int> b) {
  final shown = b.length > 48 ? b.sublist(0, 48) : b;
  final s = shown.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return b.length > 48 ? '0x$s… (${b.length} bytes)' : '0x$s';
}
