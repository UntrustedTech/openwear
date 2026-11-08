/// Answers the band's requests for phone data: weather (10/3) and music (18/x).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:openwear/platform/android_bridge.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/music.dart';
import 'package:openwear/protocol/weather.dart';
import 'package:openwear/services/band_log.dart';
import 'package:openwear/services/weather_service.dart';

typedef SendCommand = Future<void> Function(Command cmd);
typedef RequestCommand = Future<Command> Function(Command cmd);

class PhoneSync extends ChangeNotifier {
  PhoneSync({
    required this.log,
    WeatherService? weather,
    Future<MediaSnapshot> Function()? readMedia,
    Stream<MediaSnapshot> Function()? mediaUpdates,
    Future<void> Function(String action, {int? volume})? control,
  }) : weather = weather ?? WeatherService(locate: lastLocation),
       _readMedia = readMedia ?? mediaState,
       _mediaUpdates = mediaUpdates ?? mediaChanges,
       _control = control ?? mediaControl;

  final BandLog log;
  final WeatherService weather;
  final Future<MediaSnapshot> Function() _readMedia;
  final Stream<MediaSnapshot> Function() _mediaUpdates;
  final Future<void> Function(String action, {int? volume}) _control;

  bool weatherEnabled = true;
  MediaSnapshot? media;
  SendCommand? _send;
  RequestCommand? _request;
  Timer? _weatherTimer;
  static const weatherEvery = Duration(hours: 1);

  /// Last weather sent to the band, or why it was not.
  DateTime? weatherSentAt;
  String? weatherError;
  bool weatherBusy = false;
  StreamSubscription<MediaSnapshot>? _mediaSub;
  String _lastPushed = '';

  /// Starts serving a freshly authenticated band.
  Future<void> attach(SendCommand send, {RequestCommand? request}) async {
    _send = send;
    _request = request;
    try {
      _mediaSub = _mediaUpdates().listen(
        _onMedia,
        onError: (Object e) {
          log.warn('Music updates stopped: $e');
        },
      );
    } on MissingPluginException {
      // tests / non-Android
    }
    _weatherTimer = Timer.periodic(
      weatherEvery,
      (_) => unawaited(sendWeather()),
    );
    unawaited(sendWeather());
  }

  @override
  void dispose() {
    _weatherTimer?.cancel();
    unawaited(_mediaSub?.cancel());
    super.dispose();
  }

  Future<void> detach() async {
    _send = null;
    _request = null;
    _weatherTimer?.cancel();
    _weatherTimer = null;
    await _mediaSub?.cancel();
    _mediaSub = null;
  }

  /// Handles a band command if it is ours; returns whether it was.
  bool handle(Command cmd) {
    if (isWeatherRequest(cmd)) {
      final asked = requestedCity(cmd);
      log.app('Band asked for weather${asked == null ? '' : ' for $asked'}');
      final ours = weather.latest?.place.key;
      // A city we don't serve: rewrite the list so ours is the only one.
      unawaited(sendWeather(resetCities: asked != null && asked.key != ours));
      return true;
    }
    if (isMusicRequest(cmd)) {
      unawaited(_pushPlayer(force: true));
      return true;
    }
    final control = musicControl(cmd);
    if (control != null) {
      unawaited(_onControl(control.$1, control.$2));
      return true;
    }
    return false;
  }

  Future<void> sendWeather({
    bool force = false,
    bool resetCities = false,
  }) async {
    final send = _send;
    if (send == null || !weatherEnabled || weatherBusy) return;
    weatherBusy = true;
    notifyListeners();
    try {
      final w = await weather.get(force: force);
      final cityError = weather.cityError;
      if (cityError != null) {
        log.warn(
          'Xiaomi weather city not found ($cityError); using coordinates',
        );
      }
      await _syncCityList(
        WeatherCity(w.place.key, w.place.name),
        force: resetCities,
      );
      for (final cmd in w.commands()) {
        await send(cmd);
      }
      weatherSentAt = DateTime.now();
      weatherError = null;
      log.app('Weather sent: ${w.summary}');
    } on WeatherException catch (e) {
      _weatherFailed(e.message);
    } on PlatformException catch (e) {
      _weatherFailed(e.message ?? e.code);
    } on TimeoutException {
      _weatherFailed('the band did not answer');
    } on Exception catch (e) {
      // Anything else (link dropped mid-send…) must still be reported.
      _weatherFailed('$e');
    } finally {
      weatherBusy = false;
      notifyListeners();
    }
  }

  void _weatherFailed(String why) {
    weatherError = why;
    log.warn('Weather not sent: $why');
  }

  /// The band only shows weather for a city it knows. 10/7 makes ours the
  /// current city (single-city bands such as the Band 9 take only this);
  /// bands with a city list also get the list set to just ours.
  Future<void> _syncCityList(WeatherCity current, {bool force = false}) async {
    final request = _request;
    if (request == null) return;
    try {
      final r = await request(currentCityCommand(current));
      log.app('Weather city $current: ${cityStatusLabel(r.status)}');
    } on TimeoutException {
      log.warn('Band did not answer setting the weather city');
    }
    var onBand = const <WeatherCity>[];
    try {
      onBand = parseCityList(await request(cityListRequest()));
    } on TimeoutException {
      log.warn('Band did not list its weather cities');
    }
    final wanted = withCurrentCity(onBand, current);
    if (!force && listEquals(wanted, onBand)) return;
    if (onBand.isNotEmpty) {
      log.app('Weather cities on band were: ${onBand.join(', ')}');
    }
    try {
      final r = await request(cityListCommand(wanted));
      log.app('Weather city list: ${cityStatusLabel(r.status)}');
    } on TimeoutException {
      log.warn('Band did not answer the weather city list');
    }
  }

  Future<void> _pushPlayer({bool force = false}) async {
    final send = _send;
    if (send == null) return;
    MediaSnapshot m;
    try {
      m = media ?? await _readMedia();
    } on PlatformException catch (e) {
      log.warn('Could not read the music player: ${e.message}');
      return;
    }
    media = m;
    final info = playerInfo(m);
    final key =
        '${info.state}|${info.title}|${info.artist}|${info.volumePercent}';
    if (!force && key == _lastPushed) return;
    _lastPushed = key;
    await send(playerStateCommand(info));
  }

  void _onMedia(MediaSnapshot m) {
    media = m;
    unawaited(_pushPlayer());
  }

  Future<void> _onControl(MusicControl control, int volume) async {
    final action = switch (control) {
      MusicControl.play => 'play',
      MusicControl.pause => 'pause',
      MusicControl.next => 'next',
      MusicControl.previous => 'previous',
      MusicControl.volume => 'volume',
      MusicControl.unknown => null,
    };
    if (action == null) {
      log.warn('Band sent an unknown music control');
      return;
    }
    log.app(
      'Band music control: $action${control == MusicControl.volume ? ' $volume%' : ''}',
    );
    try {
      await _control(
        action,
        volume: control == MusicControl.volume ? volume : null,
      );
    } on PlatformException catch (e) {
      log.warn('Music control failed: ${e.message}');
    }
  }
}

PlayerInfo playerInfo(MediaSnapshot m) => PlayerInfo(
  state: switch (m.state) {
    'playing' => PlayerState.playing,
    'paused' => PlayerState.paused,
    'noPermission' => PlayerState.noPermission,
    _ => PlayerState.none,
  },
  title: m.title,
  artist: m.artist,
  positionS: m.positionS,
  durationS: m.durationS,
  volumePercent: m.volume,
);
