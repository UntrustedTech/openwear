import 'package:flutter/material.dart';
import 'package:openwear/services/appearance.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/ui/common.dart';
import 'package:openwear/ui/kit/kit.dart';
import 'package:openwear/ui/screens/heart_rate_screen.dart';
import 'package:openwear/ui/screens/sleep_screen.dart';
import 'package:openwear/ui/widgets/band_preview.dart';
import 'package:openwear/ui/widgets/gauges.dart';
import 'package:openwear/ui/widgets/hr_chart.dart';
import 'package:openwear/ui/widgets/tiles.dart';

/// The day at a glance: the band, today's goals, vitals and weather.
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key, required this.band});
  final BandService band;

  Future<void> _refresh() async {
    await Future.wait([band.refreshToday(), band.refreshBattery()]);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final t = band.today;
    final look = band.appearance;
    final showVitals =
        look.shows(TodayCard.heart) ||
        look.shows(TodayCard.sleep) ||
        look.shows(TodayCard.vitals);
    return TabPage(
      title: greeting(now),
      eyebrow: shortDate(now),
      trailing: bandStatus(context, band),
      onRefresh: band.connected ? _refresh : null,
      children: [
        if (look.shows(TodayCard.band)) _BandPanel(band: band),
        if (!band.connected) ...[
          const SizedBox(height: Space.m),
          ConnectPrompt(band: band),
        ],
        if (look.shows(TodayCard.goals)) ...[
          SectionLabel(
            'Today',
            trailing: band.refreshingToday
                ? const SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                : null,
          ),
          _GoalsPanel(band: band),
        ],
        if (showVitals) const SectionLabel('Vitals'),
        if (look.shows(TodayCard.heart)) ...[
          _HeartPanel(band: band),
          const SizedBox(height: Space.m),
        ],
        if (look.shows(TodayCard.sleep)) ...[
          SleepPanel(band: band),
          const SizedBox(height: Space.m),
        ],
        if (look.shows(TodayCard.vitals))
          TileGrid(
            children: [
              MetricTile(
                label: 'Resting',
                color: Metric.heart,
                value: t?.restingHeartRate,
                unit: 'bpm',
                caption: 'Resting heart rate',
              ),
              MetricTile(
                label: 'SpO₂',
                color: Metric.oxygen,
                value: t?.averageSpo2,
                unit: '%',
                caption: 'Blood oxygen, average',
              ),
              MetricTile(
                label: 'Stress',
                color: Metric.stress,
                value: t?.averageStress,
                caption: 'Average, 0–100',
              ),
              MetricTile(
                label: 'Energy',
                color: Metric.energy,
                value: t?.totalCalories,
                unit: 'kcal',
                grouped: true,
                caption: 'Active + resting',
              ),
            ],
          ),
        if (look.shows(TodayCard.weather) &&
            band.phone.weather.latest != null) ...[
          const SectionLabel('Weather'),
          _WeatherPanel(band: band),
        ],
      ],
    );
  }
}

class _BandPanel extends StatelessWidget {
  const _BandPanel({required this.band});
  final BandService band;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final battery = band.battery;
    final face = band.activeFace;
    final error = band.error;
    return Panel(
      padding: const EdgeInsets.fromLTRB(Space.s, Space.l, Space.l, Space.l),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: BandPreview(
              model: BandModel.forName(band.name, modelId: band.info?.model),
              data: screenData(band),
              height: 176,
            ),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('Your band'),
                const SizedBox(height: Space.xs),
                Text(
                  band.name.isEmpty ? 'Band' : band.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.heading,
                ),
                const SizedBox(height: Space.l),
                const Eyebrow('Battery'),
                const SizedBox(height: Space.s),
                Row(
                  children: [
                    BatteryCells(
                      percent: battery ?? 0,
                      ok: p.ok,
                      low: p.danger,
                      track: p.raised,
                      width: 80,
                    ),
                    const SizedBox(width: Space.m),
                    Readout(value: battery, unit: '%', size: 20),
                  ],
                ),
                if (face != null) ...[
                  const SizedBox(height: Space.l),
                  const Eyebrow('Face'),
                  const SizedBox(height: Space.xs),
                  // Cross-fades when the face changes.
                  AnimatedSwitcher(
                    duration: motionFor(Motion.slow),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, ?current],
                    ),
                    child: Text(
                      band.faceName(face),
                      key: ValueKey(face.id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.bodyStrong,
                    ),
                  ),
                ],
                AnimatedSize(
                  duration: motionFor(Motion.base),
                  curve: Motion.ease,
                  alignment: Alignment.topLeft,
                  child: error == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: Space.m),
                          child: Text(
                            error,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: T.small.copyWith(color: p.danger),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalsPanel extends StatelessWidget {
  const _GoalsPanel({required this.band});
  final BandService band;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = band.today;
    final goals = band.profile;
    final steps = t?.steps;
    final updated = band.todayUpdatedAt;
    return Panel(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        children: [
          TickDial(
            progress: steps == null ? null : steps / goals.stepGoal,
            color: p.tone(Metric.steps),
            track: p.raised,
            size: 232,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Eyebrow('Steps'),
                const SizedBox(height: Space.s),
                AnimatedNumber(
                  value: steps,
                  grouped: true,
                  style: T
                      .numeral(48)
                      .copyWith(color: steps == null ? p.faint : p.text),
                ),
                const SizedBox(height: Space.s),
                Text(
                  'GOAL ${groupThousands(goals.stepGoal)}',
                  style: T.unit.copyWith(color: p.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.l),
          _GoalBar(
            label: 'Move',
            color: Metric.energy,
            value: t?.activeCalories,
            goal: goals.calorieGoal,
            unit: 'kcal',
          ),
          const SizedBox(height: Space.l),
          _GoalBar(
            label: 'Stand',
            color: Metric.stand,
            value: t?.standingHours,
            goal: goals.standGoal,
            unit: 'h',
          ),
          const SizedBox(height: Space.l),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              t == null
                  ? band.connected
                        ? 'Waiting for today’s totals from the band…'
                        : 'Connect to see today’s activity.'
                  : 'Updated ${relativeTime(updated ?? DateTime.now()).toLowerCase()}'
                        ' · pull to refresh',
              style: T.small.copyWith(color: p.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalBar extends StatelessWidget {
  const _GoalBar({
    required this.label,
    required this.color,
    required this.value,
    required this.goal,
    required this.unit,
  });

  final String label;
  final Color color;
  final int? value;
  final int goal;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final v = value;
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: MetricLabel(label, color: color)),
            AnimatedNumber(
              value: v,
              grouped: true,
              style: T
                  .numeral(20)
                  .copyWith(color: v == null ? p.faint : p.text),
            ),
            Text(
              ' / ${groupThousands(goal)} ${unit.toUpperCase()}',
              style: T.unit.copyWith(color: p.muted),
            ),
          ],
        ),
        const SizedBox(height: Space.s),
        SegmentBar(
          progress: v == null ? null : v / goal,
          color: color,
          track: p.raised,
        ),
      ],
    );
  }
}

class _HeartPanel extends StatelessWidget {
  const _HeartPanel({required this.band});
  final BandService band;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final today = recentSamples(band.hrHistory, const Duration(hours: 24));
    final stats = heartRateStats(today);
    final live = band.heartRate;
    final value = live != null && live > 0
        ? live
        : today.isEmpty
        ? null
        : today.last.$2;
    return Panel(
      onTap: () => push(context, HeartRateScreen(band: band)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MetricLabel(
            live != null ? 'Heart rate · live' : 'Heart rate',
            color: Metric.heart,
            trailing: today.isEmpty ? null : relativeTime(today.last.$1),
          ),
          const SizedBox(height: Space.l),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Readout(value: value, unit: 'bpm', size: 44),
              const SizedBox(width: Space.s),
              // Beats along with the live reading; still otherwise.
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Heartbeat(
                  bpm: live != null && live > 0 ? live : null,
                  color: Metric.heart,
                  size: 18,
                ),
              ),
              const Spacer(),
              if (stats != null)
                Text(
                  '${stats.$1}–${stats.$3}\nAVG ${stats.$2}',
                  textAlign: TextAlign.right,
                  style: T.unit.copyWith(color: p.muted, height: 1.5),
                )
              else
                Icon(Icons.arrow_forward_rounded, color: p.faint, size: 20),
            ],
          ),
          if (today.isNotEmpty) ...[
            const SizedBox(height: Space.l),
            HeartRateChart(
              samples: today,
              window: fittedWindow(today),
              height: 72,
            ),
          ] else ...[
            const SizedBox(height: Space.s),
            Text(
              'Tap to take a live reading.',
              style: T.small.copyWith(color: p.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeatherPanel extends StatelessWidget {
  const _WeatherPanel({required this.band});
  final BandService band;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final w = band.phone.weather.latest;
    if (w == null) return const SizedBox.shrink();
    final u = band.units;
    final sent = band.phone.weatherSentAt;
    final today = w.daily.isEmpty ? null : w.daily.first;
    return Panel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MetricLabel(
                  w.place.name,
                  color: Metric.weather,
                  trailing: sent == null ? 'Not sent' : relativeTime(sent),
                ),
                const SizedBox(height: Space.l),
                Readout(
                  value: u.temperature(w.current.temperature),
                  unit: u.temperatureSymbol,
                  size: 40,
                ),
              ],
            ),
          ),
          if (today != null) ...[
            const SizedBox(width: Space.l),
            Text(
              'H ${u.temperature(today.high)}°\nL ${u.temperature(today.low)}°',
              textAlign: TextAlign.right,
              style: T.unit.copyWith(color: p.muted, height: 1.6),
            ),
          ],
        ],
      ),
    );
  }
}
