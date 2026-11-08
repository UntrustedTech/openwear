/// Owns the band connection and everything that flows over it.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openwear/faces/catalog.dart';
import 'package:openwear/faces/face_binary.dart';
import 'package:openwear/platform/android_bridge.dart';
import 'package:openwear/cloud/xiaomi_cloud.dart' as cloud;
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/daily_record.dart';
import 'package:openwear/protocol/daily_report.dart';
import 'package:openwear/protocol/device.dart';
import 'package:openwear/protocol/face_install.dart';
import 'package:openwear/protocol/fitness.dart' as fitness;
import 'package:openwear/protocol/health_records.dart';
import 'package:openwear/protocol/l1.dart';
import 'package:openwear/protocol/link.dart';
import 'package:openwear/protocol/link_events.dart';
import 'package:openwear/protocol/manual_measurement.dart';
import 'package:openwear/protocol/mass.dart';
import 'package:openwear/protocol/profile.dart';
import 'package:openwear/protocol/screenshot.dart';
import 'package:openwear/protocol/session_auth.dart';
import 'package:openwear/protocol/settings.dart' as settings;
import 'package:openwear/protocol/models.dart';
import 'package:openwear/protocol/sleep.dart';
import 'package:openwear/protocol/sleep_settings.dart';
import 'package:openwear/protocol/weather.dart';
import 'package:openwear/services/appearance.dart';
import 'package:openwear/services/band_apps_service.dart';
import 'package:openwear/services/at_rest.dart';
import 'package:openwear/services/band_log.dart';
import 'package:openwear/services/custom_face_previews.dart';
import 'package:openwear/services/face_names.dart';
import 'package:openwear/services/face_previews.dart';
import 'package:openwear/services/firmware_update.dart';
import 'package:openwear/services/store_face_pictures.dart' as store;
import 'package:openwear/services/xiaomi_account.dart';
import 'package:openwear/services/band_app_link.dart';
import 'package:openwear/services/data_export.dart';
import 'package:openwear/services/health_connect.dart';
import 'package:openwear/services/health_inbox.dart';
import 'package:openwear/services/phone_sync.dart';
import 'package:openwear/services/health_connect_records.dart';
import 'package:openwear/services/sleep_log.dart';
import 'package:openwear/services/units.dart';
import 'package:path_provider/path_provider.dart';

enum BandState { notPaired, disconnected, connecting, connected }

class BandService extends ChangeNotifier {
  BandService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _kAddress = 'band.address',
      _kName = 'band.name',
      _kKey = 'band.authKey',
      _kAppDeviceId = 'band.appDeviceId',
      _kWeather = 'settings.weather',
      _kFahrenheit = 'settings.fahrenheit',
      _kUnits = 'settings.units',
      _kClock24 = 'settings.clock24',
      _kProfile = 'settings.profile',
      _kHealthConnect = 'settings.healthConnect',
      _kNoAutoScreenshots = 'faces.noAutoScreenshots',
      _kSyncEvery = 'settings.syncEverySeconds';

  final FlutterSecureStorage _storage;
  Link? _link;
  StreamSubscription<Command>? _commandSub;
  StreamSubscription<PhoneEvent>? _phoneSub;
  final _assembler = fitness.FileAssembler();
  final _files = StreamController<Uint8List>.broadcast();
  bool _callRinging = false;

  BandState state = BandState.notPaired;
  String address = '';
  String name = '';
  String? error;
  int? battery;

  /// The band's own description of itself (model, firmware…), from 2/2.
  BandInfo? info;

  /// The connected model, from its Bluetooth name or reported model id.
  WearModel? get wearModel =>
      wearModelFor(bluetoothName: name, modelId: info?.model);
  int? heartRate; // null = not streaming, 0 = no reading yet

  /// Heart-rate samples recorded by the band (live sessions and synced files),
  /// newest last; capped at [hrHistoryLimit].
  final hrHistory = SplayTreeMap<DateTime, int>();
  static const hrHistoryLimit = 24 * 3600;
  final _newSamples = StreamController<List<HrSample>>.broadcast();

  /// Samples not seen before, for export (Health Connect).
  Stream<List<HrSample>> get newHeartRateSamples => _newSamples.stream;
  List<WatchFace> faces = const [];

  /// Live log of everything the band and the app exchange.
  final log = BandLog();

  /// Sleep the band recorded over the past week.
  final sleepLog = SleepLog();

  /// The latest night's sleep, if it ended within the past day.
  SleepSession? get lastNight => sleepLog.lastNight(DateTime.now());

  /// Weather and music for the band.
  late final phone = PhoneSync(log: log)..addListener(notifyListeners);

  /// Seals health files kept on the phone (lib/services/at_rest.dart).
  late final atRest = AtRest(storage: _storage);

  bool get connected => state == BandState.connected;

  /// Most recent notification forwarded to the band (for the preview).
  ({String app, String title, DateTime time})? lastNotification;

  WatchFace? get activeFace {
    for (final f in faces) {
      if (f.active) return f;
    }
    return null;
  }

  /// OpenWear's own app on the band (band-app/ in the repo).
  late final bandApp = BandAppLink(
    log: log,
    send: (c) async => _link?.send(c),
    snapshot: _bandAppSnapshot,
    actions: BandAppActions(
      findPhone: (ring) => findPhone(ring: ring),
      sync: () async {
        await syncHealth();
        await refreshToday();
      },
      sendWeather: () => phone.sendWeather(force: true),
      reply: replyToNotification,
    ),
  );

  BandAppSnapshot _bandAppSnapshot() {
    final t = today;
    final night = lastNight;
    return BandAppSnapshot(
      steps: t?.steps,
      stepGoal: profile.stepGoal,
      activeKcal: t?.activeCalories,
      kcalGoal: profile.calorieGoal,
      standHours: t?.standingHours,
      standGoal: profile.standGoal,
      heartRate:
          heartRate ??
          (hrHistory.isEmpty ? null : hrHistory[hrHistory.lastKey()]),
      restingHr: t?.restingHeartRate,
      spo2: t?.averageSpo2,
      sleepMinutes: night?.asleep.inMinutes,
      sleepStart: night?.start,
      sleepEnd: night?.end,
      battery: battery,
    );
  }

  /// Shares heart rate with Android Health Connect when enabled.
  late final healthConnect = HealthConnectSync(log: log, history: hrHistory)
    ..listenTo(newHeartRateSamples)
    ..onEnabled = _queueAllHealth;

  /// Resting heart rate last queued for Health Connect.
  int? _sharedRestingHr;

  /// Queues everything the app holds (today's activity and SpO₂, spot
  /// checks, resting HR, the past week's sleep) for Health Connect.
  void _queueAllHealth() {
    final now = DateTime.now();
    _shareMinutes(_todayRecords, now);
    _shareSpotChecks(_spotChecks.values, now);
    _sharedRestingHr = null;
    _shareRestingHr(now);
    healthConnect.queue(sleepLog.sessions.map(sleepRecord));
  }

  void _shareMinutes(List<DailyMinute> minutes, DateTime now) {
    healthConnect
      ..queue(activityRecords(minutes, now))
      ..queue(
        spo2Records([
          for (final m in minutes)
            if (m.spo2 != null) (m.time, m.spo2!),
        ], now),
      );
  }

  void _shareSpotChecks(Iterable<Measurement> checks, DateTime now) {
    healthConnect.queue(
      spo2Records([
        for (final c in checks)
          if (c.kind == MeasurementKind.spo2) (c.time, c.value),
      ], now),
    );
  }

  void _shareRestingHr(DateTime now) {
    final bpm = today?.restingHeartRate;
    if (bpm == null || bpm <= 0 || bpm == _sharedRestingHr) return;
    if (!healthConnect.active) return;
    _sharedRestingHr = bpm;
    healthConnect.queue([
      restingHeartRateRecord(
        today!.day,
        bpm,
        now,
        version: now.millisecondsSinceEpoch ~/ 1000,
      ),
    ]);
  }

  /// Saves everything the app holds as a ZIP in Download/OpenWear/Exports;
  /// returns where it went.
  Future<String> exportData({
    String? password,
    Future<String> Function(String name, Uint8List bytes)? save,
  }) async {
    final now = DateTime.now();
    final bytes = buildExport(
      ExportData(
        created: now,
        heartRate: hrHistory,
        minutes: _todayRecords,
        spotChecks: _spotChecks.values.toList(),
        sleep: sleepLog.sessions,
        log: log.export(),
      ),
      password: password,
    );
    final name = exportFileName(now);
    final where =
        await (save ??
            (n, b) => saveToDownloads(
              exportFolder,
              n,
              b,
              replace: false,
              mime: 'application/zip',
            ))(name, bytes);
    log.app(
      'Data exported to $where (${bytes.length ~/ 1024} KB, '
      '${password == null ? 'not encrypted' : 'AES-256 encrypted'})',
    );
    return where;
  }

  /// Re-checks Health Connect access, e.g. when coming back to the app.
  Future<void> refreshHealthConnect() => healthConnect.refresh();

  Future<void> setHealthConnect(bool on) async {
    if (on) {
      await healthConnect.enable();
    } else {
      healthConnect.disable();
    }
    await _storage.write(
      key: _kHealthConnect,
      value: '${healthConnect.enabled}',
    );
  }

  bool get weatherEnabled => phone.weatherEnabled;

  /// How the app shows temperatures, distances and body measurements.
  UnitSystem units = UnitSystem.metric;

  Future<void> setUnits(UnitSystem u) async {
    units = u;
    await _storage.write(key: _kUnits, value: u.name);
    notifyListeners();
    await _syncWeatherUnit();
  }

  /// Clock style on the band; follows the phone unless changed here.
  bool use24Hour = ui.PlatformDispatcher.instance.alwaysUse24HourFormat;

  Future<void> setUse24Hour(bool on) async {
    use24Hour = on;
    await _storage.write(key: _kClock24, value: '$on');
    notifyListeners();
    await _link?.send(
      setTime(DateTime.now(), await phoneTimeZone(), twelveHour: !on),
    );
    log.app('Band clock → ${on ? '24' : '12'}-hour');
  }

  /// The band's own weather settings, as last read.
  BandWeatherConfig? bandWeather;

  /// Reads the band's weather unit and sets it to match [units].
  Future<void> _syncWeatherUnit() async {
    final link = _link;
    if (link == null) return;
    try {
      bandWeather = parseWeatherConfig(
        await link.request(weatherConfigRequest()),
      );
      log.app('Band weather settings: ${bandWeather ?? 'not reported'}');
      if (bandWeather?.fahrenheit != units.isImperial) {
        await link.send(weatherUnitCommand(fahrenheit: units.isImperial));
        bandWeather = BandWeatherConfig(
          unit: units.isImperial ? bandFahrenheit : bandCelsius,
          alerts: bandWeather?.alerts ?? 0,
        );
        log.app('Band weather unit → ${units.temperatureSymbol}');
      }
      notifyListeners();
    } on TimeoutException {
      log.warn('Band did not report its weather settings');
    }
  }

  /// The wearer's body data and daily goals, shared with the band.
  UserProfile profile = const UserProfile();

  Future<void> setProfile(UserProfile p) async {
    profile = p;
    await _storage.write(key: _kProfile, value: jsonEncode(p.toJson()));
    notifyListeners();
    final link = _link;
    if (link != null) {
      await link.send(profileCommand(p));
      log.app('Profile and goals → band');
    }
  }

  Future<void> setWeather({bool? enabled}) async {
    if (enabled != null) {
      phone.weatherEnabled = enabled;
      await _storage.write(key: _kWeather, value: '$enabled');
    }
    notifyListeners();
    if (connected && phone.weatherEnabled) await phone.sendWeather();
  }

  Future<void> load() async {
    unawaited(faceNames.load());
    await account.load();
    address = await _storage.read(key: _kAddress) ?? '';
    name = await _storage.read(key: _kName) ?? '';
    phone.weatherEnabled = await _storage.read(key: _kWeather) != 'false';
    final storedUnits = await _storage.read(key: _kUnits);
    units = storedUnits != null
        ? UnitSystem.parse(storedUnits)
        : (await _storage.read(key: _kFahrenheit) == 'true'
              ? UnitSystem.imperial
              : UnitSystem.metric);
    final clock = await _storage.read(key: _kClock24);
    if (clock != null) use24Hour = clock == 'true';
    final storedProfile = await _storage.read(key: _kProfile);
    if (storedProfile != null) {
      try {
        profile = UserProfile.fromJson(
          jsonDecode(storedProfile) as Map<String, dynamic>,
        );
      } on FormatException {
        log.warn('Saved profile was unreadable; using defaults');
      }
    }
    unawaited(appearance.load());
    unawaited(firmware.load());
    phone.weather.lookupCity = _weatherCity;
    healthConnect.enabled = await _storage.read(key: _kHealthConnect) == 'true';
    final every = int.tryParse(await _storage.read(key: _kSyncEvery) ?? '');
    if (every != null && syncChoices.contains(Duration(seconds: every))) {
      syncEvery = Duration(seconds: every);
    }
    // Starts sharing (and queues everything) when access is confirmed.
    unawaited(healthConnect.refresh());
    unawaited(_loadSavedToday());
    final key = await _storage.read(key: _kKey);
    state = address.isEmpty || key == null
        ? BandState.notPaired
        : BandState.disconnected;
    notifyListeners();
  }

  /// Connects to the saved band, as the app does on launch.
  Future<void> autoConnect() async {
    if (state == BandState.disconnected) await connect();
  }

  // --- staying connected ------------------------------------------------------------

  /// True from Connect until the user taps Disconnect or forgets the band;
  /// while set, a dropped or failed link is retried with growing pauses.
  bool _wantConnected = false;
  Timer? _retryTimer;
  int _retries = 0;
  static const _retryPauses = [5, 15, 30, 60, 120, 300];

  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (!_wantConnected || state == BandState.notPaired) return;
    final pause = Duration(
      seconds: _retryPauses[_retries.clamp(0, _retryPauses.length - 1)],
    );
    _retries++;
    log.app('Reconnecting in ${pause.inSeconds} s');
    _retryTimer = Timer(pause, () {
      if (_wantConnected && state == BandState.disconnected) {
        unawaited(connect());
      }
    });
  }

  /// Saves a band paired elsewhere (key from our PC tool or an account bind).
  Future<void> savePairing(
    String bandAddress,
    String bandName,
    String authKeyHex, {
    String appDeviceId = '',
  }) async {
    final key = authKeyHex
        .replaceAll(RegExp(r'[^0-9a-fA-F]'), '')
        .toLowerCase();
    if (key.length != 32) {
      throw const FormatException(
        'The auth key must be 16 bytes (32 hex digits).',
      );
    }
    await _storage.write(key: _kAddress, value: bandAddress.toUpperCase());
    await _storage.write(key: _kName, value: bandName);
    await _storage.write(key: _kKey, value: key);
    await _storage.write(key: _kAppDeviceId, value: appDeviceId);
    await load();
  }

  Future<void> forget() async {
    await disconnect();
    for (final k in [_kAddress, _kName, _kKey, _kAppDeviceId]) {
      await _storage.delete(key: k);
    }
    await load();
  }

  Future<void> connect() async {
    final keyHex = await _storage.read(key: _kKey);
    if (address.isEmpty || keyHex == null) return;
    if (state == BandState.connecting || state == BandState.connected) return;
    _wantConnected = true;
    _retryTimer?.cancel();
    _set(BandState.connecting, error: null);
    final appDeviceId = await _storage.read(key: _kAppDeviceId) ?? '';
    log.app(
      'Connecting to $name ($address)…',
      detail:
          'pairing type: ${appDeviceId.isEmpty ? 'Xiaomi account' : 'local (no account)'}\n'
          'saved key: present (16 bytes)',
    );
    log.sessionInfo['band'] = '$name ($address)';
    final clock = Stopwatch()..start();
    final link = Link(SppTransport(address));
    link.events.listen(log.onLinkEvent);
    link.events.listen(_onLinkEvent);
    try {
      await link.open();
      link.channelHandlers[channelFitness] = _onFitnessPacket;
      await link.authenticate(
        SessionAuth(_unhex(keyHex), appDeviceId: appDeviceId),
      );
      _link = link;
      _commandSub = link.commands.listen(_onBandCommand, onDone: _onLinkClosed);
      _set(BandState.connected);
      _retries = 0;
      log.app('Connected and authenticated in ${clock.elapsedMilliseconds} ms');
      await link.send(
        setTime(DateTime.now(), await phoneTimeZone(), twelveHour: !use24Hour),
      );
      await refreshBattery();
      await refreshInfo();
      await link.send(languageCommand(_phoneLocale()));
      await link.send(profileCommand(profile));
      await _syncWeatherUnit();
      unawaited(loadRaiseToWake());
      unawaited(loadSleepSettings());
      // Mi Fitness tells the band up front that the phone may receive
      // screenshots; without it the band answers 2/108 with status 1.
      unawaited(link.send(screenshotPermissionGranted()));
      unawaited(_autoCaptureFaces());
      _startAutoSync();
      _phoneSub = phoneEvents().listen(_onPhoneEvent);
      await phone.attach(link.send, request: link.request);
      await startCompanionService();
    } on HandshakeException catch (e) {
      log.warn(
        'Connection failed: the band rejected our key (${e.message})',
        detail:
            'The band was probably reset or paired with another app. '
            'Forget it in OpenWear and pair again.',
      );
      await link.close();
      _set(BandState.disconnected, error: e.message);
    } on Exception catch (e, stack) {
      log.error(
        'Connection failed after ${clock.elapsedMilliseconds} ms',
        e,
        stack,
      );
      await link.close();
      _set(BandState.disconnected, error: '$e');
      _scheduleRetry();
    }
  }

  Future<void> disconnect() async {
    _wantConnected = false;
    _retryTimer?.cancel();
    _retries = 0;
    await phone.detach();
    await _phoneSub?.cancel();
    await _commandSub?.cancel();
    _phoneSub = _commandSub = null;
    await _link?.close();
    _link = null;
    bandApp.reset();
    heartRate = null;
    finding = false;
    _todayTimer?.cancel();
    if (state != BandState.notPaired) _set(BandState.disconnected);
    await stopCompanionService();
  }

  void _onLinkClosed() {
    unawaited(phone.detach());
    _todayTimer?.cancel();
    _link = null;
    bandApp.reset();
    heartRate = null;
    if (state == BandState.connected) {
      _set(BandState.disconnected, error: 'Band disconnected');
      _scheduleRetry();
    }
  }

  // --- basic info ---------------------------------------------------------------

  Future<void> refreshBattery() async {
    final link = _link;
    if (link == null) return;
    battery = batteryPercent(await link.request(batteryRequest()));
    notifyListeners();
  }

  /// Asks the band for its model, firmware and serial number.
  Future<void> refreshInfo() async {
    final link = _link;
    if (link == null) return;
    try {
      info = parseBandInfo(
        await link.request(
          deviceInfoRequest(),
          timeout: const Duration(seconds: 5),
        ),
      );
    } on TimeoutException {
      log.warn('Band did not send its device info');
      return;
    } on FormatException catch (e) {
      // Never let a strange reply break the connection.
      log.warn('Band device info could not be read: ${e.message}');
      return;
    }
    final i = info;
    if (i == null) {
      log.warn('Band device info reply was empty');
    } else {
      // The serial number stays out of the log.
      log.app('Band ${i.model}, firmware ${i.firmware}');
    }
    notifyListeners();
  }

  Future<void> syncTime() async => _link?.send(
    setTime(DateTime.now(), await phoneTimeZone(), twelveHour: !use24Hour),
  );

  Future<void> sendTestNotification() async => _link?.send(
    notification(
      package: 'org.openwear.openwear',
      appName: 'OpenWear',
      title: 'Hello',
      text: 'Test notification from OpenWear',
      id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      time: DateTime.now(),
    ),
  );

  // --- live heart rate --------------------------------------------------------------

  Future<void> startHeartRate() async {
    final link = _link;
    if (link == null) return;
    heartRate = 0;
    notifyListeners();
    await link.send(fitness.realtimeStart());
  }

  Future<void> stopHeartRate() async {
    heartRate = null;
    notifyListeners();
    await _link?.send(fitness.realtimeStop());
  }

  // --- band settings ------------------------------------------------------------------

  /// Band's DND state as last reported (null until it reports or we set it).
  bool? dndOn;
  settings.RaiseToWake? raiseToWake;

  /// The band's sleep-tracking switches; null until read or unsupported.
  SleepSettings? sleepSettings;
  bool finding = false;

  Future<void> findBand({bool stop = false}) async {
    final link = _link;
    if (link == null) return;
    await link.send(settings.findBand(stop: stop));
    finding = !stop;
    log.app(stop ? 'Stopped finding the band' : 'Finding the band (it rings)');
    notifyListeners();
  }

  Future<void> setDnd(bool on) async {
    final link = _link;
    if (link == null) return;
    await link.send(settings.dndCommand(on: on));
    dndOn = on;
    log.app('Do Not Disturb ${on ? 'on' : 'off'} → band');
    notifyListeners();
  }

  Future<void> loadRaiseToWake() async {
    final link = _link;
    if (link == null) return;
    try {
      raiseToWake = settings.parseRaiseToWake(
        await link.request(settings.raiseToWakeRequest()),
      );
      notifyListeners();
    } on TimeoutException {
      // logged by the link; the row stays hidden
    }
  }

  Future<void> setRaiseToWake(bool on) async {
    final link = _link;
    final current = raiseToWake;
    if (link == null || current == null) return;
    final next = current.copyWith(
      mode: on ? settings.ScheduleMode.always : settings.ScheduleMode.off,
    );
    await link.request(settings.raiseToWakeCommand(next));
    raiseToWake = next;
    log.app('Raise to wake ${on ? 'on' : 'off'} → band');
    notifyListeners();
  }

  Future<void> loadSleepSettings() async {
    final link = _link;
    if (link == null) return;
    try {
      final s = parseSleepSettings(await link.request(sleepSettingsRequest()));
      sleepSettings = s != null && s.anySupported ? s : null;
      log.app(
        s == null
            ? 'Sleep settings: band sent none'
            : 'Sleep settings: high accuracy ${s.highAccuracy}, '
                  'breathing ${s.breathingQuality}, '
                  'breathing rate ${s.breathingRate}',
      );
      notifyListeners();
    } on TimeoutException {
      // logged by the link; the rows stay hidden
    }
  }

  /// Writes [next] (the whole config, one switch changed) and keeps it.
  Future<void> setSleepSettings(SleepSettings next, String what) async {
    final link = _link;
    if (link == null || sleepSettings == null) return;
    await link.request(next.command());
    sleepSettings = next;
    log.app('Sleep: $what → band');
    notifyListeners();
  }

  // --- watch faces --------------------------------------------------------------------

  Future<void> loadFaces() async {
    final link = _link;
    if (link == null) return;
    faces = parseFaces(await link.request(listFaces()));
    notifyListeners();
    await facePreviews.load(faces.map((f) => f.id));
  }

  /// Face names in the phone's language.
  late final faceNames = FaceNames(
    language: () => ui.PlatformDispatcher.instance.locale.toLanguageTag(),
    translate: translateOnDevice,
    cacheFile: () async => File(
      '${(await getApplicationSupportDirectory()).path}/face_names.json',
    ),
  )..addListener(notifyListeners);

  /// [face]'s name as shown to the user.
  String faceName(WatchFace face) => faceNames.display(face.name);

  /// Pictures of each face, captured from the band.
  late final facePreviews = FacePreviews(
    log: log,
    directory: () => _bandDir('faces'),
    seal: atRest.seal,
    open: atRest.open,
  )..addListener(notifyListeners);

  /// Theme, accent and Today-card choices.
  late final appearance = Appearance()..addListener(notifyListeners);

  /// The band's app list and installed apps.
  late final apps = BandApps(log: log, link: () => _link)
    ..addListener(notifyListeners);

  /// Xiaomi's city key for the weather, when signed in.
  Future<({String key, String name})?> _weatherCity(
    double lat,
    double lon,
  ) async {
    final session = account.session;
    if (session == null) return null;
    try {
      final c = await cloud.weatherCity(
        session,
        account.region,
        lat: lat,
        lon: lon,
        model: info?.model ?? '',
        firmware: info?.firmware ?? '',
      );
      return c == null ? null : (key: c.key, name: c.name);
    } on cloud.CloudException catch (e) {
      if (e.expired) await account.expired();
      rethrow;
    }
  }

  /// Firmware updates from Xiaomi's servers.
  late final firmware = FirmwareUpdate(
    log: log,
    link: () => _link,
    findRelease: _findFirmware,
    directory: () async =>
        Directory('${(await getApplicationSupportDirectory()).path}/firmware'),
    export: Platform.isAndroid
        ? (name, bytes) => saveToDownloads(firmwareDownloadFolder, name, bytes)
        : null,
  )..addListener(notifyListeners);

  Future<cloud.FirmwareRelease?> _findFirmware(
    String model,
    String firmware,
  ) async {
    final session = account.session;
    if (session == null) {
      throw const cloud.CloudException(
        'Sign in to your Xiaomi account to check for updates.',
      );
    }
    cloud.cloudTrace = (line) => log.app('Xiaomi: $line');
    try {
      final devices = await cloud.listDevices(session, account.region);
      final did = cloud.didFromDevices(devices, address, model);
      if (did == null) {
        throw const cloud.CloudException(
          'This band is not on your Xiaomi account, so Xiaomi will not '
          'offer it updates.',
        );
      }
      return await cloud.latestFirmware(
        session,
        account.region,
        did: did,
        model: model,
        firmware: firmware,
      );
    } on cloud.CloudException catch (e) {
      if (e.expired) await account.expired();
      rethrow;
    }
  }

  /// One picture of what the band shows right now (PNG).
  Future<Uint8List> bandScreenshot() {
    final link = _link;
    if (link == null) throw TimeoutException('Connect the band first');
    return facePreviews.screenshot((cmd) async {
      await link.send(screenshotPermissionGranted());
      await link.send(cmd);
    });
  }

  /// Shows each face on the band in turn and keeps a screenshot of it;
  /// returns to the face that was in use.
  Future<int> captureFacePreviews({List<String>? only}) async {
    final link = _link;
    if (link == null) return 0;
    if (only == null) await _storage.delete(key: _kNoAutoScreenshots);
    if (faces.isEmpty) await loadFaces();
    final restore = activeFace?.id;
    final ids = only ?? [for (final f in faces) f.id];
    final n = await facePreviews.captureAll(
      ids,
      restoreId: restore,
      send: link.send,
      switchTo: (id) => link.request(setFace(id)),
    );
    await loadFaces();
    // The band has acknowledged the switch back yet stayed on the last face
    // captured; check, and try once more.
    if (restore != null && activeFace?.id != restore) {
      await Future<void>.delayed(const Duration(seconds: 2));
      await activateFace(restore);
      if (activeFace?.id != restore) {
        log.warn('The band did not go back to your face; choose it in Faces');
      } else {
        log.app('Switched back to your face');
      }
    }
    return n;
  }

  String _phoneLocale() {
    final l = ui.PlatformDispatcher.instance.locale;
    final country = l.countryCode;
    return country == null || country.isEmpty
        ? l.languageCode
        : '${l.languageCode}_$country';
  }

  /// The user's Xiaomi sign-in, for face pictures.
  late final account = XiaomiAccount(log: log, storage: _storage)
    ..addListener(notifyListeners);

  bool fetchingStorePictures = false;

  /// Gets official pictures of the band's built-in faces from Xiaomi.
  /// With [all] false only faces with no picture at all are fetched, so a
  /// screenshot the user chose is never replaced behind their back.
  Future<store.StoreFetchResult?> fetchStorePictures({bool all = false}) async {
    final session = account.session;
    final band = info;
    if (session == null || fetchingStorePictures) return null;
    if (band == null || band.model.isEmpty) {
      log.warn('Face pictures need the band model; connect the band first');
      return null;
    }
    if (faces.isEmpty) await loadFaces();
    final ids = [
      for (final f in faces)
        if (all || !facePreviews.images.containsKey(f.id)) f.id,
    ];
    if (ids.every(store.isOwnFace)) return const store.StoreFetchResult(0, 0);
    fetchingStorePictures = true;
    notifyListeners();
    cloud.cloudTrace = (line) => log.app('Xiaomi: $line');
    try {
      final r = await store.fetchStorePictures(
        ids,
        detail: (id) => cloud.faceDetail(
          session,
          account.region,
          model: band.model,
          id: id,
          firmware: band.firmware,
        ),
        lookupAll: (ids) => cloud.faceCheck(
          session,
          account.region,
          model: band.model,
          ids: ids,
        ),
        download: store.downloadPicture,
        keep: (id, png) => facePreviews.keep(id, png, store: true),
        warn: log.warn,
      );
      log.app(
        'Face pictures from Xiaomi: ${r.saved} saved'
        '${r.missing == 0 ? '' : ', ${r.missing} not available'}',
      );
      return r;
    } on cloud.CloudException catch (e) {
      if (e.expired) await account.expired();
      log.warn('Could not get face pictures from Xiaomi: ${e.message}');
      rethrow;
    } finally {
      fetchingStorePictures = false;
      notifyListeners();
    }
  }

  /// Takes pictures of faces that have none yet, without being asked.
  Future<void> _autoCaptureFaces() async {
    try {
      await loadFaces();
      if (account.signedIn) {
        try {
          await fetchStorePictures();
        } on cloud.CloudException {
          // Logged; fall back to screenshots below.
        }
      }
      final missing = [
        for (final f in faces)
          if (!facePreviews.images.containsKey(f.id)) f.id,
      ];
      if (missing.isEmpty) return;
      // A band that sent no screenshot before is not asked again on every
      // connect (each try switches its face); Faces → take pictures still can.
      if (await _storage.read(key: _kNoAutoScreenshots) == 'true') return;
      log.app('Taking pictures of ${missing.length} faces');
      final n = await captureFacePreviews(only: missing);
      if (n == 0) {
        await _storage.write(key: _kNoAutoScreenshots, value: 'true');
        log.app(
          'Face pictures are no longer taken automatically; use Faces to '
          'try again',
        );
      }
    } on TimeoutException {
      log.warn('Band did not answer while taking face pictures');
    }
  }

  void _onLinkEvent(LinkEvent e) {
    if (e is ChannelData && !e.outgoing && e.channel != channelFitness) {
      facePreviews.feed(e.payload);
    }
  }

  Future<void> activateFace(String id) async {
    await _link?.request(setFace(id));
    await loadFaces();
  }

  static String _language() =>
      ui.PlatformDispatcher.instance.locale.toLanguageTag();

  /// Pictures of OpenWear's own faces.
  late final customPreviews = CustomFacePreviews(language: _language);

  /// Draws [face] in the phone's language and installs it.
  Future<void> installCustomFace(CustomFace face) async {
    if (_link == null) {
      throw const FaceInstallException('Connect the band first.');
    }
    final design = await face.design(_language());
    final binary = await compute(packFace, design);
    await installFace(face.id, face.name, binary);
  }

  /// The face being installed and how far its upload has got (0–1).
  String? installingFace;
  double installProgress = 0;

  /// Installs a face binary built on the phone, then shows it.
  Future<void> installFace(String id, String name, Uint8List binary) async {
    final link = _link;
    if (link == null) {
      throw const FaceInstallException('Connect the band first.');
    }
    if (installingFace != null) {
      throw const FaceInstallException('Another face is still installing.');
    }
    installingFace = id;
    installProgress = 0;
    notifyListeners();
    try {
      log.app('Installing face "$name" ($id, ${binary.length} bytes)');
      checkPreInstall(
        await link.request(
          preInstallFace(id, binary.length),
          timeout: const Duration(seconds: 15),
        ),
      );
      final result = link.commands
          .map(installResult)
          .firstWhere((r) => r != null && r.$1 == id)
          .timeout(const Duration(seconds: 90));
      result.ignore();
      final sent = await upload(
        link,
        faceFile,
        binary,
        onProgress: (p) {
          installProgress = p;
          notifyListeners();
        },
      );
      if (sent) {
        final (_, ok) = (await result)!;
        if (!ok) {
          throw const FaceInstallException(
            'The band could not install this face.',
          );
        }
      }
      log.app('Face "$name" installed');
      await activateFace(id);
    } on TimeoutException {
      throw const FaceInstallException(
        'The band stopped answering during the install.',
      );
    } on MassException catch (e) {
      throw FaceInstallException('Upload failed: ${e.message}');
    } finally {
      installingFace = null;
      installProgress = 0;
      notifyListeners();
    }
  }

  Future<void> removeFace(String id) async {
    await _link?.request(deleteFace(id));
    facePreviews.forget(id);
    await loadFaces();
  }

  // --- health sync ----------------------------------------------------------------------

  /// Pulls today's and older health files and stores them raw; returns how many.
  Future<int> syncHealth() async {
    final link = _link;
    if (link == null) return 0;
    final ids = <fitness.FitnessId>{};
    for (final req in [
      fitness.todayIdsRequest(),
      fitness.historyIdsRequest(),
    ]) {
      try {
        ids.addAll(fitness.idsFromResponse(await link.request(req)));
      } on TimeoutException {
        continue;
      }
    }
    var saved = 0;
    for (final id in ids) {
      if (await _fetchFile(link, id) != null) saved++;
    }
    return saved;
  }

  // --- today's activity -----------------------------------------------------------------

  /// Today's running totals from the band's daily report.
  DailyReport? today;
  DateTime? todayUpdatedAt;
  Timer? _todayTimer;
  bool refreshingToday = false;

  /// How often today's activity and all-day heart rate are pulled. Each
  /// pull makes the band write an extra record and start a new file, so
  /// it is never more often than once a minute.
  Duration syncEvery = const Duration(minutes: 1);
  static const syncChoices = [
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  Future<void> setSyncEvery(Duration every) async {
    if (!syncChoices.contains(every)) return;
    syncEvery = every;
    await _storage.write(key: _kSyncEvery, value: '${every.inSeconds}');
    if (connected) _startAutoSync();
    notifyListeners();
  }

  void _startAutoSync() {
    _todayTimer?.cancel();
    unawaited(refreshToday());
    _todayTimer = Timer.periodic(syncEvery, (_) => unawaited(refreshToday()));
  }

  /// Files already received; the newest record file is refetched each time
  /// because the band keeps appending to it.
  final _fetchedRecords = <String>{};

  /// Today's health files and which ones the band may drop.
  final _inbox = HealthInbox();

  /// When the band last sent a health packet; a sync waits while it is
  /// still sending.
  DateTime _lastFitnessPacket = DateTime.fromMillisecondsSinceEpoch(0);
  static const _bandBusyFor = Duration(seconds: 5);

  /// Fetches today's daily report and the band's per-minute records
  /// (all-day heart rate).
  Future<void> refreshToday() async {
    final link = _link;
    if (link == null || refreshingToday) return;
    if (DateTime.now().difference(_lastFitnessPacket) < _bandBusyFor) return;
    refreshingToday = true;
    notifyListeners();
    try {
      final ids = fitness.idsFromResponse(
        await link.request(fitness.todayIdsRequest()),
      )..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final reports = ids.where(isDailyReport).toList();
      final records = ids.where(isDailyRecord).toList();
      final checks = ids.where(isManualMeasurement).toList();
      final sleep = ids.where(isSleepFile).toList();
      log.app(
        'Today on band: ${reports.length} report, ${records.length} minute '
        'files, ${checks.length} spot-check, ${sleep.length} sleep, '
        '${ids.length - reports.length - records.length - checks.length - sleep.length} other',
        replaceKey: 'today-ids',
      );
      final wanted = [
        if (reports.isNotEmpty) reports.last,
        for (final r in records)
          if (r == records.last || !_fetchedRecords.contains(r.hex)) r,
        for (final c in checks)
          if (c == checks.last || !_fetchedRecords.contains(c.hex)) c,
        for (final s in sleep)
          if (!_fetchedRecords.contains(s.hex) || !sleepLog.isFinished(s)) s,
      ];
      for (final id in wanted) {
        await _fetchFile(link, id, quiet: true);
      }
      await _fetchSleepHistory(link);
    } on TimeoutException {
      log.warn('Band did not list today\'s files');
    } finally {
      refreshingToday = false;
      notifyListeners();
    }
  }

  /// When the band's older files were last checked for sleep.
  DateTime _sleepHistoryCheckedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _sleepHistoryEvery = Duration(minutes: 30);

  /// A night is often listed with the older files (it started yesterday),
  /// so those are checked for sleep files now and then.
  Future<void> _fetchSleepHistory(Link link) async {
    final now = DateTime.now();
    if (now.difference(_sleepHistoryCheckedAt) < _sleepHistoryEvery) return;
    _sleepHistoryCheckedAt = now;
    try {
      final ids = fitness.idsFromResponse(
        await link.request(fitness.historyIdsRequest()),
      );
      final sleep = [
        for (final id in ids)
          if (isSleepFile(id) &&
              (!_fetchedRecords.contains(id.hex) || !sleepLog.isFinished(id)))
            id,
      ];
      if (sleep.isNotEmpty) {
        log.app('Older files on band: ${sleep.length} sleep to fetch');
      }
      for (final id in sleep) {
        await _fetchFile(link, id, quiet: true);
      }
    } on TimeoutException {
      log.warn('Band did not list its older files');
    }
  }

  /// Saves and uses one complete health file, then confirms it to the band
  /// when the band may drop it (Mi Fitness confirms each file it parsed;
  /// without that the band keeps resending its whole backlog).
  Future<void> _ingest(Uint8List file) async {
    final id = fitness.FitnessId(file.sublist(0, fitness.idLength));
    final now = DateTime.now();
    _fetchedRecords.add(id.hex);
    final saved = await _saveHealthFile(file);
    _use(file, now);
    final link = _link;
    final mayConfirm = isSleepFile(id)
        ? sleepLog.mayConfirm(id, now)
        : _inbox.mayConfirm(id, now);
    if (saved && link != null && mayConfirm) {
      _confirming = _confirming
          .then((_) => link.send(fitness.confirmFile(id)))
          .catchError(
            (Object e) => log.warn('Could not confirm ${id.hex}: $e'),
          );
    }
  }

  Future<void> _confirming = Future.value();

  void _use(Uint8List file, DateTime now) {
    final id = fitness.FitnessId(file.sublist(0, fitness.idLength));
    if (isSleepFile(id)) {
      _useSleep(file, id, now);
      return;
    }
    final checks = parseManualMeasurements(file);
    if (checks != null) {
      _useSpotChecks(checks);
      return;
    }
    final parsed = parseDailyRecord(file);
    if (parsed != null) {
      if (_inbox.add(file, now)) _scheduleRebuild();
      final day = DateTime.fromMillisecondsSinceEpoch(id.timestamp * 1000);
      if (day.year != now.year ||
          day.month != now.month ||
          day.day != now.day) {
        final older = recordsOfFiles([file], now);
        _mergeHeartRate(heartRateOf(older));
        _shareMinutes(older, now);
      }
      return;
    }
    _useDailyReport(file);
  }

  void _useSleep(Uint8List file, fitness.FitnessId id, DateTime now) {
    if (parseSleep(file) == null) {
      log.warn(
        'Sleep file ${id.hex} (type ${id.dataType} v${id.version}, '
        '${file.length} bytes) could not be read',
      );
      return;
    }
    final s = sleepLog.add(file, now);
    if (s == null) return;
    log.app('Sleep: $s', replaceKey: 'sleep-${id.hex}');
    healthConnect.queue([sleepRecord(s)]);
    notifyListeners();
  }

  Timer? _rebuildTimer;

  /// The band sends hundreds of minute files at once; the day is worked
  /// out again once they stop coming.
  void _scheduleRebuild() {
    _rebuildTimer?.cancel();
    _rebuildTimer = Timer(const Duration(milliseconds: 400), _rebuildToday);
  }

  /// Today's minute records, from every minute file of the day.
  List<DailyMinute> _todayRecords = const [];

  void _rebuildToday() {
    final now = DateTime.now();
    final records = _inbox.recordsFor(now);
    _todayRecords = [
      for (final m in records)
        if (!m.time.isAfter(now)) m,
    ];
    final t = totalsFor(_todayRecords, now);
    final hr = heartRateOf(_todayRecords);
    String hm(DateTime x) =>
        '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
    log.app(
      'Today from ${_inbox.todayFileCount} minute files: '
      '${_todayRecords.length} records'
      '${_todayRecords.isEmpty ? '' : ' ${hm(_todayRecords.first.time)}–${hm(_todayRecords.last.time)}'}'
      ', ${t.steps} steps, ${t.activeCalories} active kcal, '
      '${hr.length} heart-rate readings',
      replaceKey: 'today-minutes',
    );
    _mergeHeartRate(hr);
    _shareMinutes(_todayRecords, now);
    _fillVitals();
  }

  /// Rebuilds today from the minute files saved on the phone, so the day
  /// survives restarts after the band has dropped confirmed files.
  Future<void> _loadSavedToday() async {
    if (address.isEmpty) return;
    final now = DateTime.now();
    final List<FileSystemEntity> entries;
    try {
      entries = await (await _healthDir()).list().toList();
    } on FileSystemException catch (e) {
      log.warn('Could not read saved health files: ${e.message}');
      return;
    } on MissingPluginException {
      return; // no app storage (tests)
    } on PlatformException catch (e) {
      log.warn('Could not open app storage: ${e.message}');
      return;
    }
    var used = 0;
    for (final e in entries) {
      final name = e.uri.pathSegments.last;
      if (e is! File || !RegExp(r'^[0-9a-f]{14}\.bin$').hasMatch(name)) {
        continue;
      }
      final id = fitness.FitnessId(_unhex(name.substring(0, 14)));
      final t = DateTime.fromMillisecondsSinceEpoch(id.timestamp * 1000);
      final sameDay =
          t.year == now.year && t.month == now.month && t.day == now.day;
      final recentSleep = isSleepFile(id) && now.difference(t) <= sleepKeptFor;
      if (!sameDay && !recentSleep) continue;
      try {
        final stored = await e.readAsBytes();
        final file = await atRest.open(stored);
        // Files saved before encryption existed are sealed in place.
        if (!isSealed(stored)) {
          await e.writeAsBytes(await atRest.seal(file), flush: true);
        }
        _use(file, now);
        used++;
      } on FileSystemException {
        continue;
      } on PlatformException catch (e) {
        log.warn('Health file key unavailable: ${e.message}');
        break;
      } on FormatException {
        log.warn('Saved health file $name failed its check; skipped');
      } on RangeError {
        log.warn('Saved health file $name is damaged; skipped');
      }
    }
    if (used > 0) {
      log.app('Loaded $used saved health files for today and recent sleep');
    }
  }

  /// Today's spot checks from the band, by time.
  final _spotChecks = SplayTreeMap<DateTime, Measurement>();

  void _useSpotChecks(List<Measurement> checks) {
    for (final c in checks) {
      _spotChecks[c.time] = c;
    }
    log.app(
      'Spot checks on band: ${checks.length} '
      '(${checks.map((c) => '${c.kind.name} ${c.value}').join(', ')})',
      replaceKey: 'spot-checks',
    );
    _shareSpotChecks(checks, DateTime.now());
    _fillVitals();
  }

  /// The latest spot check of [kind] taken today.
  int? _latestCheck(MeasurementKind kind, DateTime now) {
    for (final c in _spotChecks.values.toList().reversed) {
      final t = c.time;
      if (c.kind == kind &&
          t.year == now.year &&
          t.month == now.month &&
          t.day == now.day) {
        return c.value;
      }
    }
    return null;
  }

  /// The band's own report for today, as received (no fallbacks mixed in).
  DailyReport? _bandReport;

  /// Rebuilds [today] from the band's report, the minute records and spot
  /// checks. Always starts from the raw report, so values worked out
  /// earlier in the day are recomputed rather than frozen.
  void _fillVitals() {
    final now = DateTime.now();
    final report = _bandReport;
    final base = report != null && report.isFor(now)
        ? report
        : DailyReport(day: DateTime(now.year, now.month, now.day), version: 0);
    final t = totalsFor(_todayRecords, now);
    final v = vitalsFor(_todayRecords, now);
    final filled = base
        .atLeast(
          steps: t.steps,
          activeCalories: t.activeCalories,
          totalCalories: t.totalCalories,
        )
        .withFallbacks(
          restingHeartRate: v.restingHeartRate,
          averageSpo2: v.spo2 ?? _latestCheck(MeasurementKind.spo2, now),
          averageStress: v.stress ?? _latestCheck(MeasurementKind.stress, now),
          standingHours: v.standHours,
        );
    today = filled;
    todayUpdatedAt = now;
    log.app('Vitals: $filled', replaceKey: 'today-vitals');
    _shareRestingHr(now);
    unawaited(bandApp.pushState());
    notifyListeners();
  }

  void _useDailyReport(Uint8List file) {
    final report = parseDailyReport(file);
    if (report == null) {
      final id = file.length >= 7
          ? fitness.FitnessId(file.sublist(0, 7))
          : null;
      if (id != null && isDailyReport(id)) {
        log.warn('Daily report v${id.version} could not be read');
      }
      return;
    }
    final current = _bandReport;
    if (current != null && report.day.isBefore(current.day)) return;
    if (!report.isFor(DateTime.now())) return;
    _bandReport = report;
    log.app('Today: $report', replaceKey: 'today-report');
    _fillVitals();
  }

  /// Requests one file and waits for it (matched by id: the band may push
  /// other files meanwhile); null on timeout. [_ingest] saves and uses it.
  Future<Uint8List?> _fetchFile(
    Link link,
    fitness.FitnessId id, {
    bool quiet = false,
  }) async {
    final file = _files.stream
        .firstWhere((f) => _fileId(f) == id.hex)
        .timeout(const Duration(seconds: 30));
    await link.send(fitness.requestFile(id));
    try {
      final data = await file;
      log.app(
        'Received health file ${id.hex} (${data.length} bytes)',
        replaceKey: quiet ? 'health-file' : null,
      );
      return data;
    } on TimeoutException {
      log.warn('Health file ${id.hex} did not arrive');
      return null;
    }
  }

  void _onFitnessPacket(Uint8List packet) {
    if (facePreviews.feed(packet)) return;
    _lastFitnessPacket = DateTime.now();
    final Uint8List? file;
    try {
      file = _assembler.feed(packet);
    } on FormatException catch (e) {
      log.warn('Dropped health packet: ${e.message}');
      return;
    }
    if (file == null || file.length < fitness.idLength) return;
    _files.add(file);
    final HealthFile parsed;
    try {
      parsed = parseHealthFile(file);
    } on FormatException catch (e) {
      log.warn('Unreadable health file: ${e.message}');
      return;
    }
    if (parsed.kind == HealthFileKind.heartRateSamples) {
      _mergeHeartRate(parsed.heartRate);
    }
    unawaited(_ingest(file));
  }

  void _mergeHeartRate(List<HrSample> samples) {
    final fresh = [
      for (final s in samples)
        if (s.bpm > 0 && !hrHistory.containsKey(s.time)) s,
    ];
    if (fresh.isEmpty) return;
    for (final s in fresh) {
      hrHistory[s.time] = s.bpm;
    }
    while (hrHistory.length > hrHistoryLimit) {
      hrHistory.remove(hrHistory.firstKey());
    }
    _newSamples.add(fresh);
    notifyListeners();
  }

  Future<Directory> _healthDir() => _bandDir('health');

  /// App storage for [kind] files of the paired band.
  Future<Directory> _bandDir(String kind) async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/$kind/$address',
    );
    await dir.create(recursive: true);
    return dir;
  }

  /// Keeps the latest copy of [file]; false when it could not be written.
  Future<bool> _saveHealthFile(Uint8List file) async {
    try {
      final dir = await _healthDir();
      await File('${dir.path}/${_fileId(file)}.bin')
          .writeAsBytes(await atRest.seal(file), flush: true);
      return true;
    } on PlatformException catch (e) {
      log.warn('Could not seal health file: ${e.message}');
      return false;
    } on FileSystemException catch (e) {
      log.warn('Could not save health file: ${e.message}');
      return false;
    }
  }

  // --- band → phone -------------------------------------------------------------------

  void _onBandCommand(Command cmd) {
    if (bandApp.handle(cmd)) return;
    if (phone.handle(cmd)) return;
    final ring = settings.findPhoneAsk(cmd);
    if (ring != null) {
      log.app('Band: ${ring ? 'find phone → ringing' : 'stop finding phone'}');
      unawaited(findPhone(ring: ring));
      return;
    }
    if (isScreenshotPermissionAsk(cmd)) {
      log.app('Band asked to send a screenshot → allowed');
      unawaited(_link?.send(screenshotPermissionGranted()));
      return;
    }
    final dnd = settings.dndMode(cmd);
    if (dnd != null) {
      dndOn = dnd != settings.ScheduleMode.off;
      notifyListeners();
      return;
    }
    final bpm = fitness.realtimeHeartRate(cmd);
    if (bpm != null) {
      if (heartRate != null) {
        heartRate = bpm;
        notifyListeners();
      }
      return;
    }
    final iconPackage = iconRequestPackage(cmd);
    if (iconPackage != null) {
      unawaited(_sendIcon(iconPackage));
    } else if (cmd.isA(typeNotify, callEndSubtype)) {
      log.app('Band pressed end call → ending phone call');
      unawaited(endPhoneCall());
    } else if (cmd.isA(typeNotify, callSilenceSubtype)) {
      log.app('Band pressed mute → silencing ringer');
      unawaited(silenceRinger());
    }
  }

  Future<void> _sendIcon(String package) async {
    final link = _link;
    if (link == null) return;
    try {
      final spec = parseIconSpec(await link.request(prepareIcon(package)));
      if (spec.status != 0 || spec.size == 0) {
        log.warn('Band declined the icon for $package');
        return;
      }
      final rgba =
          await appIconRgba(package, spec.size) ??
          _placeholderIcon(package, spec.size);
      final sent = await upload(
        link,
        dataAppIcon,
        encodeIconPixels(rgba, spec.pixelFormat),
      );
      log.app(
        sent
            ? 'Sent ${spec.size}×${spec.size} icon for $package'
            : 'Band already has the icon for $package',
      );
    } on Exception catch (e) {
      log.warn('Icon for $package failed: $e');
    }
  }

  // --- phone → band -------------------------------------------------------------------

  Future<void> _onPhoneEvent(PhoneEvent event) async {
    final link = _link;
    if (link == null) return;
    switch (event) {
      case PhoneFindStopped():
        log.app('Phone found (stopped ringing) → band');
        await link.send(settings.findPhoneStopped());
      case PhoneNotification():
        log.app('Phone notification from ${event.appName} → band');
        bandApp.addNote(
          BandAppNote(
            key: event.key,
            app: event.appName,
            title: event.title,
            text: event.text,
            time: event.time,
            canReply: event.canReply,
          ),
        );
        lastNotification = (
          app: event.appName,
          title: event.title,
          time: DateTime.now(),
        );
        notifyListeners();
        await link.send(
          notification(
            package: event.package,
            appName: event.appName,
            title: event.title,
            text: event.text,
            id: event.id,
            time: event.time,
            key: event.key,
          ),
        );
      case PhoneNotificationRemoved():
        bandApp.removeNote(event.key);
        log.app(
          'Notification from ${event.package} dismissed → removed from band',
        );
        await link.send(
          removeNotification(
            package: event.package,
            id: event.id,
            key: event.key,
          ),
        );
      case PhoneCall(state: 'ringing'):
        if (_callRinging) return; // the broadcast fires twice
        log.app(
          'Incoming call ${event.name.isEmpty ? event.number : event.name} → band',
        );
        _callRinging = true;
        await link.send(incomingCall(event.name, event.number, DateTime.now()));
      case PhoneCall():
        if (!_callRinging) return;
        _callRinging = false;
        log.app(
          'Call ${event.state == 'offhook' ? 'answered' : 'ended'} → stop ringing on band',
        );
        await link.send(callEnded());
    }
  }

  // --- helpers ----------------------------------------------------------------------------

  void _set(BandState s, {String? error}) {
    state = s;
    this.error = error;
    notifyListeners();
  }

  @override
  void dispose() {
    _rebuildTimer?.cancel();
    unawaited(healthConnect.flush());
    healthConnect.dispose();
    log.dispose();
    unawaited(disconnect());
    unawaited(_files.close());
    super.dispose();
  }
}

Uint8List _unhex(String s) => Uint8List.fromList([
  for (var i = 0; i + 1 < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

/// A filled circle in a colour derived from the package name (when the app has no icon).
Uint8List _placeholderIcon(String package, int size) {
  final h = package.hashCode;
  final r = 0x40 | (h & 0xFF),
      g = 0x40 | ((h >> 8) & 0xFF),
      b = 0x40 | ((h >> 16) & 0xFF);
  final out = Uint8List(size * size * 4);
  final c = (size - 1) / 2, r2 = (size / 2) * (size / 2);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if ((x - c) * (x - c) + (y - c) * (y - c) > r2) continue;
      out.setAll((y * size + x) * 4, [r, g, b, 255]);
    }
  }
  return out;
}

String _fileId(Uint8List file) =>
    fitness.FitnessId(file.sublist(0, fitness.idLength)).hex;
