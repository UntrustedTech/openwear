/// Band firmware updates from Xiaomi's servers, the way Mi Fitness gets
/// them: ask `device/latest_ver` with the band's cloud id, model and
/// firmware. A newer package is downloaded and checked first, kept on the
/// phone (also copied to Download/OpenWear/Firmware so the user can reach
/// it), and only then sent to the band. The last package stays on the phone
/// so it can be sent again to recover the band, and any package file can be
/// sent too (for example an older version, to downgrade).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:openwear/cloud/https_download.dart';
import 'package:openwear/cloud/xiaomi_cloud.dart' as cloud;
import 'package:openwear/protocol/link.dart';
import 'package:openwear/protocol/mass.dart';
import 'package:openwear/protocol/ota.dart';
import 'package:openwear/services/band_log.dart';

/// Largest package accepted.
const maxFirmwareBytes = 64 * 1024 * 1024;

/// Folder under the phone's Download folder.
const firmwareDownloadFolder = 'OpenWear/Firmware';

enum FirmwareStep { idle, checking, downloading, sending, sent }

/// Asks the server; null when the band is up to date.
typedef FindRelease = Future<cloud.FirmwareRelease?> Function(
  String model,
  String firmware,
);
typedef DownloadPackage = Future<Uint8List> Function(
  Uri url,
  void Function(double) onProgress,
);

/// Copies a package where the user can find it; returns that place.
typedef ExportPackage = Future<String> Function(String name, Uint8List bytes);

/// The package kept on the phone.
class SavedFirmware {
  const SavedFirmware({
    required this.model,
    required this.version,
    required this.md5,
    required this.file,
    this.changeLog = '',
    this.publicPath,
  });

  final String model;
  final String version;
  final String md5;
  final String file;
  final String changeLog;

  /// Where the user finds the copy, when it could be made.
  final String? publicPath;

  Map<String, Object?> toJson() => {
    'model': model,
    'version': version,
    'md5': md5,
    'file': file,
    'changeLog': changeLog,
    'publicPath': publicPath,
  };

  static SavedFirmware? fromJson(Object? j) {
    if (j is! Map) return null;
    final model = j['model'], version = j['version'];
    final md5 = j['md5'], file = j['file'];
    if (model is! String || version is! String) return null;
    if (md5 is! String || file is! String) return null;
    final log = j['changeLog'], public = j['publicPath'];
    return SavedFirmware(
      model: model,
      version: version,
      md5: md5,
      file: file,
      changeLog: log is String ? log : '',
      publicPath: public is String ? public : null,
    );
  }
}

/// `<model>_<version>.bin` with only safe characters.
String firmwareFileName(String model, String version) =>
    '${model}_$version.bin'.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

/// The `x.y.z` version in a package file name, if there is one.
String? versionInFileName(String name) =>
    RegExp(r'(\d+\.\d+\.\d+)').firstMatch(name)?.group(1);

String md5Hex(List<int> data) =>
    md5(data).map((x) => x.toRadixString(16).padLeft(2, '0')).join();

class FirmwareUpdate extends ChangeNotifier {
  FirmwareUpdate({
    required this.log,
    required this.link,
    required this.findRelease,
    required this.directory,
    DownloadPackage? download,
    this.export,
  }) : _download = download ?? _httpsDownload;

  final BandLog log;
  final Link? Function() link;
  final FindRelease findRelease;

  /// Private folder for the kept package.
  final Future<Directory> Function() directory;
  final ExportPackage? export;
  final DownloadPackage _download;

  FirmwareStep step = FirmwareStep.idle;
  double progress = 0;

  /// Version being sent, for the screen.
  String? sending;

  /// The newer release, after a check found one.
  cloud.FirmwareRelease? release;

  /// The package kept on the phone, if any.
  SavedFirmware? saved;

  /// When the last check finished, and for which firmware.
  DateTime? checkedAt;
  String? checkedFirmware;

  /// The last failure, for the screen.
  String? error;

  bool get busy =>
      step == FirmwareStep.checking ||
      step == FirmwareStep.downloading ||
      step == FirmwareStep.sending;

  /// Whether the kept package is the offered release (no download needed).
  bool get releaseDownloaded {
    final r = release, s = saved;
    return r != null && s != null && s.version == r.version && s.md5 == r.md5;
  }

  void _set(FirmwareStep s, {double progress = 0}) {
    step = s;
    this.progress = progress;
    notifyListeners();
  }

  Future<File> _index() async =>
      File('${(await directory()).path}/latest.json');

  /// Reads which package is kept.
  Future<void> load() async {
    try {
      final f = await _index();
      if (!f.existsSync()) return;
      final s = SavedFirmware.fromJson(jsonDecode(await f.readAsString()));
      if (s != null && File(s.file).existsSync()) {
        saved = s;
        notifyListeners();
      }
    } on FileSystemException catch (e) {
      log.warn('Saved firmware could not be read: ${e.message}');
    } on FormatException {
      log.warn('Saved firmware record was unreadable');
    } on Exception catch (e) {
      // No app folder (tests, desktop tools).
      log.warn('Saved firmware unavailable: $e');
    }
  }

  /// Asks Xiaomi; a newer release is downloaded and kept right away.
  Future<void> check(String model, String firmware) async {
    if (busy) return;
    error = null;
    _set(FirmwareStep.checking);
    try {
      release = await findRelease(model, firmware);
      checkedAt = DateTime.now();
      checkedFirmware = firmware;
      final r = release;
      log.app(
        r == null
            ? 'Firmware $firmware is the latest'
            : 'Firmware ${r.version} is available',
      );
      _set(FirmwareStep.idle);
      if (r != null && !releaseDownloaded) await _fetch(model, r);
    } on cloud.CloudException catch (e) {
      _fail(e.message, 'Firmware check failed');
    }
  }

  /// Downloads [r], checks it and keeps it, replacing the older package.
  Future<bool> _fetch(String model, cloud.FirmwareRelease r) async {
    try {
      _set(FirmwareStep.downloading);
      log.app('Downloading firmware ${r.version}');
      final package = await _download(r.url, (p) {
        progress = p;
        notifyListeners();
      });
      if (md5Hex(package) != r.md5) {
        throw const FirmwareException(
          'The download was damaged (checksum mismatch). Try again.',
        );
      }
      await _keep(model, r.version, r.md5, package, r.changeLog);
      _set(FirmwareStep.idle);
      return true;
    } on DownloadException catch (e) {
      _fail('Download failed: ${e.message}');
    } on FirmwareException catch (e) {
      _fail(e.message);
    } on FileSystemException catch (e) {
      _fail('Could not save the package: ${e.message}');
    }
    return false;
  }

  Future<void> _keep(
    String model,
    String version,
    String sum,
    Uint8List package,
    String changeLog,
  ) async {
    final dir = await directory();
    await dir.create(recursive: true);
    final name = firmwareFileName(model, version);
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(package, flush: true);
    String? publicPath;
    try {
      publicPath = await export?.call(name, package);
    } on Exception catch (e) {
      log.warn('Firmware not copied to Download: $e');
    }
    final old = saved;
    final kept = SavedFirmware(
      model: model,
      version: version,
      md5: sum,
      file: file.path,
      changeLog: changeLog,
      publicPath: publicPath,
    );
    saved = kept;
    await (await _index()).writeAsString(jsonEncode(kept.toJson()));
    if (old != null && old.file != file.path) {
      try {
        await File(old.file).delete();
      } on FileSystemException {
        // already gone
      }
    }
    log.app(
      'Firmware $version saved (${package.length} bytes)'
      '${publicPath == null ? '' : ' · $publicPath'}',
    );
  }

  /// Sends the offered release, downloading it first when needed.
  Future<void> install(String model) async {
    final r = release;
    if (r == null || busy) return;
    if (link() == null) {
      _fail('Connect the band first.');
      return;
    }
    error = null;
    if (!releaseDownloaded && !await _fetch(model, r)) return;
    await sendSaved();
  }

  /// Sends the kept package to the band: the update, or a recovery.
  Future<void> sendSaved() async {
    final s = saved;
    if (s == null || busy) return;
    try {
      final package = await File(s.file).readAsBytes();
      if (md5Hex(package) != s.md5) {
        _fail(
          'The saved package is damaged. Check for updates to get it again.',
        );
        return;
      }
      await _send(s.version, s.md5, package);
    } on FileSystemException catch (e) {
      _fail('The saved package could not be read: ${e.message}');
    }
  }

  /// Sends a package the user picked (e.g. an older version, to downgrade).
  /// The band decides whether it accepts it.
  Future<void> sendFile(Uint8List package, String version) async {
    if (busy) return;
    if (package.isEmpty || package.length > maxFirmwareBytes) {
      _fail('That file is not a firmware package.');
      return;
    }
    await _send(version, md5Hex(package), package);
  }

  Future<void> _send(String version, String sum, Uint8List package) async {
    final l = link();
    if (l == null) {
      _fail('Connect the band first.');
      return;
    }
    error = null;
    sending = version;
    try {
      _set(FirmwareStep.sending);
      final wanted = checkPrepareFirmware(
        await l.request(
          prepareFirmware(version, sum),
          timeout: const Duration(seconds: 20),
        ),
      );
      if (wanted) {
        log.app('Sending firmware $version (${package.length} bytes)');
        await upload(
          l,
          firmwareFile,
          package,
          onProgress: (p) {
            progress = p;
            notifyListeners();
          },
        );
        log.app('Firmware $version sent; the band installs it now');
      } else {
        log.app('The band already has firmware $version');
      }
      _set(FirmwareStep.sent, progress: 1);
    } on FirmwareException catch (e) {
      _fail(e.message);
    } on MassException catch (e) {
      _fail('Sending failed: ${e.message}');
    } on TimeoutException {
      _fail('The band stopped answering. Keep it close and try again.');
    }
  }

  void _fail(String why, [String prefix = 'Firmware update']) {
    error = why;
    log.warn('$prefix: $why');
    _set(FirmwareStep.idle);
  }
}

Future<Uint8List> _httpsDownload(Uri url, void Function(double) onProgress) =>
    httpsDownload(
      url,
      maxBytes: maxFirmwareBytes,
      timeout: const Duration(seconds: 60),
      onProgress: onProgress,
    );
