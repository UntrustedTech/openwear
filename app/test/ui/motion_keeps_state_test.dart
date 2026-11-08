// Entrance wrappers must not remount their child when an animation starts
// or ends: a remount restarts the page (state, scroll, entrance animations),
// which showed as each page "refreshing" several times.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/ui/kit/kit.dart';

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

int _mounts = 0;

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _mounts++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 10, height: 10);
}

Widget _app(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

void main() {
  setUp(() => _mounts = 0);

  testWidgets('ShowOnActivate keeps its child across activation', (t) async {
    await t.pumpWidget(
      _app(const ShowOnActivate(active: true, child: _Probe())),
    );
    await t.pumpWidget(
      _app(const ShowOnActivate(active: false, child: _Probe())),
    );
    await t.pumpWidget(
      _app(const ShowOnActivate(active: true, child: _Probe())),
    );
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    expect(_mounts, 1);
  });

  testWidgets('Reveal keeps its child when the entrance ends', (t) async {
    await t.pumpWidget(
      _app(
        EntranceScope(
          born: DateTime.now(),
          child: const Reveal(child: _Probe()),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    expect(_mounts, 1);
  });
}
