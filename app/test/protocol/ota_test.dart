import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/cloud/xiaomi_cloud.dart' as cloud;
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/ota.dart';
import 'package:openwear/protocol/pb.dart';
import 'package:openwear/services/band_log.dart';
import 'package:openwear/services/firmware_update.dart';

const _md5 = '0123456789abcdef0123456789abcdef';

Command _reply(int status) => Command.of(typeSystem, 5, [
  PbBytes(17, pbEncode([PbVarint(1, status), const PbVarint(2, 1024)])),
]);

void main() {
  group('2/5 prepare', () {
    test('announces the package like Mi Fitness', () {
      final c = prepareFirmware('2.3.120', _md5);
      expect(c.isA(typeSystem, 5), isTrue);
      final m = c.body.message(16)!;
      expect(m.int_(1), 0);
      expect(m.int_(2), 15);
      expect(m.string(3), '2.3.120');
      expect(m.string(4), _md5);
    });

    test('ready, already has it, or refused', () {
      expect(checkPrepareFirmware(_reply(0)), isTrue);
      expect(checkPrepareFirmware(_reply(2)), isFalse);
      expect(
        () => checkPrepareFirmware(_reply(1)),
        throwsA(isA<FirmwareException>()),
      );
      expect(
        () => checkPrepareFirmware(const Command(typeSystem, 5)),
        throwsA(isA<FirmwareException>()),
      );
    });
  });

  group('latest_ver result', () {
    final base = {
      'version': '2.3.120',
      'safe_url': 'https://cdn.example.com/full.bin',
      'md5': _md5.toUpperCase(),
      'changeLog': ' Fixes. ',
      'fileSize': 1048576,
    };

    test('the full package, even when a diff is offered', () {
      final r = cloud.FirmwareRelease.fromJson({
        ...base,
        'diff_safe_url': 'https://cdn.example.com/diff.bin',
        'diff_md5': 'ffffffffffffffffffffffffffffffff',
      }, '2.3.98')!;
      expect(r.url.path, '/full.bin');
      expect(r.md5, _md5);
      expect(r.changeLog, 'Fixes.');
      expect(r.size, 1048576);
    });

    test('nothing when up to date, insecure or without a checksum', () {
      expect(cloud.FirmwareRelease.fromJson(base, '2.3.120'), isNull);
      expect(cloud.FirmwareRelease.fromJson(base, '2.4.0'), isNull);
      expect(
        cloud.FirmwareRelease.fromJson({
          ...base,
          'safe_url': 'http://x/y',
        }, '2.3.98'),
        isNull,
      );
      expect(
        cloud.FirmwareRelease.fromJson({...base, 'md5': ''}, '2.3.98'),
        isNull,
      );
    });
  });

  test('versions compare numerically, part by part', () {
    expect(cloud.compareFirmware('2.3.120', '2.3.98'), 1);
    expect(cloud.compareFirmware('2.3.98', '2.10.0'), -1);
    expect(cloud.compareFirmware('2.3.98', '2.3.98'), 0);
    expect(cloud.compareFirmware('2.3', '2.3.98'), 0);
  });

  test('the band did comes from the record with its MAC', () {
    final devices = [
      {'sid': 'other', 'model': 'x', 'mac': 'AA:BB:CC:DD:EE:FF'},
      {
        'sid': 'band9',
        'model': 'miwear.watch.m2345',
        'detail': '{"mac":"08:16:D5:00:12:34"}',
      },
    ];
    expect(cloud.didFromDevices(devices, '08:16:D5:00:12:34', 'none'), 'band9');
    expect(cloud.didFromDevices(devices, '00:00:00:00:00:00', 'z'), isNull);
  });

  group('FirmwareUpdate', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('fw'));
    tearDown(() => dir.deleteSync(recursive: true));

    FirmwareUpdate make({
      cloud.FirmwareRelease? offer,
      Object? fail,
      Uint8List? package,
      List<String>? exported,
    }) => FirmwareUpdate(
      log: BandLog(),
      link: () => null,
      directory: () async => dir,
      findRelease: (_, _) async {
        if (fail != null) throw fail;
        return offer;
      },
      download: (_, onProgress) async {
        onProgress(1);
        return package ?? Uint8List(0);
      },
      export: (name, _) async {
        exported?.add(name);
        return 'Download/OpenWear/Firmware/$name';
      },
    );

    final pkg = Uint8List.fromList(List.generate(300, (i) => i & 0xff));
    cloud.FirmwareRelease offer(String sum) => cloud.FirmwareRelease(
      version: '2.4.0',
      url: Uri.parse('https://x/y'),
      md5: sum,
    );

    test('up to date keeps nothing', () async {
      final fw = make();
      await fw.check('m2345', '2.3.98');
      expect(fw.release, isNull);
      expect(fw.saved, isNull);
      expect(fw.checkedFirmware, '2.3.98');
      expect(fw.step, FirmwareStep.idle);
    });

    test('a newer release is downloaded, checked and kept', () async {
      final exported = <String>[];
      final fw = make(
        offer: offer(md5Hex(pkg)),
        package: pkg,
        exported: exported,
      );
      await fw.check('m2345', '2.3.98');
      expect(fw.error, isNull);
      expect(fw.releaseDownloaded, isTrue);
      expect(File(fw.saved!.file).readAsBytesSync(), pkg);
      expect(exported, ['m2345_2.4.0.bin']);
      expect(fw.saved!.publicPath, endsWith('m2345_2.4.0.bin'));

      // It is still there after a restart.
      final again = make();
      await again.load();
      expect(again.saved!.version, '2.4.0');
    });

    test('a damaged download is not kept', () async {
      final fw = make(offer: offer(_md5), package: pkg);
      await fw.check('m', '2.3.98');
      expect(fw.saved, isNull);
      expect(fw.error, contains('damaged'));
    });

    test('a failed check shows why', () async {
      final fw = make(fail: const cloud.CloudException('Sign in first.'));
      await fw.check('m', '1.0.0');
      expect(fw.error, 'Sign in first.');
      expect(fw.checkedFirmware, isNull);
    });

    test('sending needs a connected band', () async {
      final fw = make(offer: offer(md5Hex(pkg)), package: pkg);
      await fw.check('m', '2.3.98');
      await fw.sendSaved();
      expect(fw.error, 'Connect the band first.');
      await fw.sendFile(pkg, '2.3.50');
      expect(fw.error, 'Connect the band first.');
    });

    test('version from a package file name', () {
      expect(versionInFileName('m2345_2.3.50.bin'), '2.3.50');
      expect(versionInFileName('firmware.bin'), isNull);
    });
  });
}
