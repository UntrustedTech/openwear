/// The band's app list and installed apps, recovered from Mi Fitness 3.59.2.
///
/// Built-in apps (AppSortViewModel): 2/29 reads the list, 2/30 writes it
/// back in the new order; payload field 10 `{1: repeated app}` with app
/// `{1 id, 2 name, 3 hidden, 4 always shown, 5 may go in "More", 6 in More}`.
/// Mi Fitness writes it grouped: shown apps, then More, then hidden.
///
/// Installed (third-party) apps, type 20 (DeviceModelExtKt):
/// 20/0 list → field 1 `{1: repeated {1 package, 2 fingerprint, 3 version,
/// 4 flag, 5 name}}`; 20/1 prepare install field 2 `{1 package, 2 version,
/// 3 size}` → field 3 `{1 status (0 ok), 2 slice length}`, then the .rpk
/// is sent by mass transfer kind (4, 0); 20/3 uninstall field 5
/// `{1 package, 2 fingerprint}`.
library;

import 'dart:typed_data';

import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/pb.dart';

const _subListGet = 29, _subListSet = 30, _fList = 10;
const typeApps = 20;
const _subInstalled = 0, _subPrepare = 1, _subUninstall = 3;
const _fInstalled = 1, _fPrepare = 2, _fPrepared = 3, _fUninstall = 5;

/// Mass-transfer kind for an app package.
const appFile = (4, 0);

/// Where a built-in app sits in the band's app list.
enum AppPlace { shown, more, hidden }

class BandApp {
  const BandApp({
    required this.id,
    required this.name,
    required this.place,
    this.alwaysShown = false,
    this.mayGoInMore = false,
    this.raw,
  });

  final String id;
  final String name;
  final AppPlace place;

  /// The band does not let this app be hidden.
  final bool alwaysShown;
  final bool mayGoInMore;

  /// The app's message as received; written back with only fields 3 and
  /// 6 changed, so fields this app does not know survive.
  final Uint8List? raw;

  BandApp moveTo(AppPlace p) {
    if (alwaysShown && p != AppPlace.shown) return this;
    if (p == AppPlace.more && !mayGoInMore) return this;
    return BandApp(
      id: id,
      name: name,
      place: p,
      alwaysShown: alwaysShown,
      mayGoInMore: mayGoInMore,
      raw: raw,
    );
  }

  List<int> encode() {
    final changes = [
      PbBool(3, place == AppPlace.hidden),
      PbBool(6, place == AppPlace.more),
    ];
    final r = raw;
    if (r != null) return pbReplace(r, changes);
    return pbEncode([
      PbString(1, id),
      PbString(2, name),
      ...changes,
      PbBool(4, alwaysShown),
      PbBool(5, mayGoInMore),
    ]);
  }

  @override
  String toString() => '$name (${place.name})';
}

Command appListRequest() => const Command(typeSystem, _subListGet);

/// Reply to [appListRequest], in the band's order; null without a list.
List<BandApp>? parseAppList(Command cmd) {
  final list = cmd.body.message(_fList);
  if (list == null) return null;
  return [
    for (final raw in list.all(1).whereType<Uint8List>())
      _app(raw, PbMessage.decode(raw)),
  ];
}

BandApp _app(Uint8List raw, PbMessage m) {
  final hidden = m.int_(3) != 0, more = m.int_(6) != 0;
  return BandApp(
    id: m.string(1),
    name: m.string(2),
    place: hidden
        ? AppPlace.hidden
        : more
        ? AppPlace.more
        : AppPlace.shown,
    alwaysShown: m.int_(4) != 0,
    mayGoInMore: m.int_(5) != 0,
    raw: raw,
  );
}

/// Writes the whole list: shown apps, then More, then hidden, each group
/// in the order given.
Command appListCommand(List<BandApp> apps) =>
    Command.of(typeSystem, _subListSet, [
      PbBytes(
        _fList,
        pbEncode([
          for (final place in AppPlace.values)
            for (final a in apps)
              if (a.place == place) PbBytes(1, a.encode()),
        ]),
      ),
    ]);

class InstalledApp {
  const InstalledApp(this.package, this.name, this.version, this.fingerprint);
  final String package;
  final String name;
  final int version;
  final Uint8List fingerprint;

  @override
  String toString() => '$name ($package v$version)';
}

Command installedAppsRequest() => const Command(typeApps, _subInstalled);

List<InstalledApp>? parseInstalledApps(Command cmd) {
  final list = cmd.body.message(_fInstalled);
  if (list == null) return null;
  return [
    for (final m in list.messages(1))
      InstalledApp(
        m.string(1),
        m.string(5).isEmpty ? m.string(1) : m.string(5),
        m.int_(3),
        m.bytes(2) ?? Uint8List(0),
      ),
  ];
}

Command prepareInstallApp(String package, int version, int size) => Command.of(
  typeApps,
  _subPrepare,
  [
    PbBytes(
      _fPrepare,
      pbEncode([PbString(1, package), PbVarint(2, version), PbVarint(3, size)]),
    ),
  ],
);

class AppInstallException implements Exception {
  const AppInstallException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The slice length the band wants, or throws when it refuses.
int checkPrepareInstall(Command rsp) {
  final m = rsp.body.message(_fPrepared);
  if (m == null) {
    throw const AppInstallException('The band did not answer the install.');
  }
  final status = m.int_(1);
  if (status != 0) {
    throw AppInstallException(switch (status) {
      _ =>
        'The band refused the app (code $status). It may not support '
            'this app, or have no room left.',
    });
  }
  return m.int_(2);
}

Command uninstallApp(InstalledApp app) => Command.of(typeApps, _subUninstall, [
  PbBytes(
    _fUninstall,
    pbEncode([PbString(1, app.package), PbBytes(2, app.fingerprint)]),
  ),
]);
