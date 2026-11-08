import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openwear/platform/android_bridge.dart';
import 'package:flutter/services.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/ui/kit/kit.dart';
import 'package:openwear/ui/screens/faces_screen.dart';
import 'package:openwear/ui/screens/health_screen.dart';
import 'package:openwear/ui/screens/settings_screen.dart';
import 'package:openwear/ui/screens/summary_screen.dart';

/// Four tabs under a flat bar; a tab is built the first time it is shown
/// and then kept alive so its scroll position survives switching.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.band});
  final BandService band;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _Tab {
  const _Tab(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

const _tabs = [
  _Tab('Today', Icons.radio_button_unchecked_rounded, Icons.adjust_rounded),
  _Tab('Health', Icons.monitor_heart_outlined, Icons.monitor_heart_rounded),
  _Tab('Faces', Icons.watch_outlined, Icons.watch_rounded),
  _Tab('Settings', Icons.tune_rounded, Icons.tune_rounded),
];

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  final _built = <int>{0};

  void _select(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index = i;
      _built.add(i);
    });
  }

  Widget _page(int i) => switch (i) {
    0 => SummaryScreen(band: widget.band),
    1 => HealthScreen(band: widget.band),
    2 => FacesScreen(band: widget.band),
    _ => SettingsScreen(band: widget.band),
  };

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    // Back never closes the app: closing would end the band connection,
    // which lives with this screen. On Today it goes to the background.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index != 0) {
          _select(0);
        } else {
          unawaited(moveAppToBackground());
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: p.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          body: IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                _built.contains(i)
                    ? _TabSlot(
                        band: widget.band,
                        active: i == _index,
                        builder: () => _page(i),
                      )
                    : const SizedBox.shrink(),
            ],
          ),
          bottomNavigationBar: _TabBar(index: _index, onSelect: _select),
        ),
      ),
    );
  }
}

/// One tab's page. Only the visible tab rebuilds when the band reports
/// something (a heart-rate sample arrives every few seconds); hidden tabs
/// catch up when they are shown again, and their animations pause.
class _TabSlot extends StatefulWidget {
  const _TabSlot({
    required this.band,
    required this.active,
    required this.builder,
  });
  final BandService band;
  final bool active;
  final Widget Function() builder;

  @override
  State<_TabSlot> createState() => _TabSlotState();
}

class _TabSlotState extends State<_TabSlot> {
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    widget.band.addListener(_onBand);
  }

  @override
  void didUpdateWidget(_TabSlot old) {
    super.didUpdateWidget(old);
    if (old.band != widget.band) {
      old.band.removeListener(_onBand);
      widget.band.addListener(_onBand);
    }
  }

  @override
  void dispose() {
    widget.band.removeListener(_onBand);
    super.dispose();
  }

  void _onBand() {
    if (widget.active) {
      setState(() {});
    } else {
      _stale = true;
    }
  }

  Widget? _page;

  @override
  Widget build(BuildContext context) {
    // Inactive and nothing new: reuse the last page so nothing rebuilds.
    if (widget.active || _stale || _page == null) {
      _page = widget.builder();
      _stale = false;
    }
    return TickerMode(
      enabled: widget.active,
      child: ShowOnActivate(active: widget.active, child: _page!),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.background,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: Semantics(
                    selected: i == index,
                    button: true,
                    label: _tabs[i].label,
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelect(i),
                      child: _TabItem(tab: _tabs[i], active: i == index),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.tab, required this.active});
  final _Tab tab;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = active ? p.text : p.faint;
    return Column(
      children: [
        // The active tab is marked by a short accent bar on the top edge.
        AnimatedContainer(
          duration: Motion.base,
          curve: Motion.ease,
          height: 2,
          width: active ? 24 : 0,
          color: p.accent,
        ),
        const Spacer(),
        PopOnActivate(
          active: active,
          child: Icon(
            active ? tab.activeIcon : tab.icon,
            size: 22,
            color: color,
          ),
        ),
        const SizedBox(height: Space.xs),
        AnimatedDefaultTextStyle(
          duration: Motion.quick,
          style: T.label.copyWith(fontSize: 10, color: color),
          child: Text(tab.label.toUpperCase()),
        ),
        const Spacer(),
      ],
    );
  }
}
