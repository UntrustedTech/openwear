/// Per-connection session auth: verify (1/26) → confirm (1/27).
///
/// Pure protocol logic: each step takes the band's reply and returns the next
/// command, so it can be tested without Bluetooth.
library;

import 'dart:typed_data';

import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/crypto.dart';
import 'package:openwear/protocol/pb.dart';

const _subVerify = 26, _subConfirm = 27;
const _fVerify = 30, _fVerifyRsp = 31, _fConfirm = 32, _fConfirmRsp = 33;
const phoneModel = 'OpenWear';
const appCapability = 25188066; // the value Mi Fitness 3.59.2 sends

class HandshakeException implements Exception {
  const HandshakeException(this.message);
  final String message;
  @override
  String toString() => 'HandshakeException: $message';
}

class SessionKeys {
  const SessionKeys(this.decKey, this.encKey, this.decIv, this.encIv);
  final Uint8List decKey;
  final Uint8List encKey;
  final Uint8List decIv;
  final Uint8List encIv;
}

class SessionAuth {
  SessionAuth(
    this.authKey, {
    this.appDeviceId = '',
    this.oob = '',
    this.region = 'US',
  });

  final List<int> authKey;
  final String appDeviceId;
  final String oob;
  final String region;
  Uint8List _appRandom = Uint8List(0);
  SessionKeys? keys;
  Map<int, int> capabilities = const {};

  Command verify([Uint8List? appRandom]) {
    _appRandom = appRandom ?? randomBytes(16);
    return _auth(_subVerify, _fVerify, [
      PbBytes(1, _appRandom),
      // Cloud-bound (PSK) devices have no app device id; Mi Fitness omits 2 and 3.
      if (appDeviceId.isNotEmpty) ...[
        PbString(2, appDeviceId),
        PbBool(3, oob.isNotEmpty),
      ],
    ]);
  }

  Command onVerifyResponse(Command rsp) {
    final f = _field(rsp, _fVerifyRsp);
    final devRandom = f.bytes(1) ?? Uint8List(0);
    final devSign = f.bytes(2) ?? Uint8List(0);
    final okm = hkdfSha256('miwear-auth', authKey, [
      ..._appRandom,
      ...devRandom,
    ], 64);
    final k = SessionKeys(
      okm.sublist(0, 16),
      okm.sublist(16, 32),
      okm.sublist(32, 36),
      okm.sublist(36, 40),
    );
    keys = k;
    final expected = hmacSha256(k.decKey, [
      ...devRandom,
      ..._appRandom,
      ...oob.codeUnits,
    ]);
    if (!_equal(expected, devSign)) {
      throw const HandshakeException(
        'band session signature mismatch (wrong auth key?)',
      );
    }
    final appSign = hmacSha256(k.encKey, [..._appRandom, ...devRandom]);
    final companion = pbEncode([
      const PbVarint(1, 0),
      const PbFloat(2, 34.0),
      const PbString(3, phoneModel),
      const PbVarint(4, appCapability),
      PbString(5, region),
    ]);
    final nonce = [...k.encIv, 0, 0, 0, 0, 0, 0, 0, 0];
    return _auth(_subConfirm, _fConfirm, [
      PbBytes(1, appSign),
      PbBytes(2, ccmEncrypt(k.encKey, nonce, companion)),
    ]);
  }

  SessionKeys onConfirmResponse(Command rsp) {
    final f = _field(rsp, _fConfirmRsp);
    if (f.int_(1) == 0) {
      throw const HandshakeException('band rejected session confirm');
    }
    capabilities = {
      for (final n in [2, 3, 4]) n: f.int_(n),
    };
    final k = keys;
    if (k == null) throw const HandshakeException('confirm before verify');
    return k;
  }
}

Command _auth(int subtype, int field, List<PbField> fields) =>
    Command.of(typeAuth, subtype, [PbBytes(field, pbEncode(fields))]);

PbMessage _field(Command rsp, int field) {
  final f = rsp.body.message(field);
  if (f == null) {
    final error = rsp.body.int_(3);
    throw HandshakeException(
      'band answered ${rsp.type}/${rsp.subtype} without field $field '
      '(error $error, status ${rsp.status})',
    );
  }
  return f;
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
