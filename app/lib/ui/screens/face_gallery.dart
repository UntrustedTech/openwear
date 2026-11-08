/// OpenWear's own faces: browse, preview and install.
library;

import 'package:flutter/material.dart';
import 'package:openwear/faces/catalog.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/ui/common.dart';
import 'package:openwear/ui/kit/kit.dart';

const _kindLabels = {
  FaceKind.modern: 'Modern',
  FaceKind.animated: 'Animated',
  FaceKind.info: 'Info',
  FaceKind.retro: 'Retro',
  FaceKind.sport: 'Sport',
};

/// A grid of the 20 OpenWear faces with a filter.
class FaceGallery extends StatefulWidget {
  const FaceGallery({super.key, required this.band});
  final BandService band;

  @override
  State<FaceGallery> createState() => _FaceGalleryState();
}

class _FaceGalleryState extends State<FaceGallery> {
  FaceKind? _filter;
  bool _onWatchOnly = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final installed = {for (final f in widget.band.faces) f.id};
    final model = widget.band.wearModel;
    final fitting = [
      for (final f in customFaces)
        if (faceFits(f, model)) f,
    ];
    final hidden = customFaces.length - fitting.length;
    final faces = [
      for (final f in fitting)
        if (_onWatchOnly
            ? installed.contains(f.id)
            : (_filter == null || f.kinds.contains(_filter)))
          f,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _Chip(
                label: 'All',
                selected: _filter == null && !_onWatchOnly,
                onTap: () => setState(() {
                  _filter = null;
                  _onWatchOnly = false;
                }),
              ),
              _Chip(
                label:
                    'On watch (${customFaces.where((f) => installed.contains(f.id)).length})',
                selected: _onWatchOnly,
                onTap: () => setState(() {
                  _filter = null;
                  _onWatchOnly = true;
                }),
              ),
              for (final MapEntry(:key, :value) in _kindLabels.entries)
                _Chip(
                  label: value,
                  selected: _filter == key && !_onWatchOnly,
                  onTap: () => setState(() {
                    _filter = key;
                    _onWatchOnly = false;
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.m),
        if (hidden > 0 && model != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.m),
            child: Text(
              fitting.isEmpty
                  ? 'OpenWear’s faces are drawn for a 192×490 screen, so none '
                        'fit the ${model.name} (${model.screenLabel}) yet.'
                  : '$hidden faces are drawn for a 192×490 screen and are '
                        'hidden for the ${model.name} (${model.screenLabel}).',
              style: T.small.copyWith(color: p.muted),
            ),
          ),
        if (_onWatchOnly && faces.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.m),
            child: Text(
              widget.band.connected
                  ? 'None of OpenWear’s faces are on your watch yet.'
                  : 'Connect the band to see which faces are on it.',
              style: T.small.copyWith(color: p.muted),
            ),
          ),
        ListenableBuilder(
          listenable: widget.band.customPreviews,
          builder: (context, _) => GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Space.l,
            crossAxisSpacing: Space.m,
            childAspectRatio: 0.36,
            children: [
              for (final f in faces) _GalleryTile(face: f, band: widget.band),
            ],
          ),
        ),
        const SizedBox(height: Space.s),
        Text(
          'Designed by OpenWear and drawn on your phone, with day and month '
          'names in your language. Installing faces is experimental.',
          style: T.small.copyWith(color: p.muted),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: Space.s),
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.base,
          constraints: const BoxConstraints(minHeight: minTarget),
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? p.text : p.surface,
            borderRadius: BorderRadius.circular(minTarget / 2),
            border: Border.all(color: selected ? p.text : p.line),
          ),
          child: Text(
            label.toUpperCase(),
            style: T.label.copyWith(color: selected ? p.background : p.muted),
          ),
        ),
      ),
    );
  }
}

/// The face's picture inside a band-shaped frame.
class CustomFacePicture extends StatelessWidget {
  const CustomFacePicture({
    super.key,
    required this.face,
    required this.band,
    this.width,
  });
  final CustomFace face;
  final BandService band;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final png = band.customPreviews.of(face);
    return AspectRatio(
      aspectRatio: 192 / 490,
      child: Container(
        width: width,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF2A2A2A), width: 2),
        ),
        child: AnimatedSwitcher(
          duration: Motion.base,
          child: png == null
              ? Center(
                  key: const ValueKey('wait'),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: face.accent,
                    ),
                  ),
                )
              : Image.memory(
                  png,
                  key: const ValueKey('png'),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
        ),
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({required this.face, required this.band});
  final CustomFace face;
  final BandService band;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final match = band.faces.where((f) => f.id == face.id).firstOrNull;
    final onBand = match != null;
    final inUse = match?.active ?? false;
    return Pressable(
      onTap: () => showCustomFaceSheet(context, band, face),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Center(
                  child: CustomFacePicture(face: face, band: band),
                ),
                if (onBand)
                  Positioned(top: 4, child: _InstalledBadge(inUse: inUse)),
              ],
            ),
          ),
          const SizedBox(height: Space.s),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: face.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  face.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.small.copyWith(
                    color: p.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          Text(
            onBand
                ? (inUse ? 'IN USE ON WATCH' : 'ON WATCH')
                : face.kinds
                      .map((k) => _kindLabels[k])
                      .join(' · ')
                      .toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.label.copyWith(
              color: onBand ? p.accent : p.faint,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

/// "On watch" / "In use" marker over a gallery picture.
class _InstalledBadge extends StatelessWidget {
  const _InstalledBadge({required this.inUse});
  final bool inUse;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: inUse ? p.accent : p.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: p.accent),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              inUse ? Icons.check_circle_rounded : Icons.watch_rounded,
              size: 10,
              color: inUse ? p.background : p.accent,
            ),
            const SizedBox(width: 3),
            Text(
              inUse ? 'IN USE' : 'ON WATCH',
              style: T.label.copyWith(
                fontSize: 8,
                color: inUse ? p.background : p.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showCustomFaceSheet(
  BuildContext context,
  BandService band,
  CustomFace face,
) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (c) => ListenableBuilder(
    listenable: Listenable.merge([band, band.customPreviews]),
    builder: (c, _) => _FaceSheet(band: band, face: face),
  ),
);

class _FaceSheet extends StatelessWidget {
  const _FaceSheet({required this.band, required this.face});
  final BandService band;
  final CustomFace face;

  Future<void> _install(BuildContext context) => runAction(
    context,
    () => band.installCustomFace(face),
    failure: 'Couldn’t install ${face.name}',
  );

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final installing = band.installingFace == face.id;
    final busy = band.installingFace != null;
    final onBand = band.faces.any((f) => f.id == face.id);
    final percent = (band.installProgress * 100).round();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.l,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 112,
                  child: CustomFacePicture(face: face, band: band),
                ),
                const SizedBox(width: Space.l),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow(
                        face.kinds.map((k) => _kindLabels[k]).join(' · '),
                        color: face.accent,
                      ),
                      const SizedBox(height: Space.xs),
                      Text(face.name, style: T.title.copyWith(color: p.text)),
                      const SizedBox(height: Space.s),
                      Text(face.blurb, style: T.body.copyWith(color: p.muted)),
                      const SizedBox(height: Space.l),
                      Text(
                        'Previewed at 10:09 with sample data.',
                        style: T.small.copyWith(color: p.faint),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.xl),
            if (!band.connected)
              Text(
                'Connect your band to install this face.',
                style: T.small.copyWith(color: p.muted),
              )
            else if (onBand)
              ActionButton(
                label: 'Use this face',
                icon: Icons.check_rounded,
                onPressed: busy
                    ? null
                    : () =>
                          runAction(context, () => band.activateFace(face.id)),
              )
            else
              ActionButton(
                label: installing
                    ? percent == 0
                          ? 'Preparing…'
                          : 'Sending $percent%'
                    : 'Install on band',
                icon: Icons.download_rounded,
                busy: installing,
                onPressed: busy ? null : () => _install(context),
              ),
            if (installing) ...[
              const SizedBox(height: Space.m),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: band.installProgress == 0
                      ? null
                      : band.installProgress,
                  minHeight: 3,
                  color: face.accent,
                  backgroundColor: p.raised,
                ),
              ),
            ],
            const SizedBox(height: Space.m),
            Text(
              'Experimental. Custom faces haven’t been tested on every band '
              'yet. If one doesn’t show up, remove it from the Faces list.',
              style: T.small.copyWith(color: p.faint),
            ),
          ],
        ),
      ),
    );
  }
}
