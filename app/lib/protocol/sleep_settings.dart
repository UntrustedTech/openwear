/// Band sleep-tracking switches, recovered from Mi Fitness 3.59.2
/// (BleSleepSettingViewModel). They live in the heart-rate monitoring
/// config: 8/10 reads it, 8/11 writes it back whole, payload xva field 8.
///
/// Fields used: 5 `{1: bool}` high-accuracy ("assisted") sleep tracking,
/// 9 sleep breathing quality and 11 breathing rate during sleep
/// (0 not supported, 1 on, 2 off). Every other field is sent back
/// byte for byte, as Mi Fitness does, so the HR settings are not reset.
library;

import 'dart:typed_data';

import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/pb.dart';

const _subGet = 10, _subSet = 11, _fConfig = 8;
const _fAssist = 5, _fBreathing = 9, _fBreathingRate = 11;
const _on = 1, _off = 2;

Command sleepSettingsRequest() => const Command(typeFitness, _subGet);

class SleepSettings {
  const SleepSettings(this.raw);

  /// The band's whole config message, as received.
  final Uint8List raw;

  PbMessage get _m => PbMessage.decode(raw);

  bool? _tri(int field) => switch (_m.int_(field)) {
    _on => true,
    _off => false,
    _ => null,
  };

  /// Null when the band does not offer the switch.
  bool? get highAccuracy {
    final a = _m.message(_fAssist);
    return a == null ? null : a.int_(1) != 0;
  }

  bool? get breathingQuality => _tri(_fBreathing);
  bool? get breathingRate => _tri(_fBreathingRate);

  bool get anySupported =>
      highAccuracy != null || breathingQuality != null || breathingRate != null;

  SleepSettings _with(PbField f) => SleepSettings(pbReplace(raw, [f]));

  SleepSettings withHighAccuracy(bool on) => highAccuracy == null
      ? this
      : _with(PbBytes(_fAssist, pbEncode([PbBool(1, on)])));

  SleepSettings withBreathingQuality(bool on) => breathingQuality == null
      ? this
      : _with(PbVarint(_fBreathing, on ? _on : _off));

  SleepSettings withBreathingRate(bool on) => breathingRate == null
      ? this
      : _with(PbVarint(_fBreathingRate, on ? _on : _off));

  Command command() =>
      Command.of(typeFitness, _subSet, [PbBytes(_fConfig, raw)]);
}

/// Reply to [sleepSettingsRequest]; null when it has no config.
SleepSettings? parseSleepSettings(Command cmd) {
  final b = cmd.body.bytes(_fConfig);
  return b == null ? null : SleepSettings(b);
}
