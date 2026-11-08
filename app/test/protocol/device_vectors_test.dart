// Feature commands must match the Python prototype byte for byte.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/crc32.dart';
import 'package:openwear/protocol/device.dart';
import 'package:openwear/protocol/fitness.dart';
import 'package:openwear/protocol/mass.dart';
import 'package:openwear/protocol/pb.dart';

Uint8List unhex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);
String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final v = jsonDecode(
    File('test/fixtures/vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final fixed = DateTime(2026, 10, 31, 13, 30, 5, 123);

  test(
    'set time sends wall time, standard + DST offsets and the IANA zone',
    () {
      const ny = ZoneInfo(
        'America/New_York',
        Duration(hours: -5),
        Duration(hours: 1),
      );
      expect(hex(setTime(fixed, ny).encode()), v['set_time']);
    },
  );

  test('notification and call commands match', () {
    final n = notification(
      package: 'org.example',
      appName: 'Example',
      title: 'Hi',
      text: 'Body',
      id: 42,
      time: fixed,
    );
    expect(hex(n.encode()), v['notification']);
    expect(
      hex(incomingCall('Alice', '+1 555 0100', fixed).encode()),
      v['incoming_call'],
    );
    expect(hex(callEnded().encode()), v['call_ended']);
  });

  test('notifications carry the Android key, and removal sends it back', () {
    final n = notification(
      package: 'org.example',
      appName: 'Example',
      title: 'Hi',
      text: 'Body',
      id: 42,
      time: fixed,
      key: '0|org.example|42|null|10123',
    );
    final sent = n.body.message(3)!.message(1)!;
    expect(sent.string(12), '0|org.example|42|null|10123');

    final r = removeNotification(
      package: 'org.example',
      id: 42,
      key: '0|org.example|42|null|10123',
    );
    expect(r.isA(7, 1), isTrue);
    final item = r.body.message(4)!.message(1)!;
    expect(item.int_(1), 42);
    expect(item.string(2), 'org.example');
    expect(item.string(4), '0|org.example|42|null|10123');
  });

  test('app icon request, prepare and pixel formats', () {
    expect(hex(prepareIcon('org.example').encode()), v['prepare_icon']);
    final req = Command.of(7, 16, [
      PbBytes(16, pbEncode([const PbString(1, 'org.example')])),
    ]);
    expect(iconRequestPackage(req), 'org.example');
    final rgba = Uint8List.fromList([255, 0, 0, 128, 10, 200, 30, 255]);
    final pixels = v['pixels'] as Map<String, dynamic>;
    for (final fmt in [0, 1, 2, 7, 8]) {
      expect(
        hex(encodeIconPixels(rgba, fmt)),
        pixels['$fmt'],
        reason: 'format $fmt',
      );
    }
  });

  test('mass transfer prepare and slices match', () {
    final m = v['mass'] as Map<String, dynamic>;
    final data = unhex(m['data'] as String);
    expect(hex(prepareRequest(dataAppIcon, data).encode()), m['prepare']);
    expect(
      buildPackets(dataAppIcon, data, 300).map(hex).toList(),
      m['packets'],
    );
  });

  test('mass prepare response: slice length, already-have and busy', () {
    Command rsp(int status, int slice) => Command.of(22, 0, [
      PbBytes(2, pbEncode([PbVarint(2, status), PbVarint(5, slice)])),
    ]);
    expect(parsePrepareResponse(rsp(0, 16384)), 16384);
    expect(parsePrepareResponse(const Command(22, 0, null, 1)), isNull);
    expect(
      () => parsePrepareResponse(rsp(1, 0)),
      throwsA(isA<MassException>()),
    );
  });

  test('watch faces: set command and list parsing', () {
    expect(hex(setFace('120917343471').encode()), (v['faces'] as Map)['set']);
    Uint8List face(String id, String name, int active, int removable) =>
        pbEncode([
          PbString(1, id),
          PbString(2, name),
          PbVarint(3, active),
          PbVarint(4, removable),
        ]);
    final list = Command.of(4, 0, [
      PbBytes(
        1,
        pbEncode([
          PbBytes(1, face('a', 'Classic', 0, 1)),
          PbBytes(1, face('b', 'Sport', 1, 0)),
        ]),
      ),
    ]);
    final faces = parseFaces(list);
    expect(faces.map((f) => (f.id, f.name, f.active)).toList(), [
      ('a', 'Classic', false),
      ('b', 'Sport', true),
    ]);
  });

  test('fitness requests, file IDs and channel-5 reassembly', () {
    final f = v['fitness'] as Map<String, dynamic>;
    expect(hex(todayIdsRequest().encode()), f['today']);
    final id = FitnessId(unhex('c067e56af00501'));
    expect(hex(requestFile(id).encode()), f['request']);
    expect(
      (id.isSport, id.dataType, id.fileType, id.version),
      (false, 0, 1, 5),
    );
    expect(
      crc32(utf8.encode('123456789')),
      0xCBF43926,
    ); // standard CRC-32 check value
    final body = Uint8List.fromList([...id.raw, 1, 2, 3, 4, 5]);
    final whole = [
      ...body,
      ...(ByteData(
        4,
      )..setUint32(0, crc32(body), Endian.little)).buffer.asUint8List(),
    ];
    final asm = FileAssembler();
    expect(
      asm.feed(Uint8List.fromList([2, 0, 1, 0, ...whole.sublist(0, 6)])),
      isNull,
    );
    expect(
      asm.feed(Uint8List.fromList([2, 0, 2, 0, ...whole.sublist(6)])),
      body,
    );
    whole[8] ^= 0xFF;
    expect(
      () => asm.feed(Uint8List.fromList([1, 0, 1, 0, ...whole])),
      throwsFormatException,
    );
  });

  test('live heart rate reads field 4 of the 8/47 push', () {
    Command push(List<PbField> stats) =>
        Command.of(8, 47, [PbBytes(39, pbEncode(stats))]);
    expect(
      realtimeHeartRate(push([const PbVarint(1, 8), const PbVarint(4, 72)])),
      72,
    );
    expect(realtimeHeartRate(push([const PbVarint(1, 8)])), 0);
    expect(realtimeHeartRate(const Command(8, 1)), isNull);
  });
}
