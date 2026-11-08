import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/pb.dart';
import 'package:openwear/protocol/settings.dart';

void main() {
  test("the band's Find phone starts and stops ringing (2/17 mer.5)", () {
    Command from(List<int> bytes) => Command.decode(
      Command(2, 17, pbEncode([PbVarint(5, bytes[0])])).encode(),
    );
    expect(findPhoneAsk(from([0])), isTrue);
    expect(findPhoneAsk(from([1])), isFalse);
    expect(findPhoneAsk(const Command(2, 18)), isNull);
    expect(findPhoneAsk(const Command(2, 17)), isNull, reason: 'no payload');
  });

  test('stopping on the phone tells the band with mer.5 = 1', () {
    final c = Command.decode(findPhoneStopped().encode());
    expect(c.isA(2, 17), isTrue);
    expect(c.body.int_(5, -1), 1);
  });
}
