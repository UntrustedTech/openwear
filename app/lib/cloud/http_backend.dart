/// One HTTP exchange without redirects or cookie handling, so the cloud client can
/// keep its own cookie jar. On Android the app swaps in the native HTTP stack.
library;

import 'dart:convert';
import 'dart:io';

class HttpReply {
  const HttpReply(
    this.status,
    this.body, {
    this.location,
    this.setCookies = const [],
  });
  final int status;
  final String body;
  final String? location;
  final List<String> setCookies; // raw Set-Cookie header values

  bool get isRedirect => status >= 300 && status < 400 && location != null;
}

/// Network-level failure (DNS, connect, TLS, timeout); [kind] names it for the log.
class NetworkException implements Exception {
  const NetworkException(this.kind, this.message);
  final String kind;
  final String message;
  @override
  String toString() => '$kind: $message';
}

abstract interface class HttpBackend {
  String get name;
  Future<HttpReply> send(
    String method,
    Uri url, {
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  });
}

/// dart:io client (PC tools and tests).
class DartHttpBackend implements HttpBackend {
  @override
  String get name => 'dart:io';

  @override
  Future<HttpReply> send(
    String method,
    Uri url, {
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await _exchange(client, method, url, headers, body).timeout(
        timeout,
        onTimeout: () => throw NetworkException(
          'timeout',
          'no answer from ${url.host} within ${timeout.inSeconds} s',
        ),
      );
    } on SocketException catch (e) {
      throw NetworkException(
        'socket',
        e.message + (e.osError == null ? '' : ' (${e.osError})'),
      );
    } on HandshakeException catch (e) {
      throw NetworkException('tls', e.message);
    } on HttpException catch (e) {
      throw NetworkException('http', e.message);
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpReply> _exchange(
    HttpClient client,
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  ) async {
    final req = await client.openUrl(method, url);
    req.followRedirects = false;
    headers.forEach(req.headers.set);
    if (body != null) {
      // Xiaomi's servers reject chunked bodies (HTTP 502), so send a fixed length.
      final bytes = utf8.encode(body);
      req.contentLength = bytes.length;
      req.add(bytes);
    }
    final rsp = await req.close();
    final text = await rsp.transform(utf8.decoder).join();
    return HttpReply(
      rsp.statusCode,
      text,
      location: rsp.headers.value(HttpHeaders.locationHeader),
      setCookies: rsp.headers[HttpHeaders.setCookieHeader] ?? const [],
    );
  }
}

/// The backend every cloud call uses; main() installs the native one on Android.
HttpBackend httpBackend = DartHttpBackend();
