/// Dart side of the Kotlin bridges (SppBridge, PhoneBridge).
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:openwear/cloud/http_backend.dart';
import 'package:openwear/protocol/device.dart';
import 'package:openwear/protocol/link.dart';

const _spp = MethodChannel('openwear/spp');
const _sppIncoming = EventChannel('openwear/spp/incoming');
const _phone = MethodChannel('openwear/phone');
const _phoneEvents = EventChannel('openwear/phone/events');
const _translate = MethodChannel('openwear/translate');

/// Translates Chinese [text] to [language] on the phone (ML Kit); null when
/// the language is unsupported or the model could not be downloaded.
Future<String?> translateOnDevice(String text, String language) async {
  try {
    return await _translate.invokeMethod<String>('translate', {
      'text': text,
      'language': language,
    });
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

class BondedDevice {
  const BondedDevice(this.name, this.address);
  final String name;
  final String address;
}

Future<List<BondedDevice>> bondedDevices() async {
  final list =
      await _spp.invokeListMethod<Map<Object?, Object?>>('bondedDevices') ??
      const [];
  return [
    for (final d in list) BondedDevice('${d['name']}', '${d['address']}'),
  ];
}

/// Classic Bluetooth SPP to the band through [_spp].
class SppTransport implements Transport {
  SppTransport(this.address);
  final String address;
  Stream<Uint8List>? _incoming;

  @override
  Future<void> connect() async {
    // Subscribe before connecting so no early bytes are lost.
    _incoming = _sppIncoming
        .receiveBroadcastStream()
        .map((e) => e as Uint8List)
        .handleError(
          (Object e) => throw LinkException(
            e is PlatformException ? e.message ?? e.code : '$e',
          ),
        )
        .asBroadcastStream();
    try {
      await _spp.invokeMethod<void>('connect', {'address': address});
    } on PlatformException catch (e) {
      throw LinkException('Bluetooth connect failed: ${e.message ?? e.code}');
    }
  }

  @override
  Stream<Uint8List> get incoming => _incoming ?? const Stream.empty();

  @override
  Future<void> write(Uint8List data) => _spp.invokeMethod<void>('write', data);

  @override
  Future<void> close() => _spp.invokeMethod<void>('close');
}

/// Something that happened on the phone that the band should hear about.
sealed class PhoneEvent {
  const PhoneEvent();
}

class PhoneNotification extends PhoneEvent {
  const PhoneNotification(
    this.package,
    this.appName,
    this.title,
    this.text,
    this.id,
    this.time, {
    this.key = '',
    this.canReply = false,
  });
  final String package;
  final String appName;
  final String title;
  final String text;
  final int id;
  final DateTime time;

  /// Android's notification key, also used to remove it from the band.
  final String key;

  /// It has a reply action that takes text.
  final bool canReply;
}

class PhoneNotificationRemoved extends PhoneEvent {
  const PhoneNotificationRemoved(this.package, this.id, {this.key = ''});
  final String package;
  final int id;
  final String key;
}

/// The phone stopped ringing for Find phone by itself (timed out, or the
/// screen was turned on), so the band should stop its search too.
class PhoneFindStopped extends PhoneEvent {
  const PhoneFindStopped();
}

class PhoneCall extends PhoneEvent {
  const PhoneCall(this.state, this.number, this.name);
  final String state; // ringing | offhook | idle
  final String number;
  final String name;
}

Stream<PhoneEvent> phoneEvents() =>
    _phoneEvents.receiveBroadcastStream().map((raw) {
      final e = raw as Map<Object?, Object?>;
      String s(String k) => '${e[k] ?? ''}';
      return switch (e['kind']) {
        'notification' => PhoneNotification(
          s('package'),
          s('appName'),
          s('title'),
          s('text'),
          (e['id'] as int?) ?? 0,
          DateTime.fromMillisecondsSinceEpoch((e['postTime'] as int?) ?? 0),
          key: s('key'),
          canReply: e['canReply'] == true,
        ),
        'notificationRemoved' => PhoneNotificationRemoved(
          s('package'),
          (e['id'] as int?) ?? 0,
          key: s('key'),
        ),
        'findPhoneStopped' => const PhoneFindStopped(),
        _ => PhoneCall(s('state'), s('number'), s('name')),
      };
    });

Future<ZoneInfo> phoneTimeZone() async {
  final z =
      await _phone.invokeMapMethod<String, Object?>('timeZone') ?? const {};
  return ZoneInfo(
    '${z['id'] ?? 'UTC'}',
    Duration(milliseconds: (z['standardOffsetMs'] as int?) ?? 0),
    Duration(milliseconds: (z['dstOffsetMs'] as int?) ?? 0),
  );
}

Future<Uint8List?> appIconRgba(String package, int size) => _phone
    .invokeMethod<Uint8List>('appIcon', {'package': package, 'size': size});

Future<bool> notificationAccessGranted() async =>
    await _phone.invokeMethod<bool>('notificationAccessGranted') ?? false;

Future<void> openNotificationAccessSettings() =>
    _phone.invokeMethod('openNotificationAccessSettings');
Future<bool> endPhoneCall() async =>
    await _phone.invokeMethod<bool>('endCall') ?? false;
Future<bool> silenceRinger() async =>
    await _phone.invokeMethod<bool>('silenceRinger') ?? false;

/// App version, phone model and Android version for the log header.
Future<Map<String, String>> deviceInfo() async =>
    (await _phone.invokeMapMethod<String, String>('deviceInfo')) ?? const {};

Future<void> openBluetoothSettings() =>
    _phone.invokeMethod('openBluetoothSettings');

/// Whether Find phone may show its page over the lock screen (Android 14+
/// lets users withhold full-screen pages).
Future<bool> findPhoneOverLockScreen() async =>
    await _phone.invokeMethod<bool>('findPhoneOverLockScreen') ?? true;

Future<void> openFindPhoneOverLockScreenSettings() =>
    _phone.invokeMethod('openFindPhoneOverLockScreenSettings');

/// Rings the phone loudly (find phone), or stops it.
Future<void> findPhone({required bool ring}) =>
    _phone.invokeMethod('findPhone', {'ring': ring});

/// Answers notification [key] with [text]; false when it has no reply.
Future<bool> replyToNotification(String key, String text) async =>
    await _phone.invokeMethod<bool>('replyNotification', {
      'key': key,
      'text': text,
    }) ??
    false;

/// Sends the app to the background instead of closing it.
Future<void> moveAppToBackground() =>
    const MethodChannel('openwear/app').invokeMethod('moveToBackground');

Future<void> startCompanionService() => _phone.invokeMethod('startService');
Future<void> stopCompanionService() => _phone.invokeMethod('stopService');

const _http = MethodChannel('openwear/http');

/// Cloud requests through Android's HTTP stack (system DNS, proxy, VPN, IPv6 fallback).
class AndroidHttpBackend implements HttpBackend {
  @override
  String get name => 'Android';

  @override
  Future<HttpReply> send(
    String method,
    Uri url, {
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async {
    try {
      final r = await _http
          .invokeMapMethod<String, Object?>('send', {
            'method': method,
            'url': '$url',
            'headers': headers,
            'body': body,
            'timeoutMs': timeout.inMilliseconds,
          })
          .timeout(
            timeout * 2 + const Duration(seconds: 5),
            onTimeout: () =>
                throw NetworkException('timeout', 'no answer from ${url.host}'),
          );
      if (r == null) throw const NetworkException('http', 'empty reply');
      return HttpReply(
        r['status']! as int,
        r['body'] as String? ?? '',
        location: r['location'] as String?,
        setCookies: (r['cookies'] as List?)?.cast<String>() ?? const [],
      );
    } on PlatformException catch (e) {
      throw NetworkException(e.code, e.message ?? e.code);
    }
  }
}

/// Active network, VPN and Private DNS state.
Future<Map<String, String>> networkInfo() async =>
    (await _http.invokeMapMethod<String, String>('networkInfo')) ?? const {};

/// Approximate last-known location and its place name; null without permission or fix.
Future<({double lat, double lon, String place})?> lastLocation() async {
  final m = await _phone.invokeMapMethod<String, Object?>('lastLocation');
  if (m == null) return null;
  return (
    lat: (m['lat']! as num).toDouble(),
    lon: (m['lon']! as num).toDouble(),
    place: m['place'] as String? ?? '',
  );
}

const _media = MethodChannel('openwear/media');
const _mediaEvents = EventChannel('openwear/media/events');

/// The phone's media player as the native side reports it.
class MediaSnapshot {
  const MediaSnapshot(this.raw);
  final Map<Object?, Object?> raw;

  String get state => raw['state'] as String? ?? 'none';
  String get title => raw['title'] as String? ?? '';
  String get artist => raw['artist'] as String? ?? '';
  String get app => raw['app'] as String? ?? '';
  int get volume => (raw['volume'] as num?)?.toInt() ?? 0;
  int get positionS => ((raw['positionMs'] as num?)?.toInt() ?? 0) ~/ 1000;
  int get durationS => ((raw['durationMs'] as num?)?.toInt() ?? 0) ~/ 1000;
}

Future<MediaSnapshot> mediaState() async => MediaSnapshot(
  await _media.invokeMapMethod<Object?, Object?>('state') ?? const {},
);

Stream<MediaSnapshot> mediaChanges() => _mediaEvents
    .receiveBroadcastStream()
    .map((e) => MediaSnapshot(e as Map<Object?, Object?>));

/// play | pause | next | previous | volume (0–100).
Future<void> mediaControl(String action, {int? volume}) =>
    _media.invokeMethod('control', {'action': action, 'volume': ?volume});

// --- Health Connect -------------------------------------------------------------

const _healthConnect = MethodChannel('openwear/health_connect');

/// "unavailable", "needsUpdate", or "missing:" + the kinds not allowed.
Future<String> healthConnectStatus() async =>
    await _healthConnect.invokeMethod<String>('status') ?? 'unavailable';

/// Opens Health Connect's permission screen; true when access was granted.
Future<bool> healthConnectRequest() async =>
    await _healthConnect.invokeMethod<bool>('requestPermissions') ?? false;

/// Opens OpenWear's page in Health Connect.
Future<void> healthConnectOpenSettings() =>
    _healthConnect.invokeMethod<bool>('openSettings');

/// Writes heart-rate records; each is {id, version, samples: [[ms, bpm]]}.
Future<int> healthConnectWriteHeartRate(
  List<Map<String, Object>> records,
) async =>
    await _healthConnect.invokeMethod<int>('writeHeartRate', {
      'records': records,
    }) ??
    0;

/// Writes typed records ({kind, id, version, start, end, value, ...}).
Future<int> healthConnectWriteRecords(
  List<Map<String, Object>> records,
) async =>
    await _healthConnect.invokeMethod<int>('writeRecords', {
      'records': records,
    }) ??
    0;

const _files = MethodChannel('openwear/files');

/// Saves [bytes] as Download/[folder]/[name]; returns where the user finds
/// it. With [replace], the app's earlier files in that folder are removed.
Future<String> saveToDownloads(
  String folder,
  String name,
  Uint8List bytes, {
  bool replace = true,
  String mime = 'application/octet-stream',
}) async =>
    await _files.invokeMethod<String>('saveToDownloads', {
      'folder': folder,
      'name': name,
      'bytes': bytes,
      'replace': replace,
      'mime': mime,
    }) ??
    '';
