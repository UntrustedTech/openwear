/// Downloads a file over HTTPS only, following at most a few redirects, with
/// a size limit. Used for face pictures and firmware packages.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

const _maxRedirects = 3;

class DownloadException implements Exception {
  const DownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Downloads [url] (and any redirect) over HTTPS, at most [maxBytes].
/// [onProgress] gets 0–1 when the server sends a length.
Future<Uint8List> httpsDownload(
  Uri url, {
  required int maxBytes,
  Duration timeout = const Duration(seconds: 20),
  void Function(double)? onProgress,
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    var current = url;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      if (current.scheme != 'https') {
        throw const DownloadException('not a secure (https) address');
      }
      final req = await client.getUrl(current).timeout(timeout);
      req.followRedirects = false;
      final rsp = await req.close().timeout(timeout);
      if (rsp.isRedirect) {
        final next = rsp.headers.value(HttpHeaders.locationHeader);
        await rsp.drain<void>();
        if (next == null) {
          throw const DownloadException('redirect without address');
        }
        current = current.resolve(next);
        continue;
      }
      if (rsp.statusCode != 200) {
        await rsp.drain<void>();
        throw DownloadException('HTTP ${rsp.statusCode}');
      }
      final length = rsp.contentLength;
      if (length > maxBytes) throw const DownloadException('file too large');
      final out = BytesBuilder(copy: false);
      await for (final chunk in rsp.timeout(timeout)) {
        out.add(chunk);
        if (out.length > maxBytes) {
          throw const DownloadException('file too large');
        }
        if (length > 0) onProgress?.call(out.length / length);
      }
      return out.takeBytes();
    }
    throw const DownloadException('too many redirects');
  } on TimeoutException {
    throw const DownloadException('timed out');
  } on SocketException catch (e) {
    throw DownloadException('network: ${e.message}');
  } on HandshakeException {
    throw const DownloadException('secure connection failed');
  } on HttpException catch (e) {
    throw DownloadException(e.message);
  } finally {
    client.close(force: true);
  }
}
