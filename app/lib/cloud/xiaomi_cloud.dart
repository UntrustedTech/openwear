/// Xiaomi account login + the signed health-API calls used to bind a band.
///
/// The password is sent only to account.xiaomi.com (as its MD5, like the official
/// app) and is never stored.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:openwear/cloud/http_backend.dart';
import 'package:openwear/cloud/signing.dart';
import 'package:openwear/protocol/crypto.dart' show randomBytes;

const _passport = 'https://account.xiaomi.com/pass';
const _identity = 'https://account.xiaomi.com/identity';
const _sid = 'miothealth';
const _userAgent = 'Android-13-OpenWear APP/com.xiaomi.wearable APPV/3.59.2';
const _jsonPrefix = '&&&START&&&';
const _healthApp = '/healthapp';
const _timeout = Duration(seconds: 20);
const _wrongPassword = 70016;

/// Regions offered by Mi Fitness for the health servers.
const cloudRegions = {
  'us': 'United States', 'de': 'Europe', 'sg': 'Singapore', 'ru': 'Russia', //
  'i2': 'India', 'cn': 'China mainland',
};

class CloudException implements Exception {
  const CloudException(
    this.message, {
    this.network = false,
    this.expired = false,
  });
  final String message;

  /// True when the saved sign-in no longer works and the user must sign in.
  final bool expired;

  /// True when the server could not be reached at all (DNS, connect, timeout).
  final bool network;
  @override
  String toString() => message;
}

class CloudSession {
  const CloudSession(this.userId, this.ssecurity, this.serviceToken);
  final String userId;
  final String ssecurity;
  final String serviceToken;

  Map<String, String> toJson() => {
    'userId': userId,
    'ssecurity': ssecurity,
    'serviceToken': serviceToken,
  };

  /// Null when [json] is not a complete session.
  static CloudSession? fromJson(Object? json) {
    if (json is! Map) return null;
    final u = json['userId'], k = json['ssecurity'], t = json['serviceToken'];
    if (u is! String || k is! String || t is! String) return null;
    if (u.isEmpty || k.isEmpty || t.isEmpty) return null;
    return CloudSession(u, k, t);
  }

  /// Never shows the key or token.
  @override
  String toString() => 'CloudSession(user ${_mask(userId)})';
}

/// Asks the user for the code Xiaomi sent ("email" or "SMS").
typedef AskCode = Future<String> Function(String channel);

/// Cookies scoped by domain, so login cookies only go to Xiaomi's account hosts.
class _CookieJar {
  final _cookies = <String, Map<String, String>>{}; // domain → name → value

  /// Stores what the server set; like a browser, a cookie set expired or empty
  /// deletes it. Returns one log note per change (name, domain, length; never values).
  List<String> store(Uri uri, List<Cookie> cookies) {
    final changes = <String>[];
    final now = DateTime.now();
    for (final c in cookies) {
      final domain = (c.domain ?? uri.host).replaceFirst(RegExp(r'^\.'), '');
      final maxAge = c.maxAge, expires = c.expires;
      final expired =
          (maxAge != null && maxAge <= 0) ||
          (expires != null && expires.isBefore(now)) ||
          c.value.isEmpty ||
          c.value == 'EXPIRED';
      if (expired) {
        if (_cookies[domain]?.remove(c.name) != null) {
          changes.add('${c.name}@$domain deleted');
        }
        continue;
      }
      _cookies.putIfAbsent(domain, () => {})[c.name] = c.value;
      changes.add('${c.name}@$domain (${c.value.length} chars)');
    }
    return changes;
  }

  /// The cookie for [uri]'s host if there is one, else any domain's.
  String? valueFor(Uri uri, String name) {
    for (final entry in _cookies.entries) {
      final matches =
          uri.host == entry.key || uri.host.endsWith('.${entry.key}');
      final v = entry.value[name];
      if (matches && v != null) return v;
    }
    return value(name);
  }

  void set(String domain, String name, String value) =>
      _cookies.putIfAbsent(domain, () => {})[name] = value;

  String? value(String name) {
    for (final jar in _cookies.values) {
      final v = jar[name];
      if (v != null) return v;
    }
    return null;
  }

  String header(Uri uri) => [
    for (final entry in _cookies.entries)
      if (uri.host == entry.key || uri.host.endsWith('.${entry.key}'))
        for (final c in entry.value.entries) '${c.key}=${c.value}',
  ].join('; ');
}

/// Receives one line per server request: method, host, path, status, timing and
/// Xiaomi's result code/message. Never form data, tokens or keys.
void Function(String line)? cloudTrace;

void _trace(String line) => cloudTrace?.call(line);

/// Fields that are safe to show: result codes and human-readable messages.
const _safeFields = [
  'code',
  'result',
  'ret',
  'desc',
  'description',
  'tips',
  'message',
];

String _describeJson(Map<String, dynamic> json) {
  final parts = [
    for (final k in _safeFields)
      if (json[k] case final v? when v is! Map && v is! List) '$k=$v',
  ];
  final inner = json['result'];
  final keys = (inner is Map ? inner : json).keys.toList()..sort();
  return [...parts, 'fields: ${keys.join(', ')}'].join(' · ');
}

String _describeResponse(String text) {
  try {
    final t = text.startsWith(_jsonPrefix)
        ? text.substring(_jsonPrefix.length)
        : text;
    final json = jsonDecode(t);
    return json is Map<String, dynamic> ? _describeJson(json) : '';
  } on FormatException {
    return '';
  }
}

/// One request through [httpBackend], traced; network failures become [CloudException]s.
Future<HttpReply> _exchange(
  String method,
  Uri url,
  Map<String, String> headers, {
  String? form,
}) async {
  final clock = Stopwatch()..start();
  try {
    return await httpBackend.send(
      method,
      url,
      headers: {
        HttpHeaders.userAgentHeader: _userAgent,
        if (form != null)
          HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
        ...headers,
      },
      body: form,
      timeout: _timeout,
    );
  } on NetworkException catch (e) {
    _trace(
      '$method ${url.host}${url.path} ✗ ${e.kind} after '
      '${clock.elapsedMilliseconds} ms (${httpBackend.name}): ${e.message}',
    );
    throw CloudException(
      'Could not reach ${url.host} (${e.kind}: ${e.message}).',
      network: true,
    );
  }
}

String _head(String method, Uri url, HttpReply r, Stopwatch clock) =>
    '$method ${url.host}${url.path} → ${r.status} '
    '(${clock.elapsedMilliseconds} ms, ${r.body.length} B)';

class _Http {
  final jar = _CookieJar();

  /// GET/POST following redirects by hand so every hop's cookies are kept.
  Future<String> send(
    String method,
    Uri uri, {
    Map<String, String>? form,
  }) async {
    var url = uri;
    var verb = method;
    var body = form == null ? null : Uri(queryParameters: form).query;
    for (var hop = 0; hop < 10; hop++) {
      final clock = Stopwatch()..start();
      final cookie = jar.header(url);
      final rsp = await _exchange(verb, url, {
        if (cookie.isNotEmpty) HttpHeaders.cookieHeader: cookie,
      }, form: body);
      final parsed = [for (final c in rsp.setCookies) ?_parseCookie(c)];
      final changes = jar.store(url, parsed);
      final about = rsp.isRedirect ? 'redirect' : _describeResponse(rsp.body);
      _trace(
        '${_head(verb, url, rsp, clock)}${about.isEmpty ? '' : '  $about'}',
      );
      if (changes.isNotEmpty) _trace('  cookies: ${changes.join(', ')}');
      if (parsed.length < rsp.setCookies.length) {
        _trace(
          '  ${rsp.setCookies.length - parsed.length} cookie(s) from '
          '${url.host} could not be parsed',
        );
      }
      final location = rsp.location;
      if (rsp.isRedirect && location != null) {
        url = url.resolve(location);
        verb = 'GET';
        body = null;
        continue;
      }
      if (rsp.status >= 400) {
        throw CloudException('${url.path}: HTTP ${rsp.status}');
      }
      return rsp.body;
    }
    throw const CloudException('too many redirects');
  }

  void close() {}
}

Cookie? _parseCookie(String header) {
  try {
    return Cookie.fromSetCookieValue(header);
  } on FormatException {
    return null;
  }
}

Map<String, dynamic> _passportJson(String text) {
  final t = text.startsWith(_jsonPrefix)
      ? text.substring(_jsonPrefix.length)
      : text;
  return jsonDecode(t) as Map<String, dynamic>;
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Logs in; [deviceId] must be stable per install so Xiaomi asks for a code only once.
Future<CloudSession> login(
  String username,
  String password,
  String deviceId,
  AskCode askCode,
) async {
  final http = _Http();
  try {
    http.jar.set('account.xiaomi.com', 'sdkVersion', 'accountsdk-18.8.15');
    http.jar.set('account.xiaomi.com', 'deviceId', deviceId);
    final start = _passportJson(
      await http.send(
        'GET',
        Uri.parse('$_passport/serviceLogin')
            .replace(queryParameters: {'sid': _sid, '_json': 'true'}),
      ),
    );
    var auth = _passportJson(
      await http.send(
        'POST',
        Uri.parse('$_passport/serviceLoginAuth2'),
        form: {
          'user': username,
          'hash': _hex(md5Bytes(utf8.encode(password))).toUpperCase(),
          'sid': _sid,
          'callback': '${start['callback'] ?? ''}',
          'qs': '${start['qs'] ?? ''}',
          '_sign': '${start['_sign'] ?? ''}',
          '_json': 'true',
        },
      ),
    );
    final notificationUrl = auth['notificationUrl'];
    if (notificationUrl is String && notificationUrl.isNotEmpty) {
      _trace('Xiaomi wants to verify this device (2-step verification)');
      await _identityVerify(http, notificationUrl, askCode);
      _trace('Verification code accepted; this install is now trusted');
      auth = _passportJson(
        await http.send(
          'GET',
          Uri.parse('$_passport/serviceLogin')
              .replace(queryParameters: {'sid': _sid, '_json': 'true'}),
        ),
      );
    }
    final location = auth['location'], ssecurity = auth['ssecurity'];
    if ((auth['code'] ?? 0) != 0 ||
        location is! String ||
        ssecurity is! String) {
      final why = auth['code'] == _wrongPassword
          ? 'wrong account or password'
          : auth['desc'] ??
                auth['description'] ??
                'check the account and password';
      throw CloudException('Login failed: $why');
    }
    final sts = Uri.parse(location);
    await http.send('GET', sts);
    final token = http.jar.valueFor(sts, 'serviceToken');
    if (token == null) {
      throw const CloudException(
        'Login succeeded but no service token was issued',
      );
    }
    final userId = '${auth['userId']}';
    _trace(
      'Signed in, account ${_mask(userId)}, '
      'service token ${token.length} chars',
    );
    return CloudSession(userId, ssecurity, token);
  } finally {
    http.close();
  }
}

/// Xiaomi's extra verification: send an email (or SMS) code, ask the user, verify.
Future<void> _identityVerify(
  _Http http,
  String notificationUrl,
  AskCode askCode,
) async {
  final context = Uri.parse(notificationUrl).queryParameters['context'] ?? '';
  await http.send('GET', Uri.parse(notificationUrl));
  final options = _passportJson(
    await http.send(
      'GET',
      Uri.parse('$_identity/list').replace(
        queryParameters: {'sid': _sid, 'context': context, '_locale': 'en_US'},
      ),
    ),
  );
  final offered = (options['options'] as List?) ?? [options['flag']];
  final flag = [8, 4].firstWhere(offered.contains, orElse: () => 0);
  if (flag == 0) {
    throw CloudException(
      'Xiaomi asked for a verification method this app does not support ($offered). '
      'Sign in once on the web, then try again.',
    );
  }
  _trace('Verification methods offered: $offered; using flag $flag');
  final (send, verify, channel) = flag == 8
      ? ('sendEmailTicket', 'verifyEmail', 'email')
      : ('sendPhoneTicket', 'verifyPhone', 'SMS');
  String dc() => '${DateTime.now().millisecondsSinceEpoch}';
  final ick = http.jar.value('ick') ?? '';
  final sent = _passportJson(
    await http.send(
      'POST',
      Uri.parse('$_identity/auth/$send')
          .replace(queryParameters: {'_dc': dc()}),
      form: {'retry': '0', 'icode': '', '_json': 'true', 'ick': ick},
    ),
  );
  if ((sent['code'] ?? 0) != 0) {
    throw CloudException(
      'Could not send the $channel code: ${sent['tips'] ?? sent}',
    );
  }
  final code = (await askCode(channel)).trim();
  final result = _passportJson(
    await http.send(
      'POST',
      Uri.parse('$_identity/auth/$verify').replace(
        queryParameters: {'_flag': '$flag', '_json': 'true', '_dc': dc()},
      ),
      form: {
        '_flag': '$flag',
        'ticket': code,
        'trust': 'true',
        '_json': 'true',
        'ick': ick,
      },
    ),
  );
  final location = result['location'];
  if ((result['code'] ?? 0) != 0 || location is! String) {
    throw CloudException(
      'Verification failed: ${result['tips'] ?? 'wrong code?'}',
    );
  }
  await http.send('GET', Uri.parse(location));
}

// --- signed health API ---------------------------------------------------------------

String healthHost(String region) => region == 'cn'
    ? 'https://hlth.io.mi.com'
    : 'https://$region.hlth.io.mi.com';

Future<Map<String, dynamic>> _call(
  CloudSession s,
  String region,
  String path,
  Map<String, Object?> data, {
  String prefix = '',
  Map<String, String>? query,
}) => _signed(
  s,
  'POST',
  Uri.parse(healthHost(region) + prefix + path).replace(queryParameters: query),
  path,
  data,
);

/// The reply as JSON: normally encrypted, but some errors come back plain.
Map<String, dynamic>? _readReply(String body, String ssecurity, String nonce) {
  for (final read in [
    () => decryptResponse(body, ssecurity, nonce),
    () => body,
  ]) {
    try {
      final json = jsonDecode(read());
      if (json is Map<String, dynamic>) return json;
    } on FormatException {
      // Try the next form.
    }
  }
  return null;
}

/// One signed, encrypted request; [signPath] is the path Mi Fitness signs.
/// GET puts the encrypted params in the query, POST in the form body.
Future<Map<String, dynamic>> _signed(
  CloudSession s,
  String method,
  Uri uri,
  String signPath,
  Map<String, Object?> data, {
  Map<String, String> headers = const {},
}) async {
  final nonce = makeNonce(randomBytes(8), DateTime.now());
  final params = encryptParams(
    method,
    signPath,
    {'data': jsonEncode(data)},
    s.ssecurity,
    nonce,
  );
  final get = method == 'GET';
  final url = get
      ? uri.replace(queryParameters: {...uri.queryParameters, ...params})
      : uri;
  final clock = Stopwatch()..start();
  final rsp = await _exchange(method, url, {
    HttpHeaders.cookieHeader:
        'userId=${s.userId}; cUserId=${s.userId}; serviceToken=${s.serviceToken}; locale=en_US',
    ...headers,
  }, form: get ? null : Uri(queryParameters: params).query);
  // _head shows host and path only: the query holds the encrypted params.
  final head = _head(method, url, rsp, clock);
  if (rsp.status != 200) {
    // Error bodies are short plain messages (no secrets); show them.
    final why = rsp.body.length <= 300 ? rsp.body.trim() : '';
    _trace('$head${why.isEmpty ? '' : '  body: $why'}');
    if (rsp.status == 401 || rsp.status == 403) {
      throw const CloudException(
        'Your Xiaomi sign-in has expired. Sign in again.',
        expired: true,
      );
    }
    throw CloudException('$signPath: HTTP ${rsp.status}');
  }
  // Only 401/403 mean the sign-in was rejected; an unreadable body must not
  // sign the user out.
  final result = _readReply(rsp.body, s.ssecurity, nonce);
  if (result == null) {
    _trace('$head  (response could not be decrypted, ${rsp.body.length} B)');
    throw CloudException('$signPath: Xiaomi sent an unreadable answer');
  }
  _trace('$head  ${_describeJson(result)}');
  if ((result['code'] ?? 0) != 0) {
    throw CloudException('$signPath: ${result['message'] ?? result}');
  }
  final inner = result['result'];
  return inner is Map<String, dynamic> ? inner : result;
}

// --- watch faces ---------------------------------------------------------------------

/// Mi Fitness's watch-face server; regions other than China get a prefix.
String watchHost(String region) => region == 'cn'
    ? 'https://watch.iot.mi.com'
    : 'https://$region.watch.iot.mi.com';

const _facePath = '/ops/v1/paidwatchface/detail';

/// What Xiaomi's store says about one face.
class CloudFace {
  const CloudFace(this.name, this.pictureUrl);
  final String name;

  /// HTTPS address of the face's picture, or null when there is none.
  final Uri? pictureUrl;
}

/// An address is used only when it is plain HTTPS without credentials.
Uri? safeHttpsUrl(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  final u = Uri.tryParse(raw.trim());
  if (u == null || u.scheme != 'https' || u.host.isEmpty) return null;
  if (u.userInfo.isNotEmpty) return null;
  return u;
}

/// The store entry for face [id] on a band of [model] running [firmware].
Future<CloudFace> faceDetail(
  CloudSession s,
  String region, {
  required String model,
  required String id,
  required String firmware,
}) async {
  final r = await _signed(
    s,
    'GET',
    Uri.parse(watchHost(region) + _facePath),
    _facePath,
    {'model': model, 'id': id, 'firmware_version': firmware, 'ids': const []},
    headers: {'region_tag': region},
  );
  final face = r['watch_face'];
  if (face is! Map) return const CloudFace('', null);
  final picture = facePicture(face);
  if (picture == null) {
    final keys = face.keys.map((k) => '$k').toList()..sort();
    _trace('  face $id has no picture; fields: ${keys.join(', ')}');
  }
  return CloudFace('${face['display_name'] ?? ''}', picture);
}

const _checkPath = '/ops/v1/paidwatchface/check';

/// Store entries for the faces in [ids] in one call, by face id; the call
/// Mi Fitness makes for the faces installed on a band. Faces the store does
/// not know are left out.
Future<Map<String, CloudFace>> faceCheck(
  CloudSession s,
  String region, {
  required String model,
  required List<String> ids,
}) async {
  final r = await _signed(
    s,
    'GET',
    Uri.parse(watchHost(region) + _checkPath),
    _checkPath,
    {'model': model, 'id_list': ids},
    headers: {'region_tag': region},
  );
  return facesFromCheck(r);
}

/// The faces in a `paidwatchface/check` answer, by id.
Map<String, CloudFace> facesFromCheck(Map<String, dynamic> result) {
  final list = result['watchface_list'];
  if (list is! List) return const {};
  return {
    for (final f in list)
      if (f is Map && f['id'] != null)
        '${f['id']}': CloudFace('${f['display_name'] ?? ''}', facePicture(f)),
  };
}

/// A store face's picture, in the order Mi Fitness looks: `icon`, then the
/// first of `icon_list`, then the always-on-display `aod_icon`.
Uri? facePicture(Map<dynamic, dynamic> face) {
  final list = face['icon_list'];
  return safeHttpsUrl(face['icon']) ??
      (list is List
          ? list
                .whereType<Map<dynamic, dynamic>>()
                .map(
                  (i) => safeHttpsUrl(i['icon']) ?? safeHttpsUrl(i['aod_icon']),
                )
                .whereType<Uri>()
                .firstOrNull
          : null) ??
      safeHttpsUrl(face['aod_icon']);
}

String _b64url(List<int> b) => base64Url.encode(b);
Uint8List _unb64url(String s) => base64Url.decode(base64Url.normalize(s));

class ServerHello {
  const ServerHello(
    this.bindIndex,
    this.bindDid,
    this.serverPub,
    this.serverSign,
    this.serverRandom,
  );
  final String bindIndex;
  final String bindDid;
  final Uint8List serverPub;
  final Uint8List serverSign;
  final Uint8List serverRandom;
}

class ServerKeys {
  const ServerKeys(this.deviceKey, this.oobCode, this.bindKey);
  final Uint8List deviceKey;
  final int oobCode;
  final String bindKey;
}

Future<ServerHello> bindHello(
  CloudSession s,
  String region, {
  required int verifyMode,
  required String model,
  required String mac,
  required String sn,
  required String did,
  required List<int> deviceRandom,
  required String phoneId,
}) async {
  final r = await _call(s, region, '/bind/hello', {
    'mode': verifyMode,
    'model': model,
    'mac': mac,
    'randomMac': mac,
    'phone_id': phoneId, //
    'node_id': '',
    'sn': sn,
    'did': did,
    'random_d': _b64url(deviceRandom),
    'is_support_find': false,
  }, prefix: _healthApp);
  return ServerHello(
    '${r['bind_index']}',
    '${r['bind_did']}',
    _unb64url('${r['pub_s']}'),
    _unb64url('${r['sign_s']}'),
    _unb64url('${r['random_s']}'),
  );
}

Future<ServerKeys> bindEcdh(
  CloudSession s,
  String region,
  ServerHello hello,
  List<int> devicePub,
  List<int> deviceSign,
) async {
  final r = await _call(s, region, '/bind/ecdh', {
    'bind_index': hello.bindIndex, 'bind_did': hello.bindDid, //
    'pub_d': _b64url(devicePub), 'sign_d': _b64url(deviceSign),
  }, prefix: _healthApp);
  return ServerKeys(
    _unb64url('${r['device_key']}'),
    int.tryParse('${r['oob_code'] ?? 0}') ?? 0,
    '${r['bind_key']}',
  );
}

/// Mi Fitness treats `ret == 1` as success.
Future<void> bindConfirm(
  CloudSession s,
  String region,
  ServerHello hello,
  List<int> bindSign,
) async {
  final r = await _call(
    s,
    region,
    '/bind/bind',
    {
      'bind_index': hello.bindIndex,
      'bind_did': hello.bindDid,
      'bind_sign': _b64url(bindSign), //
    },
    prefix: _healthApp,
    query: {'locale': 'en_US'},
  );
  if (r['ret'] != 1) {
    throw CloudException('Xiaomi refused to finish the bind: $r');
  }
}

// --- weather city -------------------------------------------------------------------

/// The city Xiaomi's weather service files a place under: the band's weather
/// app only knows cities by these keys (`accu:349530`).
class WeatherCityInfo {
  const WeatherCityInfo(this.key, this.name);
  final String key;
  final String name;
}

/// Mi Fitness's `weather/get_weather_info_v3` (signed GET), read only for the
/// city key and name of [lat], [lon].
Future<WeatherCityInfo?> weatherCity(
  CloudSession s,
  String region, {
  required double lat,
  required double lon,
  required String model,
  required String firmware,
}) async {
  const path = '/weather/get_weather_info_v3';
  final r = await _signed(
    s,
    'GET',
    Uri.parse(healthHost(region) + _healthApp + path)
        .replace(queryParameters: {'locale': 'en_US'}),
    path,
    {
      'latitude': double.parse(lat.toStringAsFixed(2)),
      'longitude': double.parse(lon.toStringAsFixed(2)),
      'model': model,
      'fw_ver': firmware,
      'get_current': true,
      'get_aqi': false,
      'get_alerts': false,
      'get_indices': false,
      'get_daily_forecast': false,
      'get_hourly_forecast': false,
      'get_city_location': true,
    },
  );
  final key = '${r['locationKey'] ?? ''}';
  if (key.isEmpty) return null;
  final name = '${r['city_name'] ?? r['location_name'] ?? ''}'.trim();
  return WeatherCityInfo(key, name);
}

// --- firmware -----------------------------------------------------------------------

/// Mi Fitness 3.59.2's version code, which the update server asks for.
const miFitnessVersionCode = 359002;

/// A firmware release offered for one band.
class FirmwareRelease {
  const FirmwareRelease({
    required this.version,
    required this.url,
    required this.md5,
    this.changeLog = '',
    this.size = 0,
    this.force = false,
  });

  /// From a `device/latest_ver` result, or null when it is not newer than
  /// [current]. The server does not say; like Mi Fitness, the versions are
  /// compared here. Mi Fitness prefers the smaller diff package, which only
  /// applies on top of the current firmware; OpenWear always takes the full
  /// package so the saved copy can also restore the band later.
  static FirmwareRelease? fromJson(Map<String, dynamic> r, String current) {
    final version = '${r['version'] ?? ''}';
    final url = safeHttpsUrl(r['safe_url']);
    final md5 = '${r['md5'] ?? ''}';
    if (compareFirmware(version, current) <= 0 || url == null) return null;
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(md5)) return null;
    return FirmwareRelease(
      version: version,
      url: url,
      md5: md5.toLowerCase(),
      changeLog: '${r['changeLog'] ?? ''}'.trim(),
      size: int.tryParse('${r['fileSize'] ?? 0}') ?? 0,
      force: r['force'] == true,
    );
  }

  final String version;
  final Uri url;
  final String md5;
  final String changeLog;
  final int size;
  final bool force;
}

/// Mi Fitness's compareFirmwareVersion2: 1 when [a] is newer than [b], -1
/// when older, 0 when equal or either is not `x.y.z`.
int compareFirmware(String a, String b) {
  final re = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');
  final x = re.firstMatch(a), y = re.firstMatch(b);
  if (x == null || y == null) return 0;
  for (var i = 1; i <= 3; i++) {
    final c = int.parse(x[i]!).compareTo(int.parse(y[i]!));
    if (c != 0) return c;
  }
  return 0;
}

/// Asks Xiaomi's update server for a newer firmware than [firmware].
Future<FirmwareRelease?> latestFirmware(
  CloudSession s,
  String region, {
  required String did,
  required String model,
  required String firmware,
}) async {
  final r = await _call(
    s,
    region,
    '/device/latest_ver',
    {
      'did': did,
      'model': model,
      'platform': 'android',
      'app_level': '$miFitnessVersionCode',
      'fw_ver': firmware,
      'channel': 'prod',
    },
    prefix: _healthApp,
    query: {'locale': 'en_US'},
  );
  _trace('Update server offers firmware ${r['version'] ?? 'none'}');
  return FirmwareRelease.fromJson(r, firmware);
}

Future<List<Map<String, dynamic>>> listDevices(
  CloudSession s,
  String region,
) async {
  final devices = <Map<String, dynamic>>[];
  String? next;
  do {
    final page = await _call(s, region, '/app/v1/source/get_source_list', {
      'page_size': 50,
      'page_start': ?next,
    });
    final list =
        (page['list'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    devices.addAll(list);
    final n = page['page_next'];
    next = n is String && n.isNotEmpty && list.isNotEmpty ? n : null;
  } while (next != null);
  return devices;
}

/// The session key Mi Fitness uses for a cloud-bound band: `encrypt_key` in its device record.
Uint8List? sessionKeyFromDevices(
  List<Map<String, dynamic>> devices,
  String mac,
  String model,
) {
  for (final raw in _deviceValues(devices, mac, model, 'encrypt_key')) {
    final key = _parseKey(raw);
    if (key != null) return key;
  }
  return null;
}

/// The band's cloud device id: `sid` in its device record (Mi Fitness's
/// Device.did is serialized as `sid`).
String? didFromDevices(
  List<Map<String, dynamic>> devices,
  String mac,
  String model,
) {
  for (final d in _bandRecords(devices, mac, model)) {
    final sid = d['sid'];
    if (sid != null && '$sid'.isNotEmpty) return '$sid';
  }
  return null;
}

/// The band's device records: those that mention [mac] first, then those
/// of the same [model].
List<Map<String, dynamic>> _bandRecords(
  List<Map<String, dynamic>> devices,
  String mac,
  String model,
) {
  final wanted = mac.replaceAll(':', '').toLowerCase();
  bool hasMac(Map<String, dynamic> d) => _walk(d).any(
    (kv) =>
        kv.$2 is String &&
        (kv.$2 as String).replaceAll(':', '').toLowerCase() == wanted,
  );
  return [
    ...devices.where(hasMac),
    ...devices.where((d) => d['model'] == model),
  ];
}

/// Non-empty values named [key] anywhere in the band's device records.
/// Records nest JSON as strings, so every value is searched.
Iterable<String> _deviceValues(
  List<Map<String, dynamic>> devices,
  String mac,
  String model,
  String key,
) sync* {
  for (final d in _bandRecords(devices, mac, model)) {
    for (final kv in _walk(d)) {
      final v = kv.$2;
      if (kv.$1 == key && v != null && '$v'.isNotEmpty) yield '$v';
    }
  }
}

Iterable<(String, Object?)> _walk(Object? v, [String key = '']) sync* {
  if (v is String && (v.startsWith('{') || v.startsWith('['))) {
    try {
      v = jsonDecode(v);
    } on FormatException {
      // plain string
    }
  }
  if (v is Map) {
    for (final e in v.entries) {
      yield* _walk(e.value, '${e.key}');
    }
  } else if (v is List) {
    for (final x in v) {
      yield* _walk(x, key);
    }
  } else {
    yield (key, v);
  }
}

Uint8List? _parseKey(String raw) {
  final hex = RegExp(r'^[0-9a-fA-F]{32}$');
  if (hex.hasMatch(raw)) {
    return Uint8List.fromList([
      for (var i = 0; i < 32; i += 2)
        int.parse(raw.substring(i, i + 2), radix: 16),
    ]);
  }
  try {
    final b = base64.decode(raw);
    return b.length == 16 ? b : null;
  } on FormatException {
    return null;
  }
}

/// Keeps only the last 4 characters of an account id for the log.
String _mask(String id) => id.length <= 4
    ? id
    : '${'•' * (id.length - 4)}${id.substring(id.length - 4)}';
