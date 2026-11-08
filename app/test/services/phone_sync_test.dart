import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/cloud/http_backend.dart';
import 'package:openwear/platform/android_bridge.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/pb.dart';
import 'package:openwear/protocol/weather.dart';
import 'package:openwear/services/band_log.dart';
import 'package:openwear/services/phone_sync.dart';
import 'package:openwear/services/weather_service.dart';

final fixture = File('test/fixtures/open_meteo.json').readAsStringSync();

class FixtureBackend implements HttpBackend {
  var calls = 0;
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
    calls++;
    return HttpReply(200, fixture);
  }
}

class Harness {
  Harness({bool located = true}) {
    sync = PhoneSync(
      log: log,
      weather: WeatherService(
        locate: () async =>
            located ? (lat: 40.71, lon: -74.01, place: 'New York') : null,
        backend: backend,
      ),
      readMedia: () async => media,
      mediaUpdates: () => updates.stream,
      control: (action, {volume}) async => controls.add((action, volume)),
    );
  }

  final log = BandLog();
  final backend = FixtureBackend();
  final updates = StreamController<MediaSnapshot>();
  final sent = <Command>[];
  final requests = <Command>[];
  var bandCities = <WeatherCity>[const WeatherCity('accu:349727', 'Paris')];
  var bandAnswers = true;

  Future<Command> request(Command c) async {
    requests.add(c);
    if (!bandAnswers) throw TimeoutException('no reply');
    if (c.isA(10, 5)) {
      return Command.decode(cityListCommand(bandCities).encode());
    }
    if (c.isA(10, 6)) bandCities = parseCityList(c);
    return Command(c.type, c.subtype);
  }

  final controls = <(String, int?)>[];
  var media = const MediaSnapshot({
    'state': 'playing',
    'title': 'Song',
    'artist': 'Band',
    'volume': 40,
  });
  late final PhoneSync sync;

  Future<void> attach() =>
      sync.attach((c) async => sent.add(c), request: request);
  Iterable<String> get titles => log.entries.map((e) => e.title);
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

Command control(int code, [int volume = 0]) => Command.of(18, 2, [
  PbBytes(2, pbEncode([PbVarint(1, code), PbVarint(2, volume)])),
]);

void main() {
  test('attach pushes current, daily and hourly weather', () async {
    final h = Harness();
    await h.attach();
    await settle();
    expect(h.sent.map((c) => (c.type, c.subtype)), [
      (10, 0),
      (10, 1),
      (10, 2),
      (10, 4),
    ]);
    expect(h.titles.any((t) => t.startsWith('Weather sent')), isTrue);
  });

  test('current location goes first in the band city list', () async {
    final h = Harness()
      ..bandCities = [
        const WeatherCity('51.50,-0.12', 'Old place'),
        const WeatherCity('accu:349727', 'Paris'),
      ];
    await h.attach();
    await settle();
    expect(h.bandCities.map((c) => c.name), ['New York']);
    expect(h.bandCities.first.key, fallbackCityKey('New York'));
    expect(h.sync.weatherSentAt, isNotNull);
    expect(h.sync.weatherError, isNull);
  });

  test('a request for another city rewrites the list', () async {
    final h = Harness()
      ..bandCities = [WeatherCity(fallbackCityKey('New York'), 'New York')];
    await h.attach();
    await settle();
    h.requests.clear();
    h.sync.handle(
      Command.of(10, 3, [
        PbBytes(
          5,
          pbEncode([PbString(1, 'accu:349727'), PbString(2, 'Paris')]),
        ),
      ]),
    );
    await settle();
    expect(h.requests.where((c) => c.isA(10, 6)), hasLength(1));
  });

  test('the city is made current with 10/7 before the weather', () async {
    final h = Harness();
    await h.attach();
    await settle();
    final current = h.requests.firstWhere((c) => c.isA(10, 7));
    expect(current.body.message(5)?.string(1), fallbackCityKey('New York'));
    expect(h.requests.first.isA(10, 7), isTrue);
  });

  test('an unchanged city list is not rewritten', () async {
    final h = Harness()
      ..bandCities = [WeatherCity(fallbackCityKey('New York'), 'New York')];
    await h.attach();
    await settle();
    expect(h.requests.where((c) => c.isA(10, 6)), isEmpty);
  });

  test('a band that does not answer still gets the weather', () async {
    final h = Harness()..bandAnswers = false;
    await h.attach();
    await settle();
    expect(h.sent.map((c) => (c.type, c.subtype)), [
      (10, 0),
      (10, 1),
      (10, 2),
      (10, 4),
    ]);
  });

  test('weather request is answered from the cache', () async {
    final h = Harness();
    await h.attach();
    await settle();
    expect(h.sync.handle(const Command(10, 3)), isTrue);
    await settle();
    expect(h.sent, hasLength(8));
    expect(h.backend.calls, 1);
  });

  test('no location logs a warning and sends nothing', () async {
    final h = Harness(located: false);
    await h.attach();
    await settle();
    expect(h.sent, isEmpty);
    expect(h.titles.any((t) => t.contains('No location')), isTrue);
    expect(h.sync.weatherError, contains('No location'));
  });

  test('weather off sends nothing', () async {
    final h = Harness()..sync.weatherEnabled = false;
    await h.attach();
    await settle();
    expect(h.sent, isEmpty);
  });

  test('music request sends the player state', () async {
    final h = Harness()..sync.weatherEnabled = false;
    await h.attach();
    expect(h.sync.handle(const Command(18, 0)), isTrue);
    await settle();
    final p = h.sent.single.body.message(1)!;
    expect((p.int_(1), p.string(4), p.int_(2)), (1, 'Song', 40));
  });

  test('media changes are pushed once per distinct state', () async {
    final h = Harness()..sync.weatherEnabled = false;
    await h.attach();
    h.updates
      ..add(h.media)
      ..add(h.media);
    await settle();
    await settle();
    expect(h.sent, hasLength(1));
    h.updates.add(const MediaSnapshot({'state': 'paused', 'title': 'Song'}));
    await settle();
    await settle();
    expect(h.sent, hasLength(2));
    expect(h.sent.last.body.message(1)!.int_(1), 2);
  });

  test('band controls reach the phone player', () async {
    final h = Harness()..sync.weatherEnabled = false;
    await h.attach();
    expect(h.sync.handle(control(4)), isTrue);
    expect(h.sync.handle(control(5, 70)), isTrue);
    await settle();
    expect(h.controls, [('next', null), ('volume', 70)]);
  });

  test('other commands are not handled', () async {
    final h = Harness();
    expect(h.sync.handle(const Command(2, 1)), isFalse);
  });

  test('detached sync sends nothing', () async {
    final h = Harness();
    await h.attach();
    await settle();
    await h.sync.detach();
    h.sent.clear();
    h.sync.handle(const Command(10, 3));
    await settle();
    expect(h.sent, isEmpty);
  });
}
