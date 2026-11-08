// Cloud signing and band bind messages must match the Python prototype byte for byte.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/cloud/signing.dart';
import 'package:openwear/protocol/bind.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/crypto.dart';
import 'package:openwear/protocol/pb.dart';
import 'package:openwear/protocol/session_auth.dart';
import 'package:pointycastle/export.dart';

Uint8List unhex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);
String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List be32(BigInt v) => unhex(v.toRadixString(16).padLeft(64, '0'));

Command authReply(int subtype, int field, List<PbField> fields) =>
    Command.of(typeAuth, subtype, [PbBytes(field, pbEncode(fields))]);

void main() {
  final v = jsonDecode(
    File('test/fixtures/vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  group('cloud signing', () {
    final c = v['cloud'] as Map<String, dynamic>;
    final ssecurity = c['ssecurity'] as String, nonce = c['nonce'] as String;

    test('signed nonce and encrypted params match', () {
      expect(signedNonce(ssecurity, nonce), c['signed_nonce']);
      final params = (c['params'] as Map).cast<String, String>();
      expect(
        encryptParams('POST', '/bind/hello', params, ssecurity, nonce),
        c['encrypted'],
      );
    });

    test('response decrypts with a fresh stream', () {
      expect(
        decryptResponse(c['body'] as String, ssecurity, nonce),
        '{"code":0,"result":{"ret":1}}',
      );
    });
  });

  group('account bind', () {
    final a = v['account_bind'] as Map<String, dynamic>;
    final deviceKey = unhex(a['device_key'] as String);
    final appRandom = unhex(a['app_random'] as String);

    test('band commands match', () {
      final bind = AccountBind(a['user_id'] as String);
      expect(hex(bindInfoRequest(a['user_id'] as String).encode()), a['info']);
      expect(
        hex(
          bind
              .verifyServer(
                List.filled(65, 0x50),
                List.filled(64, 0x53),
                List.filled(16, 0x52),
              )
              .encode(),
        ),
        a['verify'],
      );
      expect(
        hex(bind.confirm(deviceKey, 4321, 'bk-abc', appRandom).encode()),
        a['confirm'],
      );
      expect(hex(bind.bindResult().encode()), a['result']);
    });

    test('band signature is checked and errors are explained', () {
      final bind = AccountBind('1')..confirm(deviceKey, 4321, 'k', appRandom);
      final devRandom = Uint8List(16)..fillRange(0, 16, 7);
      final sign = hmacSha256(deviceKey, [
        ...devRandom,
        ...utf8.encode('004321'),
      ]);
      final ok = authReply(19, 16, [
        PbBytes(1, devRandom),
        PbBytes(2, sign),
        const PbBytes(3, [9, 9]),
      ]);
      expect(bind.onConfirmResponse(ok), [9, 9]);

      final forged = authReply(19, 16, [
        PbBytes(1, devRandom),
        PbBytes(2, Uint8List(32)),
      ]);
      expect(
        () => bind.onConfirmResponse(forged),
        throwsA(isA<HandshakeException>()),
      );
      final cancelled = Command.of(typeAuth, 19, [const PbVarint(3, 6)]);
      expect(
        () => bind.onConfirmResponse(cancelled),
        throwsA(predicate((e) => '$e'.contains('cancelled'))),
      );
    });

    test('bind info parses and reports an already bound band', () {
      final rsp = authReply(17, 12, [
        const PbVarint(1, 1),
        const PbString(2, 'SN1'),
        const PbString(3, '08:16:D5:00:12:34'),
        const PbString(4, 'miwear.watch.n66gl'),
        const PbVarint(5, 3),
      ]);
      final info = parseBindInfo(rsp);
      expect(info.verifyMode, verifyModeAccount);
      expect(info.model, 'miwear.watch.n66gl');
      expect(info.oobMode, 3);
      expect(
        () => parseBindInfo(Command.of(typeAuth, 17, [const PbVarint(3, 1)])),
        throwsA(predicate((e) => '$e'.contains('already bound'))),
      );
    });

    test('local bind device id matches', () {
      expect(
        LocalBind(mac: '08:16:d5:00:12:34', phoneId: 'phone-1').deviceId,
        a['device_id'],
      );
    });
  });

  test('local bind completes against a simulated band', () {
    final domain = ECDomainParameters('secp256r1');
    final rng = FortunaRandom()..seed(KeyParameter(Uint8List(32)));
    final band =
        (ECKeyGenerator()..init(
              ParametersWithRandom(ECKeyGeneratorParameters(domain), rng),
            ))
            .generateKeyPair();
    final bandPub = band.publicKey;

    final bind = LocalBind(mac: 'AA:BB', phoneId: 'p', userId: 'u1');
    final hello = bind.hello().body.message(17)!;
    final appPub = hello.bytes(2)!;
    expect(appPub.length, 64);

    final shared = be32(
      (ECDHBasicAgreement()..init(band.privateKey)).calculateAgreement(
        ECPublicKey(domain.curve.decodePoint([4, ...appPub]), domain),
      ),
    );
    final devRandom = Uint8List(16)..fillRange(0, 16, 3);
    final q = bandPub.Q!;
    final confirm = bind.onHelloResponse(
      authReply(18, 18, [
        PbBytes(1, [
          ...be32(q.x!.toBigInteger()!),
          ...be32(q.y!.toBigInteger()!),
        ]),
        PbBytes(2, devRandom),
        PbBytes(3, hmacSha256(shared, devRandom)),
      ]),
    );
    final c = confirm.body.message(19)!;
    final appRandom = c.bytes(1)!;
    expect(c.bytes(2), hmacSha256(shared, appRandom));

    final okm = hkdfSha256('miwear-bind', shared, [
      ...appRandom,
      ...devRandom,
    ], 56);
    expect(bind.authKey, okm.sublist(40, 56));
    final result = bind.onConfirmResponse(authReply(19, 20, const []));
    final sealed = result.body.message(29)!.bytes(1)!;
    final info = PbMessage.decode(
      ccmDecrypt(
        okm.sublist(16, 32),
        List.generate(12, (i) => 0x10 + i),
        sealed,
        utf8.encode('bind-data'),
      ),
    );
    expect(info.string(1), 'u1');
  });
}
