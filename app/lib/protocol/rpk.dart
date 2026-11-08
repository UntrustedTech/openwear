/// Reads an .rpk band app package (a zip with manifest.json).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class RpkInfo {
  const RpkInfo(this.package, this.name, this.version);
  final String package;
  final String name;
  final int version;
}

/// Package, name and version code from [file]; throws [FormatException]
/// when it is not an app package.
RpkInfo readRpk(Uint8List file) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(file);
  } on Object {
    throw const FormatException('Not an .rpk app package');
  }
  final entry = zip.findFile('manifest.json');
  if (entry == null) {
    throw const FormatException('The package has no manifest.json');
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(entry.content));
  } on FormatException {
    throw const FormatException('The package manifest is unreadable');
  }
  if (json is! Map) throw const FormatException('Bad package manifest');
  final package = json['package'];
  if (package is! String || package.isEmpty) {
    throw const FormatException('The manifest names no package');
  }
  final version = switch (json['versionCode']) {
    final int v => v,
    final String s => int.tryParse(s) ?? 1,
    _ => 1,
  };
  final name = json['name'];
  return RpkInfo(
    package,
    name is String && name.isNotEmpty ? name : package,
    version,
  );
}
