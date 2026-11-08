import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/fitness.dart';
import 'package:openwear/protocol/health_records.dart';

Uint8List unhex(String s) {
  final t = s.replaceAll(' ', '');
  return Uint8List.fromList([
    for (var i = 0; i < t.length; i += 2)
      int.parse(t.substring(i, i + 2), radix: 16),
  ]);
}

/// Channel-5 packet #64 from the user's live-HR log (Smart Band 9, 2026-10-31).
final livePacket = unhex(
  '01000100 c067e56af00218 00 '
  '09f9e56a116e 0af9e56a116d 0bf9e56a116c 0cf9e56a116b 2cf9e56a116c 2ff9e56a116b '
  'c8c9fba6',
);

void main() {
  test('live heart-rate file decodes into timed samples', () {
    final file = FileAssembler().feed(livePacket)!;
    final parsed = parseHealthFile(file);

    expect(parsed.id.hex, 'c067e56af00218');
    expect(parsed.kind, HealthFileKind.heartRateSamples);
    final samples = parsed.heartRate;
    expect(samples.map((s) => s.bpm), [110, 109, 108, 107, 108, 107]);
    expect(samples.first.time.toUtc(), DateTime.utc(2026, 10, 31, 14, 19, 53));
    expect(samples.last.time.toUtc(), DateTime.utc(2026, 10, 31, 14, 20, 31));
    expect(describeHealthFile(parsed), contains('6 HR samples'));
    expect(describeHealthFile(parsed), contains('110 bpm'));
  });

  test('a truncated record set is reported, not misread', () {
    final file = FileAssembler().feed(livePacket)!;
    final cut = Uint8List.sublistView(file, 0, file.length - 2);
    final parsed = parseHealthFile(cut);
    expect(parsed.heartRate.length, 5);
    expect(parsed.trailingBytes, 4);
  });

  test('other file types are kept raw', () {
    final parsed = parseHealthFile(unhex('c067e56af00501 0102030405'));
    expect(parsed.kind, HealthFileKind.other);
    expect(parsed.heartRate, isEmpty);
    expect(describeHealthFile(parsed), contains('type 0'));
  });
}
