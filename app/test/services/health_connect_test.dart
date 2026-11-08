import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/health_records.dart';
import 'package:openwear/services/band_log.dart';
import 'package:openwear/services/health_connect.dart';

class FakeHealthConnect {
  String status = 'notGranted';
  bool grant = true;
  int settingsOpened = 0;
  final writes = <List<Map<String, Object>>>[];
  final recordWrites = <List<Map<String, Object>>>[];
  PlatformException? failWith;

  HealthConnectApi get api => (
    status: () async => status,
    request: () async {
      if (grant) status = 'granted';
      return grant;
    },
    openSettings: () async => settingsOpened++,
    writeHeartRate: (records) async {
      final f = failWith;
      if (f != null) throw f;
      writes.add(records);
      return records.length;
    },
    writeRecords: (records) async {
      final f = failWith;
      if (f != null) throw f;
      recordWrites.add(records);
      return records.length;
    },
  );
}

DateTime t(int minute, int second) =>
    DateTime(2026, 10, 31, 10, minute, second);

void main() {
  group('heartRateBuckets', () {
    final history = SplayTreeMap<DateTime, int>.from({
      t(19, 53): 110,
      t(19, 59): 109,
      t(20, 0): 108,
      t(20, 31): 107,
      t(22, 5): 90,
    });

    test('groups samples by minute, only for the minutes asked', () {
      final b = heartRateBuckets(history, [t(19, 55), t(20, 10), t(20, 40)]);
      expect(b, hasLength(2));
      expect(b[0].samples.map((s) => s.$2), [110, 109]);
      expect(b[1].samples.map((s) => s.$2), [108, 107]);
    });

    test('ids are stable per minute and versions grow with samples', () {
      final first = heartRateBuckets(history, [t(20, 0)]).single;
      final grown = heartRateBuckets(
        SplayTreeMap.from({...history, t(20, 45): 106}),
        [t(20, 0)],
      ).single;
      expect(grown.id, first.id);
      expect(grown.version, first.version + 1);
      expect(first.toJson()['samples'], [
        [t(20, 0).millisecondsSinceEpoch, 108],
        [t(20, 31).millisecondsSinceEpoch, 107],
      ]);
    });

    test('minutes with no samples produce nothing', () {
      expect(heartRateBuckets(history, [t(30, 0)]), isEmpty);
    });
  });

  group('HealthConnectSync', () {
    late FakeHealthConnect fake;
    late SplayTreeMap<DateTime, int> history;
    late StreamController<List<HrSample>> samples;
    late HealthConnectSync sync;

    setUp(() {
      fake = FakeHealthConnect();
      history = SplayTreeMap();
      samples = StreamController();
      sync = HealthConnectSync(
        log: BandLog(),
        history: history,
        api: fake.api,
        batchDelay: Duration.zero,
      )..listenTo(samples.stream);
    });

    test('enable asks for access and writes the last day', () async {
      final now = DateTime.now();
      history[now.subtract(const Duration(minutes: 5))] = 80;
      history[now.subtract(const Duration(days: 2))] = 70;
      await sync.enable();
      expect(sync.active, isTrue);
      expect(fake.writes.single, hasLength(1));
      expect(sync.written, 1);
    });

    test('denied access leaves sharing off', () async {
      fake.grant = false;
      await sync.enable();
      expect(sync.active, isFalse);
      expect(sync.state, HealthConnectState.notGranted);
    });

    test('new samples are batched into one write', () async {
      await sync.enable();
      final now = DateTime.now();
      final a = HrSample(now, 90),
          b = HrSample(now.add(const Duration(seconds: 1)), 91);
      history[a.time] = a.bpm;
      history[b.time] = b.bpm;
      samples
        ..add([a])
        ..add([b]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final last = fake.writes.last;
      expect(last, hasLength(1), reason: 'same minute → one record');
      expect((last.single['samples'] as List).length, 2);
    });

    test('samples are ignored while sharing is off', () async {
      samples.add([HrSample(DateTime.now(), 90)]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fake.writes, isEmpty);
    });

    test('a revoked permission is reported', () async {
      await sync.enable();
      fake.failWith = PlatformException(code: 'permission', message: 'no');
      fake.status = 'notGranted';
      final now = DateTime.now();
      history[now] = 99;
      samples.add([HrSample(now, 99)]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(sync.state, HealthConnectState.notGranted);
      expect(sync.error, 'no');
    });

    test('queued records are written once per version', () async {
      await sync.enable();
      Map<String, Object> steps(int v) => {
        'kind': 'steps',
        'id': 'openwear-steps-1',
        'version': v,
        'start': 0,
        'end': 1,
        'value': v,
      };
      sync.queue([steps(100)]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      sync.queue([steps(100)]); // unchanged: skipped
      await Future<void>.delayed(const Duration(milliseconds: 10));
      sync.queue([steps(150)]); // grew: replaces
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fake.recordWrites.map((w) => w.single['value']), [100, 150]);
    });

    test('enabling asks the app to queue what it has', () async {
      var asked = 0;
      sync.onEnabled = () => asked++;
      await sync.enable();
      expect(asked, 1);
    });

    Map<String, Object> steps(int v) => {
      'kind': 'steps',
      'id': 'openwear-steps-1',
      'version': v,
      'start': 0,
      'end': 1,
      'value': v,
    };
    Map<String, Object> sleep() => {
      'kind': 'sleep',
      'id': 'openwear-sleep-1',
      'version': 1,
      'start': 0,
      'end': 1,
    };

    test(
      'partial access shares the allowed kinds and names the rest',
      () async {
        fake.status = 'missing:steps';
        fake.grant = false;
        await sync.enable();
        expect(sync.active, isTrue);
        expect(sync.state, HealthConnectState.partial);
        expect(sync.missingLabel, 'steps');
        sync.queue([steps(100), sleep()]);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(fake.recordWrites.single.map((r) => r['kind']), ['sleep']);
      },
    );

    test(
      'enable opens Health Connect when the request leaves access off',
      () async {
        fake.grant = false;
        await sync.enable();
        expect(fake.settingsOpened, 1);
      },
    );

    test(
      'enable does not open Health Connect when access is granted',
      () async {
        await sync.enable();
        expect(fake.settingsOpened, 0);
      },
    );

    test('access restored in Health Connect is picked up on refresh', () async {
      fake.status = 'missing:steps';
      fake.grant = false;
      await sync.enable();
      sync.queue([steps(100)]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fake.recordWrites, isEmpty);
      var requeued = 0;
      sync.onEnabled = () {
        requeued++;
        sync.queue([steps(100)]);
      };
      fake.status = 'granted';
      await sync.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(requeued, 1);
      expect(fake.recordWrites.single.single['kind'], 'steps');
    });

    test(
      'a saved "on" setting starts sharing once access is confirmed',
      () async {
        fake.status = 'granted';
        var queued = 0;
        sync
          ..enabled = true
          ..onEnabled = () => queued++;
        await sync.refresh();
        expect(sync.active, isTrue);
        expect(queued, 1);
        await sync.refresh();
        expect(queued, 1, reason: 'unchanged access does not re-queue');
      },
    );

    test(
      'access removed while on is reported with the missing kinds',
      () async {
        fake.status = 'granted';
        sync.enabled = true;
        await sync.refresh();
        fake.status = 'notGranted';
        await sync.refresh();
        expect(sync.active, isFalse);
        expect(sync.missingLabel, contains('steps'));
      },
    );

    test('records refused for permission are kept for the next try', () async {
      await sync.enable();
      fake.failWith = PlatformException(code: 'permission', message: 'no');
      fake.status = 'missing:steps';
      sync.queue([steps(100), sleep()]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(sync.state, HealthConnectState.partial);
      fake.failWith = null;
      await sync.flush();
      expect(fake.recordWrites.single.map((r) => r['kind']), ['sleep']);
      fake.status = 'granted';
      await sync.refresh();
      await sync.flush();
      expect(fake.recordWrites.last.single['kind'], 'steps');
    });

    test('unavailable phones say so', () async {
      fake.status = 'unavailable';
      await sync.refresh();
      expect(sync.state, HealthConnectState.unavailable);
    });
  });
}
