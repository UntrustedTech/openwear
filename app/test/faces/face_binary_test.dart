import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/faces/face_binary.dart';
import 'package:openwear/faces/image_codec.dart';
import 'package:openwear/faces/rle.dart';

Raster solid(int w, int h, List<int> rgba) =>
    Raster(w, h, Uint8List.fromList([for (var i = 0; i < w * h; i++) ...rgba]));

Raster noisy(int w, int h) => Raster(
  w,
  h,
  Uint8List.fromList([
    for (var i = 0; i < w * h; i++) ...[
      i & 0xff,
      (i >> 8) * 60 & 0xff,
      i & 0xff,
      255,
    ],
  ]),
);

int u32(Uint8List b, int o) =>
    ByteData.sublistView(b).getUint32(o, Endian.little);
int u16(Uint8List b, int o) =>
    ByteData.sublistView(b).getUint16(o, Endian.little);

void main() {
  group('RLE', () {
    test('v1 round-trips runs and singles', () {
      final data = Uint8List.fromList([
        for (var i = 0; i < 300; i++) ...[1, 2, 3],
        4, 5, 6, 7, 8, 9, //
      ]);
      final enc = encodeRleV1(data, 3);
      expect(enc.length, lessThan(data.length ~/ 10));
      expect(decodeRleV1(enc, data.length, 3), data);
    });

    test('v2 round-trips runs and literals', () {
      final data = Uint8List.fromList([
        ...List.filled(200, 7),
        1, 2, 3, 3, 4, 5, 5, 5, 5, 9, //
        for (var i = 0; i < 300; i++) i & 0xff,
      ]);
      expect(decodeRleV2(encodeRleV2(data), data.length), data);
    });

    test('rejects data that expands past its declared size', () {
      expect(
        () => decodeRleV2(Uint8List.fromList([10, 1]), 4),
        throwsA(isA<RleException>()),
      );
    });
  });

  group('images', () {
    test('few colours use the palette and decode exactly', () {
      final r = solid(20, 10, [255, 80, 0, 255]);
      final block = encodeImage(r);
      expect(block[0], signIndexed);
      expect(u16(block, 4), 20);
      expect(u16(block, 6), 10);
      expect(u32(block, 8), block.length - imageHeaderSize);
      expect(decodeImage(block, 0).rgba, r.rgba);
    });

    test('many colours use RGB565 + alpha (Band 9)', () {
      final r = noisy(32, 32);
      final block = encodeImage(r);
      expect(block[0], signRgb565Alpha);
      final back = decodeImage(block, 0).rgba;
      for (var i = 0; i < r.rgba.length; i += 4) {
        expect(back[i], r.rgba[i] & 0xf8);
        expect(back[i + 1], r.rgba[i + 1] & 0xfc);
        expect(back[i + 2], r.rgba[i + 2] & 0xf8);
        expect(back[i + 3], 255);
      }
    });

    test('image lists keep every frame', () {
      final frames = [
        for (var i = 0; i < 5; i++) solid(8, 8, [i * 40, 0, 0, 255]),
      ];
      final block = encodeImageList(frames);
      expect(block[1], 5);
      final back = decodeImageList(block, 0);
      expect([for (final f in back) f.rgba[0]], [0, 40, 80, 120, 160]);
    });

    test('image list frames must share a size', () {
      expect(
        () => encodeImageList([
          solid(2, 2, [0, 0, 0, 0]),
          solid(3, 2, [0, 0, 0, 0]),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('packFace', () {
    final digits = [
      for (var i = 0; i < 10; i++) solid(10, 16, [i, i, i, 255]),
    ];
    final design = FaceDesign(
      id: '960000001',
      name: 'Test Face',
      preview: solid(40, 100, [0, 0, 0, 255]),
      elements: [
        StaticImage(0, 0, solid(192, 490, [10, 10, 30, 255])),
        Animation(20, 30, [
          solid(4, 4, [255, 0, 0, 255]),
          solid(4, 4, [0, 0, 0, 0]),
        ], intervalMs: 500),
        DigitNumber(30, 100, FaceData.hour, digits, count: 2),
        DigitNumber(80, 100, FaceData.minute, digits, count: 2),
        ImageSwitch(
          10,
          400,
          FaceData.battery,
          [
            solid(6, 6, [0, 255, 0, 255]),
            solid(6, 6, [255, 0, 0, 255]),
          ],
          const [0, 20],
        ),
      ],
    );
    final bin = packFace(design);

    test('writes the main header', () {
      expect(bin.sublist(0, 4), faceMagic);
      expect(u32(bin, 0x10), 0x800);
      expect(u16(bin, 0x1C), 1);
      expect(ascii.decode(bin.sublist(0x28, 0x31)), '960000001');
      expect(utf8.decode(bin.sublist(0x68, 0x68 + 9)), 'Test Face');
    });

    test('face header counts each definition type', () {
      const f = mainHeaderSize;
      expect(u32(bin, f + 0x08), 5); // elements
      expect(u32(bin, f + 0x18), 1); // single images
      expect(u32(bin, f + 0x20), 3); // anim frames, digits, battery icons
      expect(u32(bin, f + 0x28), 1); // animations
      expect(u32(bin, f + 0x40), 3); // widgets
    });

    test('every definition points inside the file and decodes', () {
      const f = mainHeaderSize;
      final defStart = u32(bin, f + 0x0C);
      final total = 5 + 1 + 3 + 1 + 3;
      for (var i = 0; i < total; i++) {
        final o = defStart + i * 16;
        final off = u32(bin, o + 8), len = u32(bin, o + 12);
        expect(off + len, lessThanOrEqualTo(bin.length));
        if (bin[o + 3] == 2) decodeImage(bin, off);
        if (bin[o + 3] == 3) decodeImageList(bin, off);
      }
      expect(decodeImage(bin, u32(bin, 0x20)).width, 40);
    });

    test('digit widgets name their data source and digit count', () {
      const f = mainHeaderSize;
      final widgetDefs = u32(bin, f + 0x44);
      final hour = u32(bin, widgetDefs + 8);
      expect(bin.sublist(hour, hour + 4), [0x08, 0x11, 2, 0x15]);
      final battery = u32(bin, widgetDefs + 32 + 8);
      expect(bin[battery + 3], 0x20);
      expect(u16(bin, battery + 20), 20);
    });

    test('rejects ids that are not nine digits', () {
      expect(
        () => packFace(
          FaceDesign(
            id: '12',
            name: 'x',
            elements: const [],
            preview: digits[0],
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Lua faces', () {
    test('a stored file is size, path length, 16 zeros, path, contents', () {
      final b = encodeFaceFile(FaceFile('lua/main.lua', utf8.encode('x=1')));
      expect(b.sublist(0, 4), [3, 0, 0, 12]);
      expect(b.sublist(4, 20), List.filled(16, 0));
      expect(utf8.decode(b.sublist(20, 32)), 'lua/main.lua');
      expect(utf8.decode(b.sublist(32)), 'x=1');
    });

    test('the script is an element of type 5 pointing at its file', () {
      final bin = packFace(
        FaceDesign(
          id: '960000099',
          name: 'Lua',
          preview: solid(4, 4, [0, 0, 0, 255]),
          elements: [
            StaticImage(0, 0, solid(8, 8, [0, 0, 0, 255])),
            LuaApp('lua/main.lua', [
              FaceFile('lua/util.lua', utf8.encode('return {}')),
              FaceFile('lua/main.lua', utf8.encode('print(1)')),
            ]),
          ],
        ),
      );
      const f = mainHeaderSize;
      expect(u32(bin, f + 0x08), 2); // elements
      expect(u32(bin, f + 0x30), 2); // files
      final files = u32(bin, f + 0x34);
      for (var i = 0; i < 2; i++) {
        final d = files + i * 16;
        expect(bin[d + 3], 5);
        final at = u32(bin, d + 8), len = u32(bin, d + 12);
        final pathLen = bin[at + 3];
        final path = utf8.decode(bin.sublist(at + 20, at + 20 + pathLen));
        expect(path, ['lua/util.lua', 'lua/main.lua'][i]);
        expect(len, 20 + pathLen + u32(bin, at) % 0x1000000);
        expect(at + len, lessThanOrEqualTo(bin.length));
      }
      // The second element references file 1 (main.lua) as type 5.
      final elements = u32(bin, f + 0x0C);
      final prop = u32(bin, elements + 16 + 8);
      expect(bin[prop + 3], 5);
      expect(bin[prop] | bin[prop + 1] << 8 | bin[prop + 2] << 16, 1);
    });

    test('an entry that is not among the files is refused', () {
      expect(
        () => LuaApp('lua/main.lua', [FaceFile('lua/a.lua', const [])]),
        throwsArgumentError,
      );
    });
  });
}
