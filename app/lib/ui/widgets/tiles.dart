/// Compact metric tiles laid out two per row.
library;

import 'package:flutter/material.dart';
import 'package:openwear/ui/kit/kit.dart';

/// One metric: label with its colour tick, a readout and a caption.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.color,
    required this.value,
    this.unit,
    this.caption,
    this.grouped = false,
    this.onTap,
  });

  final String label;
  final Color color;
  final int? value;
  final String? unit;
  final String? caption;
  final bool grouped;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final caption = this.caption;
    return Panel(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MetricLabel(label, color: color),
          const SizedBox(height: Space.l),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Readout(
              value: value,
              unit: unit,
              size: 30,
              grouped: grouped,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: Space.xs),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.small.copyWith(color: p.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// Children two per row, each row as tall as its tallest tile.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < children.length; i += 2) ...[
        if (i > 0) const SizedBox(height: Space.m),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[i]),
              const SizedBox(width: Space.m),
              Expanded(
                child: i + 1 < children.length
                    ? children[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}
