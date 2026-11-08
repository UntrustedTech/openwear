import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/cloud/xiaomi_cloud.dart' as cloud;
import 'package:openwear/platform/android_bridge.dart';
import 'package:openwear/protocol/bind.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/crypto.dart';
import 'package:openwear/protocol/l1.dart';
import 'package:openwear/protocol/link.dart';
import 'package:openwear/protocol/pb.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/services/pairing_service.dart';

final deviceKey = Uint8List.fromList(List.generate(16, (i) => 0x40 + i));
final accountKey = Uint8List.fromList(List.generate(16, (i) => 0x70 + i));
const oobCode = 1234;

Command authReply(int subtype, int field, List<PbField> fields) =>
    Command.of(typeAuth, subtype, [PbBytes(field, pbEncode(fields))]);

/// A factory-reset band that needs the account (PSK) bind, like Smart Band 9.
class AccountBand implements Transport {
  AccountBand({this.cancelOnBand = false});
  final bool cancelOnBand;
  final _out = StreamController<Uint8List>();
  final _reader = FrameReader();
  final received = <int>[];
  int _seq = 0;

  @override
  Future<void> connect() async {}
  @override
  Stream<Uint8List> get incoming => _out.stream;
  @override
  Future<void> close() async {
    if (!_out.isClosed) await _out.close();
  }

  void _reply(Command c) => _out.add(
    Frame(
      frameData,
      _seq++,
      l2Encode(channelPb, opcodePlain, c.encode()),
    ).encode(),
  );

  @override
  Future<void> write(Uint8List data) async {
    if (data[0] == 0xBA) {
      _out.add(
        Uint8List.fromList([
          0xBA,
          0xDC,
          0xFE,
          0,
          0,
          6,
          0,
          0,
          1,
          0,
          2,
          0,
          0x61,
          0xEF,
        ]),
      );
      return;
    }
    for (final frame in _reader.feed(data)) {
      if (frame.type == frameCmd) {
        _out.add(
          Frame(frameCmd, 0, Uint8List.fromList([cmdStartRsp])).encode(),
        );
        continue;
      }
      if (frame.type != frameData) continue;
      final (_, _, payload) = l2Decode(frame.payload);
      final cmd = Command.decode(payload);
      received.add(cmd.subtype);
      switch (cmd.subtype) {
        case 17:
          _reply(
            authReply(17, 12, [
              const PbVarint(1, verifyModeAccount),
              const PbString(2, 'SN9'),
              const PbString(4, 'miwear.watch.n66gl'),
              const PbVarint(5, 3),
              const PbBytes(6, [1, 2, 3]),
            ]),
          );
        case 18:
          _reply(
            authReply(18, 14, [
              const PbBytes(1, [4]),
              const PbBytes(2, [5]),
            ]),
          );
        case 19:
          if (cancelOnBand) {
            _reply(Command.of(typeAuth, 19, [const PbVarint(3, 6)]));
            break;
          }
          final devRandom = Uint8List(16)..fillRange(0, 16, 9);
          _reply(
            authReply(19, 16, [
              PbBytes(1, devRandom),
              PbBytes(
                2,
                hmacSha256(deviceKey, [...devRandom, ...utf8.encode('001234')]),
              ),
              const PbBytes(3, [7, 7]),
            ]),
          );
        case 25:
          _reply(Command.of(typeAuth, 25, const []));
      }
    }
  }
}

class FakeCloud implements BindCloud {
  final calls = <String>[];
  List<int>? bindSign;

  @override
  String get userId => '42';

  @override
  Future<cloud.ServerHello> hello(
    BindInfo info,
    String mac,
    String phoneId,
  ) async {
    calls.add('hello ${info.model} $mac');
    return cloud.ServerHello(
      'i',
      'd',
      Uint8List(65),
      Uint8List(64),
      Uint8List(16),
    );
  }

  @override
  Future<cloud.ServerKeys> ecdh(
    cloud.ServerHello hello,
    List<int> pub,
    List<int> sign,
  ) async {
    calls.add('ecdh $pub $sign');
    return cloud.ServerKeys(deviceKey, oobCode, 'bk');
  }

  @override
  Future<void> confirm(cloud.ServerHello hello, List<int> bindSign) async {
    this.bindSign = bindSign;
    calls.add('bind');
  }

  @override
  Future<Uint8List?> sessionKey(String mac, String model) async => accountKey;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const device = BondedDevice('Xiaomi Smart Band 9', '08:16:d5:00:12:34');

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'account bind runs every step and saves the session key from the account',
    () async {
      const storage = FlutterSecureStorage();
      final band = BandService(storage: storage);
      final fake = AccountBand();
      final server = FakeCloud();
      final pairing = PairingService(
        band,
        storage: storage,
        transportFor: (_) => fake,
        onPaired: () async {},
      )..account = server;
      final steps = <bool>[];
      pairing.addListener(() => steps.add(pairing.waitingForTap));

      await pairing.pair(device);

      expect(fake.received, [17, 18, 19, 25]);
      expect(server.calls, [
        'hello miwear.watch.n66gl 08:16:D5:00:12:34',
        'ecdh [4] [5]',
        'bind',
      ]);
      expect(server.bindSign, [7, 7]);
      expect(
        steps,
        contains(true),
        reason: 'the user is asked to tap the band',
      );
      expect(
        await storage.read(key: 'band.authKey'),
        accountKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      );
      expect(await storage.read(key: 'band.address'), '08:16:D5:00:12:34');
      expect(
        band.log.export(),
        contains('Pairing: Paired with Xiaomi Smart Band 9'),
      );
    },
  );

  test(
    'account band without sign-in explains that an account is needed',
    () async {
      final band = BandService();
      final pairing = PairingService(band, transportFor: (_) => AccountBand());
      await expectLater(
        pairing.pair(device),
        throwsA(
          isA<PairingException>().having(
            (e) => e.message,
            'message',
            contains('Sign in'),
          ),
        ),
      );
      expect(band.state, BandState.notPaired);
      expect(pairing.busy, isFalse);
    },
  );

  test('cancelling on the band is reported and nothing is saved', () async {
    const storage = FlutterSecureStorage();
    final band = BandService(storage: storage);
    final pairing = PairingService(
      band,
      storage: storage,
      transportFor: (_) => AccountBand(cancelOnBand: true),
    )..account = FakeCloud();
    await expectLater(
      pairing.pair(device),
      throwsA(
        isA<PairingException>().having(
          (e) => e.message,
          'message',
          contains('cancelled'),
        ),
      ),
    );
    expect(await storage.read(key: 'band.authKey'), isNull);
    expect(pairing.waitingForTap, isFalse);
  });
}
