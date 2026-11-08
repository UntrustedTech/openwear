/// First-time bind of a factory-reset band (docs/protocol/02-pairing-and-auth).
///
/// - Account bind (verifyMode 1, e.g. Smart Band 9): Xiaomi's server vouches for us;
///   the server calls live in cloud/xiaomi_cloud.dart.
/// - Local bind (verifyMode 2): ECDH with the band, no account at all.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:openwear/cloud/signing.dart' show md5Bytes;
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/crypto.dart';
import 'package:openwear/protocol/pb.dart';
import 'package:openwear/protocol/session_auth.dart';
import 'package:pointycastle/export.dart';

const _fError = 3;
const _fBindInfoReq = 11, _fBindInfoRsp = 12;
const _fPskVerify = 13,
    _fPskVerifyRsp = 14,
    _fPskConfirm = 15,
    _fPskConfirmRsp = 16;
const _fHello = 17,
    _fHelloRsp = 18,
    _fConfirm = 19,
    _fConfirmRsp = 20,
    _fResult = 29;
const _subInfo = 17, _subHello = 18, _subConfirm = 19, _subResult = 25;
const verifyModeAccount = 1, verifyModeLocal = 2;
const _errorAlreadyBound = 1;
final _resultNonce = Uint8List.fromList(List.generate(12, (i) => 0x10 + i));

Command _auth(int subtype, int field, List<PbField> fields) =>
    Command.of(typeAuth, subtype, [PbBytes(field, pbEncode(fields))]);

PbMessage _field(Command rsp, int field) {
  final body = rsp.body;
  final error = body.int_(_fError);
  if (error != 0) {
    throw HandshakeException(
      'band returned error $error (step ${rsp.subtype})',
    );
  }
  final f = body.message(field);
  if (f == null) {
    throw HandshakeException(
      'band reply ${rsp.type}/${rsp.subtype} is missing field $field',
    );
  }
  return f;
}

Uint8List _phoneInfo({bool withCapability = false}) => pbEncode([
  const PbVarint(1, 0),
  const PbFloat(2, 34.0),
  const PbString(3, phoneModel),
  if (withCapability) const PbVarint(4, appCapability),
]);

class BindInfo {
  const BindInfo(
    this.verifyMode,
    this.oobMode,
    this.model,
    this.mac,
    this.sn,
    this.did,
    this.deviceRandom,
  );
  final int verifyMode; // 1 = account (PSK), 2 = local
  final int oobMode; // 3 = confirm on the band
  final String model;
  final String mac;
  final String sn;
  final String did;
  final Uint8List deviceRandom;
}

Command bindInfoRequest(String userId) => _auth(_subInfo, _fBindInfoReq, [
  const PbBool(1, false),
  if (userId.isNotEmpty) PbBytes(2, md5Bytes(utf8.encode(userId))),
]);

BindInfo parseBindInfo(Command rsp) {
  if (rsp.body.int_(_fError) == _errorAlreadyBound) {
    throw const HandshakeException(
      'This band is already bound to an account. '
      'Reset it on the band (Settings → System → Reset) and pair again.',
    );
  }
  final f = _field(rsp, _fBindInfoRsp);
  return BindInfo(
    f.int_(1),
    f.int_(5),
    f.string(4),
    f.string(3),
    f.string(2),
    f.string(7),
    f.bytes(6) ?? Uint8List(0),
  );
}

/// Band side of the account (PSK) bind; the app talks to Xiaomi's server between steps.
class AccountBind {
  AccountBind(this.userId);
  final String userId;
  Uint8List _deviceKey = Uint8List(0);
  Uint8List _oob = Uint8List(0);

  /// 1/18: pass the server's hello to the band.
  Command verifyServer(
    List<int> serverPub,
    List<int> serverSign,
    List<int> serverRandom,
  ) => _auth(_subHello, _fPskVerify, [
    PbBytes(1, serverPub),
    PbBytes(2, serverSign),
    PbBytes(3, serverRandom),
  ]);

  /// The band's public key and signature, for the server's bind/ecdh.
  (Uint8List, Uint8List) onVerifyServerResponse(Command rsp) {
    final f = _field(rsp, _fPskVerifyRsp);
    return (f.bytes(1) ?? Uint8List(0), f.bytes(2) ?? Uint8List(0));
  }

  /// 1/19: the band then asks the user to confirm.
  Command confirm(
    Uint8List deviceKey,
    int oobCode,
    String bindKey, [
    Uint8List? appRandom,
  ]) {
    _deviceKey = deviceKey;
    _oob = Uint8List.fromList(utf8.encode(oobCode.toString().padLeft(6, '0')));
    final random = appRandom ?? randomBytes(16);
    return _auth(_subConfirm, _fPskConfirm, [
      PbBytes(1, random),
      PbBytes(2, hmacSha256(deviceKey, [...random, ..._oob])),
      PbBytes(3, utf8.encode(bindKey)),
    ]);
  }

  /// Checks the band's signature; returns its bind signature for the server's bind/bind.
  Uint8List onConfirmResponse(Command rsp) {
    final code = rsp.body.int_(_fError);
    if (code == 6) {
      throw const HandshakeException('Pairing was cancelled on the band.');
    }
    if (code == 7) {
      throw const HandshakeException('The band rejected the app signature.');
    }
    final f = _field(rsp, _fPskConfirmRsp);
    final devRandom = f.bytes(1) ?? Uint8List(0);
    final expected = hmacSha256(_deviceKey, [...devRandom, ..._oob]);
    if (!_same(expected, f.bytes(2) ?? Uint8List(0))) {
      throw const HandshakeException(
        'Band signature check failed (wrong device key).',
      );
    }
    return f.bytes(3) ?? Uint8List(0);
  }

  /// 1/25: tells the band which account owns it.
  Command bindResult() {
    final info = pbEncode([
      PbString(1, userId),
      PbBytes(2, _phoneInfo(withCapability: true)),
    ]);
    final sealed = ccmEncrypt(
      _deviceKey,
      _resultNonce,
      info,
      utf8.encode('bind-data'),
    );
    return _auth(_subResult, _fResult, [PbBytes(1, sealed)]);
  }

  void onResultResponse(Command rsp) {
    final code = rsp.body.int_(_fError);
    if (code != 0) {
      throw HandshakeException(
        'The band rejected the bind result (code $code).',
      );
    }
  }
}

/// No-account bind (verifyMode 2): ECDH with the band; yields the session auth key.
class LocalBind {
  LocalBind({
    this.userId = '',
    required String mac,
    required String phoneId,
    String oob = '',
  }) : _oob = Uint8List.fromList(utf8.encode(oob)),
       deviceId = _hexOf(
         md5Bytes(
           utf8.encode(
             '$phoneId${mac.toUpperCase()}${userId.isEmpty ? 'None' : userId}',
           ),
         ),
       );

  final String userId;
  final String deviceId;
  final Uint8List _oob;
  final _domain = ECDomainParameters('secp256r1');
  late final AsymmetricKeyPair<ECPublicKey, ECPrivateKey> _keys = _generate();
  Uint8List _shared = Uint8List(0), _bindKey = Uint8List(0);
  Uint8List authKey = Uint8List(0);

  AsymmetricKeyPair<ECPublicKey, ECPrivateKey> _generate() {
    final rng = FortunaRandom()..seed(KeyParameter(randomBytes(32)));
    final gen = ECKeyGenerator()
      ..init(ParametersWithRandom(ECKeyGeneratorParameters(_domain), rng));
    final pair = gen.generateKeyPair();
    return AsymmetricKeyPair(pair.publicKey, pair.privateKey);
  }

  Command hello() {
    final q = _keys.publicKey.Q!;
    final raw = [
      ..._be32(q.x!.toBigInteger()!),
      ..._be32(q.y!.toBigInteger()!),
    ];
    return _auth(_subHello, _fHello, [PbString(1, deviceId), PbBytes(2, raw)]);
  }

  Command onHelloResponse(Command rsp, [Uint8List? appRandom]) {
    final f = _field(rsp, _fHelloRsp);
    final devPub = f.bytes(1) ?? Uint8List(0);
    final devRandom = f.bytes(2) ?? Uint8List(0);
    if (devPub.length != 64) {
      throw const HandshakeException('band public key has the wrong size');
    }
    final point = _domain.curve.decodePoint([4, ...devPub]);
    final agreement = ECDHBasicAgreement()..init(_keys.privateKey);
    _shared = _be32(agreement.calculateAgreement(ECPublicKey(point, _domain)));
    if (!_same(
      hmacSha256(_shared, [...devRandom, ..._oob]),
      f.bytes(3) ?? Uint8List(0),
    )) {
      throw const HandshakeException(
        'Band signature check failed (wrong code?)',
      );
    }
    final random = appRandom ?? randomBytes(16);
    final okm = hkdfSha256('miwear-bind', _shared, [
      ...random,
      ...devRandom,
    ], 56);
    _bindKey = okm.sublist(16, 32);
    authKey = okm.sublist(40, 56);
    return _auth(_subConfirm, _fConfirm, [
      PbBytes(1, random),
      PbBytes(2, hmacSha256(_shared, [...random, ..._oob])),
    ]);
  }

  Command onConfirmResponse(Command rsp) {
    _field(rsp, _fConfirmRsp);
    final info = pbEncode([PbString(1, userId), PbBytes(2, _phoneInfo())]);
    return _auth(_subResult, _fResult, [
      PbBytes(
        1,
        ccmEncrypt(_bindKey, _resultNonce, info, utf8.encode('bind-data')),
      ),
    ]);
  }

  void onResultResponse(Command rsp) {
    final code = rsp.body.int_(_fError);
    if (code != 0) {
      throw HandshakeException(
        'The band rejected the bind result (code $code).',
      );
    }
  }
}

Uint8List _be32(BigInt v) {
  final out = Uint8List(32);
  var x = v;
  for (var i = 31; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xFF)).toInt();
    x = x >> 8;
  }
  return out;
}

String _hexOf(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}
