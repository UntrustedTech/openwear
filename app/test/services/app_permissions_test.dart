import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/services/app_permissions.dart';
import 'package:openwear/services/health_connect.dart';

void main() {
  test('every permission row explains why and what happens without it', () {
    for (final p in appPermissions) {
      expect(p.why, isNotEmpty, reason: p.title);
      expect(p.ifOff, isNotEmpty, reason: p.title);
      expect(p.permissions, isNotEmpty, reason: p.title);
    }
  });

  test('only Bluetooth is required to reach the band', () {
    expect(appPermissions.where((p) => p.required).map((p) => p.title), [
      'Nearby devices',
    ]);
  });

  test('every Health Connect kind has a use described', () {
    expect(healthKindUse.keys.toSet(), healthKinds.keys.toSet());
  });
}
