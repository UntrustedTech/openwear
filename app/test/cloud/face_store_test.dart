import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/cloud/http_backend.dart';
import 'package:openwear/cloud/signing.dart';
import 'package:openwear/cloud/xiaomi_cloud.dart';
import 'package:openwear/services/store_face_pictures.dart';

const _security = 'c2VjcmV0LXNlY3VyaXR5LWtleQ==';
const _token = 'service-token-value';

/// Answers like Xiaomi: the JSON reply RC4-encrypted with the signed nonce.
class FaceServer implements HttpBackend {
  FaceServer(this.reply, {this.status = 200, this.raw});
  final Map<String, Object?> reply;
  final int status;

  /// Sent as is instead of the encrypted [reply].
  final String? raw;
  Uri? url;
  Map<String, String> headers = const {};
  String? body;

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
    this.url = url;
    this.headers = headers;
    this.body = body;
    final plain = raw;
    if (plain != null) return HttpReply(status, plain);
    final nonce = url.queryParameters['_nonce']!;
    final key = base64.decode(signedNonce(_security, nonce));
    final enc = Rc4(key).crypt(utf8.encode(jsonEncode(reply)));
    return HttpReply(status, base64.encode(enc));
  }
}

void main() {
  const session = CloudSession('1234567890', _security, _token);
  final trace = <String>[];

  setUp(() {
    trace.clear();
    cloudTrace = trace.add;
  });
  tearDown(() {
    httpBackend = DartHttpBackend();
    cloudTrace = null;
  });

  test('face detail is a signed GET to the regional face server', () async {
    final server = FaceServer({
      'code': 0,
      'result': {
        'watch_face': {
          'display_name': 'Classic',
          'icon': 'https://cdn.example.mi.com/face.png',
        },
      },
    });
    httpBackend = server;

    final face = await faceDetail(
      session,
      'us',
      model: 'miwear.watch.n66gl',
      id: '365001',
      firmware: '2.3.85',
    );

    expect(face.name, 'Classic');
    expect(face.pictureUrl, Uri.parse('https://cdn.example.mi.com/face.png'));
    final url = server.url!;
    expect(url.host, 'us.watch.iot.mi.com');
    expect(url.path, '/ops/v1/paidwatchface/detail');
    expect(
      url.queryParameters.keys,
      containsAll(['data', 'rc4_hash__', 'signature', '_nonce']),
    );
    expect(server.body, isNull);
    expect(server.headers['region_tag'], 'us');
    // The request data is encrypted, not sent in the clear.
    expect(url.queryParameters['data'], isNot(contains('n66gl')));
  });

  test('the log never sees the token, key or query', () async {
    httpBackend = FaceServer({
      'code': 0,
      'result': {'watch_face': <String, Object?>{}},
    });
    await faceDetail(session, 'cn', model: 'm', id: 'x', firmware: '1');
    final all = trace.join('\n');
    expect(all, contains('watch.iot.mi.com/ops/v1/paidwatchface/detail'));
    expect(all, isNot(contains(_token)));
    expect(all, isNot(contains(_security)));
    expect(all, isNot(contains('_nonce')));
    expect('$session', isNot(contains(_token)));
  });

  test('a rejected sign-in is reported as expired', () async {
    httpBackend = FaceServer(const {}, status: 401);
    await expectLater(
      faceDetail(session, 'us', model: 'm', id: 'x', firmware: '1'),
      throwsA(isA<CloudException>().having((e) => e.expired, 'expired', true)),
    );
  });

  test('an unreadable reply is an error but keeps the sign-in', () async {
    httpBackend = FaceServer(const {}, raw: 'not base64 at all!');
    await expectLater(
      faceDetail(session, 'us', model: 'm', id: 'x', firmware: '1'),
      throwsA(isA<CloudException>().having((e) => e.expired, 'expired', false)),
    );
  });

  test('a plain JSON error reply is read and reported', () async {
    httpBackend = FaceServer(
      const {},
      raw: '{"code":-2,"message":"city not supported","result":null}',
    );
    await expectLater(
      faceDetail(session, 'us', model: 'm', id: 'x', firmware: '1'),
      throwsA(
        isA<CloudException>()
            .having((e) => e.expired, 'expired', false)
            .having((e) => '$e', 'text', contains('city not supported')),
      ),
    );
  });

  test('a face picture falls back to icon_list, then aod_icon', () {
    expect(
      facePicture({
        'icon': '',
        'icon_list': [
          {'icon': 'https://a.mi.com/list.png'},
        ],
        'aod_icon': 'https://a.mi.com/aod.png',
      }),
      Uri.parse('https://a.mi.com/list.png'),
    );
    expect(
      facePicture({'aod_icon': 'https://a.mi.com/aod.png'}),
      Uri.parse('https://a.mi.com/aod.png'),
    );
    expect(facePicture({'icon_list': 'nope'}), isNull);
  });

  test('only plain https picture addresses are used', () {
    expect(safeHttpsUrl('https://a.mi.com/x.png'), isNotNull);
    expect(safeHttpsUrl('http://a.mi.com/x.png'), isNull);
    expect(safeHttpsUrl('file:///etc/passwd'), isNull);
    expect(safeHttpsUrl('https://user:pw@a.mi.com/x.png'), isNull);
    expect(safeHttpsUrl(''), isNull);
    expect(safeHttpsUrl(42), isNull);
  });

  test('a session survives a JSON round trip; partial ones are refused', () {
    final back = CloudSession.fromJson(
      jsonDecode(jsonEncode(session.toJson())),
    );
    expect(back?.serviceToken, _token);
    expect(CloudSession.fromJson({'userId': '1'}), isNull);
    expect(CloudSession.fromJson('nope'), isNull);
  });

  group('store pictures', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

    test('recognises image files', () {
      expect(looksLikeImage(png), isTrue);
      expect(looksLikeImage(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0])), isTrue);
      expect(
        looksLikeImage(Uint8List.fromList([...'RIFF0000WEBP'.codeUnits])),
        isTrue,
      );
      expect(
        looksLikeImage(Uint8List.fromList(utf8.encode('<html>'))),
        isFalse,
      );
    });

    test('skips own faces, keeps images and counts the rest', () async {
      final kept = <String>[];
      final asked = <String>[];
      final r = await fetchStorePictures(
        ['960000001', 'a', 'b', 'c'],
        detail: (id) async {
          asked.add(id);
          return CloudFace(
            id,
            id == 'b' ? null : Uri.parse('https://x.mi.com/$id'),
          );
        },
        download: (url) async =>
            url.path == '/c' ? Uint8List.fromList(utf8.encode('<html>')) : png,
        keep: (id, _) async => kept.add(id),
      );
      expect(asked, ['a', 'b', 'c']);
      expect(kept, ['a']);
      expect((r.saved, r.missing), (1, 2));
    });

    test('downloads refuse plain http', () async {
      await expectLater(
        downloadPicture(Uri.parse('http://example.com/x.png')),
        throwsA(isA<PictureDownloadException>()),
      );
    });
  });

  test('face check asks for every installed face in one signed GET', () async {
    final server = FaceServer({
      'code': 0,
      'result': {
        'unavailable_id_list': <String>[],
        'watchface_list': [
          {
            'id': '111',
            'display_name': 'A',
            'icon': 'https://cdn.example/a.png',
          },
          {'id': '222', 'display_name': 'B', 'icon': 'http://insecure/b.png'},
        ],
      },
    });
    httpBackend = server;
    final faces = await faceCheck(
      session,
      'us',
      model: 'miwear.watch.n66gl',
      ids: const ['111', '222', '333'],
    );
    expect(server.url!.host, 'us.watch.iot.mi.com');
    expect(server.url!.path, '/ops/v1/paidwatchface/check');
    expect(faces['111']!.pictureUrl.toString(), 'https://cdn.example/a.png');
    expect(faces['222']!.pictureUrl, isNull);
    expect(faces.containsKey('333'), isFalse);
  });

  test(
    'pictures come from the face list first, detail only for the rest',
    () async {
      final asked = <String>[];
      final kept = <String>[];
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0]);
      final r = await fetchStorePictures(
        ['111', '333'],
        lookupAll: (ids) async => {
          '111': CloudFace('A', Uri.parse('https://cdn.example/a.png')),
        },
        detail: (id) async {
          asked.add(id);
          return const CloudFace('', null);
        },
        download: (_) async => png,
        keep: (id, _) async => kept.add(id),
      );
      expect(kept, ['111']);
      expect(asked, ['333']);
      expect(r.saved, 1);
      expect(r.missing, 1);
    },
  );
}
