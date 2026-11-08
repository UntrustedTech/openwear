/// Request signing / encryption of the Xiaomi health API (docs/protocol/02, "Cloud API signing").
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

const _rc4Drop = 1024;

/// RC4 with the first 1024 keystream bytes dropped; one instance = one continuous stream.
class Rc4 {
  Rc4(List<int> key) {
    for (var i = 0; i < 256; i++) {
      _s[i] = i;
    }
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + _s[i] + key[i % key.length]) & 0xFF;
      final t = _s[i];
      _s[i] = _s[j];
      _s[j] = t;
    }
    crypt(Uint8List(_rc4Drop));
  }

  final _s = Uint8List(256);
  int _i = 0, _j = 0;

  Uint8List crypt(List<int> data) {
    final out = Uint8List(data.length);
    for (var n = 0; n < data.length; n++) {
      _i = (_i + 1) & 0xFF;
      _j = (_j + _s[_i]) & 0xFF;
      final t = _s[_i];
      _s[_i] = _s[_j];
      _s[_j] = t;
      out[n] = data[n] ^ _s[(_s[_i] + _s[_j]) & 0xFF];
    }
    return out;
  }
}

Uint8List _sha1(List<int> d) => SHA1Digest().process(Uint8List.fromList(d));
Uint8List _sha256(List<int> d) => SHA256Digest().process(Uint8List.fromList(d));
Uint8List md5Bytes(List<int> d) => MD5Digest().process(Uint8List.fromList(d));

/// base64(8 random bytes ‖ BE int32 minutes since epoch).
String makeNonce(List<int> random8, DateTime now) {
  final minutes = now.millisecondsSinceEpoch ~/ 60000;
  final m = ByteData(4)..setInt32(0, minutes);
  return base64.encode([...random8, ...m.buffer.asUint8List()]);
}

String signedNonce(String ssecurity, String nonce) => base64.encode(
  _sha256([...base64.decode(ssecurity), ...base64.decode(nonce)]),
);

String _signature(
  String method,
  String path,
  Map<String, String> params,
  String key,
) {
  final keys = params.keys.toList()..sort();
  final parts = [
    method.toUpperCase(),
    path,
    for (final k in keys) '$k=${params[k]}',
    key,
  ];
  return base64.encode(_sha1(utf8.encode(parts.join('&'))));
}

/// The request params Mi Fitness sends for an encrypted-response API call.
Map<String, String> encryptParams(
  String method,
  String path,
  Map<String, String> params,
  String ssecurity,
  String nonce,
) {
  final key = signedNonce(ssecurity, nonce);
  final plain = {
    for (final e in params.entries)
      if (e.key.isNotEmpty && e.value.isNotEmpty) e.key: e.value,
  };
  plain['rc4_hash__'] = _signature(method, path, plain, key);
  final rc4 = Rc4(base64.decode(key));
  final keys = plain.keys.toList()..sort();
  final encrypted = {
    for (final k in keys) k: base64.encode(rc4.crypt(utf8.encode(plain[k]!))),
  };
  return {
    ...encrypted,
    'signature': _signature(method, path, encrypted, key),
    '_nonce': nonce,
  };
}

String decryptResponse(String body, String ssecurity, String nonce) =>
    utf8.decode(
      Rc4(base64.decode(signedNonce(ssecurity, nonce)))
          .crypt(base64.decode(body.trim())),
    );
