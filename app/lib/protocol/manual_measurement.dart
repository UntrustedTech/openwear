/// Spot checks started on the band (heart rate, SpO₂, stress …): health
/// file with data type 6, file type 0.
///
/// Layout (version 2): id(7) · encryption/compression(1) · then entries of
///   time u32 LE · kind byte (low nibble: 1 heart rate, 2 SpO₂, 3 stress,
///   4 temperature, 5 blood pressure) · value (1, 1, 1, 4 or 6 bytes).
library;

import 'dart:typed_data';

import 'package:openwear/protocol/fitness.dart';

const _headerLength = 8;
const _dataType = 6;

enum MeasurementKind { heartRate, spo2, stress, temperature, bloodPressure }

const _sizes = {1: 1, 2: 1, 3: 1, 4: 4, 5: 6};

class Measurement {
  const Measurement(this.time, this.kind, this.value);
  final DateTime time;
  final MeasurementKind kind;

  /// The reading (heart rate, SpO₂ %, stress 0–100); 0 for the kinds we
  /// do not show.
  final int value;
}

bool isManualMeasurement(FitnessId id) =>
    !id.isSport && id.dataType == _dataType && id.fileType == 0;

/// Parses a measurement file; null when it is not one.
List<Measurement>? parseManualMeasurements(Uint8List file) {
  if (file.length < _headerLength) return null;
  final id = FitnessId(file.sublist(0, 7));
  if (!isManualMeasurement(id)) return null;
  final v = ByteData.sublistView(file);
  final out = <Measurement>[];
  var at = _headerLength;
  while (at + 5 <= file.length) {
    final time = v.getUint32(at, Endian.little);
    final kind = file[at + 4] & 0x0f;
    final size = _sizes[kind];
    if (size == null || at + 5 + size > file.length) break;
    final value = size == 1 ? file[at + 5] : 0;
    out.add(
      Measurement(
        DateTime.fromMillisecondsSinceEpoch(time * 1000),
        MeasurementKind.values[kind - 1],
        value,
      ),
    );
    at += 5 + size;
  }
  return out;
}
