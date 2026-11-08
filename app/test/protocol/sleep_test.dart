import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/fitness.dart';
import 'package:openwear/protocol/sleep.dart';
import 'package:openwear/services/sleep_log.dart';

/// Little-endian byte builder for test files.
class _Bytes {
  final _b = BytesBuilder();
  void u8(int v) => _b.addByte(v);
  void u16(int v) => _b.add([v & 0xff, v >> 8 & 0xff]);
  void u32(int v) => _b.add([for (var i = 0; i < 4; i++) v >> (8 * i) & 0xff]);
  void id(int ts, int version, int dataType, {int fileType = 0}) {
    u32(ts);
    u8(0xf0); // UTC-4 in quarters
    u8(version);
    u8(dataType << 2 | fileType);
    u8(0); // no encryption/compression
  }

  Uint8List get bytes => _b.toBytes();
}

const _bed = 1793500000; // seconds
DateTime _t(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000);

Uint8List _night({int version = 2, bool scoreValid = true}) {
  final b = _Bytes()..id(_bed, version, 3);
  // Validity: 15 report fields (16 in v2), all valid except maybe score.
  b
    ..u8(scoreValid ? 0xff : 0x7f)
    ..u8(version >= 2 ? 0xff : 0xfe);
  b
    ..u8(82) // total score
    ..u8(1)
    ..u8(2)
    ..u8(3)
    ..u8(4)
    ..u16(420) // asleep minutes
    ..u32(_bed)
    ..u32(_bed + 7 * 3600 + 1800)
    ..u8(70)
    ..u8(30)
    ..u8(2) // awake count
    ..u16(90)
    ..u16(240)
    ..u16(90)
    ..u16(30);
  if (version >= 2) b.u8(80);
  for (final (offset, stage) in [
    (0, 3), // light
    (3600, 2), // deep
    (2 * 3600, 4), // REM
    (3 * 3600, 5), // awake
    (3 * 3600 + 600, 3), // light
    (7 * 3600 + 1800, 5), // end marker
  ]) {
    b
      ..u32(_bed + offset)
      ..u8(stage);
  }
  return b.bytes;
}

Uint8List _segment({required int version, bool finished = true}) {
  final b = _Bytes()..id(_bed, version, 8, fileType: 1);
  if (version == 5) {
    // start, end, quality, efficiency, latency, in bed, to bed, left bed,
    // heart rate, SpO₂, snoring(off)
    b
      ..u8(0xff)
      ..u8(0xc0);
  } else {
    // v6: 8 times/quality, 11 HRV stats, then heart rate, SpO₂, HRV and
    // snoring series (the last two empty); the lowest bit is unused.
    b
      ..u8(0xff)
      ..u8(0xff)
      ..u8(0xfe);
  }
  b
    ..u8(finished ? 1 : 0)
    ..u32(_bed)
    ..u32(_bed + 6 * 3600)
    ..u8(88) // breathing quality
    ..u8(91) // efficiency
    ..u32(600)
    ..u32(6 * 3600 + 900)
    ..u32(_bed - 600)
    ..u32(_bed + 6 * 3600 + 300);
  if (version >= 6) {
    b.u16(48); // HRV average
    for (final size in [2, 2, 2, 2, 2, 4, 2, 2, 2, 2]) {
      size == 2 ? b.u16(1) : b.u32(1);
    }
  }
  // Heart rate every 60 s.
  b
    ..u16(60)
    ..u16(4)
    ..u32(_bed);
  for (final bpm in [58, 54, 0, 52]) {
    b.u8(bpm);
  }
  // SpO₂ every 10 minutes.
  b
    ..u16(600)
    ..u16(2)
    ..u32(_bed);
  for (final v in [96, 97]) {
    b.u8(v);
  }
  if (version >= 6) {
    // HRV series present but empty, snoring present but empty.
    b
      ..u16(300)
      ..u16(0)
      ..u16(60)
      ..u16(0);
  }
  // Raw features follow.
  return Uint8List.fromList([...b.bytes, 1, 2, 3, 4, 5]);
}

void main() {
  test('reads a staged night', () {
    final s = parseSleep(_night())!;
    expect(s.kind, SleepKind.night);
    expect(s.start, _t(_bed));
    expect(s.end, _t(_bed + 7 * 3600 + 1800));
    expect(s.score, 82);
    expect(s.awakeCount, 2);
    expect(s.stages.map((x) => x.stage), [
      SleepStage.light,
      SleepStage.deep,
      SleepStage.rem,
      SleepStage.awake,
      SleepStage.light,
    ]);
    expect(s.stages.last.end, s.end);
    // Asleep = everything but the 10 awake minutes.
    expect(s.asleep, const Duration(hours: 7, minutes: 20));
    expect(s.stageTotals[SleepStage.deep], const Duration(hours: 1));
  });

  test('a night without a valid score keeps the rest', () {
    final s = parseSleep(_night(version: 1, scoreValid: false))!;
    expect(s.score, isNull);
    expect(s.deepMinutes, 90);
    expect(s.stages, hasLength(5));
  });

  test('reads a nap', () {
    final b = _Bytes()
      ..id(_bed, 2, 2)
      ..u8(0x80)
      ..u16(25)
      ..u32(_bed)
      ..u8(3)
      ..u32(_bed + 1500)
      ..u8(5);
    final s = parseSleep(b.bytes)!;
    expect(s.kind, SleepKind.nap);
    expect(s.reportedAsleepMinutes, 25);
    expect(s.asleep, const Duration(minutes: 25));
  });

  test('nap version 1 is not read', () {
    final b = _Bytes()
      ..id(_bed, 1, 2)
      ..u8(0x80)
      ..u16(25);
    expect(parseSleep(b.bytes), isNull);
  });

  for (final v in [5, 6]) {
    test('reads a full-day sleep segment v$v', () {
      final s = parseSleep(_segment(version: v))!;
      expect(s.kind, SleepKind.segment);
      expect(s.finished, isTrue);
      expect(s.start, _t(_bed));
      expect(s.end, _t(_bed + 6 * 3600));
      expect(s.wentToBed, _t(_bed - 600));
      expect(s.leftBed, _t(_bed + 6 * 3600 + 300));
      expect(s.efficiency, 91);
      expect(s.breathingQuality, 88);
      expect(s.hasStages, isFalse);
      expect(s.asleep, const Duration(hours: 6));
      // The 0 bpm gap is dropped; points are 60 s apart.
      expect(s.heartRate.map((x) => x.$2), [58, 54, 52]);
      expect(s.heartRate.last.$1, _t(_bed + 180));
      expect(s.lowestHeartRate, 52);
      expect(s.spo2.last.$1, _t(_bed + 600));
      expect(s.averageSpo2, 97);
      if (v == 6) expect(s.hrvAverage, 48);
    });
  }

  test('a cut-short file is not read', () {
    final f = _segment(version: 5);
    expect(parseSleep(Uint8List.sublistView(f, 0, 20)), isNull);
  });

  test('other health files are not sleep', () {
    final b = _Bytes()..id(_bed, 4, 0);
    expect(isSleepFile(FitnessId(b.bytes.sublist(0, 7))), isFalse);
    expect(parseSleep(b.bytes), isNull);
  });

  group('SleepLog', () {
    final morning = _t(_bed + 9 * 3600);

    test('last night prefers the staged night', () {
      final log = SleepLog()
        ..add(_segment(version: 5), morning)
        ..add(_night(), morning);
      expect(log.lastNight(morning)!.kind, SleepKind.night);
    });

    test('nothing is last night two days later', () {
      final log = SleepLog()..add(_night(), morning);
      expect(log.lastNight(morning.add(const Duration(days: 2))), isNull);
    });

    test('an unfinished segment is not confirmed until it is old', () {
      final file = _segment(version: 6, finished: false);
      final id = FitnessId(file.sublist(0, 7));
      final log = SleepLog()..add(file, morning);
      expect(log.isFinished(id), isFalse);
      expect(log.mayConfirm(id, morning), isFalse);
      expect(log.mayConfirm(id, morning.add(const Duration(days: 3))), isTrue);
    });

    test('a resent unchanged file changes nothing', () {
      final log = SleepLog();
      expect(log.add(_night(), morning), isNotNull);
      expect(log.add(_night(), morning), isNull);
      expect(log.sessions, hasLength(1));
    });
  });
}
