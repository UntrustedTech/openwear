/// Bottom sheets: choose one option, confirm a destructive action, or pick
/// a value on a wheel.
library;

import 'package:flutter/cupertino.dart'
    show CupertinoTheme, CupertinoThemeData, CupertinoTextThemeData;
import 'package:flutter/material.dart';
import 'package:openwear/ui/kit/basics.dart';
import 'package:openwear/ui/kit/controls.dart';
import 'package:openwear/ui/theme.dart';

class SheetOption<V> {
  const SheetOption(this.value, this.label, {this.detail});
  final V value;
  final String label;
  final String? detail;
}

/// Lets the user pick one of [options]; null when dismissed.
Future<V?> showOptionSheet<V>(
  BuildContext context, {
  required String title,
  required List<SheetOption<V>> options,
  String? message,
  V? selected,
}) => showModalBottomSheet<V>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (c) {
    final p = Palette.of(c);
    return _SheetBody(
      title: title,
      message: message,
      children: [
        for (final o in options)
          Pressable(
            onTap: () => Navigator.pop(c, o.value),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.l,
                vertical: Space.m,
              ),
              margin: const EdgeInsets.only(bottom: Space.s),
              decoration: BoxDecoration(
                color: o.value == selected ? p.raised : p.background,
                borderRadius: BorderRadius.circular(Radii.control),
                border: Border.all(
                  color: o.value == selected ? p.accent : p.line,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.label, style: T.bodyStrong),
                        if (o.detail case final d?)
                          Text(d, style: T.small.copyWith(color: p.muted)),
                      ],
                    ),
                  ),
                  if (o.value == selected)
                    Icon(Icons.check_rounded, color: p.accent, size: 20),
                ],
              ),
            ),
          ),
      ],
    );
  },
);

/// Asks before a destructive action; true when confirmed.
Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    builder: (c) {
      final p = Palette.of(c);
      return _SheetBody(
        title: title,
        message: message,
        children: [
          ActionButton(
            label: action,
            color: p.danger,
            onPressed: () => Navigator.pop(c, true),
          ),
          const SizedBox(height: Space.s),
          ActionButton(
            label: 'Cancel',
            kind: ButtonKind.secondary,
            onPressed: () => Navigator.pop(c, false),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}

/// A sheet holding a wheel picker; true when the user taps Done.
Future<bool> showWheelSheet(
  BuildContext context, {
  required String title,
  required Widget wheel,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    builder: (c) {
      final p = Palette.of(c);
      return _SheetBody(
        title: title,
        children: [
          SizedBox(
            height: 216,
            child: CupertinoTheme(
              data: CupertinoThemeData(
                brightness: p.dark ? Brightness.dark : Brightness.light,
                textTheme: CupertinoTextThemeData(
                  pickerTextStyle: T.heading.copyWith(color: p.text),
                  dateTimePickerTextStyle: T.heading.copyWith(color: p.text),
                ),
              ),
              child: wheel,
            ),
          ),
          const SizedBox(height: Space.l),
          ActionButton(label: 'Done', onPressed: () => Navigator.pop(c, true)),
        ],
      );
    },
  );
  return ok ?? false;
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.title, required this.children, this.message});
  final String title;
  final String? message;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final message = this.message;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.l,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: T.heading.copyWith(color: p.text)),
            if (message != null) ...[
              const SizedBox(height: Space.s),
              Text(message, style: T.small.copyWith(color: p.muted)),
            ],
            const SizedBox(height: Space.l),
            ...children,
          ],
        ),
      ),
    );
  }
}
