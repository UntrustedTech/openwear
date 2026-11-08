import 'package:flutter/material.dart';
import 'package:openwear/platform/android_bridge.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/ui/common.dart';
import 'package:openwear/ui/kit/kit.dart';
import 'package:openwear/ui/log_screen.dart';
import 'package:openwear/ui/screens/export_sheet.dart';
import 'package:openwear/ui/screens/band_apps_screen.dart';
import 'package:openwear/ui/screens/appearance_screen.dart';
import 'package:openwear/ui/screens/band_settings_screen.dart';
import 'package:openwear/ui/screens/firmware_screen.dart';
import 'package:openwear/ui/screens/device_info_screen.dart';
import 'package:openwear/ui/screens/permissions_screen.dart';
import 'package:openwear/ui/screens/profile_screen.dart';
import 'package:openwear/ui/screens/supported_devices_screen.dart';
import 'package:openwear/ui/screens/xiaomi_account_screen.dart';
import 'package:openwear/ui/widgets/band_preview.dart';
import 'package:openwear/ui/widgets/openwear_logo.dart';

/// Asked once: the app version doesn't change while it runs.
final Future<Map<String, String>> _appInfo = deviceInfo().catchError(
  (Object _) => const <String, String>{},
);

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.band});
  final BandService band;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final connected = band.connected;
    return TabPage(
      title: 'Settings',
      children: [
        _DevicePanel(band: band),
        if (connected)
          RowGroup(
            children: [
              KitRow(
                icon: Icons.volume_up_outlined,
                title: band.finding ? 'Stop ringing' : 'Find band',
                subtitle: 'Rings and vibrates the band',
                onTap: () =>
                    runAction(context, () => band.findBand(stop: band.finding)),
              ),
              ToggleRow(
                icon: Icons.do_not_disturb_on_outlined,
                title: 'Do Not Disturb',
                value: band.dndOn ?? false,
                onChanged: (on) => runAction(context, () => band.setDnd(on)),
              ),
            ],
          ),
        RowGroup(
          label: 'Band',
          children: [
            KitRow(
              icon: Icons.apps_rounded,
              title: 'Apps',
              subtitle: 'Order, hide, install and remove',
              chevron: true,
              onTap: connected
                  ? () => push(context, BandAppsScreen(band: band))
                  : null,
            ),
            KitRow(
              icon: Icons.tune_rounded,
              title: 'Band settings',
              subtitle: 'Sleep tracking, weather, raise to wake',
              chevron: true,
              onTap: () => push(context, BandSettingsScreen(band: band)),
            ),
            KitRow(
              icon: Icons.system_update_alt_rounded,
              title: 'Software update',
              value: band.info?.firmware,
              chevron: true,
              onTap: () => push(context, FirmwareScreen(band: band)),
            ),
            KitRow(
              icon: Icons.info_outline_rounded,
              title: 'About this band',
              chevron: true,
              onTap: () => push(context, DeviceInfoScreen(band: band)),
            ),
          ],
        ),
        RowGroup(
          label: 'App',
          children: [
            KitRow(
              icon: Icons.palette_outlined,
              title: 'Appearance',
              value: band.appearance.accent.label,
              chevron: true,
              onTap: () =>
                  push(context, AppearanceScreen(look: band.appearance)),
            ),
            KitRow(
              icon: Icons.person_outline_rounded,
              title: 'Profile & goals',
              chevron: true,
              onTap: () => push(context, ProfileScreen(band: band)),
            ),
            KitRow(
              icon: Icons.straighten_rounded,
              title: 'Units',
              value: band.units.label,
              chevron: true,
              onTap: () => chooseUnits(context, band),
            ),
            ToggleRow(
              icon: Icons.schedule_rounded,
              title: '24-hour time',
              value: band.use24Hour,
              onChanged: (on) =>
                  runAction(context, () => band.setUse24Hour(on)),
            ),
          ],
        ),
        RowGroup(
          label: 'Phone',
          children: [
            const _NotificationAccessRow(),
            const KitRow(
              icon: Icons.music_note_outlined,
              title: 'Music controls',
              subtitle: 'The band controls what’s playing',
            ),
            KitRow(
              icon: Icons.account_circle_outlined,
              title: 'Xiaomi account',
              value: band.account.signedIn ? 'Signed in' : 'Not signed in',
              chevron: true,
              onTap: () => push(context, XiaomiAccountScreen(band: band)),
            ),
          ],
        ),
        RowGroup(
          label: 'Privacy & data',
          children: [
            KitRow(
              icon: Icons.shield_outlined,
              title: 'App permissions',
              subtitle: 'What OpenWear can access, and why',
              chevron: true,
              onTap: () => push(context, PermissionsScreen(band: band)),
            ),
            KitRow(
              icon: Icons.download_rounded,
              title: 'Export data',
              subtitle: 'Heart rate, activity and sleep as a ZIP, optionally encrypted',
              chevron: true,
              onTap: () => _export(context),
            ),
          ],
        ),
        RowGroup(
          label: 'Help',
          children: [
            KitRow(
              icon: Icons.devices_other_rounded,
              title: 'Supported devices',
              subtitle: 'Which Xiaomi bands and watches work with OpenWear',
              chevron: true,
              onTap: () => push(
                context,
                SupportedDevicesScreen(current: band.wearModel),
              ),
            ),
            KitRow(
              icon: Icons.terminal_rounded,
              title: 'Live log',
              subtitle: 'Everything the band and app exchange',
              chevron: true,
              onTap: () => push(context, LogScreen(log: band.log)),
            ),
            KitRow(
              icon: Icons.link_off_rounded,
              title: 'Forget this band',
              tone: RowTone.danger,
              onTap: () => _forget(context),
            ),
          ],
        ),
        const SizedBox(height: Space.xl),
        const Center(child: OpenWearLogo(size: 44)),
        const SizedBox(height: Space.s),
        Center(
          child: Eyebrow('OpenWear · open-source companion', color: p.faint),
        ),
        const SizedBox(height: Space.xs),
        // The installed version, e.g. "OpenWear 1.0.0".
        Center(
          child: FutureBuilder<Map<String, String>>(
            future: _appInfo,
            builder: (context, snap) =>
                Eyebrow(snap.data?['app'] ?? '', color: p.faint),
          ),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context) async {
    final choice = await showExportSheet(context);
    if (choice == null || !context.mounted) return;
    await _save(context, choice.password);
  }

  Future<void> _save(BuildContext context, String? password) =>
      runAction(context, () async {
        final where = await band.exportData(password: password);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Saved to $where')));
      }, failure: 'Couldn’t export the data');

  Future<void> _forget(BuildContext context) async {
    final ok = await confirmSheet(
      context,
      title: 'Forget this band?',
      message:
          'OpenWear deletes the saved key. You will need to pair the band '
          'again to use it.',
      action: 'Forget band',
    );
    if (ok && context.mounted) await runAction(context, band.forget);
  }
}

/// The paired band with its state and the connect/disconnect action.
class _DevicePanel extends StatelessWidget {
  const _DevicePanel({required this.band});
  final BandService band;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final error = band.error;
    final connecting = band.state == BandState.connecting;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 44,
                child: BandPreview(
                  model: BandModel.forName(
                    band.name,
                    modelId: band.info?.model,
                  ),
                  data: screenData(band),
                  height: 72,
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      band.name.isEmpty ? 'Band' : band.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.bodyStrong,
                    ),
                    const SizedBox(height: 2),
                    Text(band.address, style: T.unit.copyWith(color: p.muted)),
                  ],
                ),
              ),
              bandStatus(context, band),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: Space.m),
            Text(error, style: T.small.copyWith(color: p.danger)),
          ],
          const SizedBox(height: Space.l),
          band.connected
              ? ActionButton(
                  label: 'Disconnect',
                  kind: ButtonKind.secondary,
                  onPressed: () => runAction(context, band.disconnect),
                )
              : ActionButton(
                  label: 'Connect',
                  icon: Icons.link_rounded,
                  busy: connecting,
                  onPressed: () => runAction(context, band.connect),
                ),
        ],
      ),
    );
  }
}

class _NotificationAccessRow extends StatefulWidget {
  const _NotificationAccessRow();
  @override
  State<_NotificationAccessRow> createState() => _NotificationAccessRowState();
}

class _NotificationAccessRowState extends State<_NotificationAccessRow>
    with WidgetsBindingObserver {
  bool? _granted;

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

  /// Re-checks when returning from Android's settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  void _check() {
    notificationAccessGranted().then(
      (g) => mounted ? setState(() => _granted = g) : null,
      onError: (Object _) => null,
    );
  }

  @override
  Widget build(BuildContext context) => KitRow(
    icon: Icons.mark_chat_unread_outlined,
    title: 'Notifications',
    subtitle: 'Mirror phone notifications on the band',
    value: _granted == true ? 'On' : 'Off',
    chevron: true,
    onTap: openNotificationAccessSettings,
  );
}
