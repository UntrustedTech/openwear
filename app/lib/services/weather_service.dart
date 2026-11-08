/// Weather for the band from Open-Meteo (free, no account), cached for an hour.
/// Only the approximate location is sent, to api.open-meteo.com.
library;

import 'dart:async';

import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:openwear/cloud/http_backend.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/weather.dart';

const _host = 'api.open-meteo.com';
const _cacheFor = Duration(hours: 1);
const _hoursAhead = 24;

class WeatherBundle {
  const WeatherBundle(this.place, this.current, this.daily, this.hourly);
  final WeatherPlace place;
  final CurrentWeather current;
  final List<DailyWeather> daily;
  final List<HourlyWeather> hourly;

  /// Always Celsius: the band converts to its own unit.
  List<Command> commands() => [
    currentWeatherCommand(place, current),
    dailyForecastCommand(place, daily),
    hourlyForecastCommand(place, hourly),
    if (current.pressureHpa case final hpa?) pressureCommand(hpa),
  ];

  String get summary =>
      '${place.name} [${place.key}]: ${current.temperature}°, code ${current.code}, '
      '${daily.length} days, ${hourly.length} hours';
}

typedef Locate = Future<({double lat, double lon, String place})?> Function();

/// The band-style city key and name for a place, or null when unknown.
typedef LookupCity = Future<({String key, String name})?> Function(
  double lat,
  double lon,
);

class WeatherService {
  WeatherService({required this.locate, this.backend});

  final Locate locate;
  final HttpBackend? backend;
  WeatherBundle? _cached;
  DateTime? _fetchedAt;

  WeatherBundle? get latest => _cached;

  /// Xiaomi's city key for a place. The band's weather app only shows
  /// weather filed under a city it knows, so the key comes from the same
  /// service Mi Fitness asks. Without it [fallbackCityKey] is used.
  LookupCity? lookupCity;
  String? _cityAt;
  ({String key, String name})? _city;

  /// Why the last city lookup failed, for the log.
  String? cityError;

  Future<({String key, String name})?> _cityFor(double lat, double lon) async {
    final lookup = lookupCity;
    if (lookup == null) return null;
    final at = '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';
    if (_cityAt == at && _city != null) return _city;
    try {
      final c = await lookup(lat, lon).timeout(const Duration(seconds: 20));
      cityError = c == null ? 'Xiaomi knows no city here' : null;
      if (c != null) {
        _cityAt = at;
        _city = c;
      }
      return c;
    } on TimeoutException {
      cityError = 'Xiaomi weather timed out';
    } on Exception catch (e) {
      cityError = '$e';
    }
    return _cityAt == at ? _city : null;
  }

  /// Fresh or cached weather; throws [WeatherException] when unavailable.
  Future<WeatherBundle> get({bool force = false}) async {
    final at = _fetchedAt, cached = _cached;
    if (!force &&
        cached != null &&
        at != null &&
        DateTime.now().difference(at) < _cacheFor) {
      return cached;
    }
    final ({double lat, double lon, String place})? where;
    try {
      where = await locate().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const WeatherException(
        'The phone took too long to find your location.',
      );
    } on PlatformException catch (e) {
      throw WeatherException(e.message ?? 'Location unavailable (${e.code})');
    }
    if (where == null) {
      throw const WeatherException(
        'No location yet — allow approximate location for OpenWear.',
      );
    }
    final url = Uri.https(_host, '/v1/forecast', {
      'latitude': where.lat.toStringAsFixed(2),
      'longitude': where.lon.toStringAsFixed(2),
      'current':
          'temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,'
          'wind_direction_10m,surface_pressure,uv_index',
      'hourly': 'temperature_2m,weather_code,wind_speed_10m',
      'daily':
          'weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset',
      'timezone': 'auto',
      'forecast_days': '$maxDailyDays',
    });
    final HttpReply reply;
    try {
      reply = await (backend ?? httpBackend).send(
        'GET',
        url,
        headers: const {},
        timeout: const Duration(seconds: 15),
      );
    } on NetworkException catch (e) {
      throw WeatherException('Open-Meteo unreachable ($e)');
    }
    if (reply.status != 200) {
      throw WeatherException('Open-Meteo answered HTTP ${reply.status}');
    }
    final city = await _cityFor(where.lat, where.lon);
    final name = where.place.isNotEmpty
        ? where.place
        : (city?.name.isNotEmpty ?? false)
        ? city!.name
        : 'Current location';
    final place = WeatherPlace(
      name: name,
      key: city?.key ?? fallbackCityKey(name),
      published: DateTime.now(),
    );
    final WeatherBundle bundle;
    try {
      bundle = parseOpenMeteo(
        jsonDecode(reply.body) as Map<String, dynamic>,
        place,
        now: DateTime.now(),
      );
    } on FormatException catch (e) {
      throw WeatherException('Open-Meteo sent unreadable data (${e.message})');
      // A field of an unexpected type in the server's answer.
      // ignore: avoid_catching_errors
    } on TypeError catch (e) {
      throw WeatherException('Open-Meteo sent unexpected data ($e)');
    }
    _cached = bundle;
    _fetchedAt = DateTime.now();
    return bundle;
  }
}

class WeatherException implements Exception {
  const WeatherException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Open-Meteo JSON → the band's weather; hourly starts at [now]'s hour.
WeatherBundle parseOpenMeteo(
  Map<String, dynamic> json,
  WeatherPlace place, {
  required DateTime now,
}) {
  final c = json['current'] as Map<String, dynamic>;
  int round(Object? v) => (v as num? ?? 0).round();
  double dbl(Object? v) => (v as num? ?? 0).toDouble();
  final current = CurrentWeather(
    code: xiaomiWeatherCode(round(c['weather_code'])),
    temperature: round(c['temperature_2m']),
    humidity: round(c['relative_humidity_2m']),
    windKmh: dbl(c['wind_speed_10m']),
    windDirection: _compass(dbl(c['wind_direction_10m'])),
    uvIndex: round(c['uv_index']),
    pressureHpa: c['surface_pressure'] == null
        ? null
        : dbl(c['surface_pressure']),
  );

  final d = json['daily'] as Map<String, dynamic>;
  List<T> col<T>(Map<String, dynamic> m, String k) =>
      ((m[k] as List?) ?? const []).cast<T>();
  final codes = col<num>(d, 'weather_code');
  final highs = col<num>(d, 'temperature_2m_max');
  final lows = col<num>(d, 'temperature_2m_min');
  final rises = col<String>(d, 'sunrise');
  final sets = col<String>(d, 'sunset');
  // Open-Meteo gives local "2026-11-03T06:41"; the band wants the offset.
  final offset = isoOffset(now.timeZoneOffset);
  String clock(List<String> l, int i) => i < l.length && l[i].length >= 16
      ? '${l[i].substring(0, 16)}:00$offset'
      : '';
  final daily = [
    for (
      var i = 0;
      i < codes.length && i < highs.length && i < lows.length;
      i++
    )
      DailyWeather(
        dayCode: xiaomiWeatherCode(codes[i].round()),
        nightCode: xiaomiWeatherCode(codes[i].round()),
        high: highs[i].round(),
        low: lows[i].round(),
        sunrise: clock(rises, i),
        sunset: clock(sets, i),
      ),
  ];

  final h = json['hourly'] as Map<String, dynamic>;
  final times = col<String>(h, 'time');
  final hCodes = col<num>(h, 'weather_code');
  final temps = col<num>(h, 'temperature_2m');
  final winds = col<num>(h, 'wind_speed_10m');
  final hourKey =
      '${now.year}-${_two(now.month)}-${_two(now.day)}T${_two(now.hour)}:00';
  final start = times.indexOf(hourKey).clamp(0, times.length);
  final hourly = [
    for (
      var i = start;
      i < times.length &&
          i < start + _hoursAhead &&
          i < hCodes.length &&
          i < temps.length;
      i++
    )
      HourlyWeather(
        code: xiaomiWeatherCode(hCodes[i].round()),
        temperature: temps[i].round(),
        windKmh: i < winds.length ? winds[i].toDouble() : 0,
      ),
  ];
  return WeatherBundle(place, current, daily, hourly);
}

String _two(int n) => n.toString().padLeft(2, '0');

String _compass(double degrees) {
  const names = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  return names[((degrees % 360) / 45).round() % 8];
}
