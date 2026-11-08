import 'package:permission_handler/permission_handler.dart';

/// Everything the companion needs; returns the permissions still denied.
Future<List<Permission>> requestCompanionPermissions() async {
  const wanted = [
    Permission.bluetoothConnect,
    Permission.bluetoothScan,
    Permission.notification,
    Permission.phone, // READ_PHONE_STATE + ANSWER_PHONE_CALLS
    Permission.contacts, // caller names
    Permission.locationWhenInUse, // approximate location for weather
  ];
  final results = await wanted.request();
  return [
    for (final entry in results.entries)
      if (!entry.value.isGranted) entry.key,
  ];
}
