import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/profile.dart';

void main() {
  test('profile goes to 8/0 with the Mi Fitness field numbers', () {
    final p = UserProfile(
      heightCm: 180,
      weightKg: 75.5,
      birthday: DateTime(1995, 6, 9),
      sex: Sex.female,
      stepGoal: 10000,
    );
    final cmd = Command.decode(profileCommand(p).encode());
    expect(cmd.isA(8, 0), isTrue);
    final m = cmd.body.message(1)!;
    expect(m.int_(1), 180);
    expect(m.int_(3), 19950609);
    expect(m.int_(4), 2);
    expect(m.int_(7), 10000);
    expect(m.int_(12), 0);
  });

  test('unknown values use defaults and are flagged', () {
    final m = Command.decode(profileCommand(const UserProfile()).encode()).body
        .message(1)!;
    expect(m.int_(1), 170);
    expect(m.int_(3), 19900101);
    expect([m.int_(12), m.int_(13), m.int_(14), m.int_(15)], [1, 1, 1, 1]);
  });

  test('max heart rate is 220 minus age', () {
    final p = UserProfile(birthday: DateTime(2000, 12, 31));
    expect(p.maxHeartRate(now: DateTime(2026, 10, 31)), 220 - 25);
  });

  test('json round trip', () {
    final p = UserProfile(heightCm: 170, birthday: DateTime(1990, 2, 3));
    final back = UserProfile.fromJson(p.toJson());
    expect(back.heightCm, 170);
    expect(back.birthday, DateTime(1990, 2, 3));
    expect(back.stepGoal, 8000);
  });
}
