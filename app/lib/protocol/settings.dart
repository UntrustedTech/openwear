/// Band settings recovered from Mi Fitness 3.59.2 (docs/protocol/03-commands.md):
/// find band (2/18), Do Not Disturb (2/23) and raise-to-wake (2/24 get, 2/25 set).
library;

import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/pb.dart';

const _typeSystem = 2;
const _subFind = 18, _subDnd = 23, _subWakeGet = 24, _subWakeSet = 25;
const _fFind = 5, _fDnd = 11, _fWake = 7;

const _subFindPhone = 17;

/// The band's own Find phone (2/17, `mer.5`: 0 start ringing, else stop),
/// as Mi Fitness's BleDataHandler reads it. True to ring, false to stop,
/// null for other commands.
bool? findPhoneAsk(Command cmd) {
  if (!cmd.isA(_typeSystem, _subFindPhone) || cmd.payload == null) return null;
  return cmd.body.int_(_fFind) == 0;
}

/// Tells the band the phone stopped ringing (Mi Fitness sendStopEvent2Device).
Command findPhoneStopped() =>
    Command.of(_typeSystem, _subFindPhone, [const PbVarint(_fFind, 1)]);

/// Rings and vibrates the band until stopped (or the user dismisses it there).
Command findBand({bool stop = false}) =>
    Command.of(_typeSystem, _subFind, [PbVarint(_fFind, stop ? 1 : 0)]);

/// Schedule modes shared by DND and raise-to-wake.
enum ScheduleMode {
  always(0),
  scheduled(1),
  off(2);

  const ScheduleMode(this.code);
  final int code;

  static ScheduleMode fromCode(int code) =>
      values.firstWhere((m) => m.code == code, orElse: () => off);
}

/// Turns Do Not Disturb on (all day) or off now; Mi Fitness sends the same
/// message to mirror the phone's DND onto the band.
Command dndCommand({required bool on}) => Command.of(_typeSystem, _subDnd, [
  PbBytes(
    _fDnd,
    pbEncode([
      PbVarint(1, on ? ScheduleMode.always.code : ScheduleMode.off.code),
    ]),
  ),
]);

/// DND mode from a 2/23 the band sends when it changes; null for other commands.
ScheduleMode? dndMode(Command cmd) {
  if (!cmd.isA(_typeSystem, _subDnd)) return null;
  final m = cmd.body.message(_fDnd);
  return m == null ? null : ScheduleMode.fromCode(m.int_(1));
}

class TimeOfDay24 {
  const TimeOfDay24(this.hour, this.minute);
  final int hour;
  final int minute;

  List<int> encode() => pbEncode([PbVarint(1, hour), PbVarint(2, minute)]);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is TimeOfDay24 && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}

class RaiseToWake {
  const RaiseToWake({
    required this.mode,
    this.start = const TimeOfDay24(8, 0),
    this.end = const TimeOfDay24(22, 0),
    this.sensitivity = 0,
  });

  final ScheduleMode mode;
  final TimeOfDay24 start;
  final TimeOfDay24 end;
  final int sensitivity;

  bool get enabled => mode != ScheduleMode.off;

  RaiseToWake copyWith({ScheduleMode? mode}) => RaiseToWake(
    mode: mode ?? this.mode,
    start: start,
    end: end,
    sensitivity: sensitivity,
  );
}

Command raiseToWakeRequest() => const Command(_typeSystem, _subWakeGet);

/// Reply to [raiseToWakeRequest]; defaults match Mi Fitness (08:00–22:00).
RaiseToWake? parseRaiseToWake(Command cmd) {
  final m = cmd.body.message(_fWake);
  if (m == null) return null;
  TimeOfDay24 time(int field, TimeOfDay24 fallback) {
    final t = m.message(field);
    return t == null ? fallback : TimeOfDay24(t.int_(1), t.int_(2));
  }

  return RaiseToWake(
    mode: ScheduleMode.fromCode(m.int_(1)),
    start: time(2, const TimeOfDay24(8, 0)),
    end: time(3, const TimeOfDay24(22, 0)),
    sensitivity: m.int_(4),
  );
}

Command raiseToWakeCommand(RaiseToWake w) =>
    Command.of(_typeSystem, _subWakeSet, [
      PbBytes(
        _fWake,
        pbEncode([
          PbVarint(1, w.mode.code),
          PbBytes(2, w.start.encode()),
          PbBytes(3, w.end.encode()),
          PbVarint(4, w.sensitivity),
        ]),
      ),
    ]);
