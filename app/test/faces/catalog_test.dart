import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/faces/calendar_names.dart';
import 'package:openwear/faces/catalog.dart';
import 'package:openwear/faces/face_binary.dart';
import 'package:openwear/faces/image_codec.dart';

void main() {
  test('sixty faces with unique ids and names', () {
    expect(customFaces, hasLength(61));
    expect(customFaces.map((f) => f.id).toSet(), hasLength(61));
    expect(customFaces.map((f) => f.name).toSet(), hasLength(61));
    for (final f in customFaces) {
      expect(f.id, matches(RegExp(r'^\d{9}$')));
    }
    expect(
      customFaces.where((f) => f.kinds.contains(FaceKind.animated)).length,
      greaterThanOrEqualTo(8),
    );
    expect(
      customFaces.where((f) => f.kinds.contains(FaceKind.info)).length,
      greaterThanOrEqualTo(4),
    );
  });

  test('weekday and month names follow the phone language', () {
    expect(weekdayNames('es-MX').first, 'Dom');
    expect(monthNames('de').last, 'Dez');
    expect(weekdayNames('xx'), weekdayNames('en'));
  });

  for (final f in customFaces) {
    testWidgets('${f.name} builds a valid binary', (tester) async {
      await tester.runAsync(() async {
        final design = await f.design('en');
        final bin = packFace(design);
        expect(bin.sublist(0, 4), faceMagic);
        expect(design.preview.width, 96);
        expect(
          bin.length,
          lessThan(1500 * 1024),
          reason: '${bin.length} bytes',
        );
        // ignore: avoid_print
        print(
          '${f.name}: ${(bin.length / 1024).toStringAsFixed(0)} KB, '
          '${design.elements.length} elements',
        );
        // Every image block decodes.
        decodeImage(bin, ByteDataReader.previewOffset(bin));
      });
    });
  }
}

abstract final class ByteDataReader {
  static int previewOffset(List<int> b) =>
      b[0x20] | b[0x21] << 8 | b[0x22] << 16 | b[0x23] << 24;
}
