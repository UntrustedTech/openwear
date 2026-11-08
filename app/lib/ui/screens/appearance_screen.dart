import 'package:flutter/material.dart';
import 'package:openwear/services/appearance.dart';
import 'package:openwear/ui/kit/kit.dart';

/// Theme, accent colour, pure black, motion and Today cards.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key, required this.look});
  final Appearance look;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: look,
    builder: (context, _) => SubPage(
      title: 'Appearance',
      children: [
        const SectionLabel('Theme'),
        _ModePicker(look: look),
        const SectionLabel('Accent'),
        _AccentPicker(look: look),
        const SizedBox(height: Space.l),
        RowGroup(
          note:
              'Pure black turns dark surfaces fully black, which looks '
              'sharper and saves battery on OLED screens. Reduce motion '
              'shows pages without entrance animations.',
          children: [
            ToggleRow(
              icon: Icons.contrast_rounded,
              title: 'Pure black in dark mode',
              value: look.pureBlack,
              onChanged: look.setPureBlack,
            ),
            ToggleRow(
              icon: Icons.motion_photos_off_outlined,
              title: 'Reduce motion',
              value: look.reduceMotion,
              onChanged: look.setReduceMotion,
            ),
          ],
        ),
        RowGroup(
          label: 'Today tab',
          note: 'Choose which cards the Today tab shows.',
          children: [
            for (final c in TodayCard.values)
              ToggleRow(
                title: c.label,
                value: look.shows(c),
                onChanged: (on) => look.setShown(c, on),
              ),
          ],
        ),
      ],
    ),
  );
}

class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.look});
  final Appearance look;

  @override
  Widget build(BuildContext context) => SegmentedButton<ThemeMode>(
    showSelectedIcon: false,
    segments: const [
      ButtonSegment(
        value: ThemeMode.system,
        label: Text('Auto'),
        icon: Icon(Icons.brightness_auto_outlined),
      ),
      ButtonSegment(
        value: ThemeMode.light,
        label: Text('Light'),
        icon: Icon(Icons.light_mode_outlined),
      ),
      ButtonSegment(
        value: ThemeMode.dark,
        label: Text('Dark'),
        icon: Icon(Icons.dark_mode_outlined),
      ),
    ],
    selected: {look.mode},
    onSelectionChanged: (s) => look.setMode(s.single),
  );
}

class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.look});
  final Appearance look;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Panel(
      child: Wrap(
        spacing: Space.l,
        runSpacing: Space.l,
        children: [
          for (final a in Accent.values)
            Semantics(
              button: true,
              selected: a == look.accent,
              label: a.label,
              child: GestureDetector(
                onTap: () => look.setAccent(a),
                child: SizedBox(
                  width: 64,
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: Motion.quick,
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: p.dark ? a.dark : a.light,
                          border: Border.all(
                            color: a == look.accent ? p.text : p.line,
                            width: a == look.accent ? 3 : 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        a.label,
                        style: T.small.copyWith(
                          color: a == look.accent ? p.text : p.muted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
