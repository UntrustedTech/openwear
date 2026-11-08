/// Weather pushes (type 10), as Mi Fitness sends them (docs/protocol/03-commands.md):
/// 10/0 current conditions, 10/1 daily forecast (≤ 7 days), 10/2 hourly forecast.
/// The band asks for an update with 10/3.
library;

import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/pb.dart';

const typeWeather = 10;
const weatherRequestSubtype = 3;
const _subCurrent = 0, _subDaily = 1, _subHourly = 2, _subPressure = 4;
const _fPressure = 3;
const _subCityListGet = 5, _subCityListSet = 6, _subCurrentCity = 7;
const _fCurrent = 1, _fForecast = 2, _fCityList = 4, _fRequestCity = 5;
const maxDailyDays = 7;

/// Xiaomi weather codes (the China Meteorological Administration set).
abstract final class XiaomiWeather {
  static const sunny = 0, cloudy = 1, overcast = 2, shower = 3;
  static const thunderShower = 4, thunderHail = 5, sleet = 6;
  static const lightRain = 7, moderateRain = 8, heavyRain = 9, storm = 10;
  static const snowFlurry = 13, lightSnow = 14, moderateSnow = 15;
  static const heavySnow = 16, fog = 18, freezingRain = 19;
}

/// WMO weather interpretation code (Open-Meteo) → Xiaomi weather code.
int xiaomiWeatherCode(int wmo) => switch (wmo) {
  0 || 1 => XiaomiWeather.sunny,
  2 => XiaomiWeather.cloudy,
  3 => XiaomiWeather.overcast,
  45 || 48 => XiaomiWeather.fog,
  51 || 53 || 55 || 61 => XiaomiWeather.lightRain,
  56 || 57 || 66 || 67 => XiaomiWeather.freezingRain,
  63 => XiaomiWeather.moderateRain,
  65 => XiaomiWeather.heavyRain,
  71 => XiaomiWeather.lightSnow,
  73 => XiaomiWeather.moderateSnow,
  75 || 86 => XiaomiWeather.heavySnow,
  77 || 85 => XiaomiWeather.snowFlurry,
  80 || 81 => XiaomiWeather.shower,
  82 => XiaomiWeather.storm,
  95 => XiaomiWeather.thunderShower,
  96 || 99 => XiaomiWeather.thunderHail,
  _ => XiaomiWeather.cloudy,
};

/// Beaufort-like wind level Mi Fitness derives from km/h.
int windLevel(double kmh) {
  const limits = [1, 6, 12, 20, 29, 39, 50, 62, 75, 89, 103, 117];
  var level = 0;
  for (final l in limits) {
    if (kmh >= l) level++;
  }
  return level;
}

class WeatherPlace {
  const WeatherPlace({
    required this.name,
    required this.key,
    required this.published,
    this.isCurrentLocation = true,
  });
  final String name;
  final String key; // stable id for the place, e.g. "lat,lon"
  final DateTime published;
  final bool isCurrentLocation;
}

class CurrentWeather {
  const CurrentWeather({
    required this.code,
    required this.temperature,
    required this.humidity,
    required this.windKmh,
    this.windDirection = '',
    this.uvIndex = 0,
    this.pressureHpa,
  });
  final int code; // Xiaomi code
  final int temperature;
  final int humidity;
  final double windKmh;
  final String windDirection;
  final int uvIndex;
  final double? pressureHpa;
}

class DailyWeather {
  const DailyWeather({
    required this.dayCode,
    required this.nightCode,
    required this.high,
    required this.low,
    this.sunrise = '',
    this.sunset = '',
  });
  final int dayCode;
  final int nightCode;
  final int high;
  final int low;
  final String sunrise; // ISO-8601 with offset, as Xiaomi's server sends it
  final String sunset;
}

class HourlyWeather {
  const HourlyWeather({
    required this.code,
    required this.temperature,
    required this.windKmh,
    this.windDirection = '',
  });
  final int code;
  final int temperature;
  final double windKmh;
  final String windDirection;
}

/// The band always gets Celsius with this symbol, as Mi Fitness sends it;
/// the band converts to °F itself. Sending "℉" values makes it show 0.
const temperatureUnit = '℃';

/// The band's own weather settings (a3u field 6): how it shows
/// temperatures and whether it raises weather alerts. 10/9 reads them,
/// 10/10 changes them; 0 in a field means "leave as is" / not supported.
class BandWeatherConfig {
  const BandWeatherConfig({this.unit = 0, this.alerts = 0});

  /// 1 Celsius, 2 Fahrenheit.
  final int unit;

  /// 1 on, 2 off (0 unknown).
  final int alerts;

  bool get fahrenheit => unit == 2;

  @override
  String toString() =>
      'unit ${switch (unit) {
        1 => '°C',
        2 => '°F',
        _ => 'unset',
      }}, alerts ${alerts == 1 ? 'on' : 'off'}';
}

const _fConfig = 6, _subConfigGet = 9, _subConfigSet = 10;
const bandCelsius = 1, bandFahrenheit = 2;

Command weatherConfigRequest() => const Command(typeWeather, _subConfigGet);

BandWeatherConfig? parseWeatherConfig(Command rsp) {
  final m = rsp.body.message(_fConfig);
  if (m == null) return null;
  return BandWeatherConfig(unit: m.int_(1), alerts: m.int_(2));
}

/// Sets the band's display unit (alerts untouched).
Command weatherUnitCommand({required bool fahrenheit}) =>
    Command.of(typeWeather, _subConfigSet, [
      PbBytes(
        _fConfig,
        pbEncode([PbVarint(1, fahrenheit ? bandFahrenheit : bandCelsius)]),
      ),
    ]);

/// 10/4: air pressure in Pa (Mi Fitness also sends it on its own).
Command pressureCommand(double hpa) =>
    Command.of(typeWeather, _subPressure, [PbFloat(_fPressure, hpa * 100)]);

List<int> _place(WeatherPlace p) => pbEncode([
  PbString(1, _isoWithOffset(p.published)),
  PbString(2, p.name),
  PbString(3, p.name),
  PbString(4, p.key),
  PbBool(5, p.isCurrentLocation),
]);

List<int> _keyValue(String key, int value) =>
    pbEncode([PbString(1, key), PbSint(2, value)]);

List<int> _range(int from, int to) =>
    pbEncode([PbSint(1, from), PbSint(2, to)]);

Command currentWeatherCommand(WeatherPlace place, CurrentWeather w) {
  final pressure = w.pressureHpa;
  return Command.of(typeWeather, _subCurrent, [
    PbBytes(
      _fCurrent,
      pbEncode([
        PbBytes(1, _place(place)),
        PbVarint(2, w.code),
        PbBytes(3, _keyValue(temperatureUnit, w.temperature)),
        PbBytes(4, _keyValue('%', w.humidity)),
        PbBytes(5, _keyValue(w.windDirection, windLevel(w.windKmh))),
        PbBytes(6, _keyValue('', w.uvIndex)),
        PbBytes(7, _keyValue('', 0)),
        // Alerts: Mi Fitness always sends this list, empty when there are
        // none (BlueToothSender.getAlertsList).
        const PbBytes(8, <int>[]),
        // Mi Fitness converts the server's hPa/mbar to Pa.
        if (pressure != null) PbFloat(9, pressure * 100),
      ]),
    ),
  ]);
}

Command dailyForecastCommand(WeatherPlace place, List<DailyWeather> days) =>
    Command.of(typeWeather, _subDaily, [
      PbBytes(
        _fForecast,
        pbEncode([
          PbBytes(1, _place(place)),
          PbBytes(
            2,
            pbEncode([
              for (final d in days.take(maxDailyDays))
                PbBytes(
                  1,
                  pbEncode([
                    PbBytes(1, _keyValue('', 0)),
                    PbBytes(2, _range(d.dayCode, d.nightCode)),
                    PbBytes(3, _range(d.high, d.low)),
                    PbString(4, temperatureUnit),
                    PbBytes(
                      5,
                      pbEncode([PbString(1, d.sunrise), PbString(2, d.sunset)]),
                    ),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    ]);

Command hourlyForecastCommand(
  WeatherPlace place,
  List<HourlyWeather> hours,
) => Command.of(typeWeather, _subHourly, [
  PbBytes(
    _fForecast,
    pbEncode([
      PbBytes(1, _place(place)),
      PbBytes(
        2,
        pbEncode([
          for (final h in hours)
            PbBytes(
              1,
              pbEncode([
                PbBytes(1, _keyValue('', 0)),
                // "from" is unused for hours but the band needs it set.
                PbBytes(2, _range(0, h.code)),
                PbBytes(3, _range(0, h.temperature)),
                PbString(4, temperatureUnit),
                PbBytes(6, _keyValue(h.windDirection, windLevel(h.windKmh))),
              ]),
            ),
        ]),
      ),
    ]),
  ),
]);

/// A city in the band's weather list. The band shows weather only for
/// cities in this list, so the current location must be in it (first).
class WeatherCity {
  const WeatherCity(this.key, this.name);
  final String key;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is WeatherCity && other.key == key && other.name == name;

  @override
  int get hashCode => Object.hash(key, name);

  @override
  String toString() => '$name ($key)';
}

/// 10/7: makes [city] the band's current weather city, adding it when
/// missing. Bands that keep a single weather city (the Band 9 among them)
/// refuse the list write (10/6) and only take this.
Command currentCityCommand(WeatherCity city) =>
    Command.of(typeWeather, _subCurrentCity, [
      PbBytes(
        _fRequestCity,
        pbEncode([PbString(1, city.key), PbString(2, city.name)]),
      ),
    ]);

/// What the band's status on a city command means (Gadgetbridge's reading).
String cityStatusLabel(int? status) => switch (status) {
  null || 0 => 'ok',
  1 => 'not supported',
  3 => 'already there',
  _ => 'status $status',
};

/// A Xiaomi-style key for a place when Xiaomi's own lookup is unavailable
/// (signed out). The band ignores weather under keys it can't read, such
/// as "lat,lon"; an `accu:` number like the server's works. The number is
/// a stable hash of [name], so the same place keeps the same key.
String fallbackCityKey(String name) {
  var h = 0;
  for (final unit in name.codeUnits) {
    h = (31 * h + unit) & 0x7fffffff;
  }
  return 'accu:${h % 1000000}';
}

Command cityListRequest() => const Command(typeWeather, _subCityListGet);

List<WeatherCity> parseCityList(Command reply) => [
  for (final c in reply.body.message(_fCityList)?.messages(1) ?? const [])
    if (c.string(1).isNotEmpty) WeatherCity(c.string(1), c.string(2)),
];

Command cityListCommand(List<WeatherCity> cities) =>
    Command.of(typeWeather, _subCityListSet, [
      PbBytes(
        _fCityList,
        pbEncode([
          for (final c in cities)
            PbBytes(1, pbEncode([PbString(1, c.key), PbString(2, c.name)])),
        ]),
      ),
    ]);

/// The list we want on the band: only the current location. Cities left
/// by another app would have no weather from us, and the band shows 0 for
/// them when one is selected.
List<WeatherCity> withCurrentCity(
  List<WeatherCity> onBand,
  WeatherCity current,
) => [current];

/// The city the band asks weather for (10/3 field 5), if it names one.
WeatherCity? requestedCity(Command cmd) {
  final c = cmd.body.message(_fRequestCity);
  if (c == null || c.string(1).isEmpty) return null;
  return WeatherCity(c.string(1), c.string(2));
}

bool isWeatherRequest(Command cmd) =>
    cmd.isA(typeWeather, weatherRequestSubtype);

String _isoWithOffset(DateTime t) {
  String two(int n) => n.abs().toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:${two(t.minute)}:'
      '${two(t.second)}${isoOffset(t.timeZoneOffset)}';
}

/// "+01:00" / "-05:00".
String isoOffset(Duration o) {
  String two(int n) => n.abs().toString().padLeft(2, '0');
  final sign = o.isNegative ? '-' : '+';
  return '$sign${two(o.inHours)}:${two(o.inMinutes % 60)}';
}
