import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/cloud/http_backend.dart';
import 'package:openwear/cloud/network_check.dart';
import 'package:openwear/cloud/xiaomi_cloud.dart';

/// A backend whose every request fails the way a black-holed host does.
class StalledBackend implements HttpBackend {
  final requests = <String>[];

  @override
  String get name => 'fake';

  @override
  Future<HttpReply> send(
    String method,
    Uri url, {
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async {
    requests.add('$method ${url.host}${url.path}');
    throw NetworkException('SocketTimeout', 'connect timed out');
  }
}

void main() {
  tearDown(() {
    httpBackend = DartHttpBackend();
    cloudTrace = null;
  });

  test(
    'an unreachable login server is reported as a network failure',
    () async {
      final backend = StalledBackend();
      httpBackend = backend;
      final trace = <String>[];
      cloudTrace = trace.add;

      await expectLater(
        login('user', 'password', 'device', (_) async => ''),
        throwsA(
          isA<CloudException>()
              .having((e) => e.network, 'network', isTrue)
              .having(
                (e) => e.message,
                'message',
                contains('account.xiaomi.com'),
              )
              .having((e) => e.message, 'message', contains('SocketTimeout')),
        ),
      );
      expect(backend.requests, ['GET account.xiaomi.com/pass/serviceLogin']);
      expect(trace.single, contains('✗ SocketTimeout'));
      expect(trace.single, contains('(fake)'));
    },
  );

  test('a host resolving to loopback is called out as DNS-blocked', () async {
    final lines = await networkCheck(
      backend: StalledBackend(),
      describeNetwork: () async => {'network': 'Wi-Fi', 'vpn': 'false'},
      hosts: ['localhost', 'connectivitycheck.gstatic.com'],
    );
    expect(lines.first, 'network: Wi-Fi');
    expect(lines, contains(contains('blocked by a DNS filter')));
    expect(lines.last, startsWith('Conclusion:'));
  });

  test('a token deleted during login is not sent; the real one is', () async {
    final backend = ScriptedXiaomi();
    httpBackend = backend;
    final trace = <String>[];
    cloudTrace = trace.add;

    final session = await login('user', 'pw', 'dev', (_) async => '');
    expect(session.serviceToken, 'real/Token+1==');
    expect(session.userId, '1234561259');

    await expectLater(
      bindHello(
        session,
        'us',
        verifyMode: 1,
        model: 'm',
        mac: 'AA',
        sn: 's',
        did: 'd',
        deviceRandom: const [1],
        phoneId: 'p',
      ),
      throwsA(isA<CloudException>()),
    );
    expect(backend.lastCookie, contains('serviceToken=real/Token+1=='));
    expect(backend.lastCookie, isNot(contains('EXPIRED')));
    expect(trace, contains(contains('serviceToken@xiaomi.com deleted')));
    expect(trace, contains(contains('body: {"code":401')));
    expect(
      trace.join('\n'),
      isNot(contains('real/Token')),
      reason: 'no values',
    );
  });
}

/// Xiaomi's login as seen by the client, ending with a 401 from the health API.
class ScriptedXiaomi implements HttpBackend {
  String lastCookie = '';
  static const _ssecurity = 'AAECAwQFBgcICQoLDA0ODw==';

  @override
  String get name => 'scripted';

  @override
  Future<HttpReply> send(
    String method,
    Uri url, {
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async {
    lastCookie = headers['cookie'] ?? '';
    String json(Map<String, Object> m) => '&&&START&&&${jsonEncode(m)}';
    return switch (url.path) {
      '/pass/serviceLogin' => HttpReply(
        200,
        json({'code': 70016, '_sign': 's'}),
      ),
      '/pass/serviceLoginAuth2' => HttpReply(
        200,
        json({
          'code': 0,
          'userId': 1234561259,
          'ssecurity': _ssecurity,
          'location': 'https://sts-hlth.io.mi.com/healthapp/sts?x=1',
        }),
      ),
      '/healthapp/sts' => const HttpReply(
        200,
        'ok',
        setCookies: [
          'serviceToken=stale; Domain=.xiaomi.com; Path=/',
          'serviceToken=EXPIRED; Domain=.xiaomi.com; Expires=Thu, 01-Jan-1970 00:00:10 GMT',
          'serviceToken=real/Token+1==; Domain=hlth.io.mi.com; Path=/',
        ],
      ),
      _ => const HttpReply(401, '{"code":401,"message":"auth err"}'),
    };
  }
}
