import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/ui/common.dart';
import 'package:openwear/ui/kit/kit.dart';

/// Screenshots taken on the band. The Band 9 cannot send a live picture of
/// its screen on request: 2/108 only collects screenshots already taken on
/// the band (Mi Fitness sends it once on connect), and answers status 1
/// when there are none.
class BandMirrorScreen extends StatefulWidget {
  const BandMirrorScreen({super.key, required this.band});
  final BandService band;

  @override
  State<BandMirrorScreen> createState() => _BandMirrorScreenState();
}

class _BandMirrorScreenState extends State<BandMirrorScreen> {
  bool _checking = false;
  String? _note;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _note = null;
    });
    try {
      await widget.band.bandScreenshot();
    } on TimeoutException {
      _note = 'No new screenshots on the band.';
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: subPageBar(context, 'Band screenshots'),
      body: ListenableBuilder(
        listenable: widget.band.facePreviews,
        builder: (context, _) {
          final png = widget.band.facePreviews.latest;
          return ListView(
            padding: const EdgeInsets.all(Space.gutter),
            children: [
              if (png != null)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: Image.memory(png, gaplessPlayback: true),
                  ),
                )
              else
                Panel(
                  child: Text(
                    'Screenshots you take on the band show up here. The band '
                    'cannot stream its screen live; it only sends pictures '
                    'taken on it.',
                    style: T.body.copyWith(color: p.muted),
                  ),
                ),
              const SizedBox(height: Space.l),
              RowGroup(
                children: [
                  KitRow(
                    icon: Icons.download_rounded,
                    title: _checking ? 'Checking…' : 'Get screenshots now',
                    subtitle: _note,
                    onTap: _checking ? null : () => runAction(context, _check),
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
