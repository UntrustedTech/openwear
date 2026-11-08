import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/band_app_messages.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/pb.dart';

Uint8List appId(String pkg, List<int> fp) =>
    pbEncode([PbString(1, pkg), PbBytes(2, Uint8List.fromList(fp))]);

void main() {
  const pkg = 'org.openwear.band';

  test('the band asking for its phone app is recognised', () {
    final ask = Command.of(20, 6, [
      PbBytes(5, appId(pkg, [1, 2])),
    ]);
    final app = bandAppStatusAsk(ask)!;
    expect(app.package, pkg);
    expect(app.fingerprint, [1, 2]);
    expect(bandAppStatusAsk(Command.of(20, 0, const [])), isNull);
  });

  test('the status answer carries the app and "connected"', () {
    final reply = bandAppStatus(BandAppId(pkg, Uint8List.fromList([1, 2])));
    expect(reply.isA(20, 7), isTrue);
    final m = reply.body.message(8)!;
    expect(m.message(1)!.string(1), pkg);
    expect(m.message(1)!.bytes(2), [1, 2]);
    expect(m.int_(2), 1);
  });

  test('a band app message is read as JSON, plain or wrapped in a string', () {
    Command from(String data) => Command.of(20, 9, [
      PbBytes(
        9,
        pbEncode([
          PbBytes(1, appId(pkg, [7])),
          PbBytes(2, Uint8List.fromList(utf8.encode(data))),
        ]),
      ),
    ]);
    final plain = bandAppMessage(from('{"t":"hello"}'))!;
    expect(plain.app.package, pkg);
    expect(plain.json, {'t': 'hello'});
    expect(bandAppMessage(from(jsonEncode('{"t":"cmd"}')))!.json, {'t': 'cmd'});
    expect(bandAppMessage(from('not json'))!.json, isNull);
  });

  test('our own 20/8 is not mistaken for a band message', () {
    final out = phoneToBandApp(BandAppId(pkg, Uint8List(0)), {'t': 'state'});
    expect(out.isA(20, 8), isTrue);
    expect(bandAppMessage(out), isNull);
    final m = out.body.message(9)!;
    expect(m.message(1)!.string(1), pkg);
    expect(jsonDecode(utf8.decode(m.bytes(2)!)), {'t': 'state'});
  });
}
