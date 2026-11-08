import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/daily_record.dart';

/// A v4 record file starting at [start] (unix seconds) with [steps] per record.
Uint8List recordFile(int start, List<int> steps) {
  final id = [
    start & 0xff, start >> 8 & 0xff, start >> 16 & 0xff, start >> 24 & 0xff,
    0xf0, 0x04, 0x00, // tz −4 h, v4, daily record
  ];
  return Uint8List.fromList([
    ...id,
    0x00,
    0xff,
    0xff,
    0xf8,
    0xcf,
    0xff,
    0xff,
    for (final s in steps) ...[
      s & 0xff,
      s >> 8,
      0x00,
      0xe0,
      0,
      0,
      0x68,
      0x64,
      0xe4,
      0x04,
      0,
      0,
      0,
      0,
      0,
      0,
    ],
  ]);
}

void main() {
  // 2026-10-31 19:38 EDT, as in the user's log.
  const t0 = 1793489880;
  final now = DateTime.fromMillisecondsSinceEpoch((t0 + 3600) * 1000);

  test('every record counts, even when the band wrote several a minute', () {
    final files = [
      recordFile(t0, [15, 24, 0, 0, 0, 0, 0]),
      recordFile(t0 + 60, [40, 40, 40]),
      recordFile(t0 + 120, [5]),
    ];
    final records = recordsOfFiles(files, now);
    expect(records, hasLength(11));
    expect(totalsFor(records, records.first.time).steps, 15 + 24 + 120 + 5);
  });

  test('records stay inside their file and are never in the future', () {
    final files = [
      recordFile(t0, List.filled(7, 1)),
      recordFile(t0 + 60, List.filled(7, 1)),
    ];
    final soon = DateTime.fromMillisecondsSinceEpoch((t0 + 90) * 1000);
    final records = recordsOfFiles(files, soon);
    final firstFile = records.take(7).map((r) => r.time.millisecondsSinceEpoch);
    expect(firstFile.every((ms) => ms < (t0 + 60) * 1000), isTrue);
    expect(records.every((r) => !r.time.isAfter(soon)), isTrue);
  });

  test('a minute-a-record file keeps one-minute spacing', () {
    final files = [
      recordFile(t0, List.filled(35, 0)),
      recordFile(t0 + 35 * 60, [0]),
    ];
    final records = recordsOfFiles(files, now);
    expect(records[1].time.difference(records[0].time).inSeconds, 60);
  });

  test('a file the band resent as it grew counts once (longest copy)', () {
    final records = recordsOfFiles([
      recordFile(t0, [10, 10, 10]),
      recordFile(t0, [10, 10, 10, 10, 10]),
      recordFile(t0, [10, 10, 10, 10]),
    ], now);
    expect(totalsFor(records, records.first.time).steps, 50);
  });
}
