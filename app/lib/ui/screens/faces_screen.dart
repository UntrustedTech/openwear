import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openwear/faces/catalog.dart';
import 'package:openwear/protocol/device.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/ui/screens/xiaomi_account_screen.dart';
import 'package:openwear/ui/common.dart';
import 'package:openwear/ui/kit/kit.dart';
import 'package:openwear/ui/screens/face_gallery.dart';
import 'package:openwear/ui/widgets/band_preview.dart';

class FacesScreen extends StatelessWidget {
  const FacesScreen({super.key, required this.band});
  final BandService band;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final model = BandModel.forName(band.name, modelId: band.info?.model);
    final current = band.activeFace;
    final count = band.faces.length;
    return TabPage(
      title: 'Faces',
      eyebrow: count == 0 ? 'Watch faces' : '$count on the band',
      onRefresh: band.connected ? band.loadFaces : null,
      children: [
        _Stage(
          child: Column(
            children: [
              BandPreview(model: model, data: screenData(band), height: 260),
              const SizedBox(height: Space.l),
              AnimatedSwitcher(
                duration: Motion.base,
                child: Column(
                  key: ValueKey(current?.id),
                  children: [
                    Eyebrow('In use', color: p.accent),
                    const SizedBox(height: Space.xs),
                    Text(
                      current == null ? 'Current face' : band.faceName(current),
                      textAlign: TextAlign.center,
                      style: T.heading,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!band.connected) ...[
          const SizedBox(height: Space.m),
          ConnectPrompt(band: band, what: 'manage faces'),
        ] else if (band.faces.isEmpty) ...[
          const SizedBox(height: Space.l),
          ActionButton(
            label: 'Load faces from band',
            icon: Icons.download_rounded,
            onPressed: () => runAction(context, band.loadFaces),
          ),
        ] else ...[
          const SectionLabel('Library'),
          SizedBox(
            height: 228,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              clipBehavior: Clip.none,
              itemCount: band.faces.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.m),
              itemBuilder: (context, i) =>
                  _FaceTile(face: band.faces[i], band: band, model: model),
            ),
          ),
          const SizedBox(height: Space.s),
          Text(
            'Tap a face to use it. Touch and hold for more.',
            style: T.small.copyWith(color: p.muted),
          ),
          const SizedBox(height: Space.xl),
          _CaptureButton(band: band),
        ],
        const SectionLabel('OpenWear originals'),
        FaceGallery(band: band),
      ],
    );
  }
}

/// Raised backdrop with a fine dot grid, like a product shot.
class _Stage extends StatelessWidget {
  const _Stage({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.card),
      child: CustomPaint(
        painter: _DotGrid(color: p.line, background: p.surface),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: Space.xl),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: p.line),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _DotGrid extends CustomPainter {
  _DotGrid({required this.color, required this.background});
  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final dot = Paint()..color = color;
    const step = 14.0;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 0.9, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGrid old) =>
      old.color != color || old.background != background;
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.band});
  final BandService band;

  String? _progress() {
    final id = band.facePreviews.capturing;
    if (id == null) return null;
    final i = band.faces.indexWhere((f) => f.id == id);
    return 'Capturing ${i + 1} of ${band.faces.length}…';
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final previews = band.facePreviews;
    final missing = band.faces.where((f) => !previews.images.containsKey(f.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ActionButton(
          label: missing.isEmpty ? 'Refresh pictures' : 'Capture pictures',
          icon: Icons.photo_camera_outlined,
          kind: ButtonKind.secondary,
          busy: previews.busy,
          onPressed: () => runAction(
            context,
            () => band.captureFacePreviews(),
            failure: 'Couldn’t capture the faces',
          ),
        ),
        const SizedBox(height: Space.s),
        ActionButton(
          label: band.account.signedIn
              ? 'Get official pictures from Xiaomi'
              : 'Sign in for official pictures',
          icon: Icons.image_outlined,
          kind: ButtonKind.quiet,
          busy: band.fetchingStorePictures,
          onPressed: band.account.signedIn
              ? () => runAction(
                  context,
                  () => band.fetchStorePictures(all: true),
                  failure: 'Couldn’t get the pictures',
                )
              : () => push(context, XiaomiAccountScreen(band: band)),
        ),
        const SizedBox(height: Space.s),
        Text(
          _progress() ??
              'The band shows each face for a moment so OpenWear can take a '
                  'picture of it, then goes back to your face.',
          style: T.small.copyWith(color: p.muted),
        ),
      ],
    );
  }
}

enum _FaceAction { use, picture, remove }

class _FaceTile extends StatelessWidget {
  const _FaceTile({
    required this.face,
    required this.band,
    required this.model,
  });
  final WatchFace face;
  final BandService band;
  final BandModel model;

  /// For OpenWear's own faces, the picture drawn on the phone.
  Uint8List? _ownPicture() {
    final own = customFaceById(face.id);
    return own == null ? null : band.customPreviews.of(own);
  }

  Future<void> _use(BuildContext context) =>
      runAction(context, () => band.activateFace(face.id));

  Future<void> _more(BuildContext context) async {
    final action = await showOptionSheet<_FaceAction>(
      context,
      title: band.faceName(face),
      message: band.faceName(face) == face.name
          ? null
          : 'Name on the band: ${face.name}',
      options: [
        if (!face.active) const SheetOption(_FaceAction.use, 'Use this face'),
        const SheetOption(_FaceAction.picture, 'Update picture'),
        if (face.removable)
          const SheetOption(_FaceAction.remove, 'Remove from band'),
      ],
    );
    if (!context.mounted) return;
    switch (action) {
      case _FaceAction.use:
        await _use(context);
      case _FaceAction.picture:
        await runAction(
          context,
          () => band.captureFacePreviews(only: [face.id]),
          failure: 'Couldn’t capture this face',
        );
      case _FaceAction.remove:
        await _remove(context);
      case null:
        break;
    }
  }

  Future<void> _remove(BuildContext context) async {
    final ok = await confirmSheet(
      context,
      title: 'Remove “${band.faceName(face)}”?',
      message:
          'It will be deleted from the band. Built-in faces may only come '
          'back after a factory reset.',
      action: 'Remove face',
    );
    if (ok && context.mounted) {
      await runAction(context, () => band.removeFace(face.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final capturing = band.facePreviews.capturing == face.id;
    return SizedBox(
      width: 108,
      child: Pressable(
        onTap: face.active || band.facePreviews.busy
            ? null
            : () => _use(context),
        onLongPress: () => _more(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: Motion.base,
              height: 156,
              width: 108,
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(Radii.card),
                border: Border.all(
                  color: face.active ? p.accent : p.line,
                  width: face.active ? 2 : 1,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  BandPreview(
                    model: model,
                    data: BandScreenData(
                      connected: true,
                      faceName: band.faceName(face),
                      battery: band.battery,
                      heartRate: band.heartRate,
                      screenshot:
                          band.facePreviews.images[face.id] ?? _ownPicture(),
                    ),
                    height: 136,
                  ),
                  if (capturing)
                    const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.s),
            Text(
              band.faceName(face),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: T.small.copyWith(color: p.text, height: 1.25),
            ),
            if (face.active) Eyebrow('In use', color: p.accent),
          ],
        ),
      ),
    );
  }
}
