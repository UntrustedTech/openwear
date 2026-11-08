/// Messages between a band app and its phone app (Mi Fitness 3.59.2,
/// XmsComponent / DeviceModelExtKt), all type 20 like the app list:
///
/// - band → phone 20/6: is the phone app there? field 5 `{1 package,
///   2 fingerprint}`; the phone answers 20/7 field 8 `{1 {package,
///   fingerprint}, 2 status}` with status 1 connected, 2 not connected,
///   3 not installed.
/// - phone → band 20/8 and band → phone (other subtypes): field 9
///   `{1 {1 package, 2 fingerprint}, 2 data}`.
///
/// OpenWear's band app sends and receives UTF-8 JSON objects as data.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:openwear/protocol/band_apps.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/pb.dart';

const _subAskStatus = 6, _subStatus = 7, _subPhoneMessage = 8;
const _fApp = 5, _fStatus = 8, _fMessage = 9;

/// Status in the 20/7 answer.
const appStatusConnected = 1;

/// A band app, by package and the fingerprint the band knows it by.
class BandAppId {
  const BandAppId(this.package, this.fingerprint);
  final String package;
  final Uint8List fingerprint;

  static BandAppId? _from(PbMessage? m) {
    if (m == null || m.string(1).isEmpty) return null;
    return BandAppId(m.string(1), m.bytes(2) ?? Uint8List(0));
  }

  Uint8List _encode() => pbEncode([
    PbString(1, package),
    if (fingerprint.isNotEmpty) PbBytes(2, fingerprint),
  ]);
}

/// The band app asking whether its phone app is there (20/6).
BandAppId? bandAppStatusAsk(Command cmd) => cmd.isA(typeApps, _subAskStatus)
    ? BandAppId._from(cmd.body.message(_fApp))
    : null;

/// Our answer to [bandAppStatusAsk].
Command bandAppStatus(BandAppId app, {int status = appStatusConnected}) =>
    Command.of(typeApps, _subStatus, [
      PbBytes(
        _fStatus,
        pbEncode([PbBytes(1, app._encode()), PbVarint(2, status)]),
      ),
    ]);

/// A message from a band app: who sent it and its data.
class BandAppMessage {
  const BandAppMessage(this.app, this.data);
  final BandAppId app;
  final Uint8List data;

  /// [data] as a JSON object, or null when it is not one.
  Map<String, dynamic>? get json {
    try {
      final v = jsonDecode(utf8.decode(data, allowMalformed: true));
      if (v is Map<String, dynamic>) return v;
      // The band may wrap the object in a JSON string.
      if (v is String) {
        final inner = jsonDecode(v);
        if (inner is Map<String, dynamic>) return inner;
      }
    } on FormatException {
      // Not JSON.
    }
    return null;
  }
}

/// A message sent by a band app, from any type-20 command that carries one.
BandAppMessage? bandAppMessage(Command cmd) {
  if (cmd.type != typeApps || cmd.subtype == _subPhoneMessage) return null;
  final m = cmd.body.message(_fMessage);
  final app = BandAppId._from(m?.message(1));
  if (m == null || app == null) return null;
  return BandAppMessage(app, m.bytes(2) ?? Uint8List(0));
}

/// Sends [json] to the band app [app] (20/8).
Command phoneToBandApp(BandAppId app, Map<String, Object?> json) =>
    Command.of(typeApps, _subPhoneMessage, [
      PbBytes(
        _fMessage,
        pbEncode([
          PbBytes(1, app._encode()),
          PbBytes(2, utf8.encode(jsonEncode(json))),
        ]),
      ),
    ]);
