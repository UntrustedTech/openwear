import 'package:flutter/material.dart';
import 'package:openwear/protocol/sleep_settings.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/ui/common.dart';
import 'package:openwear/ui/kit/kit.dart';
import 'package:openwear/ui/screens/band_mirror_screen.dart';

/// Settings stored on the band: raise to wake, sleep tracking, weather,
/// plus a few band actions.
class BandSettingsScreen extends StatelessWidget {
  const BandSettingsScreen({super.key, required this.band});
  final BandService band;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: band,
    builder: (context, _) {
      final connected = band.connected;
      final wake = band.raiseToWake;
      return SubPage(
        title: 'Band settings',
        children: [
          if (!connected)
            Panel(
              child: Text(
                'Connect the band to change its settings.',
                style: T.body.copyWith(color: Palette.of(context).muted),
              ),
            ),
          if (connected && wake != null)
            RowGroup(
              label: 'Display',
              note: 'Raise to wake is experimental.',
              children: [
                ToggleRow(
                  icon: Icons.back_hand_outlined,
                  title: 'Raise to wake',
                  subtitle: wake.mode.name == 'scheduled'
                      ? '${wake.start}–${wake.end}'
                      : null,
                  value: wake.enabled,
                  onChanged: (on) =>
                      runAction(context, () => band.setRaiseToWake(on)),
                ),
              ],
            ),
          if (connected && band.sleepSettings != null)
            _SleepSettingsGroup(band: band, s: band.sleepSettings!),
          RowGroup(
            label: 'Weather',
            note:
                'Forecast from Open-Meteo for your approximate location. '
                'When you are signed in, Xiaomi is also asked which city '
                'that is, so the band shows its name.',
            children: [
              ToggleRow(
                icon: Icons.wb_sunny_outlined,
                title: 'Weather on band',
                value: band.weatherEnabled,
                onChanged: (on) =>
                    runAction(context, () => band.setWeather(enabled: on)),
              ),
              KitRow(
                icon: Icons.north_east_rounded,
                title: 'Send weather now',
                subtitle: _weatherStatus(),
                trailing: band.phone.weatherBusy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap:
                    connected && band.weatherEnabled && !band.phone.weatherBusy
                    ? () => band.phone.sendWeather(force: true)
                    : null,
              ),
            ],
          ),
          if (connected)
            RowGroup(
              label: 'Tools',
              children: [
                KitRow(
                  icon: Icons.update_rounded,
                  title: 'Sync time',
                  onTap: () => runAction(context, band.syncTime),
                ),
                KitRow(
                  icon: Icons.notifications_none_rounded,
                  title: 'Send test notification',
                  onTap: () => runAction(context, band.sendTestNotification),
                ),
                KitRow(
                  icon: Icons.screenshot_outlined,
                  title: 'Band screenshots',
                  subtitle: 'Pictures taken on the band',
                  chevron: true,
                  onTap: () => push(context, BandMirrorScreen(band: band)),
                ),
              ],
            ),
        ],
      );
    },
  );

  String _weatherStatus() {
    final p = band.phone;
    if (p.weatherBusy) return 'Sending…';
    final error = p.weatherError;
    if (error != null) return 'Not sent: $error';
    final at = p.weatherSentAt;
    if (at != null) return 'Last sent ${relativeTime(at).toLowerCase()}';
    return band.connected ? 'Not sent yet' : 'Connect the band first';
  }
}

/// The band's sleep-tracking switches, shown only where the band has them.
class _SleepSettingsGroup extends StatelessWidget {
  const _SleepSettingsGroup({required this.band, required this.s});
  final BandService band;
  final SleepSettings s;

  @override
  Widget build(BuildContext context) {
    void set(SleepSettings next, String what) =>
        runAction(context, () => band.setSleepSettings(next, what));
    final accurate = s.highAccuracy, breathing = s.breathingQuality;
    final rate = s.breathingRate;
    return RowGroup(
      label: 'Sleep tracking',
      note:
          'High-accuracy tracking gives more detailed sleep but uses more '
          'battery. Your sleep shows on the Summary and Health tabs.',
      children: [
        if (accurate != null)
          ToggleRow(
            icon: Icons.bedtime_outlined,
            title: 'High-accuracy sleep tracking',
            value: accurate,
            onChanged: (on) => set(
              s.withHighAccuracy(on),
              'high accuracy ${on ? 'on' : 'off'}',
            ),
          ),
        if (breathing != null)
          ToggleRow(
            icon: Icons.air_rounded,
            title: 'Sleep breathing quality',
            subtitle: 'Measures SpO₂ while you sleep',
            value: breathing,
            onChanged: (on) => set(
              s.withBreathingQuality(on),
              'breathing quality ${on ? 'on' : 'off'}',
            ),
          ),
        if (rate != null)
          ToggleRow(
            icon: Icons.monitor_heart_outlined,
            title: 'Breathing rate during sleep',
            value: rate,
            onChanged: (on) => set(
              s.withBreathingRate(on),
              'breathing rate ${on ? 'on' : 'off'}',
            ),
          ),
      ],
    );
  }
}
