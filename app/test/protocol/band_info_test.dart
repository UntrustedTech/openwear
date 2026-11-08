import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/device.dart';
import 'package:openwear/protocol/pb.dart';
import 'package:openwear/ui/screens/device_info_screen.dart';

void main() {
  // The payload of a system command is the system message itself; device
  // info is its field 3 (same level as battery in field 2).
  Command reply(List<PbField> info) =>
      Command.of(2, 2, [PbBytes(3, pbEncode(info))]);

  test('device info request is system 2/2', () {
    final c = deviceInfoRequest();
    expect((c.type, c.subtype), (2, 2));
  });

  test('reads serial, firmware, model and the rest', () {
    final info = parseBandInfo(
      reply([
        PbString(1, 'SN123456'),
        PbString(2, '2.3.85'),
        PbString(3, 'hw-x'),
        PbString(4, 'miwear.watch.n66gl'),
        PbString(5, 'Xiaomi Smart Band 9'),
        PbVarint(6, 1),
      ]),
    )!;
    expect(info.serial, 'SN123456');
    expect(info.firmware, '2.3.85');
    expect(info.model, 'miwear.watch.n66gl');
    expect(info.product, 'Xiaomi Smart Band 9');
    expect(info.channel, 1);
    expect(info.extra, {3: 'hw-x'});
  });

  test('a reply without device info gives null', () {
    expect(parseBandInfo(Command.of(2, 2, [PbVarint(1, 0)])), isNull);
  });

  test('the About rows show everything and mark what is unknown', () {
    final rows = deviceInfoRows(
      name: 'Band 9',
      address: '08:16:D5:00:12:34',
      battery: 80,
      info: const BandInfo(
        serial: 'SN1',
        firmware: '2.3.85',
        model: 'miwear.watch.n66gl',
        extra: {7: 'x'},
      ),
      faces: 5,
      activeFace: 'Classic',
    );
    final map = Map.fromEntries(rows.map((r) => MapEntry(r.$1, r.$2)));
    expect(map['Firmware version'], '2.3.85');
    expect(map['Serial number'], 'SN1');
    expect(map['Battery'], '80%');
    expect(map['Other (field 7)'], 'x');
    final empty = deviceInfoRows(
      name: '',
      address: '',
      battery: null,
      info: null,
      faces: 0,
      activeFace: null,
    );
    expect(
      empty.firstWhere((r) => r.$1 == 'Firmware version').$2,
      'Not read yet',
    );
  });
}
