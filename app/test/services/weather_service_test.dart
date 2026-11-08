import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/cloud/http_backend.dart';
import 'package:openwear/protocol/weather.dart';
import 'package:openwear/services/weather_service.dart';

/// Real Open-Meteo output for New York (public coordinates), 2026-10-31.
final fixture = File('test/fixtures/open_meteo.json').readAsStringSync();

class FixtureBackend implements HttpBackend {
  final urls = <Uri>[];
  @override
  String get name => 'fixture';
  @override
  Future<HttpReply> send(
    String method,
    Uri url, {
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async {
    urls.add(url);
    return HttpReply(200, fixture);
  }
}

void main() {
  final place = WeatherPlace(
    name: 'New York',
    key: '40.71,-74.01',
    published: DateTime(2026, 10, 31, 10, 30),
  );

  test('Open-Meteo output becomes current, 7-day and 24-hour weather', () {
    final b = parseOpenMeteo(
      jsonDecode(fixture) as Map<String, dynamic>,
      place,
      now: DateTime(2026, 10, 31, 10, 30),
    );
    expect(b.current.temperature, 12);
    expect(b.current.humidity, 51);
    expect(b.current.code, XiaomiWeather.sunny);
    expect(b.current.windDirection, 'N');
    expect(b.current.pressureHpa, closeTo(1025.9, 0.01));
    expect(b.daily, hasLength(7));
    expect(b.daily.first.sunrise, startsWith('2026-10-31T07:25:00'));
    expect(b.daily.first.sunrise, matches(RegExp(r'[+-]\d\d:\d\d$')));
    expect(b.daily.first.high, greaterThanOrEqualTo(b.daily.first.low));
    expect(b.hourly, hasLength(24));
    expect(b.commands().map((c) => c.subtype), [0, 1, 2, 4]);
  });

  test(
    'the service caches for an hour and sends only rounded coordinates',
    () async {
      final backend = FixtureBackend();
      final service = WeatherService(
        locate: () async =>
            (lat: 40.712776, lon: -74.005974, place: 'New York'),
        backend: backend,
      );
      final first = await service.get();
      await service.get();
      expect(backend.urls, hasLength(1));
      expect(backend.urls.single.queryParameters['latitude'], '40.71');
      expect(backend.urls.single.queryParameters['longitude'], '-74.01');
      expect(first.place.name, 'New York');
      await service.get(force: true);
      expect(backend.urls, hasLength(2));
    },
  );

  test('no location gives a clear message', () async {
    final service = WeatherService(
      locate: () async => null,
      backend: FixtureBackend(),
    );
    await expectLater(
      service.get(),
      throwsA(
        isA<WeatherException>().having(
          (e) => e.message,
          'message',
          contains('location'),
        ),
      ),
    );
  });

  test('weather is filed under Xiaomi\'s city key when there is one', () async {
    var asked = 0;
    final service =
        WeatherService(
            locate: () async => (lat: 41.250, lon: -73.500, place: ''),
            backend: FixtureBackend(),
          )
          ..lookupCity = (lat, lon) async {
            asked++;
            return (key: 'accu:349530', name: 'Riverton');
          };
    final b = await service.get();
    expect(b.place.key, 'accu:349530');
    expect(b.place.name, 'Riverton');
    await service.get(force: true);
    expect(asked, 1, reason: 'the city is looked up once per place');
  });

  test('a failed city lookup falls back to an accu-style key', () async {
    final service = WeatherService(
      locate: () async => (lat: 41.250, lon: -73.500, place: 'Riverton'),
      backend: FixtureBackend(),
    )..lookupCity = (_, _) async => throw const FormatException('down');
    final b = await service.get();
    expect(b.place.key, fallbackCityKey('Riverton'));
    expect(b.place.key, matches(RegExp(r'^accu:\d+$')));
    expect(service.cityError, contains('down'));
  });
}
