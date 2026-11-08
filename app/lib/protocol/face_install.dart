/// Installing a watch face: 4/4 announces it, the binary goes over the mass
/// channel as file kind (1, 0), and the band reports the result with 4/5.
library;

import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/pb.dart';

const faceFile = (1, 0);
const _subPreInstall = 4, subInstallResult = 5;

class FaceInstallException implements Exception {
  const FaceInstallException(this.message);
  final String message;
  @override
  String toString() => message;
}

Command preInstallFace(String id, int size, {int version = 1}) =>
    Command.of(typeFace, _subPreInstall, [
      PbBytes(
        6,
        pbEncode([
          PbString(1, id),
          PbVarint(2, size),
          PbVarint(3, version),
          PbBytes(5, pbEncode(const [PbString(1, ''), PbString(2, '')])),
        ]),
      ),
    ]);

/// Throws when the band will not take the face.
void checkPreInstall(Command rsp) {
  final body = rsp.body;
  if (body.has(5)) {
    final code = body.int_(5);
    if (code != 0) throw FaceInstallException('Band refused the face ($code)');
    return;
  }
  final reply = body.message(9);
  if (reply == null) {
    throw FaceInstallException(
      'Band gave no answer to the install request (status ${rsp.status})',
    );
  }
  if (reply.int_(5) != 0) {
    throw const FaceInstallException(
      'Not enough space on the band. Remove a face and try again.',
    );
  }
  final status = reply.int_(2);
  if (status != 0) {
    throw FaceInstallException('Band refused the face ($status)');
  }
}

/// (face id, success) from a 4/5 result, or null for anything else.
(String, bool)? installResult(Command cmd) {
  if (!cmd.isA(typeFace, subInstallResult)) return null;
  final r = cmd.body.message(7);
  if (r == null) return null;
  final code = r.int_(2);
  return (r.string(1), code == 2 || code == 3);
}
