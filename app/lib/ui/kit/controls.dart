/// Buttons and the segmented choice.
library;

import 'package:flutter/material.dart';
import 'package:openwear/ui/kit/basics.dart';
import 'package:openwear/ui/theme.dart';

enum ButtonKind { primary, secondary, quiet }

/// Full-width action button. Primary is the accent fill; there should be
/// at most one per screen.
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ButtonKind.primary,
    this.icon,
    this.busy = false,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final IconData? icon;
  final bool busy;

  /// Overrides the primary fill (e.g. heart red on the heart-rate screen).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = onPressed != null && !busy;
    final (bg, fg, border) = switch (kind) {
      ButtonKind.primary => (color ?? p.accent, p.onAccent, null),
      ButtonKind.secondary => (p.surface, p.text, p.line),
      ButtonKind.quiet => (Colors.transparent, p.accent, null),
    };
    final icon = this.icon;
    return Pressable(
      onTap: enabled ? onPressed : null,
      child: AnimatedContainer(
        duration: Motion.base,
        height: 52,
        decoration: BoxDecoration(
          color: enabled ? bg : p.raised,
          borderRadius: BorderRadius.circular(Radii.control),
          border: border == null ? null : Border.all(color: border),
        ),
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: Motion.quick,
          child: busy
              ? SizedBox(
                  key: const ValueKey('busy'),
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Row(
                  key: ValueKey(label),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: enabled ? fg : p.faint),
                      const SizedBox(width: Space.s),
                    ],
                    Text(
                      label,
                      style: T.bodyStrong.copyWith(
                        color: enabled ? fg : p.faint,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Two or more mutually exclusive options in a track; the selected one
/// slides.
class Segmented<V> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(V, String)> options;
  final V value;
  final ValueChanged<V>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final index = options.indexWhere((o) => o.$1 == value);
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.raised,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth / options.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: Motion.base,
                curve: Motion.ease,
                left: w * index.clamp(0, options.length - 1),
                top: 0,
                bottom: 0,
                width: w,
                child: Container(
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(Radii.control - 3),
                    border: Border.all(color: p.line),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final (v, label) in options)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onChanged == null
                            ? null
                            : () => onChanged?.call(v),
                        child: Center(
                          child: Text(
                            label,
                            style: T.bodyStrong.copyWith(
                              fontSize: 14,
                              color: v == value ? p.text : p.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
