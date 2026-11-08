/// Crypto primitives of the Xiaomi Wear protocol (docs/protocol/02-pairing-and-auth).
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

const ccmTagBytes = 4;

final _random = Random.secure();

Uint8List randomBytes(int n) =>
    Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

Uint8List hmacSha256(List<int> key, List<int> message) {
  final mac = HMac(SHA256Digest(), 64)
    ..init(KeyParameter(Uint8List.fromList(key)));
  return mac.process(Uint8List.fromList(message));
}

Uint8List hkdfSha256(String info, List<int> ikm, List<int> salt, int length) {
  final hkdf = HKDFKeyDerivator(SHA256Digest())
    ..init(
      HkdfParameters(
        Uint8List.fromList(ikm),
        length,
        Uint8List.fromList(salt),
        Uint8List.fromList(info.codeUnits),
      ),
    );
  return hkdf.process(Uint8List(0));
}

Uint8List _ccm(
  bool encrypt,
  List<int> key,
  List<int> nonce,
  List<int> data,
  List<int>? aad,
) {
  final ccm = CCMBlockCipher(AESEngine())
    ..init(
      encrypt,
      AEADParameters(
        KeyParameter(Uint8List.fromList(key)),
        ccmTagBytes * 8,
        Uint8List.fromList(nonce),
        Uint8List.fromList(aad ?? const []),
      ),
    );
  return ccm.process(Uint8List.fromList(data));
}

Uint8List ccmEncrypt(
  List<int> key,
  List<int> nonce,
  List<int> plain, [
  List<int>? aad,
]) => _ccm(true, key, nonce, plain, aad);

Uint8List ccmDecrypt(
  List<int> key,
  List<int> nonce,
  List<int> sealed, [
  List<int>? aad,
]) => _ccm(false, key, nonce, sealed, aad);

/// V2 link cipher: AES-128-CTR with the key also used as the IV (encrypt == decrypt).
Uint8List aesCtr(List<int> key, List<int> data) {
  final k = Uint8List.fromList(key);
  final cipher = CTRStreamCipher(AESEngine())
    ..init(true, ParametersWithIV(KeyParameter(k), k));
  return cipher.process(Uint8List.fromList(data));
}
