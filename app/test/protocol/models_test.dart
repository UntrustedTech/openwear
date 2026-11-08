import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/faces/catalog.dart';
import 'package:openwear/protocol/models.dart';
import 'package:openwear/ui/pair_screen.dart' show modelSupportLine;

void main() {
  group('wearModelFor', () {
    test('Bluetooth names pick the most specific model', () {
      expect(
        wearModelFor(bluetoothName: 'Xiaomi Smart Band 9 1A2B')?.name,
        'Xiaomi Smart Band 9',
      );
      expect(
        wearModelFor(bluetoothName: 'Xiaomi Smart Band 9 Pro 1A2B')?.name,
        'Xiaomi Smart Band 9 Pro',
      );
      expect(
        wearModelFor(bluetoothName: 'Redmi Watch 5 Lite 00FF')?.name,
        'Redmi Watch 5 Lite',
      );
      expect(
        wearModelFor(bluetoothName: 'Redmi Watch 3 Active AB12')?.name,
        'Redmi Watch 3 Active',
      );
      expect(wearModelFor(bluetoothName: 'Pixel Buds'), isNull);
    });

    test('a reported model id wins over the name', () {
      final m = wearModelFor(
        bluetoothName: 'renamed',
        modelId: 'miwear.watch.n66gl',
      );
      expect(m?.name, 'Xiaomi Smart Band 9');
      expect(m?.verified, isTrue);
    });

    test('screens follow the face tables', () {
      final band9 = wearModelFor(bluetoothName: 'Xiaomi Smart Band 9 0001')!;
      expect((band9.width, band9.height, band9.faceType), (192, 490, 366));
      final rw4 = wearModelFor(bluetoothName: 'Redmi Watch 4 0001')!;
      expect((rw4.width, rw4.height, rw4.faceType), (390, 450, 365));
      final s3 = wearModelFor(bluetoothName: 'Xiaomi Watch S3 0001')!;
      expect(s3.shape, BandScreenShape.round);
    });

    test('every model name is unique and its pattern compiles', () {
      expect(
        wearModels.map((m) => m.name).toSet(),
        hasLength(wearModels.length),
      );
      for (final m in wearModels) {
        expect(() => RegExp(m.namePattern), returnsNormally, reason: m.name);
      }
    });
  });

  group('faceFits', () {
    final luaFace = customFaceById('960000061')!;
    final imageFace = customFaces.firstWhere((f) => !f.lua);

    test('image faces need a 192×490 screen', () {
      final band9 = wearModelFor(bluetoothName: 'Xiaomi Smart Band 9 0001');
      final rw4 = wearModelFor(bluetoothName: 'Redmi Watch 4 0001');
      expect(faceFits(imageFace, band9), isTrue);
      expect(faceFits(imageFace, rw4), isFalse);
    });

    test('Lua faces go on any Lua model', () {
      final rw4 = wearModelFor(bluetoothName: 'Redmi Watch 4 0001');
      final rw3 = wearModelFor(bluetoothName: 'Redmi Watch 3 0001');
      expect(faceFits(luaFace, rw4), isTrue);
      expect(faceFits(luaFace, rw3), isFalse);
    });

    test('unknown models keep every face', () {
      expect(faceFits(imageFace, null), isTrue);
      expect(faceFits(luaFace, null), isTrue);
    });
  });

  test('the device picker says what OpenWear can do with a model', () {
    expect(
      modelSupportLine('Xiaomi Smart Band 9 0001'),
      contains('tested with OpenWear'),
    );
    expect(
      modelSupportLine('Xiaomi Smart Band 8 0001'),
      contains('not supported yet'),
    );
    expect(modelSupportLine('Redmi Watch 4 0001'), contains('not tested'));
    expect(modelSupportLine('Headphones'), isNull);
  });
}
