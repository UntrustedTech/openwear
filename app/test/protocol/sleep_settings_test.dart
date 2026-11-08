import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/pb.dart';
import 'package:openwear/protocol/sleep_settings.dart';

/// An HR config like a band's: continuous HR on, 10 min, alert sub-message,
/// a field this app does not know (20), assisted sleep off, breathing on,
/// breathing rate not supported.
final _config = pbEncode([
  const PbVarint(1, 1),
  const PbVarint(2, 10),
  PbBytes(6, pbEncode([const PbVarint(1, 120)])),
  const PbVarint(20, 7),
  PbBytes(5, pbEncode([const PbBool(1, false)])),
  const PbVarint(9, 1),
]);

Command _reply() => Command.of(typeFitness, 10, [PbBytes(8, _config)]);

void main() {
  test('reads which sleep switches the band offers', () {
    final s = parseSleepSettings(_reply())!;
    expect(s.highAccuracy, isFalse);
    expect(s.breathingQuality, isTrue);
    expect(s.breathingRate, isNull);
    expect(s.anySupported, isTrue);
  });

  test('writing a switch keeps every other field as it was', () {
    final s = parseSleepSettings(_reply())!.withHighAccuracy(true);
    final cmd = s.command();
    expect((cmd.type, cmd.subtype), (typeFitness, 11));
    final sent = cmd.body.message(8)!;
    expect(sent.message(5)!.int_(1), 1);
    expect(sent.int_(1), 1);
    expect(sent.int_(2), 10);
    expect(sent.message(6)!.int_(1), 120);
    expect(sent.int_(20), 7);
    expect(sent.int_(9), 1);
  });

  test('breathing switches send 1 for on and 2 for off', () {
    final s = parseSleepSettings(_reply())!.withBreathingQuality(false);
    expect(s.breathingQuality, isFalse);
    expect(PbMessage.decode(s.raw).int_(9), 2);
  });

  test('a switch the band does not offer is never written', () {
    final s = parseSleepSettings(_reply())!;
    expect(s.withBreathingRate(true).raw, s.raw);
  });

  test('a reply without a config is ignored', () {
    expect(parseSleepSettings(const Command(typeFitness, 10)), isNull);
  });
}
