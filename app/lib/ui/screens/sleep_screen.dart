import 'package:flutter/material.dart';
import 'package:openwear/protocol/sleep.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/ui/common.dart';
import 'package:openwear/ui/kit/kit.dart';
import 'package:openwear/ui/widgets/hr_chart.dart';
import 'package:openwear/ui/widgets/sleep_chart.dart';
import 'package:openwear/ui/widgets/tiles.dart';

/// "7 h 20 min".
String sleepLength(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

String _range(SleepSession s) => '${clockTime(s.start)}–${clockTime(s.end)}';

/// Hours and minutes as two readouts.
class _AsleepReadout extends StatelessWidget {
  const _AsleepReadout({required this.asleep});
  final Duration? asleep;

  @override
  Widget build(BuildContext context) {
    final a = asleep;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Readout(value: a?.inHours, unit: 'h', size: 44),
        const SizedBox(width: Space.s),
        Readout(
          value: a == null ? null : a.inMinutes % 60,
          unit: 'min',
          size: 44,
        ),
      ],
    );
  }
}

/// Last night at a glance; opens [SleepScreen].
class SleepPanel extends StatelessWidget {
  const SleepPanel({super.key, required this.band});
  final BandService band;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final night = band.lastNight;
    return Panel(
      onTap: () => push(context, SleepScreen(band: band)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MetricLabel(
            'Sleep · last night',
            color: Metric.sleep,
            trailing: night == null ? null : _range(night),
          ),
          const SizedBox(height: Space.l),
          _AsleepReadout(asleep: night?.asleep),
          const SizedBox(height: Space.l),
          if (night != null) ...[
            SleepChart(session: night, height: 64),
            if (night.hasStages) ...[
              const SizedBox(height: Space.m),
              StageBar(totals: night.stageTotals),
            ],
          ] else
            Text(
              band.sleepLog.sessions.isEmpty
                  ? 'Wear the band to bed. Sleep shows up here after you '
                        'wake and the band syncs.'
                  : 'No sleep in the past day. Tap to see earlier nights.',
              style: T.small.copyWith(color: p.muted),
            ),
        ],
      ),
    );
  }
}

/// One night (or nap) in detail, with the past week to pick from.
class SleepScreen extends StatefulWidget {
  const SleepScreen({super.key, required this.band});
  final BandService band;

  @override
  State<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends State<SleepScreen> {
  String? _selected;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: subPageBar(context, 'Sleep'),
    body: ListenableBuilder(
      listenable: widget.band,
      builder: (context, _) => _body(context),
    ),
  );

  Widget _body(BuildContext context) {
    final band = widget.band;
    final p = Palette.of(context);
    final all = band.sleepLog.sessions.reversed.toList();
    final chosen =
        all.where((s) => s.id.hex == _selected).firstOrNull ??
        band.lastNight ??
        all.firstOrNull;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.xl,
        Space.gutter,
        Space.xxl,
      ),
      children: [
        if (chosen == null)
          Panel(
            child: Text(
              'No sleep from the band yet. Wear it to bed; the night is '
              'copied over the next time the band syncs after you wake.',
              style: T.body.copyWith(color: p.muted),
            ),
          )
        else
          ..._details(context, chosen),
        if (all.length > 1) ...[
          const SectionLabel('Past week'),
          RowGroup(
            children: [
              for (final s in all)
                KitRow(
                  icon: s.kind == SleepKind.nap
                      ? Icons.wb_sunny_outlined
                      : Icons.bedtime_outlined,
                  title: '${shortDate(s.end)} · ${_range(s)}',
                  subtitle: s.kind == SleepKind.nap ? 'Nap' : null,
                  value: sleepLength(s.asleep),
                  chevron: s != chosen,
                  onTap: () => setState(() => _selected = s.id.hex),
                ),
            ],
          ),
        ],
      ],
    );
  }

  List<Widget> _details(BuildContext context, SleepSession s) {
    final p = Palette.of(context);
    final totals = s.stageTotals;
    final whole = totals.values.fold(Duration.zero, (a, b) => a + b);
    final tiles = [
      if (s.score != null)
        MetricTile(
          label: 'Score',
          color: Metric.sleep,
          value: s.score,
          caption: 'Sleep score, 0–100',
        ),
      if (s.efficiency != null)
        MetricTile(
          label: 'Efficiency',
          color: Metric.sleep,
          value: s.efficiency,
          unit: '%',
          caption: 'Time in bed asleep',
        ),
      if (s.averageHeartRate != null)
        MetricTile(
          label: 'Heart rate',
          color: Metric.heart,
          value: s.averageHeartRate,
          unit: 'bpm',
          caption: 'Average asleep',
        ),
      if (s.lowestHeartRate != null)
        MetricTile(
          label: 'Lowest',
          color: Metric.heart,
          value: s.lowestHeartRate,
          unit: 'bpm',
          caption: 'Lowest heart rate',
        ),
      if (s.averageSpo2 != null)
        MetricTile(
          label: 'SpO₂',
          color: Metric.oxygen,
          value: s.averageSpo2,
          unit: '%',
          caption: 'Average asleep',
        ),
      if (s.breathingQuality != null)
        MetricTile(
          label: 'Breathing',
          color: Metric.oxygen,
          value: s.breathingQuality,
          caption: 'Breathing quality',
        ),
      if (s.hrvAverage != null)
        MetricTile(
          label: 'HRV',
          color: Metric.stress,
          value: s.hrvAverage,
          unit: 'ms',
          caption: 'Average',
        ),
      if (s.awakeCount != null)
        MetricTile(
          label: 'Woke up',
          color: StageColors.awake,
          value: s.awakeCount,
          unit: '×',
          caption: 'Times awake',
        ),
    ];
    return [
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MetricLabel(
              s.kind == SleepKind.nap ? 'Nap' : longDate(s.end),
              color: Metric.sleep,
              trailing: s.finished ? null : 'Still recording',
            ),
            const SizedBox(height: Space.l),
            _AsleepReadout(asleep: s.asleep),
            const SizedBox(height: Space.xs),
            Text(
              'Asleep ${_range(s)}',
              style: T.small.copyWith(color: p.muted),
            ),
            const SizedBox(height: Space.l),
            SleepChart(session: s, height: 140),
          ],
        ),
      ),
      if (totals.isNotEmpty && whole > Duration.zero) ...[
        const SectionLabel('Stages'),
        Panel(
          child: Column(
            children: [
              StageBar(totals: totals),
              const SizedBox(height: Space.m),
              for (final stage in [
                SleepStage.deep,
                SleepStage.light,
                SleepStage.rem,
                SleepStage.awake,
              ])
                if (totals[stage] != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: MetricLabel(
                            stageName(stage),
                            color: StageColors.of(stage),
                          ),
                        ),
                        Text(sleepLength(totals[stage]!), style: T.bodyStrong),
                        SizedBox(
                          width: 48,
                          child: Text(
                            '${(totals[stage]!.inSeconds * 100 / whole.inSeconds).round()}%',
                            textAlign: TextAlign.right,
                            style: T.unit.copyWith(color: p.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ] else if (s.kind == SleepKind.segment) ...[
        const SizedBox(height: Space.m),
        Text(
          'Your band records this sleep without stages. Mi Fitness works out '
          'deep, light and REM sleep on the phone with a closed Xiaomi '
          'model, which OpenWear can’t include.',
          style: T.small.copyWith(color: p.muted),
        ),
      ],
      if (tiles.isNotEmpty) ...[
        const SectionLabel('Overnight'),
        TileGrid(children: tiles),
      ],
      if (s.heartRate.length > 1) ...[
        const SectionLabel('Heart rate asleep'),
        Panel(
          child: HeartRateChart(
            samples: s.heartRate,
            window: s.heartRate.last.$1.difference(s.heartRate.first.$1),
            now: s.heartRate.last.$1,
          ),
        ),
      ],
      const SectionLabel('Timeline'),
      RowGroup(
        children: [
          if (s.wentToBed != null)
            KitRow(
              icon: Icons.bed_outlined,
              title: 'Went to bed',
              value: clockTime(s.wentToBed!),
            ),
          KitRow(
            icon: Icons.bedtime_outlined,
            title: 'Fell asleep',
            value: clockTime(s.start),
          ),
          KitRow(
            icon: Icons.wb_twilight_rounded,
            title: 'Woke up',
            value: clockTime(s.end),
          ),
          if (s.leftBed != null)
            KitRow(
              icon: Icons.directions_walk_rounded,
              title: 'Got up',
              value: clockTime(s.leftBed!),
            ),
        ],
      ),
    ];
  }
}
