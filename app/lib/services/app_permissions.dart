/// What each Android permission OpenWear asks for is used for, and what
/// stops working without it. Shown in Settings → App permissions.
library;

import 'package:permission_handler/permission_handler.dart';

class PermissionInfo {
  const PermissionInfo({
    required this.title,
    required this.why,
    required this.ifOff,
    required this.permissions,
    this.required = false,
  });
  final String title;

  /// Why the app asks.
  final String why;

  /// What happens to the band and its data without it.
  final String ifOff;

  /// The Android permissions behind this row; all must be allowed.
  final List<Permission> permissions;

  /// Without it the app cannot reach the band at all.
  final bool required;
}

const appPermissions = [
  PermissionInfo(
    title: 'Nearby devices',
    why:
        'Finds the band and keeps the Bluetooth link to it open. Everything '
        'else goes over this link.',
    ifOff:
        'OpenWear cannot connect, so nothing syncs: no steps, heart rate or '
        'sleep reach the phone, and no notifications, weather or calls reach '
        'the band. The band keeps recording and sends it all once allowed.',
    permissions: [Permission.bluetoothConnect, Permission.bluetoothScan],
    required: true,
  ),
  PermissionInfo(
    title: 'Notifications',
    why:
        'Shows the “Connected to your band” notification that lets Android '
        'keep OpenWear running in the background.',
    ifOff:
        'Android may stop the app when it is in the background. The band '
        'then only syncs while OpenWear is open, which leaves gaps in heart '
        'rate and in what Health Connect receives until the next sync.',
    permissions: [Permission.notification],
  ),
  PermissionInfo(
    title: 'Phone & calls',
    why:
        'Shows who is calling on the band, and lets you reject or end a call '
        'from it.',
    ifOff:
        'Incoming calls are not shown on the band. Health data is not '
        'affected.',
    permissions: [Permission.phone],
  ),
  PermissionInfo(
    title: 'Contacts',
    why: 'Turns a caller’s number into the name shown on the band.',
    ifOff: 'The band shows the number instead of the name.',
    permissions: [Permission.contacts],
  ),
  PermissionInfo(
    title: 'Approximate location',
    why:
        'Finds your city for the band’s weather. Only the rough area is '
        'used, and only when weather is sent.',
    ifOff: 'The band gets no weather updates. Health data is not affected.',
    permissions: [Permission.locationWhenInUse],
  ),
];

/// Why each Health Connect kind is written, by the names in [healthKinds].
const healthKindUse = {
  'heartRate': 'Every heart-rate reading, minute by minute',
  'steps': 'Steps per hour',
  'activeKcal': 'Calories burned by moving',
  'totalKcal': 'All calories burned, resting included',
  'spo2': 'Blood oxygen from automatic and spot checks',
  'restingHr': 'Resting heart rate for each day',
  'sleep': 'Sleep sessions, with stages when the band records them',
};

const healthConnectIfOff =
    'A kind without access is kept in OpenWear but not shared, so other apps '
    '(Google Fit, Samsung Health and others) do not see it, and Health '
    'Connect lists OpenWear as inactive for it. What was written before stays '
    'in Health Connect. Once access is back, OpenWear sends what it still '
    'has: the past day of heart rate, today’s activity and the past week’s '
    'sleep.';

const findPhoneScreenUse = (
  why:
      'When the band looks for your phone, OpenWear shows a flashing page '
      'over the lock screen and turns the screen on, so the phone is easy '
      'to spot.',
  ifOff:
      'Find phone still rings and vibrates, but the screen stays dark '
      'while the phone is locked.',
);

const notificationAccessUse = (
  why:
      'Lets OpenWear read phone notifications to show them on the band, and '
      'see what is playing so the band can control music.',
  ifOff:
      'The band gets no app notifications, and its music controls do '
      'nothing. Health data is not affected.',
);
