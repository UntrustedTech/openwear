import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openwear/services/band_log.dart';
import 'package:openwear/ui/kit/kit.dart';

/// Live view of everything the band and the app exchange.
class LogView extends StatefulWidget {
  const LogView({super.key, required this.log});
  final BandLog log;

  @override
  State<LogView> createState() => _LogViewState();
}

enum _Filter { all, fromBand, toBand, app }

class _LogViewState extends State<LogView> {
  _Filter _filter = _Filter.all;
  bool _hideLiveStats = true;
  final _expanded = <LogEntry>{};

  bool _visible(LogEntry e) {
    if (_hideLiveStats && e.title.startsWith('8/47 ')) return false;
    return switch (_filter) {
      _Filter.all => true,
      _Filter.fromBand => e.direction == LogDirection.fromBand,
      _Filter.toBand => e.direction == LogDirection.toBand,
      _Filter.app =>
        e.direction == LogDirection.app || e.direction == LogDirection.warning,
    };
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.log.export()));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Log copied')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final shown = log.entries.where(_visible).toList();
        return Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  for (final (f, label) in const [
                    (_Filter.all, 'All'),
                    (_Filter.fromBand, 'Band → phone'),
                    (_Filter.toBand, 'Phone → band'),
                    (_Filter.app, 'App'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                  FilterChip(
                    label: const Text('Live stats'),
                    selected: !_hideLiveStats,
                    onSelected: (on) => setState(() => _hideLiveStats = !on),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    log.paused
                        ? 'PAUSED · ${shown.length} SHOWN'
                        : '● LIVE · ${shown.length} SHOWN',
                    style: T.label.copyWith(
                      color: log.paused
                          ? Palette.of(context).muted
                          : Palette.of(context).ok,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(log.paused ? Icons.play_arrow : Icons.pause),
                  tooltip: log.paused ? 'Resume' : 'Pause',
                  onPressed: log.togglePause,
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy log',
                  onPressed: _copy,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: 'Clear',
                  onPressed: log.clear,
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: shown.isEmpty
                  ? const Center(
                      child: Text('Nothing yet — connect to the band.'),
                    )
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) => _LogTile(
                        entry: shown[i],
                        expanded: _expanded.contains(shown[i]),
                        onTap: () => setState(() {
                          if (!_expanded.remove(shown[i])) {
                            _expanded.add(shown[i]);
                          }
                        }),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({
    required this.entry,
    required this.expanded,
    required this.onTap,
  });
  final LogEntry entry;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (icon, color) = switch (entry.direction) {
      LogDirection.fromBand => (Icons.south_west_rounded, p.tone(Metric.stand)),
      LogDirection.toBand => (Icons.north_east_rounded, p.accent),
      LogDirection.app => (Icons.circle_outlined, p.muted),
      LogDirection.warning => (Icons.warning_amber_rounded, p.danger),
    };
    final t = entry.time;
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
    final mono = T.unit.copyWith(fontSize: 11, color: p.text);
    return InkWell(
      onTap: entry.detail == null ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(stamp, style: mono.copyWith(color: p.faint)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: entry.title,
                          style: T.small.copyWith(
                            color: color,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (entry.summary != null && entry.summary!.isNotEmpty)
                          TextSpan(
                            text: '  ${entry.summary}',
                            style: T.small.copyWith(color: p.muted),
                          ),
                      ],
                    ),
                  ),
                ),
                if (entry.detail != null)
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: p.faint,
                  ),
              ],
            ),
            if (expanded)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4, left: 22),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(Radii.small),
                  border: Border.all(color: p.line),
                ),
                child: SelectableText(entry.detail!, style: mono),
              ),
          ],
        ),
      ),
    );
  }
}

/// The live log as a pushed page.
class LogScreen extends StatelessWidget {
  const LogScreen({super.key, required this.log});
  final BandLog log;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: subPageBar(context, 'Live log'),
    body: LogView(log: log),
  );
}
