import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/daily_record.dart';
import 'package:openwear/protocol/fitness.dart';
import 'package:openwear/services/health_inbox.dart';

import '../protocol/day_records_test.dart' show recordFile;

FitnessId idOf(Uint8List f) => FitnessId(f.sublist(0, 7));

FitnessId otherId(int start, int typeByte) => FitnessId([
  start & 0xff,
  start >> 8 & 0xff,
  start >> 16 & 0xff,
  start >> 24 & 0xff,
  0xf0,
  0x05,
  typeByte,
]);

void main() {
  final now = DateTime(2026, 10, 31, 23, 25);
  final s = now.millisecondsSinceEpoch ~/ 1000;

  test('adds today\'s minute files and sums them', () {
    final inbox = HealthInbox();
    expect(inbox.add(recordFile(s - 600, [10, 20]), now), isTrue);
    expect(inbox.add(recordFile(s - 540, [5]), now), isTrue);
    expect(totalsFor(inbox.recordsFor(now), now).steps, 35);
  });

  test('a resent copy that is not longer changes nothing', () {
    final inbox = HealthInbox();
    inbox.add(recordFile(s - 600, [10, 20]), now);
    expect(inbox.add(recordFile(s - 600, [10, 20]), now), isFalse);
    expect(inbox.add(recordFile(s - 600, [10, 20, 3]), now), isTrue);
    expect(totalsFor(inbox.recordsFor(now), now).steps, 33);
  });

  test('yesterday\'s files are not part of today', () {
    final inbox = HealthInbox();
    expect(inbox.add(recordFile(s - 86400, [10]), now), isFalse);
    expect(inbox.todayFileCount, 0);
  });

  test('the newest minute file is kept on the band; older ones confirmed', () {
    final inbox = HealthInbox();
    final old = recordFile(s - 600, [1]);
    final newest = recordFile(s - 60, [1]);
    inbox.add(newest, now);
    inbox.add(old, now);
    expect(inbox.mayConfirm(idOf(old), now), isTrue);
    expect(inbox.mayConfirm(idOf(newest), now), isFalse);
  });

  test('today\'s report and heart-rate file are never confirmed', () {
    final inbox = HealthInbox()..add(recordFile(s - 60, [1]), now);
    final midnight = DateTime(2026, 10, 31).millisecondsSinceEpoch ~/ 1000;
    expect(inbox.mayConfirm(otherId(midnight, 0x01), now), isFalse);
    expect(inbox.mayConfirm(otherId(midnight, 0x18), now), isFalse);
  });

  test('files from earlier days are confirmed', () {
    final inbox = HealthInbox();
    expect(inbox.mayConfirm(otherId(s - 2 * 86400, 0x01), now), isTrue);
  });
}
