import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/band_apps.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/pb.dart';
import 'package:openwear/protocol/rpk.dart';

List<int> _app(
  String id, {
  bool hidden = false,
  bool more = false,
  bool always = false,
  bool mayMore = true,
}) => pbEncode([
  PbString(1, id),
  PbString(2, id.toUpperCase()),
  PbBool(3, hidden),
  PbBool(4, always),
  PbBool(5, mayMore),
  PbBool(6, more),
  const PbVarint(9, 42), // unknown to us
]);

Command _list() => Command.of(typeSystem, 29, [
  PbBytes(
    10,
    pbEncode([
      PbBytes(1, _app('clock', always: true)),
      PbBytes(1, _app('timer', more: true)),
      PbBytes(1, _app('music', hidden: true)),
    ]),
  ),
]);

void main() {
  test('reads where each built-in app sits', () {
    final apps = parseAppList(_list())!;
    expect(apps.map((a) => a.place), [
      AppPlace.shown,
      AppPlace.more,
      AppPlace.hidden,
    ]);
    expect(apps.first.alwaysShown, isTrue);
  });

  test('an always-shown app cannot be hidden', () {
    final clock = parseAppList(_list())!.first;
    expect(clock.moveTo(AppPlace.hidden).place, AppPlace.shown);
  });

  test('writing the list keeps order and unknown fields', () {
    final apps = parseAppList(_list())!;
    final edited = [apps[2].moveTo(AppPlace.shown), apps[0], apps[1]];
    final cmd = appListCommand(edited);
    expect((cmd.type, cmd.subtype), (typeSystem, 30));
    final sent = cmd.body.message(10)!.messages(1);
    expect(sent.map((m) => m.string(1)), ['music', 'clock', 'timer']);
    expect(sent.first.int_(3), 0);
    expect(sent.first.int_(6), 0);
    expect(sent.first.int_(9), 42);
  });

  test('reads installed apps', () {
    final cmd = Command.of(typeApps, 0, [
      PbBytes(
        1,
        pbEncode([
          PbBytes(
            1,
            pbEncode([
              const PbString(1, 'com.example.calc'),
              const PbBytes(2, [1, 2, 3]),
              const PbVarint(3, 7),
              const PbString(5, 'Calculator'),
            ]),
          ),
        ]),
      ),
    ]);
    final app = parseInstalledApps(cmd)!.single;
    expect(app.name, 'Calculator');
    expect(app.version, 7);
    final un = uninstallApp(app).body.message(5)!;
    expect(un.string(1), 'com.example.calc');
    expect(un.bytes(2), [1, 2, 3]);
  });

  test('a refused install says so', () {
    final ok = Command.of(typeApps, 1, [
      PbBytes(3, pbEncode([const PbVarint(1, 0), const PbVarint(2, 4096)])),
    ]);
    expect(checkPrepareInstall(ok), 4096);
    final no = Command.of(typeApps, 1, [
      PbBytes(3, pbEncode([const PbVarint(1, 3)])),
    ]);
    expect(() => checkPrepareInstall(no), throwsA(isA<AppInstallException>()));
  });

  test('reads an .rpk manifest', () {
    final zip = Archive()
      ..addFile(
        ArchiveFile.bytes(
          'manifest.json',
          utf8.encode(
            '{"package":"com.example.calc","name":"Calc","versionCode":3}',
          ),
        ),
      );
    final info = readRpk(Uint8List.fromList(ZipEncoder().encode(zip)));
    expect(
      (info.package, info.name, info.version),
      ('com.example.calc', 'Calc', 3),
    );
    expect(() => readRpk(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });
}
