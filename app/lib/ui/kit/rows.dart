/// Grouped rows for settings-style lists.
library;

import 'package:flutter/material.dart';
import 'package:openwear/ui/kit/basics.dart';
import 'package:openwear/ui/kit/page.dart';
import 'package:openwear/ui/theme.dart';

/// Rows in one panel, divided by inset hairlines, with an optional label
/// above and a note below.
class RowGroup extends StatelessWidget {
  const RowGroup({super.key, required this.children, this.label, this.note});
  final List<Widget> children;
  final String? label;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final label = this.label;
    final note = this.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null)
          SectionLabel(label)
        else
          const SizedBox(height: Space.l),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: Space.l, color: p.line),
                children[i],
              ],
            ],
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xs, Space.s, Space.xs, 0),
            child: Text(note, style: T.small.copyWith(color: p.muted)),
          ),
      ],
    );
  }
}

enum RowTone { normal, action, danger }

/// One row: icon, title and subtitle, then a value, a trailing control or
/// a chevron.
class KitRow extends StatelessWidget {
  const KitRow({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.tone = RowTone.normal,
    this.subtitleLines = 3,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;

  /// Lines the subtitle may use before it is cut; null shows all of it.
  final int? subtitleLines;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final RowTone tone;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = onTap != null || trailing != null;
    final titleColor = switch (tone) {
      RowTone.normal => p.text,
      RowTone.action => p.accent,
      RowTone.danger => p.danger,
    };
    final icon = this.icon;
    final subtitle = this.subtitle;
    final value = this.value;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.l,
          vertical: Space.m,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 20,
                color: tone == RowTone.normal ? p.muted : titleColor,
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: T.body.copyWith(
                      color: enabled || tone == RowTone.normal
                          ? titleColor
                          : p.faint,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        maxLines: subtitleLines,
                        overflow: subtitleLines == null
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: T.small.copyWith(color: p.muted),
                      ),
                    ),
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: Space.m),
              Text(value.toUpperCase(), style: T.unit.copyWith(color: p.muted)),
            ],
            if (trailing case final t?) ...[const SizedBox(width: Space.m), t],
            if (chevron) ...[
              const SizedBox(width: Space.xs),
              Icon(Icons.chevron_right_rounded, size: 20, color: p.faint),
            ],
          ],
        ),
      ),
    );
    final tap = onTap;
    return tap == null ? row : Pressable(onTap: tap, child: row);
  }
}

/// A row with a switch.
class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.subtitle,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => KitRow(
    title: title,
    icon: icon,
    subtitle: subtitle,
    onTap: onChanged == null ? null : () => onChanged?.call(!value),
    trailing: Switch(value: value, onChanged: onChanged),
  );
}
