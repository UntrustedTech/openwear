import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/cloud/xiaomi_cloud.dart';
import 'package:openwear/services/band_log.dart';
import 'package:openwear/services/xiaomi_account.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const session = CloudSession('42', 'a2V5', 'tok');

  test('sign-in is kept, reloaded and deleted on sign-out', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final log = BandLog();
    String? usedPassword;
    final a = XiaomiAccount(
      log: log,
      login: (user, password, deviceId, ask) async {
        usedPassword = password;
        expect(deviceId, hasLength(16));
        return session;
      },
    );
    await a.signIn(' me@example.com ', 'pw', 'de', (_) async => '');
    expect(usedPassword, 'pw');
    expect(a.signedIn, isTrue);

    const storage = FlutterSecureStorage();
    final saved = await storage.read(key: 'cloud.session');
    expect(saved, isNot(contains('pw')));
    expect(jsonDecode(saved!)['region'], 'de');

    final b = XiaomiAccount(log: log);
    await b.load();
    expect(b.session?.serviceToken, 'tok');
    expect(b.region, 'de');

    await b.signOut();
    expect(b.signedIn, isFalse);
    expect(await storage.read(key: 'cloud.session'), isNull);
    // Nothing secret reaches the log.
    final text = log.entries.map((e) => '$e').join('\n');
    expect(text, isNot(contains('tok')));
    expect(text, isNot(contains('a2V5')));
  });

  test('a damaged saved sign-in is removed', () async {
    FlutterSecureStorage.setMockInitialValues({'cloud.session': '{"userId":'});
    final a = XiaomiAccount(log: BandLog());
    await a.load();
    expect(a.signedIn, isFalse);
    expect(
      await const FlutterSecureStorage().read(key: 'cloud.session'),
      isNull,
    );
  });

  test('unknown regions are refused before anything is sent', () async {
    FlutterSecureStorage.setMockInitialValues({});
    var called = false;
    final a = XiaomiAccount(
      log: BandLog(),
      login: (_, _, _, _) async {
        called = true;
        return session;
      },
    );
    await expectLater(
      a.signIn('u', 'p', 'evil.example', (_) async => ''),
      throwsA(isA<CloudException>()),
    );
    expect(called, isFalse);
  });
}
