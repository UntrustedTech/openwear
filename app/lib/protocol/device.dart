/// System, notification, call and watch-face commands (docs/protocol/03-commands).
library;

import 'dart:typed_data';

import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/pb.dart';

// --- system (type 2) ---------------------------------------------------------

Command batteryRequest() => const Command(typeSystem, 1);

/// Battery percent from a 2/1 reply (`f2.f1.f1`; Band 9 log: `2 { 1 { 1: 96 } }`).
int? batteryPercent(Command rsp) => rsp.body.message(2)?.message(1)?.int_(1);

/// 2/2: the band's own description of itself.
Command deviceInfoRequest() => const Command(typeSystem, 2);

/// What a band says about itself in a 2/2 reply (system message field 3).
class BandInfo {
  const BandInfo({
    required this.serial,
    required this.firmware,
    required this.model,
    this.product = '',
    this.channel,
    this.extra = const {},
  });

  final String serial;
  final String firmware;
  final String model;

  /// Product (marketing) device name, when the band sends one.
  final String product;

  /// Firmware release channel, when the band sends one.
  final int? channel;

  /// Fields Mi Fitness reads but never names, keyed by field number.
  final Map<int, String> extra;
}

/// Parses a 2/2 reply; null when it holds no device info.
BandInfo? parseBandInfo(Command rsp) {
  final m = rsp.body.message(3);
  if (m == null) return null;
  return BandInfo(
    serial: m.string(1),
    firmware: m.string(2),
    model: m.string(4),
    product: m.string(5),
    channel: m.has(6) ? m.int_(6) : null,
    extra: {
      for (final n in const [3, 7])
        if (m.string(n).isNotEmpty) n: m.string(n),
    },
  );
}

/// Time zone facts the band needs; on Android these come from `java.util.TimeZone`.
class ZoneInfo {
  const ZoneInfo(this.id, this.standardOffset, this.dstOffset);
  final String
  id; // IANA id, e.g. "America/New_York" (abbreviations break the band)
  final Duration standardOffset;
  final Duration dstOffset;
}

/// 2/3 as Mi Fitness sends it: local wall time, standard and DST offsets in
/// 15-minute units, the IANA zone id and the 12/24 h preference.
Command setTime(DateTime local, ZoneInfo zone, {bool twelveHour = false}) {
  final date = pbEncode([
    PbVarint(1, local.year),
    PbVarint(2, local.month),
    PbVarint(3, local.day),
  ]);
  final clock = pbEncode([
    PbVarint(1, local.hour),
    PbVarint(2, local.minute),
    PbVarint(3, local.second),
    PbVarint(4, local.millisecond),
  ]);
  final tz = pbEncode([
    PbSint(1, zone.standardOffset.inMinutes ~/ 15),
    PbSint(2, zone.dstOffset.inMinutes ~/ 15),
    PbString(3, zone.id),
  ]);
  final system = pbEncode([
    PbBytes(1, date),
    PbBytes(2, clock),
    PbBytes(3, tz),
    PbBool(4, twelveHour),
  ]);
  return Command.of(typeSystem, 3, [PbBytes(4, system)]);
}

/// 2/6: the phone's language as `ll_CC` (e.g. `en_US`); Mi Fitness sends
/// it so the band's language (and its regional formats) follow the phone.
Command languageCommand(String locale) => Command.of(typeSystem, 6, [
  PbBytes(20, pbEncode([PbString(1, locale)])),
]);

// --- notifications and calls (type 7) -----------------------------------------

const _subNotifyAdd = 0,
    _subNotifyRemove = 1,
    _subPrepareIcon = 15,
    _subIconRequest = 16;
const callEndSubtype = 2, callSilenceSubtype = 5;
const callIncoming = 1, callOutgoing = 3;
const _callPackage = 'phone';

String notifyTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}T${two(t.hour)}${two(t.minute)}${two(t.second)}';
}

Command _addNotification(List<PbField> item) =>
    Command.of(typeNotify, _subNotifyAdd, [
      PbBytes(3, pbEncode([PbBytes(1, pbEncode(item))])),
    ]);

Command notification({
  required String package,
  required String appName,
  required String title,
  required String text,
  required int id,
  required DateTime time,
  String key = '',
}) => _addNotification([
  PbString(1, package),
  PbString(2, appName),
  PbString(3, title),
  const PbString(4, ''),
  PbString(5, text),
  PbString(6, notifyTime(time)),
  PbVarint(7, id),
  const PbString(9, ''),
  PbString(12, key.isEmpty ? '$package|$id' : key),
]);

/// Removes a forwarded notification from the band (dismissed on the
/// phone): `{1 id, 2 package, 3 "", 4 key}`, the key sent in field 12.
Command removeNotification({
  required String package,
  required int id,
  required String key,
}) => Command.of(typeNotify, _subNotifyRemove, [
  PbBytes(
    4,
    pbEncode([
      PbBytes(
        1,
        pbEncode([
          PbVarint(1, id),
          PbString(2, package),
          const PbString(3, ''),
          if (key.isNotEmpty) PbString(4, key),
        ]),
      ),
    ]),
  ),
]);

/// Rings the watch. With no caller name the number becomes the title.
Command incomingCall(
  String caller,
  String number,
  DateTime time, {
  int callType = callIncoming,
}) {
  final (title, text) = caller.isEmpty ? (number, '') : (caller, number);
  return _addNotification([
    const PbString(1, _callPackage),
    const PbString(2, _callPackage),
    PbString(3, title),
    const PbString(4, ''),
    PbString(5, text),
    PbString(6, notifyTime(time)),
    const PbVarint(7, 0),
    PbVarint(8, callType),
    const PbString(9, ''),
    const PbBool(11, false),
  ]);
}

/// Stops the ringing / call screen (Mi Fitness alertInCallStop).
Command callEnded() => Command.of(typeNotify, _subNotifyRemove, [
  PbBytes(
    4,
    pbEncode([
      PbBytes(
        1,
        pbEncode([
          const PbVarint(1, 0),
          const PbString(2, _callPackage),
          const PbString(3, ''),
        ]),
      ),
    ]),
  ),
]);

/// Package name from a watch → phone 7/16 icon request, else null.
String? iconRequestPackage(Command cmd) => cmd.isA(typeNotify, _subIconRequest)
    ? cmd.body.message(16)?.string(1)
    : null;

Command prepareIcon(String package) => Command.of(typeNotify, _subPrepareIcon, [
  PbBytes(14, pbEncode([PbString(1, package)])),
]);

class IconSpec {
  const IconSpec(this.status, this.pixelFormat, this.size);
  final int status;
  final int pixelFormat;
  final int size;
}

IconSpec parseIconSpec(Command rsp) {
  final sti = rsp.body.message(15);
  return IconSpec(sti?.int_(1) ?? -1, sti?.int_(2) ?? 0, sti?.int_(3) ?? 0);
}

int _rgb565(int r, int g, int b) =>
    ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);

/// Converts RGBA rows into the watch's raw pixel format (code from the 7/15 reply).
Uint8List encodeIconPixels(Uint8List rgba, int format) {
  final out = BytesBuilder(copy: false);
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2], a = rgba[i + 3];
    final c = _rgb565(r, g, b);
    switch (format) {
      case 0 || 4:
        out.add([c & 0xFF, c >> 8]);
      case 1:
        out.add([c >> 8, c & 0xFF]);
      case 2 || 3:
        out.add([b, g, r, a]);
      case 7:
        out.add([c & 0xFF, c >> 8, a]);
      case 8:
        out.add([c >> 8, c & 0xFF, a]);
      default:
        throw ArgumentError('unknown icon pixel format $format');
    }
  }
  return out.takeBytes();
}

// --- watch faces (type 4) -------------------------------------------------------

class WatchFace {
  const WatchFace(
    this.id,
    this.name, {
    required this.active,
    required this.removable,
  });
  final String id;
  final String name;
  final bool active;
  final bool removable; // Band 9 reports false only for the active face
}

Command listFaces() => const Command(typeFace, 0);
Command setFace(String id) => Command.of(typeFace, 1, [PbString(2, id)]);
Command deleteFace(String id) => Command.of(typeFace, 2, [PbString(2, id)]);

List<WatchFace> parseFaces(Command rsp) => [
  for (final f in rsp.body.message(1)?.messages(1) ?? const <PbMessage>[])
    WatchFace(
      f.string(1),
      f.string(2),
      active: f.int_(3) != 0,
      removable: f.int_(4) != 0,
    ),
];
