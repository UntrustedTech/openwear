/// The band's app list (order, shown / More / hidden), installed apps,
/// installing and removing .rpk apps, and live pictures of the screen.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:openwear/protocol/band_apps.dart';
import 'package:openwear/protocol/link.dart';
import 'package:openwear/protocol/mass.dart';
import 'package:openwear/protocol/rpk.dart';
import 'package:openwear/services/band_log.dart';

/// How long to wait for a newly sent app to show up as installed.
const _installCheckFor = Duration(seconds: 40);
const _installCheckEvery = Duration(seconds: 4);

class BandApps extends ChangeNotifier {
  BandApps({required this.log, required this.link});

  final BandLog log;
  final Link? Function() link;

  /// Built-in apps in the band's order; null until read.
  List<BandApp>? builtIn;

  /// Apps installed from packages; null until read or not supported.
  List<InstalledApp>? installed;

  String? installing;
  double progress = 0;

  Link _need() {
    final l = link();
    if (l == null) throw const AppInstallException('Connect the band first.');
    return l;
  }

  Future<void> load() async {
    final l = link();
    if (l == null) return;
    try {
      builtIn = parseAppList(await l.request(appListRequest()));
      log.app('Band apps: ${builtIn?.join(', ') ?? 'none'}');
    } on TimeoutException {
      log.warn('The band did not send its app list');
    }
    notifyListeners();
    await loadInstalled();
  }

  Future<void> loadInstalled() async {
    final l = link();
    if (l == null) return;
    try {
      installed = parseInstalledApps(await l.request(installedAppsRequest()));
      log.app('Installed apps: ${installed?.join(', ') ?? 'none'}');
    } on TimeoutException {
      log.warn('The band did not list installed apps');
    }
    notifyListeners();
  }

  /// Writes [apps] (in this order) to the band.
  Future<void> save(List<BandApp> apps) async {
    await _need().request(appListCommand(apps));
    builtIn = List.unmodifiable(apps);
    log.app('Band app list saved: ${apps.join(', ')}');
    notifyListeners();
  }

  /// Sends an .rpk to the band and waits until it is listed as installed.
  Future<RpkInfo> install(Uint8List rpk) async {
    final l = _need();
    if (installing != null) {
      throw const AppInstallException('Another app is still installing.');
    }
    final RpkInfo info;
    try {
      info = readRpk(rpk);
    } on FormatException catch (e) {
      throw AppInstallException(e.message);
    }
    installing = info.name;
    progress = 0;
    notifyListeners();
    try {
      log.app('Installing ${info.package} v${info.version} (${rpk.length} B)');
      checkPrepareInstall(
        await l.request(
          prepareInstallApp(info.package, info.version, rpk.length),
          timeout: const Duration(seconds: 15),
        ),
      );
      await upload(
        l,
        appFile,
        rpk,
        onProgress: (p) {
          progress = p;
          notifyListeners();
        },
      );
      final until = DateTime.now().add(_installCheckFor);
      while (DateTime.now().isBefore(until)) {
        await Future<void>.delayed(_installCheckEvery);
        await loadInstalled();
        if (installed?.any((a) => a.package == info.package) ?? false) {
          log.app('Installed ${info.name}');
          return info;
        }
      }
      throw const AppInstallException(
        'The app was sent but the band has not listed it as installed.',
      );
    } on MassException catch (e) {
      throw AppInstallException('Sending the app failed: ${e.message}');
    } finally {
      installing = null;
      notifyListeners();
    }
  }

  Future<void> uninstall(InstalledApp app) async {
    await _need().send(uninstallApp(app));
    log.app('Removing ${app.name} from the band');
    await Future<void>.delayed(const Duration(seconds: 2));
    await loadInstalled();
  }
}
