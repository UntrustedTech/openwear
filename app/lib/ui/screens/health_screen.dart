import 'package:flutter/material.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/services/health_connect.dart';
import 'package:openwear/ui/common.dart';
import 'package:openwear/ui/kit/kit.dart';
import 'package:openwear/ui/screens/heart_rate_screen.dart';
import 'package:openwear/ui/screens/sleep_screen.dart';
import 'package:openwear/ui/widgets/hr_chart.dart';
import 'package:openwear/ui/widgets/tiles.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key, required this.band});
  final BandService band;

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  String? _syncResult;
  bool _syncing = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    await runAction(context, () async {
      final n = await widget.band.syncHealth();
      _syncResult = 'Copied $n file${n == 1 ? '' : 's'} from the band';
    }, failure: 'Couldn’t sync');
    if (mounted) setState(() => _syncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final band = widget.band;
    final t = band.today;
    final updated = band.todayUpdatedAt;
    return TabPage(
      title: 'Health',
      eyebrow: updated == null
          ? 'Not synced yet'
          : 'Synced ${relativeTime(updated)}',
      onRefresh: band.connected ? band.refreshToday : null,
      children: [
        _HeartDay(band: band),
        const SizedBox(height: Space.m),
        SleepPanel(band: band),
        const SectionLabel('Today'),
        TileGrid(
          children: [
            MetricTile(
              label: 'Steps',
              color: Metric.steps,
              value: t?.steps,
              grouped: true,
              caption: 'Goal ${groupThousands(band.profile.stepGoal)}',
            ),
            MetricTile(
              label: 'Move',
              color: Metric.energy,
              value: t?.activeCalories,
              unit: 'kcal',
              caption: 'Active energy',
            ),
            MetricTile(
              label: 'Resting',
              color: Metric.heart,
              value: t?.restingHeartRate,
              unit: 'bpm',
              caption: 'Resting heart rate',
            ),
            MetricTile(
              label: 'Stand',
              color: Metric.stand,
              value: t?.standingHours,
              unit: 'h',
              caption: 'Hours with movement',
            ),
            MetricTile(
              label: 'SpO₂',
              color: Metric.oxygen,
              value: t?.averageSpo2,
              unit: '%',
              caption: 'Blood oxygen',
            ),
            MetricTile(
              label: 'Stress',
              color: Metric.stress,
              value: t?.averageStress,
              caption: 'Average, 0–100',
            ),
          ],
        ),
        RowGroup(
          label: 'Data',
          note:
              'Totals, all-day heart rate and sleep come from the band’s '
              'own records.',
          children: [
            KitRow(
              icon: Icons.schedule_rounded,
              title: 'Automatic sync',
              value: syncEveryLabel(band.syncEvery),
              chevron: true,
              onTap: () => _chooseSyncEvery(context, band),
            ),
            KitRow(
              icon: Icons.sync_rounded,
              title: 'Sync health data',
              subtitle:
                  _syncResult ??
                  (band.connected
                      ? 'Copy every health file from the band'
                      : 'Connect the band first'),
              trailing: _syncing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              chevron: !_syncing,
              onTap: band.connected && !_syncing ? _sync : null,
            ),
            _HealthConnectRow(sync: band.healthConnect, band: band),
          ],
        ),
      ],
    );
  }
}

/// The day's heart rate as a chart with its range.
class _HeartDay extends StatelessWidget {
  const _HeartDay({required this.band});
  final BandService band;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final day = recentSamples(band.hrHistory, const Duration(hours: 24));
    final stats = heartRateStats(day);
    return Panel(
      onTap: () => push(context, HeartRateScreen(band: band)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MetricLabel(
            'Heart rate · 24 h',
            color: Metric.heart,
            trailing: day.isEmpty ? null : relativeTime(day.last.$1),
          ),
          const SizedBox(height: Space.l),
          Readout(
            value: day.isEmpty ? null : day.last.$2,
            unit: 'bpm',
            size: 44,
          ),
          const SizedBox(height: Space.l),
          HeartRateChart(samples: day, window: fittedWindow(day)),
          const SizedBox(height: Space.m),
          Row(
            children: [
              for (final (label, v) in [
                ('Min', stats?.$1),
                ('Avg', stats?.$2),
                ('Max', stats?.$3),
              ])
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow(label, color: p.faint),
                      const SizedBox(height: Space.xs),
                      Readout(value: v, size: 20),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthConnectRow extends StatelessWidget {
  const _HealthConnectRow({required this.sync, required this.band});
  final HealthConnectSync sync;
  final BandService band;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sync,
    builder: (context, _) {
      final available = sync.state != HealthConnectState.unavailable;
      final subtitle = switch (sync.state) {
        HealthConnectState.unavailable => 'Not available on this phone',
        HealthConnectState.needsUpdate => 'Update Health Connect to use it',
        _ when sync.active && sync.missing.isNotEmpty =>
          'Not sharing ${sync.missingLabel}: allow it in Settings → App '
              'permissions',
        _ when sync.active =>
          sync.written == 0
              ? 'Sharing heart rate, steps, calories, SpO₂ and sleep'
              : 'Sharing · ${sync.written} records written',
        HealthConnectState.notGranted when sync.enabled =>
          'Access was removed, so nothing is shared. Turn on to allow again',
        _ => 'Share heart rate, steps, calories, SpO₂ and sleep',
      };
      return ToggleRow(
        icon: Icons.favorite_border_rounded,
        title: 'Health Connect',
        subtitle: sync.error ?? subtitle,
        value: sync.active,
        onChanged: available
            ? (on) => runAction(context, () => band.setHealthConnect(on))
            : null,
      );
    },
  );
}

Future<void> _chooseSyncEvery(BuildContext context, BandService band) async {
  final chosen = await showOptionSheet<Duration>(
    context,
    title: 'Automatic sync',
    message:
        'How often OpenWear reads activity and heart rate from the band '
        'while connected. Shorter intervals use more battery.',
    selected: band.syncEvery,
    options: [
      for (final d in BandService.syncChoices)
        SheetOption(d, syncEveryLabel(d)),
    ],
  );
  if (chosen != null) await band.setSyncEvery(chosen);
}
