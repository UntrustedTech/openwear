import 'package:flutter/material.dart';
import 'package:openwear/protocol/models.dart';
import 'package:openwear/ui/kit/kit.dart';

/// Which Xiaomi models OpenWear can connect to, and what works on each.
class SupportedDevicesScreen extends StatelessWidget {
  const SupportedDevicesScreen({super.key, this.current});

  /// The connected model, marked in the list.
  final WearModel? current;

  @override
  Widget build(BuildContext context) {
    final tested = [
      for (final m in wearModels)
        if (m.verified) m,
    ];
    final untested = [
      for (final m in wearModels)
        if (!m.verified && m.reachable) m,
    ];
    final ble = [
      for (final m in wearModels)
        if (!m.reachable) m,
    ];
    return SubPage(
      title: 'Supported devices',
      children: [
        RowGroup(label: 'Tested', children: [for (final m in tested) _row(m)]),
        RowGroup(
          label: 'Should work, not tested yet',
          note:
              'These use Bluetooth Classic like the Smart Band 9, including '
              'older models that speak the first version of the link '
              'protocol. If you have one, the live log shows how far it gets.',
          children: [for (final m in untested) _row(m)],
        ),
        RowGroup(
          label: 'Not supported yet',
          note:
              'These connect over Bluetooth Low Energy only, which OpenWear '
              'does not speak yet.',
          children: [for (final m in ble) _row(m)],
        ),
      ],
    );
  }

  Widget _row(WearModel m) => KitRow(
    icon: switch (m.shape) {
      BandScreenShape.round => Icons.watch_outlined,
      _ => Icons.watch_rounded,
    },
    title: m == current ? '${m.name} (this band)' : m.name,
    subtitle: _details(m),
    subtitleLines: null,
  );

  String _details(WearModel m) => [
    if (m.width != null) 'Screen ${m.screenLabel}',
    if (m.fitsOpenWearFaces) 'OpenWear faces',
    if (m.luaFaces) 'Lua faces',
    switch (m.link) {
      BandLink.classic => 'Bluetooth Classic',
      BandLink.both => 'Bluetooth Classic or LE',
      BandLink.bleOnly => 'Bluetooth LE',
    },
  ].join(' · ');
}
