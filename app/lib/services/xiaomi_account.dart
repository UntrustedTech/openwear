/// The user's Xiaomi sign-in, kept so OpenWear can fetch watch-face pictures.
///
/// Only the session (user id, session key and service token) is stored, in
/// Android's encrypted storage (Keystore-backed). The password is never
/// stored, and nothing here is written to the log.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openwear/protocol/crypto.dart' show randomBytes;
import 'package:openwear/cloud/xiaomi_cloud.dart' as cloud;
import 'package:openwear/services/band_log.dart';

/// Signs in to Xiaomi; swapped out in tests.
typedef CloudLogin = Future<cloud.CloudSession> Function(
  String user,
  String password,
  String deviceId,
  cloud.AskCode askCode,
);

class XiaomiAccount extends ChangeNotifier {
  XiaomiAccount({
    required this.log,
    FlutterSecureStorage? storage,
    CloudLogin? login,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _login = login ?? cloud.login;

  static const _kSession = 'cloud.session', _kDeviceId = 'pair.cloudDeviceId';

  final BandLog log;
  final FlutterSecureStorage _storage;
  final CloudLogin _login;

  cloud.CloudSession? _session;
  String region = 'us';

  cloud.CloudSession? get session => _session;
  bool get signedIn => _session != null;

  /// Reads the saved sign-in, if any. A damaged entry is deleted.
  Future<void> load() async {
    final String? raw;
    try {
      raw = await _storage.read(key: _kSession);
    } on PlatformException catch (e) {
      // Keystore entries can be lost (e.g. after a restore); start fresh.
      log.warn('Saved Xiaomi sign-in could not be decrypted (${e.code})');
      await _forgetQuietly();
      return;
    }
    if (raw == null || raw.isEmpty) return;
    try {
      final json = jsonDecode(raw);
      final s = cloud.CloudSession.fromJson(json);
      final r = json is Map ? json['region'] : null;
      if (s == null || r is! String || !cloud.cloudRegions.containsKey(r)) {
        throw const FormatException('incomplete session');
      }
      _session = s;
      region = r;
    } on FormatException {
      log.warn('Saved Xiaomi sign-in was damaged and has been removed');
      await _forgetQuietly();
    }
    notifyListeners();
  }

  Future<void> _forgetQuietly() async {
    try {
      await _storage.delete(key: _kSession);
    } on PlatformException {
      // Nothing more to do; the next sign-in overwrites it.
    }
  }

  /// A device id that stays the same for this phone, as Mi Fitness has.
  Future<String> deviceId() async {
    final existing = await _storage.read(key: _kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = randomBytes(8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await _storage.write(key: _kDeviceId, value: id);
    return id;
  }

  /// Signs in and keeps the session; the password is used once and dropped.
  Future<cloud.CloudSession> signIn(
    String user,
    String password,
    String region,
    cloud.AskCode askCode,
  ) async {
    if (!cloud.cloudRegions.containsKey(region)) {
      throw cloud.CloudException('Unknown server region "$region".');
    }
    final s = await _login(user.trim(), password, await deviceId(), askCode);
    await keep(s, region);
    return s;
  }

  /// Saves [s] for [region].
  Future<void> keep(cloud.CloudSession s, String region) async {
    _session = s;
    this.region = region;
    await _storage.write(
      key: _kSession,
      value: jsonEncode({...s.toJson(), 'region': region}),
    );
    log.app('Xiaomi sign-in saved on this phone (encrypted)');
    notifyListeners();
  }

  /// Forgets the saved sign-in.
  Future<void> signOut() async {
    _session = null;
    await _storage.delete(key: _kSession);
    log.app('Signed out of Xiaomi; the saved sign-in was deleted');
    notifyListeners();
  }

  /// Called when Xiaomi rejects the saved session.
  Future<void> expired() async {
    if (_session == null) return;
    log.warn('Xiaomi sign-in expired; sign in again to fetch face pictures');
    await signOut();
  }
}
