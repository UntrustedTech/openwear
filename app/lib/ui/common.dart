import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/ui/kit/kit.dart';
import 'package:openwear/ui/widgets/band_preview.dart';

/// Runs a band action; a failure is shown in a dialog.
Future<void> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String failure = 'Couldn’t complete that',
}) async {
  try {
    await action();
  } on Exception catch (e) {
    if (!context.mounted) return;
    await HapticFeedback.heavyImpact();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(failure),
        content: Text('$e'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

BandScreenData screenData(BandService band) {
  final note = band.lastNotification;
  return BandScreenData(
    connected: band.connected,
    battery: band.battery,
    heartRate: band.heartRate ?? _latestHr(band),
    faceName: switch (band.activeFace) {
      final f? => band.faceName(f),
      null => null,
    },
    notificationApp: note?.app,
    notificationTitle: note?.title,
    notificationTime: note?.time,
    screenshot: band.facePreviews.images[band.activeFace?.id],
  );
}

int? _latestHr(BandService band) =>
    band.hrHistory.isEmpty ? null : band.hrHistory[band.hrHistory.lastKey()];

/// Connection state as a chip.
Widget bandStatus(BuildContext context, BandService band) {
  final p = Palette.of(context);
  return switch (band.state) {
    BandState.connected => StatusChip(label: 'Linked', color: p.ok, live: true),
    BandState.connecting => StatusChip(
      label: 'Linking',
      color: Metric.weather,
      busy: true,
    ),
    _ => StatusChip(label: 'Offline', color: p.faint),
  };
}

/// Panel asking to connect, shown where the band is needed.
class ConnectPrompt extends StatelessWidget {
  const ConnectPrompt({super.key, required this.band, this.what = ''});
  final BandService band;
  final String what;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Panel(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.bluetooth_disabled_rounded, size: 28, color: p.muted),
          const SizedBox(height: Space.m),
          Text(
            what.isEmpty ? 'Band offline' : 'Connect to $what',
            style: T.heading,
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Keep the band nearby with Bluetooth on.',
            style: T.small.copyWith(color: p.muted),
          ),
          const SizedBox(height: Space.l),
          ActionButton(
            label: 'Connect',
            icon: Icons.link_rounded,
            busy: band.state == BandState.connecting,
            onPressed: () => runAction(context, band.connect),
          ),
        ],
      ),
    );
  }
}

String relativeTime(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 60) return 'Now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  if (d.inHours < 24) return '$hh:$mm';
  return '${t.day}/${t.month}';
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Fri 31 Oct"
String shortDate(DateTime t) =>
    '${_days[t.weekday - 1]} ${t.day} ${_months[t.month - 1].substring(0, 3)}';

/// "Friday, October 31"
String longDate(DateTime t) =>
    '${_weekdays[t.weekday - 1]}, ${_months[t.month - 1]} ${t.day}';

/// "Every 10 Seconds", "Every Minute", …
String syncEveryLabel(Duration d) {
  if (d.inSeconds < 60) return 'Every ${d.inSeconds} Seconds';
  if (d.inMinutes == 1) return 'Every Minute';
  return 'Every ${d.inMinutes} Minutes';
}
