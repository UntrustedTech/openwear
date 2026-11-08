/// Pictures of OpenWear's own faces, drawn on the phone one at a time.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:openwear/faces/catalog.dart';
import 'package:openwear/faces/kit.dart';

class CustomFacePreviews extends ChangeNotifier {
  CustomFacePreviews({required this.language});

  /// The phone's language tag.
  final String Function() language;

  final _png = <String, Uint8List>{};
  final _queue = <CustomFace>[];
  final _failed = <String>{};
  bool _running = false;

  /// PNG of [face] as it looks on the band, or null while it is drawn.
  Uint8List? of(CustomFace face) {
    final png = _png[face.id];
    if (png == null && !_failed.contains(face.id) && !_queue.contains(face)) {
      _queue.add(face);
      unawaited(_drain());
    }
    return png;
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final face = _queue.removeAt(0);
        try {
          final design = await face.design(language());
          final raster = await composePreview(design.elements);
          final image = await rasterImage(raster);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          if (data == null) throw StateError('no preview data');
          _png[face.id] = data.buffer.asUint8List();
        } on Object catch (e) {
          debugPrint('Preview of ${face.name} failed: $e');
          _failed.add(face.id);
        }
        notifyListeners();
      }
    } finally {
      _running = false;
    }
  }
}
