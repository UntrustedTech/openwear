import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openwear/protocol/device.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/ui/common.dart';
import 'package:openwear/ui/kit/kit.dart';

/// Everything the band reports about itself.
class DeviceInfoScreen extends StatelessWidget {
  const DeviceInfoScreen({super.key, required this.band});
  final BandService band;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: band,
    builder: (context, _) {
      final i = band.info;
      return SubPage(
        title: 'About this band',
        children: [
          if (!band.connected && i == null)
            ConnectPrompt(band: band, what: 'read the band’s details'),
          RowGroup(
            label: 'Band',
            note: 'Tap a row to copy it.',
            children: [
              for (final (title, value) in deviceInfoRows(
                name: band.name,
                address: band.address,
                battery: band.battery,
                info: i,
                faces: band.faces.length,
                activeFace: band.activeFace == null
                    ? null
                    : band.faceName(band.activeFace!),
              ))
                KitRow(
                  title: title,
                  value: value,
                  onTap: () => _copy(context, title, value),
                ),
            ],
          ),
          if (band.connected)
            RowGroup(
              children: [
                KitRow(
                  icon: Icons.refresh_rounded,
                  title: 'Read again from the band',
                  onTap: () => runAction(context, () async {
                    await band.refreshInfo();
                    await band.refreshBattery();
                  }),
                ),
              ],
            ),
        ],
      );
    },
  );

  Future<void> _copy(BuildContext context, String title, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$title copied')));
  }
}

/// The rows shown on the About screen, as (title, value).
List<(String, String)> deviceInfoRows({
  required String name,
  required String address,
  required int? battery,
  required BandInfo? info,
  required int faces,
  required String? activeFace,
}) {
  const unknown = 'Not read yet';
  String or(String? v) => v == null || v.isEmpty ? unknown : v;
  return [
    ('Name', or(name)),
    ('Model', or(info?.model)),
    if (info != null && info.product.isNotEmpty) ('Product', info.product),
    ('Firmware version', or(info?.firmware)),
    if (info?.channel case final c?) ('Update channel', '$c'),
    ('Serial number', or(info?.serial)),
    ('Bluetooth address', or(address)),
    ('Battery', battery == null ? unknown : '$battery%'),
    ('Watch faces', '$faces'),
    if (activeFace != null) ('Current face', activeFace),
    if (info != null)
      for (final e in info.extra.entries) ('Other (field ${e.key})', e.value),
  ];
}
