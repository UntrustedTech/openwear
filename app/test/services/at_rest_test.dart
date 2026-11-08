import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/services/at_rest.dart';

void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  final plain = Uint8List.fromList(List.generate(300, (i) => i * 7 & 0xFF));

  test('sealed data hides the plain bytes and opens again', () {
    final sealed = sealWithKey(key, plain);
    expect(isSealed(sealed), isTrue);
    expect(sealed.length, 4 + 12 + plain.length + 16);
    expect(sealed.sublist(16, 16 + plain.length), isNot(plain));
    expect(openWithKey(key, sealed), plain);
  });

  test('each seal uses a fresh nonce', () {
    expect(sealWithKey(key, plain), isNot(sealWithKey(key, plain)));
  });

  test('a changed byte or another key fails the check', () {
    final sealed = sealWithKey(key, plain);
    final tampered = Uint8List.fromList(sealed)..[40] ^= 1;
    expect(() => openWithKey(key, tampered), throwsFormatException);
    final other = Uint8List.fromList(List.generate(32, (i) => 255 - i));
    expect(() => openWithKey(other, sealed), throwsFormatException);
  });

  group('AtRest', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('creates one key and keeps using it', () async {
      final a = AtRest();
      final sealed = await a.seal(plain);
      expect(await AtRest().open(sealed), plain, reason: 'key was stored');
      expect(await a.key, await AtRest().key);
    });

    test('files saved before encryption are read as they are', () async {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
      expect(await AtRest().open(png), png);
    });
  });
}
