/// Explains why the Xiaomi servers can't be reached: DNS, TCP connect, HTTPS, per host.
library;

import 'dart:io';

import 'package:openwear/cloud/http_backend.dart';

const _step = Duration(seconds: 6);

/// Hosts the app needs, plus a neutral control site.
const checkedHosts = [
  'account.xiaomi.com',
  'us.hlth.io.mi.com',
  'connectivitycheck.gstatic.com',
];

/// One line per finding, ending with a plain-language conclusion.
Future<List<String>> networkCheck({
  HttpBackend? backend,
  Future<Map<String, String>> Function()? describeNetwork,
  List<String> hosts = checkedHosts,
}) async {
  final lines = <String>[];
  if (describeNetwork != null) {
    try {
      final info = await describeNetwork();
      lines.addAll(info.entries.map((e) => '${e.key}: ${e.value}'));
    } on Exception catch (e) {
      lines.add('network info unavailable: $e');
    }
  }
  final reachable = <String, bool>{};
  for (final host in hosts) {
    reachable[host] = await _checkHost(host, backend ?? httpBackend, lines);
  }
  lines.add(_conclusion(reachable));
  return lines;
}

Future<bool> _checkHost(
  String host,
  HttpBackend backend,
  List<String> lines,
) async {
  final clock = Stopwatch()..start();
  final List<InternetAddress> addresses;
  try {
    addresses = await InternetAddress.lookup(host).timeout(_step);
  } on Exception catch (e) {
    lines.add('$host  DNS ✗ ${_short(e)} (${clock.elapsedMilliseconds} ms)');
    return false;
  }
  final shown = addresses.map((a) => a.address).join(', ');
  final blocked = addresses.any(
    (a) => a.isLoopback || a.address == '0.0.0.0' || a.address == '::',
  );
  lines.add(
    '$host  DNS ✓ $shown (${clock.elapsedMilliseconds} ms)'
    '${blocked ? '  ← blocked by a DNS filter' : ''}',
  );
  if (blocked) return false;

  for (final type in [InternetAddressType.IPv4, InternetAddressType.IPv6]) {
    final address = addresses.where((a) => a.type == type).firstOrNull;
    if (address == null) continue;
    clock.reset();
    try {
      final socket = await Socket.connect(address, 443, timeout: _step);
      socket.destroy();
      lines.add('$host  TCP ${type.name} ✓ ${clock.elapsedMilliseconds} ms');
    } on Exception catch (e) {
      lines.add('$host  TCP ${type.name} ✗ ${_short(e)}');
    }
  }

  clock.reset();
  try {
    final r = await backend.send(
      'GET',
      Uri.https(host, '/'),
      headers: const {},
      timeout: _step,
    );
    lines.add(
      '$host  HTTPS (${backend.name}) ✓ HTTP ${r.status}, ${clock.elapsedMilliseconds} ms',
    );
    return true;
  } on NetworkException catch (e) {
    lines.add('$host  HTTPS (${backend.name}) ✗ $e');
    return false;
  }
}

String _conclusion(Map<String, bool> reachable) {
  final control = reachable['connectivitycheck.gstatic.com'] ?? true;
  final xiaomiDown = reachable.entries
      .where((e) => e.key.contains('xiaomi') || e.key.contains('mi.com'))
      .where((e) => !e.value)
      .map((e) => e.key);
  if (!control) {
    return 'Conclusion: this phone has no working internet connection right now.';
  }
  if (xiaomiDown.isEmpty) return 'Conclusion: all servers reachable.';
  return 'Conclusion: the internet works but ${xiaomiDown.join(', ')} cannot be reached. '
      'A Private DNS / ad-blocker / VPN, or the mobile network, is blocking Xiaomi.';
}

String _short(Object e) => switch (e) {
  SocketException(:final message, :final osError) =>
    '$message${osError == null ? '' : ' ($osError)'}',
  _ => '$e',
};
