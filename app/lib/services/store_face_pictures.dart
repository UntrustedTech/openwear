/// Official pictures of the band's built-in faces, from Xiaomi's face store
/// (the same `paidwatchface/detail` call Mi Fitness makes). Pictures are
/// fetched only for faces on the user's own band, with the user's sign-in,
/// and kept on the phone; none are bundled with OpenWear.
library;

import 'dart:typed_data';

import 'package:openwear/cloud/https_download.dart';
import 'package:openwear/cloud/xiaomi_cloud.dart' as cloud;

/// Largest picture accepted.
const maxPictureBytes = 3 * 1024 * 1024;

typedef FetchDetail = Future<cloud.CloudFace> Function(String faceId);
typedef FetchAll = Future<Map<String, cloud.CloudFace>> Function(
  List<String> faceIds,
);
typedef Download = Future<Uint8List> Function(Uri url);

/// True when [b] starts like a PNG, JPEG, WebP or GIF file.
bool looksLikeImage(Uint8List b) {
  bool at(int offset, List<int> sig) =>
      b.length >= offset + sig.length &&
      [for (var i = 0; i < sig.length; i++) b[offset + i]].join(',') ==
          sig.join(',');
  return at(0, const [0x89, 0x50, 0x4E, 0x47]) ||
      at(0, const [0xFF, 0xD8, 0xFF]) ||
      (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits)) ||
      at(0, 'GIF8'.codeUnits);
}

/// Faces OpenWear made itself already have pictures.
bool isOwnFace(String id) => id.startsWith('9600000');

/// Result of one fetch run.
class StoreFetchResult {
  const StoreFetchResult(this.saved, this.missing);
  final int saved;

  /// Faces the store had no picture for.
  final int missing;
}

/// Fetches and checks pictures for [faceIds]; [keep] stores each one.
Future<StoreFetchResult> fetchStorePictures(
  List<String> faceIds, {
  required FetchDetail detail,
  required Download download,
  required Future<void> Function(String id, Uint8List picture) keep,
  FetchAll? lookupAll,
  void Function(String line)? warn,
}) async {
  var saved = 0, missing = 0;
  final wanted = [
    for (final id in faceIds)
      if (!isOwnFace(id)) id,
  ];
  var known = const <String, cloud.CloudFace>{};
  if (lookupAll != null && wanted.isNotEmpty) {
    try {
      known = await lookupAll(wanted);
    } on cloud.CloudException catch (e) {
      if (e.expired || e.network) rethrow;
      warn?.call('Xiaomi face list lookup failed: ${e.message}');
    }
  }
  for (final id in wanted) {
    final cloud.CloudFace face;
    try {
      final listed = known[id];
      face = listed != null && listed.pictureUrl != null
          ? listed
          : await detail(id);
    } on cloud.CloudException catch (e) {
      // An expired sign-in or no network ends the run; a face the store
      // does not know (common for built-in faces) is just skipped.
      if (e.expired || e.network) rethrow;
      warn?.call('Xiaomi has no entry for face $id: ${e.message}');
      missing++;
      continue;
    }
    final url = face.pictureUrl;
    if (url == null) {
      missing++;
      continue;
    }
    try {
      final bytes = await download(url);
      if (!looksLikeImage(bytes)) {
        warn?.call('Picture for face $id was not an image; skipped');
        missing++;
        continue;
      }
      await keep(id, bytes);
      saved++;
    } on PictureDownloadException catch (e) {
      warn?.call('Picture for face $id not downloaded: ${e.message}');
      missing++;
    }
  }
  return StoreFetchResult(saved, missing);
}

typedef PictureDownloadException = DownloadException;

/// Downloads [url] over HTTPS only (redirects too), at most [maxPictureBytes].
Future<Uint8List> downloadPicture(Uri url) =>
    httpsDownload(url, maxBytes: maxPictureBytes);
