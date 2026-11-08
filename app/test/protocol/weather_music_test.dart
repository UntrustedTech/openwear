import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/music.dart';
import 'package:openwear/protocol/pb.dart';
import 'package:openwear/protocol/weather.dart';

int unzigzag(int v) => (v >> 1) ^ -(v & 1);

final place = WeatherPlace(
  name: 'New York',
  key: '40.71,-74.01',
  published: DateTime(2026, 10, 31, 10, 30),
);

void main() {
  group('weather', () {
    test('WMO codes map onto the Xiaomi set', () {
      expect(xiaomiWeatherCode(0), XiaomiWeather.sunny);
      expect(xiaomiWeatherCode(3), XiaomiWeather.overcast);
      expect(xiaomiWeatherCode(45), XiaomiWeather.fog);
      expect(xiaomiWeatherCode(63), XiaomiWeather.moderateRain);
      expect(xiaomiWeatherCode(75), XiaomiWeather.heavySnow);
      expect(xiaomiWeatherCode(95), XiaomiWeather.thunderShower);
      expect(xiaomiWeatherCode(12345), XiaomiWeather.cloudy);
    });

    test('wind level follows the Mi Fitness thresholds', () {
      expect(windLevel(0.5), 0);
      expect(windLevel(5), 1);
      expect(windLevel(25), 4);
      expect(windLevel(130), 12);
    });

    test('current conditions carry place, code, temperature, humidity', () {
      final cmd = currentWeatherCommand(
        place,
        const CurrentWeather(
          code: XiaomiWeather.cloudy,
          temperature: -3,
          humidity: 64,
          windKmh: 14,
          pressureHpa: 1013.5,
        ),
      );
      final back = Command.decode(cmd.encode());
      expect((back.type, back.subtype), (10, 0));
      final w = back.body.message(1)!;
      final p = w.message(1)!;
      expect(p.string(2), 'New York');
      expect(p.string(4), '40.71,-74.01');
      expect(p.string(1), startsWith('2026-10-31T10:30:00'));
      expect(w.int_(2), XiaomiWeather.cloudy);
      expect(w.message(3)!.string(1), '℃');
      expect(unzigzag(w.message(3)!.int_(2)), -3);
      expect(unzigzag(w.message(4)!.int_(2)), 64);
      expect(unzigzag(w.message(5)!.int_(2)), 3, reason: '14 km/h = level 3');
      final pa = ByteData.sublistView(w.bytes(9)!).getFloat32(0, Endian.little);
      expect(pa, closeTo(101350, 1), reason: 'pressure in Pa, like Mi Fitness');
      expect(w.bytes(8), isEmpty, reason: 'empty alert list, like Mi Fitness');
    });

    test('city list round-trips and keeps our place first', () {
      const here = WeatherCity('40.71,-74.01', 'New York');
      final merged = withCurrentCity([
        const WeatherCity('40.70,-74.00', 'Earlier fix'),
        const WeatherCity('accu:1', 'Paris'),
        here,
      ], here);
      expect(merged, [here]);
      final cmd = Command.decode(cityListCommand(merged).encode());
      expect((cmd.type, cmd.subtype), (10, 6));
      expect(parseCityList(cmd), merged);
      expect((cityListRequest().type, cityListRequest().subtype), (10, 5));
    });

    test('daily forecast is capped at 7 days with high/low and sun times', () {
      final days = List.generate(
        9,
        (i) => DailyWeather(
          dayCode: 0,
          nightCode: 1,
          high: 20 + i,
          low: 10 - i,
          sunrise: '07:2$i',
          sunset: '17:5$i',
        ),
      );
      final back = Command.decode(dailyForecastCommand(place, days).encode());
      final list = back.body.message(2)!.message(2)!.messages(1);
      expect(list, hasLength(7));
      expect(unzigzag(list.first.message(3)!.int_(1)), 20);
      expect(unzigzag(list.first.message(3)!.int_(2)), 10);
      expect(list[6].message(5)!.string(1), '07:26');
    });

    test('hourly forecast keeps code and temperature in the "to" slot', () {
      final back = Command.decode(
        hourlyForecastCommand(place, const [
          HourlyWeather(code: 7, temperature: 12, windKmh: 30),
        ]).encode(),
      );
      expect((back.type, back.subtype), (10, 2));
      final h = back.body.message(2)!.message(2)!.messages(1).single;
      expect(unzigzag(h.message(2)!.int_(2)), 7);
      expect(unzigzag(h.message(3)!.int_(2)), 12);
      expect(unzigzag(h.message(6)!.int_(2)), 5);
    });
  });

  group('music', () {
    test('player state carries title, artist, position and volume', () {
      final cmd = playerStateCommand(
        const PlayerInfo(
          state: PlayerState.playing,
          title: 'Song',
          artist: 'Band',
          positionS: 42,
          durationS: 200,
          volumePercent: 130,
        ),
      );
      final p = Command.decode(cmd.encode()).body.message(1)!;
      expect(p.int_(1), 1);
      expect(p.int_(2), 100, reason: 'volume is clamped');
      expect(p.string(4), 'Song');
      expect(p.string(5), 'Band');
      expect((p.int_(6), p.int_(7)), (42, 200));
    });

    test('band controls are decoded', () {
      Command control(int code, [int volume = 0]) => Command.of(18, 2, [
        PbBytes(2, pbEncode([PbVarint(1, code), PbVarint(2, volume)])),
      ]);
      expect(musicControl(control(0))!.$1, MusicControl.play);
      expect(musicControl(control(4))!.$1, MusicControl.next);
      expect(musicControl(control(5, 60)), (MusicControl.volume, 60));
      expect(musicControl(const Command(18, 0)), isNull);
      expect(isMusicRequest(const Command(18, 0)), isTrue);
    });
  });

  test('band weather unit: 1 Celsius, 2 Fahrenheit, in field 6', () {
    final set = Command.decode(weatherUnitCommand(fahrenheit: true).encode());
    expect(set.isA(10, 10), isTrue);
    expect(set.body.message(6)!.int_(1), 2);
    expect(weatherConfigRequest().isA(10, 9), isTrue);
    final reply = Command.decode(set.encode());
    expect(parseWeatherConfig(reply)!.fahrenheit, isTrue);
    expect(parseWeatherConfig(const Command(10, 9)), isNull);
  });

  test('10/7 sets the current weather city in field 5', () {
    final cmd = Command.decode(
      currentCityCommand(const WeatherCity('accu:349727', 'Paris')).encode(),
    );
    expect(cmd.isA(10, 7), isTrue);
    expect(cmd.body.message(5)?.string(1), 'accu:349727');
    expect(cmd.body.message(5)?.string(2), 'Paris');
  });

  test('fallback city keys are stable accu numbers', () {
    expect(fallbackCityKey('New York'), fallbackCityKey('New York'));
    expect(fallbackCityKey('New York'), isNot(fallbackCityKey('Riverton')));
    expect(fallbackCityKey('New York'), matches(RegExp(r'^accu:\d{1,6}$')));
  });

  test('hourly entries carry both ends of their ranges', () {
    final place = WeatherPlace(
      name: 'X',
      key: 'accu:1',
      published: DateTime(2026),
    );
    final cmd = Command.decode(
      hourlyForecastCommand(place, const [
        HourlyWeather(code: 7, temperature: 12, windKmh: 0),
      ]).encode(),
    );
    final entry = cmd.body.message(2)!.message(2)!.messages(1).single;
    expect(entry.message(3)!.has(1), isTrue);
    expect(entry.message(3)!.int_(2), 24, reason: "zigzag of 12");
    expect(entry.message(2)!.int_(2), 14, reason: "zigzag of 7");
  });

  test('city command statuses read as Gadgetbridge documents them', () {
    expect(cityStatusLabel(0), 'ok');
    expect(cityStatusLabel(1), 'not supported');
    expect(cityStatusLabel(3), 'already there');
  });
}
