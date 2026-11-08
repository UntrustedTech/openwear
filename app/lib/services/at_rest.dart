/// Encryption for health data OpenWear keeps on the phone.
///
/// Files are sealed with AES-256-GCM under a random key that lives in
/// Android's Keystore-backed secure storage, never on disk next to the data.
/// Layout: `OWE1` magic, 12-byte nonce, ciphertext with 16-byte tag.
/// Files written before encryption existed have no magic; they are read as
/// they are and re-sealed by the caller.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openwear/protocol/crypto.dart';
import 'package:pointycastle/export.dart';

const _magic = [0x4F, 0x57, 0x45, 0x31]; // "OWE1"
const _nonceBytes = 12, _tagBits = 128, _keyBytes = 32;
const _kAtRestKey = 'at_rest_key_v1';

/// Whether [data] was written by [AtRest.seal].
bool isSealed(List<int> data) =>
    data.length >= _magic.length + _nonceBytes + _tagBits ~/ 8 &&
    data[0] == _magic[0] &&
    data[1] == _magic[1] &&
    data[2] == _magic[2] &&
    data[3] == _magic[3];

Uint8List _gcm(bool encrypt, Uint8List key, Uint8List nonce, Uint8List data) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      encrypt,
      AEADParameters(KeyParameter(key), _tagBits, nonce, Uint8List(0)),
    );
  return cipher.process(data);
}

/// Seals [plain] under [key] (32 bytes) with a fresh random nonce.
Uint8List sealWithKey(Uint8List key, List<int> plain) {
  final nonce = randomBytes(_nonceBytes);
  final body = _gcm(true, key, nonce, Uint8List.fromList(plain));
  return Uint8List.fromList([..._magic, ...nonce, ...body]);
}

/// Opens data from [sealWithKey]. A wrong key or a modified file is a
/// [FormatException].
Uint8List openWithKey(Uint8List key, List<int> sealed) {
  if (!isSealed(sealed)) throw const FormatException('not an OpenWear file');
  final bytes = Uint8List.fromList(sealed);
  final nonce = Uint8List.sublistView(bytes, 4, 4 + _nonceBytes);
  final body = Uint8List.sublistView(bytes, 4 + _nonceBytes);
  try {
    return _gcm(false, key, nonce, body);
    // pointycastle reports a failed tag as InvalidCipherTextException.
  } on InvalidCipherTextException {
    throw const FormatException('file failed its integrity check');
  }
}

/// The app's at-rest key, created on first use.
class AtRest {
  AtRest({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  Future<Uint8List>? _key;

  Future<Uint8List> _loadKey() async {
    final stored = await _storage.read(key: _kAtRestKey);
    if (stored != null) {
      final key = base64.decode(stored);
      if (key.length == _keyBytes) return key;
    }
    final key = randomBytes(_keyBytes);
    await _storage.write(key: _kAtRestKey, value: base64.encode(key));
    return key;
  }

  Future<Uint8List> get key => _key ??= _loadKey().catchError((Object e) {
    _key = null; // try again next time
    throw e;
  });

  Future<Uint8List> seal(List<int> plain) async =>
      sealWithKey(await key, plain);

  /// Plain bytes of [data]; legacy unsealed files come back unchanged.
  Future<Uint8List> open(List<int> data) async =>
      isSealed(data) ? openWithKey(await key, data) : Uint8List.fromList(data);
}
