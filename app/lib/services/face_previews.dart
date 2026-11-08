/// Pictures of each watch face. Either captured from the band itself (the
/// band shows the face, the phone asks for a screenshot, 2/108) or, when the
/// user is signed in to Xiaomi, the official picture from Xiaomi's face store.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/screenshot.dart';
import 'package:openwear/services/band_log.dart';

typedef Send = Future<void> Function(Command);
typedef SwitchFace = Future<void> Function(String id);

class FacePreviews extends ChangeNotifier {
  FacePreviews({
    required this.log,
    required this.directory,
    this.seal = _same,
    this.open = _same,
  });

  static Future<Uint8List> _same(Uint8List b) async => b;

  final BandLog log;

  /// Encrypts a picture before it is written, and decrypts it after reading
  /// (band screenshots can show readings and notifications).
  final Future<Uint8List> Function(Uint8List) seal, open;

  /// Where previews are kept (per band).
  final Future<Directory> Function() directory;

  /// Time for the band to draw a face after switching to it.
  static const settleTime = Duration(milliseconds: 1800);
  static const timeout = Duration(seconds: 20);

  final _assembler = ScreenshotAssembler();
  final _shots = StreamController<Screenshot>.broadcast();

  /// The last screenshot the band sent (PNG), e.g. one taken on the band.
  Uint8List? latest;
  final _images = <String, Uint8List>{};

  Map<String, Uint8List> get images => Map.unmodifiable(_images);

  /// Face being captured now, if any.
  String? capturing;
  bool get busy => capturing != null;

  /// Faces whose picture came from Xiaomi's store (not a screenshot).
  final fromStore = <String>{};

  Future<File> _storeList() async =>
      File('${(await directory()).path}/from_store.txt');

  Future<File> _file(String faceId) async {
    final name = base64Url.encode(utf8.encode(faceId)).replaceAll('=', '');
    return File('${(await directory()).path}/$name.png');
  }

  /// Loads saved previews for [faceIds].
  Future<void> load(Iterable<String> faceIds) async {
    try {
      final list = await _storeList();
      if (await list.exists()) {
        fromStore
          ..clear()
          ..addAll((await list.readAsLines()).where((l) => l.isNotEmpty));
      }
    } on FileSystemException catch (e) {
      log.warn('Could not read face picture list: ${e.message}');
    }
    for (final id in faceIds) {
      if (_images.containsKey(id)) continue;
      try {
        final f = await _file(id);
        if (await f.exists()) _images[id] = await open(await f.readAsBytes());
      } on FileSystemException catch (e) {
        log.warn('Could not read face preview: ${e.message}');
      } on FormatException {
        log.warn('A saved face preview failed its check; skipped');
      } on PlatformException catch (e) {
        log.warn('Face preview key unavailable: ${e.message}');
        break;
      }
    }
    notifyListeners();
  }

  /// Feeds a data packet from the band; true when it was a screenshot part.
  bool feed(Uint8List packet) {
    if (!isScreenshotPacket(packet)) return false;
    try {
      final shot = _assembler.feed(packet);
      if (shot != null) {
        log.app('Band screenshot received (${shot.png.length} bytes)');
        latest = shot.png;
        _shots.add(shot);
        notifyListeners();
      }
    } on FormatException catch (e) {
      log.warn('Dropped screenshot packet: ${e.message}');
    }
    return true;
  }

  /// Asks the band for a picture of its screen.
  Future<Uint8List> screenshot(Send send) async {
    final next = _shots.stream.first.timeout(timeout);
    _assembler.reset();
    await send(screenshotRequest());
    try {
      return (await next).png;
    } on TimeoutException {
      throw TimeoutException('The band did not send a screenshot');
    }
  }

  /// Captures each face in [faceIds] in turn, then returns to [restoreId].
  Future<int> captureAll(
    List<String> faceIds, {
    required String? restoreId,
    required Send send,
    required SwitchFace switchTo,
    Duration settle = settleTime,
  }) async {
    if (busy) return 0;
    var captured = 0;
    try {
      for (final id in faceIds) {
        capturing = id;
        notifyListeners();
        try {
          await switchTo(id);
          await Future<void>.delayed(settle);
          await keep(id, await screenshot(send));
          captured++;
        } on TimeoutException catch (e) {
          log.warn('No preview for face $id: ${e.message}');
          // A band that refuses the first picture refuses them all; stop
          // instead of cycling through every face for minutes.
          if (captured == 0) {
            log.warn('Band is not sending screenshots; stopped capturing');
            break;
          }
        }
      }
    } finally {
      if (restoreId != null) {
        try {
          await switchTo(restoreId);
        } on TimeoutException {
          log.warn('Could not switch back to the original face');
        }
      }
      capturing = null;
      notifyListeners();
    }
    log.app('Captured $captured of ${faceIds.length} face previews');
    return captured;
  }

  /// Saves [png] (any image format) as [id]'s picture.
  Future<void> keep(String id, Uint8List png, {bool store = false}) async {
    _images[id] = png;
    final changed = store ? fromStore.add(id) : fromStore.remove(id);
    if (changed) await _saveStoreList();
    notifyListeners();
    try {
      await (await _file(id)).writeAsBytes(await seal(png), flush: true);
    } on FileSystemException catch (e) {
      log.warn('Could not save face preview: ${e.message}');
    } on PlatformException catch (e) {
      log.warn('Could not seal face preview: ${e.message}');
    }
  }

  Future<void> _saveStoreList() async {
    try {
      await (await _storeList()).writeAsString(fromStore.join('\n'));
    } on FileSystemException catch (e) {
      log.warn('Could not save face picture list: ${e.message}');
    }
  }

  void forget(String id) {
    if (fromStore.remove(id)) unawaited(_saveStoreList());
    if (_images.remove(id) == null) return;
    notifyListeners();
    unawaited(_delete(id));
  }

  Future<void> _delete(String id) async {
    try {
      final f = await _file(id);
      if (await f.exists()) await f.delete();
    } on FileSystemException catch (e) {
      log.warn('Could not delete face preview: ${e.message}');
    }
  }

  @override
  void dispose() {
    unawaited(_shots.close());
    super.dispose();
  }
}
