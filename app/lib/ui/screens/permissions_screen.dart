import 'package:flutter/material.dart';
import 'package:openwear/platform/android_bridge.dart';
import 'package:openwear/services/app_permissions.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/services/health_connect.dart';
import 'package:openwear/ui/common.dart';
import 'package:openwear/ui/kit/kit.dart';
import 'package:permission_handler/permission_handler.dart';

/// Which permissions OpenWear holds, why it asks for each, and what stops
/// working without it. Tapping a row asks again, or opens Android's page
/// for the app when Android no longer shows the request.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key, required this.band});
  final BandService band;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  final _allowed = <String, bool>{};
  bool? _notificationAccess;
  bool? _overLockScreen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Re-checks when returning from Android's or Health Connect's settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final allowed = <String, bool>{};
    for (final p in appPermissions) {
      var all = true;
      for (final perm in p.permissions) {
        if (!await perm.isGranted) all = false;
      }
      allowed[p.title] = all;
    }
    bool? access;
    try {
      access = await notificationAccessGranted();
    } on Exception {
      access = null;
    }
    bool? overLock;
    try {
      overLock = await findPhoneOverLockScreen();
    } on Exception {
      overLock = null;
    }
    await widget.band.refreshHealthConnect();
    if (!mounted) return;
    setState(() {
      _allowed
        ..clear()
        ..addAll(allowed);
      _notificationAccess = access;
      _overLockScreen = overLock;
    });
  }

  /// Asks when off. Android's own page for the app is opened to turn a
  /// permission off, or when Android no longer shows the request because it
  /// was declined before.
  Future<void> _change(PermissionInfo p) async {
    if (_allowed[p.title] ?? false) {
      await openAppSettings();
      return;
    }
    final results = await p.permissions.request();
    if (results.values.any((s) => s.isPermanentlyDenied)) {
      await openAppSettings();
    }
    await _check();
  }

  @override
  Widget build(BuildContext context) => SubPage(
    title: 'App permissions',
    children: [
      RowGroup(
        label: 'Android',
        note:
            'Tap a row to allow it, or to open Android’s settings for '
            'OpenWear to turn it off.',
        children: [
          for (final p in appPermissions)
            _PermissionRow(
              title: p.required ? '${p.title} (required)' : p.title,
              icon: _icon(p.title),
              allowed: _allowed[p.title],
              why: p.why,
              ifOff: p.ifOff,
              onTap: () => _change(p),
            ),
          _PermissionRow(
            title: 'Notification access',
            icon: Icons.mark_chat_unread_outlined,
            allowed: _notificationAccess,
            why: notificationAccessUse.why,
            ifOff: notificationAccessUse.ifOff,
            onTap: openNotificationAccessSettings,
          ),
          _PermissionRow(
            title: 'Find phone on lock screen',
            icon: Icons.flashlight_on_outlined,
            allowed: _overLockScreen,
            why: findPhoneScreenUse.why,
            ifOff: findPhoneScreenUse.ifOff,
            onTap: openFindPhoneOverLockScreenSettings,
          ),
        ],
      ),
      _HealthConnectGroup(band: widget.band),
      const RowGroup(
        label: 'Always on',
        children: [
          KitRow(
            icon: Icons.public_rounded,
            title: 'Internet',
            value: 'Allowed',
            subtitleLines: null,
            subtitle:
                'Granted at install. Used for Xiaomi account sign-in, '
                'weather and firmware updates. Health data stays on this '
                'phone; it only goes to Health Connect and to exports you '
                'make.',
          ),
        ],
      ),
    ],
  );

  IconData _icon(String title) => switch (title) {
    'Nearby devices' => Icons.bluetooth_rounded,
    'Notifications' => Icons.notifications_none_rounded,
    'Phone & calls' => Icons.call_outlined,
    'Contacts' => Icons.contacts_outlined,
    'Approximate location' => Icons.location_on_outlined,
    _ => Icons.shield_outlined,
  };
}

class _HealthConnectGroup extends StatelessWidget {
  const _HealthConnectGroup({required this.band});
  final BandService band;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: band.healthConnect,
    builder: (context, _) {
      final sync = band.healthConnect;
      final usable =
          sync.state != HealthConnectState.unavailable &&
          sync.state != HealthConnectState.needsUpdate;
      final status = switch (sync.state) {
        HealthConnectState.unavailable => 'Health Connect is not on this phone',
        HealthConnectState.needsUpdate => 'Update Health Connect to use it',
        _ when !sync.enabled =>
          'Sharing is off. Turn it on in Health to send band data there.',
        _ when sync.missing.isEmpty => 'Sharing everything below',
        _ => 'Not shared: ${sync.missingLabel}',
      };
      return RowGroup(
        label: 'Health Connect',
        note: healthConnectIfOff,
        children: [
          KitRow(
            icon: Icons.favorite_border_rounded,
            title: 'Health Connect',
            subtitle: status,
            chevron: usable,
            onTap: usable ? () => runAction(context, sync.openSettings) : null,
          ),
          if (usable)
            for (final MapEntry(key: kind, value: use) in healthKindUse.entries)
              KitRow(
                title: _capitalized(healthKinds[kind]!),
                subtitle: use,
                value: sync.state == HealthConnectState.unknown
                    ? null
                    : sync.missing.contains(kind)
                    ? 'Off'
                    : 'Allowed',
                onTap: () => runAction(context, sync.openSettings),
              ),
        ],
      );
    },
  );
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.title,
    required this.icon,
    required this.allowed,
    required this.why,
    required this.ifOff,
    required this.onTap,
  });
  final String title;
  final IconData icon;
  final bool? allowed;
  final String why;
  final String ifOff;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KitRow(
    icon: icon,
    title: title,
    subtitle: allowed == false ? '$why\n\nWhile off: $ifOff' : why,
    subtitleLines: null,
    value: switch (allowed) {
      true => 'Allowed',
      false => 'Off',
      null => null,
    },
    chevron: true,
    onTap: onTap,
  );
}

/// "heart rate" → "Heart rate"; SpO₂ keeps its own capitals.
String _capitalized(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
