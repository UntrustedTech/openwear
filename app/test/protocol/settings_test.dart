import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/pb.dart';
import 'package:openwear/protocol/settings.dart';

void main() {
  test('find band starts and stops with field 5', () {
    final start = Command.decode(findBand().encode());
    expect((start.type, start.subtype), (2, 18));
    expect(start.body.int_(5, -1), 0);
    expect(Command.decode(findBand(stop: true).encode()).body.int_(5), 1);
  });

  test('DND on is mode 0, off is mode 2, as the band reports it', () {
    final on = Command.decode(dndCommand(on: true).encode());
    expect((on.type, on.subtype), (2, 23));
    expect(on.body.message(11)!.int_(1, -1), 0);
    expect(dndMode(on), ScheduleMode.always);
    // What the Band 9 sent on connect: 2/23 {11: {1: 2}}
    final report = Command.of(2, 23, [
      PbBytes(11, pbEncode([PbVarint(1, 2)])),
    ]);
    expect(dndMode(report), ScheduleMode.off);
    expect(dndMode(const Command(2, 1)), isNull);
  });

  test('raise-to-wake round-trips mode, times and sensitivity', () {
    const w = RaiseToWake(
      mode: ScheduleMode.scheduled,
      start: TimeOfDay24(7, 30),
      end: TimeOfDay24(23, 15),
      sensitivity: 1,
    );
    final cmd = Command.decode(raiseToWakeCommand(w).encode());
    expect((cmd.type, cmd.subtype), (2, 25));
    final back = parseRaiseToWake(cmd)!;
    expect(back.mode, ScheduleMode.scheduled);
    expect((back.start, back.end), (w.start, w.end));
    expect(back.sensitivity, 1);
    expect(back.enabled, isTrue);
    expect(back.copyWith(mode: ScheduleMode.off).enabled, isFalse);
  });

  test('missing times fall back to the Mi Fitness defaults', () {
    final reply = Command.of(2, 24, [
      PbBytes(7, pbEncode([PbVarint(1, 0)])),
    ]);
    final w = parseRaiseToWake(reply)!;
    expect(w.mode, ScheduleMode.always);
    expect('${w.start}–${w.end}', '08:00–22:00');
  });
}
