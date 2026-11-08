/// Command envelope (`wyt`): type, subtype, one family payload, optional status.
library;

import 'dart:typed_data';

import 'package:openwear/protocol/pb.dart';

/// Command.type → oneof field number carrying that family's payload.
const Map<int, int> payloadField = {
  1: 3, 2: 4, 4: 6, 5: 7, 7: 9, 8: 10, 9: 11, 10: 12, 11: 13, 12: 14, 13: 15, //
  14: 16,
  15: 17,
  16: 18,
  17: 19,
  18: 20,
  19: 21,
  20: 22,
  21: 23,
  22: 24,
  23: 25,
};
const _statusField = 100;

const typeAuth = 1,
    typeSystem = 2,
    typeFace = 4,
    typeNotify = 7,
    typeFitness = 8;
const typeMass = 22;

class Command {
  const Command(this.type, this.subtype, [this.payload, this.status]);

  final int type;
  final int subtype;
  final Uint8List? payload;
  final int? status;

  /// Builds a command whose payload is the given fields.
  factory Command.of(int type, int subtype, List<PbField> fields) =>
      Command(type, subtype, pbEncode(fields));

  PbMessage get body => PbMessage.decode(payload ?? Uint8List(0));

  bool isA(int t, int s) => type == t && subtype == s;

  Uint8List encode() {
    final field = payloadField[type];
    return pbEncode([
      PbVarint(1, type),
      PbVarint(2, subtype),
      if (field != null && payload != null) PbBytes(field, payload),
      PbVarint(_statusField, status),
    ]);
  }

  factory Command.decode(List<int> data) {
    final msg = PbMessage.decode(data);
    final type = msg.int_(1);
    final field = payloadField[type];
    return Command(
      type,
      msg.int_(2),
      field == null ? null : msg.bytes(field),
      msg.has(_statusField) ? msg.int_(_statusField) : null,
    );
  }

  @override
  String toString() =>
      'Command($type/$subtype, status=$status, ${payload?.length ?? 0} B)';
}
