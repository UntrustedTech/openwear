/// In-app first-time pairing of a factory-reset band, with or without a Xiaomi account.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openwear/cloud/http_backend.dart';
import 'package:openwear/cloud/network_check.dart';
import 'package:openwear/cloud/xiaomi_cloud.dart' as cloud;
import 'package:openwear/platform/android_bridge.dart';
import 'package:openwear/protocol/bind.dart';
import 'package:openwear/protocol/crypto.dart';
import 'package:openwear/protocol/link.dart';
import 'package:openwear/protocol/session_auth.dart';
import 'package:openwear/services/band_service.dart';

const _kPhoneId = 'pair.phoneId';
const _tapTimeout = Duration(seconds: 70);

/// Xiaomi's side of an account bind; swapped for a fake in tests.
abstract interface class BindCloud {
  String get userId;
  Future<cloud.ServerHello> hello(BindInfo info, String mac, String phoneId);
  Future<cloud.ServerKeys> ecdh(
    cloud.ServerHello hello,
    List<int> pub,
    List<int> sign,
  );
  Future<void> confirm(cloud.ServerHello hello, List<int> bindSign);
  Future<Uint8List?> sessionKey(String mac, String model);
}

class XiaomiBindCloud implements BindCloud {
  XiaomiBindCloud(this.session, this.region);
  final cloud.CloudSession session;
  final String region;

  @override
  String get userId => session.userId;

  @override
  Future<cloud.ServerHello> hello(BindInfo info, String mac, String phoneId) =>
      cloud.bindHello(
        session,
        region,
        verifyMode: info.verifyMode,
        model: info.model,
        mac: mac,
        sn: info.sn,
        did: info.did,
        deviceRandom: info.deviceRandom,
        phoneId: phoneId,
      );

  @override
  Future<cloud.ServerKeys> ecdh(
    cloud.ServerHello hello,
    List<int> pub,
    List<int> sign,
  ) => cloud.bindEcdh(session, region, hello, pub, sign);

  @override
  Future<void> confirm(cloud.ServerHello hello, List<int> bindSign) =>
      cloud.bindConfirm(session, region, hello, bindSign);

  @override
  Future<Uint8List?> sessionKey(String mac, String model) async =>
      cloud.sessionKeyFromDevices(
        await cloud.listDevices(session, region),
        mac,
        model,
      );
}

class PairingException implements Exception {
  const PairingException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PairingService extends ChangeNotifier {
  PairingService(
    this.band, {
    FlutterSecureStorage? storage,
    Transport Function(String address)? transportFor,
    Future<void> Function()? onPaired,
    this.describeNetwork,
  }) : _onPaired = onPaired ?? band.connect,
       _storage = storage ?? const FlutterSecureStorage(),
       _transportFor = transportFor ?? SppTransport.new;

  final BandService band;
  final FlutterSecureStorage _storage;
  final Transport Function(String address) _transportFor;
  final Future<void> Function() _onPaired;

  /// Network type, VPN and Private DNS for the network check (Android only).
  final Future<Map<String, String>> Function()? describeNetwork;

  BindCloud? account;
  String status = '';
  bool busy = false;
  bool waitingForTap = false;
  final _clock = Stopwatch();
  String _stepName = '';

  void _step(String message, {bool tap = false}) {
    status = message;
    _stepName = message;
    waitingForTap = tap;
    band.log.app('Pairing: $message  (+${_seconds(_clock)})');
    notifyListeners();
  }

  Future<String> _stableId(String key, int bytes) async {
    final existing = await _storage.read(key: key);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _hex(randomBytes(bytes));
    await _storage.write(key: key, value: id);
    return id;
  }

  /// Signs in to Xiaomi; [askCode] is called when the account needs a 2FA code.
  Future<void> signIn(
    String username,
    String password,
    String region,
    cloud.AskCode askCode,
  ) => _run(() async {
    _step('Signing in to Xiaomi…');
    cloud.cloudTrace = (line) => band.log.app('Xiaomi: $line');
    final cloud.CloudSession session;
    try {
      // Kept (encrypted) so face pictures can be fetched later.
      session = await band.account.signIn(username, password, region, askCode);
    } on cloud.CloudException catch (e) {
      if (e.network) await _diagnose();
      rethrow;
    }
    account = XiaomiBindCloud(session, region);
    _step('Signed in');
  });

  /// Runs the network check and puts the findings in the live log.
  Future<void> checkNetwork() => _run(() async {
    _step('Checking the connection to Xiaomi…');
    await _diagnose();
    _step('Connection check finished — see the live log');
  });

  Future<void> _diagnose() async {
    band.log.app('Network check (${httpBackend.name} HTTP)…');
    final lines = await networkCheck(describeNetwork: describeNetwork);
    final conclusion = lines.removeLast();
    final failed = lines.any((l) => l.contains('✗') || l.contains('blocked'));
    final log = failed ? band.log.warn : band.log.app;
    log(conclusion, detail: lines.join('\n'));
  }

  void signOut() {
    account = null;
    status = '';
    notifyListeners();
  }

  /// Binds the band (already Bluetooth-paired with the phone) and saves it.
  Future<void> pair(BondedDevice device) => _run(() async {
    final mac = device.address.toUpperCase();
    _step('Connecting to ${device.name}…');
    final link = Link(_transportFor(mac));
    final logSub = link.events.listen(band.log.onLinkEvent);
    try {
      await link.open();
      final userId = account?.userId ?? '';
      _step('Reading band info…');
      final info = parseBindInfo(
        await link.request(
          bindInfoRequest(userId),
          encrypted: false,
          timeout: const Duration(seconds: 15),
        ),
      );
      band.log.app(
        'Band ${info.model}: ${_verifyModes[info.verifyMode] ?? 'bind mode ${info.verifyMode}'}',
        detail: [
          'model: ${info.model}',
          'MAC reported by band: ${info.mac.isEmpty ? '(none)' : info.mac}',
          'serial: ${_maskSerial(info.sn)}',
          'verify mode: ${info.verifyMode} (${_verifyModes[info.verifyMode] ?? 'unknown'})',
          'confirmation: ${info.oobMode} (${_oobModes[info.oobMode] ?? 'unknown'})',
          'device random: ${info.deviceRandom.length} bytes',
          'signed in to Xiaomi: ${account != null}',
        ].join('\n'),
      );
      final phoneId = await _stableId(_kPhoneId, 8);
      final (key, appDeviceId) = info.verifyMode == verifyModeLocal
          ? await _bindLocal(link, info, mac, userId, phoneId)
          : await _bindAccount(link, info, mac, phoneId);
      await link.close();
      await band.savePairing(
        mac,
        device.name,
        _hex(key),
        appDeviceId: appDeviceId,
      );
      _step('Paired with ${device.name}');
    } finally {
      await logSub.cancel();
      await link.close();
    }
    unawaited(_onPaired());
  });

  Future<(Uint8List, String)> _bindAccount(
    Link link,
    BindInfo info,
    String mac,
    String phoneId,
  ) async {
    final server = account;
    if (server == null) {
      throw const PairingException(
        'This band can only be paired through a Xiaomi account. Sign in first.',
      );
    }
    final bind = AccountBind(server.userId);
    _step('Asking Xiaomi to vouch for the band…');
    final hello = await server.hello(info, mac, phoneId);
    final (pub, sign) = bind.onVerifyServerResponse(
      await link.request(
        bind.verifyServer(
          hello.serverPub,
          hello.serverSign,
          hello.serverRandom,
        ),
        encrypted: false,
      ),
    );
    final keys = await server.ecdh(hello, pub, sign);
    _step('Tap the check mark on the band to confirm', tap: true);
    final confirmed = await link.request(
      bind.confirm(keys.deviceKey, keys.oobCode, keys.bindKey),
      encrypted: false,
      timeout: _tapTimeout,
    );
    _step('Confirmed on the band, finishing…');
    await server.confirm(hello, bind.onConfirmResponse(confirmed));
    bind.onResultResponse(
      await link.request(bind.bindResult(), encrypted: false),
    );
    _step('Fetching the band key from your account…');
    final key = await server.sessionKey(mac, info.model);
    if (key == null) {
      band.log.warn('No encrypt_key in the device list; using the bind key');
    } else {
      band.log.app('Band key found in your Xiaomi device list (16 bytes)');
    }
    return (key ?? keys.deviceKey, '');
  }

  Future<(Uint8List, String)> _bindLocal(
    Link link,
    BindInfo info,
    String mac,
    String userId,
    String phoneId,
  ) async {
    final bind = LocalBind(userId: userId, mac: mac, phoneId: phoneId);
    _step('Exchanging keys with the band…');
    final confirm = bind.onHelloResponse(
      await link.request(bind.hello(), encrypted: false),
    );
    if (info.oobMode == 3) {
      _step('Tap the check mark on the band to confirm', tap: true);
    }
    final result = bind.onConfirmResponse(
      await link.request(confirm, encrypted: false, timeout: _tapTimeout),
    );
    bind.onResultResponse(await link.request(result, encrypted: false));
    return (bind.authKey, bind.deviceId);
  }

  Future<void> _run(Future<void> Function() body) async {
    if (busy) return;
    busy = true;
    _clock
      ..reset()
      ..start();
    _stepName = '';
    notifyListeners();
    try {
      await body();
      band.log.app('Pairing: done in ${_seconds(_clock)}');
    } on TimeoutException {
      _fail(
        'The band did not answer in time. Keep it awake and close to the phone, then retry.',
      );
    } on HandshakeException catch (e) {
      _fail(e.message);
    } on cloud.CloudException catch (e) {
      _fail(e.message);
    } on LinkException catch (e) {
      _fail(e.message);
    } on PairingException catch (e) {
      _fail(e.message);
    } on Exception catch (e, stack) {
      band.log.error('Unexpected pairing error', e, stack);
      _fail('$e');
    } finally {
      _clock.stop();
      busy = false;
      waitingForTap = false;
      notifyListeners();
    }
  }

  void _fail(String message) {
    band.log.warn(
      'Pairing failed: $message',
      detail:
          'at step: ${_stepName.isEmpty ? '(start)' : _stepName}\n'
          'after: ${_seconds(_clock)}',
    );
    status = message;
    throw PairingException(message);
  }
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

const _verifyModes = {
  1: 'account bind (Xiaomi server)',
  2: 'local bind (no account)',
};
const _oobModes = {0: 'none', 2: 'code shown on band', 3: 'tap ✓ on band'};

String _seconds(Stopwatch s) =>
    '${(s.elapsedMilliseconds / 1000).toStringAsFixed(1)} s';

String _maskSerial(String sn) => sn.length <= 4
    ? (sn.isEmpty ? '(none)' : sn)
    : '${'•' * (sn.length - 4)}${sn.substring(sn.length - 4)}';
