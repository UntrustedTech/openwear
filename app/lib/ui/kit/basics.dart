/// Building blocks: panels, labels, numeric readouts, press feedback and
/// entrance motion.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openwear/ui/kit/motion.dart';
import 'package:openwear/ui/theme.dart';

/// A flat surface with a hairline border. Tappable when [onTap] is set.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.l),
    this.onTap,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: borderColor ?? p.line),
      ),
      child: Padding(padding: padding, child: child),
    );
    final tap = onTap;
    return tap == null ? box : Pressable(onTap: tap, child: box);
  }
}

/// Shrinks and dims slightly while pressed; light haptic on tap.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
  });
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return Semantics(
      button: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap?.call();
              },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                _set(false);
                HapticFeedback.mediumImpact();
                widget.onLongPress?.call();
              },
        child: AnimatedScale(
          scale: _down ? 0.98 : 1,
          duration: Motion.quick,
          curve: Motion.ease,
          child: AnimatedOpacity(
            opacity: _down ? 0.8 : 1,
            duration: Motion.quick,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Small uppercase mono label, the system's signature voice.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color, this.maxLines = 1});
  final String text;
  final Color? color;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: T.label.copyWith(color: color ?? Palette.of(context).muted),
  );
}

/// A coloured tick + label heading a block of data.
class MetricLabel extends StatelessWidget {
  const MetricLabel(this.text, {super.key, required this.color, this.trailing});
  final String text;
  final Color color;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = trailing;
    return Row(
      children: [
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: Space.s),
        Expanded(child: Eyebrow(text, color: p.text)),
        if (t != null) Eyebrow(t, color: p.faint),
      ],
    );
  }
}

/// Number + unit on a shared baseline. The number counts to new values.
class Readout extends StatelessWidget {
  const Readout({
    super.key,
    required this.value,
    this.unit,
    this.size = 40,
    this.color,
    this.grouped = false,
    this.placeholder = '—',
  });

  final int? value;
  final String? unit;
  final double size;
  final Color? color;
  final bool grouped;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final u = unit;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        AnimatedNumber(
          value: value,
          grouped: grouped,
          placeholder: placeholder,
          style: T
              .numeral(size)
              .copyWith(color: value == null ? p.faint : color ?? p.text),
        ),
        if (u != null && u.isNotEmpty) ...[
          const SizedBox(width: Space.xs),
          Text(u.toUpperCase(), style: T.unit.copyWith(color: p.muted)),
        ],
      ],
    );
  }
}

/// An integer that counts smoothly to its new value.
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber({
    super.key,
    required this.value,
    required this.style,
    this.placeholder = '—',
    this.grouped = false,
  });

  final int? value;
  final TextStyle style;
  final String placeholder;

  /// Thousands separators (8,000).
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v == null) return Text(placeholder, style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: v.toDouble()),
      duration: motionFor(const Duration(milliseconds: 700)),
      curve: Motion.ease,
      builder: (context, x, _) {
        final n = x.round();
        return Text(grouped ? groupThousands(n) : '$n', style: style);
      },
    );
  }
}

String groupThousands(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// Marks when a page opened, so entrance animations play once and not
/// again when a card scrolls back into view.
class EntranceScope extends InheritedWidget {
  const EntranceScope({super.key, required this.born, required super.child});
  final DateTime born;

  /// True once the page's entrance is over (or outside any page).
  static bool settled(BuildContext context) {
    if (reduceMotion) return true;
    final s = context.getInheritedWidgetOfExactType<EntranceScope>();
    return s == null ||
        DateTime.now().difference(s.born) > Motion.entranceWindow;
  }

  @override
  bool updateShouldNotify(EntranceScope old) => old.born != born;
}

/// Fades in and rises a few pixels, after [index] × stagger.
/// Only while the page is opening; later it shows the child at once.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.slow,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Motion.ease,
  );

  Timer? _delay;

  @override
  void initState() {
    super.initState();
    if (EntranceScope.settled(context)) {
      _c.value = 1;
      return;
    }
    final delay = Motion.stagger * widget.index.clamp(0, 10);
    if (delay == Duration.zero) {
      _c.forward();
    } else {
      _delay = Timer(delay, _c.forward);
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    child: widget.child,
    builder: (context, child) => _t.value == 1
        ? child!
        : Opacity(
            opacity: _t.value,
            child: Transform.translate(
              offset: Offset(0, 12 * (1 - _t.value)),
              child: child,
            ),
          ),
  );
}

/// A dot and a mono label, e.g. "● LINKED".
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.busy = false,
    this.live = false,
  });
  final String label;
  final Color color;
  final bool busy;

  /// A slow pulse on the dot, e.g. while the band is linked.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return AnimatedContainer(
      duration: Motion.base,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: p.dark ? 0.12 : 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          busy
              ? SizedBox(
                  width: 8,
                  height: 8,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: color,
                  ),
                )
              : live
              ? PulsingDot(color: color)
              : Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
          SizedBox(width: live && !busy ? 3 : 6),
          Text(
            label.toUpperCase(),
            style: T.label.copyWith(color: p.tone(color)),
          ),
        ],
      ),
    );
  }
}

/// "Good morning" etc. for the time of day.
String greeting(DateTime t) => t.hour < 5
    ? 'Good night'
    : t.hour < 12
    ? 'Good morning'
    : t.hour < 18
    ? 'Good afternoon'
    : 'Good evening';
