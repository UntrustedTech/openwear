import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/face_install.dart';
import 'package:openwear/protocol/pb.dart';

Command reply(List<PbField> fields, {int sub = 4}) =>
    Command.decode(Command.of(typeFace, sub, fields).encode());

void main() {
  test('pre-install carries id, size, version and an empty licence', () {
    final cmd = preInstallFace('960000001', 12345);
    expect(cmd.type, typeFace);
    expect(cmd.subtype, 4);
    final info = cmd.body.message(6)!;
    expect(info.string(1), '960000001');
    expect(info.int_(2), 12345);
    expect(info.int_(3), 1);
    expect(info.message(5)!.string(1), '');
  });

  test('accepts a plain zero code and an ok status', () {
    checkPreInstall(reply([const PbVarint(5, 0)]));
    checkPreInstall(
      reply([
        PbBytes(
          9,
          pbEncode([
            const PbString(1, 'x'),
            const PbVarint(2, 0),
            const PbVarint(4, 4096),
          ]),
        ),
      ]),
    );
  });

  test('explains a full band and other refusals', () {
    expect(
      () => checkPreInstall(
        reply([
          PbBytes(9, pbEncode([const PbVarint(2, 3), const PbBool(5, true)])),
        ]),
      ),
      throwsA(
        isA<FaceInstallException>().having(
          (e) => e.message,
          'message',
          contains('space'),
        ),
      ),
    );
    expect(
      () => checkPreInstall(reply([const PbVarint(5, 7)])),
      throwsA(isA<FaceInstallException>()),
    );
    expect(
      () => checkPreInstall(reply(const [])),
      throwsA(isA<FaceInstallException>()),
    );
  });

  test('reads the install result for codes 2 and 3 as success', () {
    Command result(int code) => reply([
      PbBytes(7, pbEncode([const PbString(1, '960000001'), PbVarint(2, code)])),
    ], sub: 5);
    expect(installResult(result(2)), ('960000001', true));
    expect(installResult(result(3)), ('960000001', true));
    expect(installResult(result(1)), ('960000001', false));
    expect(installResult(reply(const [])), isNull);
  });
}
