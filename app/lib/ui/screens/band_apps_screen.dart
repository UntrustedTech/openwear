import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:openwear/protocol/band_apps.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/ui/common.dart';
import 'package:openwear/ui/kit/kit.dart';

String placeLabel(AppPlace p) => switch (p) {
  AppPlace.shown => 'Shown',
  AppPlace.more => 'In More',
  AppPlace.hidden => 'Hidden',
};

/// The band's app list: drag to reorder, tap to show, move to More or
/// hide; plus apps installed from .rpk packages.
class BandAppsScreen extends StatefulWidget {
  const BandAppsScreen({super.key, required this.band});
  final BandService band;

  @override
  State<BandAppsScreen> createState() => _BandAppsScreenState();
}

/// Shown apps first, then More, then hidden — the order the band uses.
List<BandApp>? _grouped(List<BandApp>? apps) => apps == null
    ? null
    : [
        for (final p in AppPlace.values)
          for (final a in apps)
            if (a.place == p) a,
      ];

class _BandAppsScreenState extends State<BandAppsScreen> {
  List<BandApp>? _draft;
  bool _dirty = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.band.apps.load().whenComplete(() {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _draft = _grouped(widget.band.apps.builtIn);
      });
    });
  }

  Future<void> _choosePlace(int i) async {
    final app = _draft![i];
    final place = await showOptionSheet<AppPlace>(
      context,
      title: app.name,
      selected: app.place,
      options: [
        const SheetOption(AppPlace.shown, 'Shown'),
        if (app.mayGoInMore && !app.alwaysShown)
          const SheetOption(AppPlace.more, 'In More'),
        if (!app.alwaysShown) const SheetOption(AppPlace.hidden, 'Hidden'),
      ],
    );
    if (place == null || place == app.place) return;
    setState(() {
      _draft![i] = app.moveTo(place);
      _draft = _grouped(_draft);
      _dirty = true;
    });
  }

  Future<void> _install() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || !mounted) return;
    final bytes = await picked.single.xFile.readAsBytes();
    if (!mounted) return;
    await runAction(
      context,
      () => widget.band.apps.install(bytes),
      failure: 'Couldn’t install the app',
    );
  }

  Future<void> _uninstall(InstalledApp app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${app.name}?'),
        content: const Text('It is deleted from the band.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await runAction(context, () => widget.band.apps.uninstall(app));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: subPageBar(
      context,
      'Band apps',
      actions: [
        if (_dirty)
          TextButton(
            onPressed: () => runAction(context, () async {
              await widget.band.apps.save(_draft!);
              if (mounted) setState(() => _dirty = false);
            }),
            child: const Text('Save'),
          ),
      ],
    ),
    body: ListenableBuilder(
      listenable: widget.band.apps,
      builder: (context, _) => _body(context),
    ),
  );

  Widget _body(BuildContext context) {
    final p = Palette.of(context);
    final draft = _draft;
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.l,
        Space.gutter,
        Space.xxl,
      ),
      header: Padding(
        padding: const EdgeInsets.only(bottom: Space.m),
        child: Text(
          draft == null
              ? 'The band did not send its app list. Connect it and try '
                    'again.'
              : 'Drag to change the order on the band. Tap an app to show '
                    'it, move it into More, or hide it. Save sends it.',
          style: T.small.copyWith(color: p.muted),
        ),
      ),
      footer: _Installed(
        band: widget.band,
        onInstall: _install,
        onUninstall: _uninstall,
      ),
      itemCount: draft?.length ?? 0,
      onReorderItem: (from, to) => setState(() {
        final app = draft!.removeAt(from);
        draft.insert(to, app);
        _dirty = true;
      }),
      itemBuilder: (context, i) {
        final app = draft![i];
        return Material(
          key: ValueKey(app.id),
          color: Colors.transparent,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              app.place == AppPlace.hidden
                  ? Icons.visibility_off_outlined
                  : app.place == AppPlace.more
                  ? Icons.folder_outlined
                  : Icons.apps_rounded,
              color: app.place == AppPlace.hidden ? p.muted : null,
            ),
            title: Text(
              app.name.isEmpty ? app.id : app.name,
              style: T.body.copyWith(
                color: app.place == AppPlace.hidden ? p.muted : null,
              ),
            ),
            subtitle: Text(
              app.alwaysShown ? 'Always shown' : placeLabel(app.place),
              style: T.small.copyWith(color: p.muted),
            ),
            trailing: ReorderableDragStartListener(
              index: i,
              child: const Icon(Icons.drag_handle_rounded),
            ),
            onTap: () => _choosePlace(i),
          ),
        );
      },
    );
  }
}

class _Installed extends StatelessWidget {
  const _Installed({
    required this.band,
    required this.onInstall,
    required this.onUninstall,
  });
  final BandService band;
  final VoidCallback onInstall;
  final void Function(InstalledApp) onUninstall;

  @override
  Widget build(BuildContext context) {
    final apps = band.apps;
    final list = apps.installed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RowGroup(
          label: 'Installed apps',
          note:
              'Apps come as .rpk packages made for this band. Only install '
              'packages you trust.',
          children: [
            if (list != null && list.isEmpty)
              const KitRow(title: 'No apps installed'),
            for (final a in list ?? const <InstalledApp>[])
              KitRow(
                icon: Icons.widgets_outlined,
                title: a.name,
                subtitle: '${a.package} · v${a.version}',
                value: 'Remove',
                onTap: () => onUninstall(a),
              ),
            KitRow(
              icon: Icons.add_rounded,
              title: apps.installing == null
                  ? 'Install app (.rpk)…'
                  : 'Installing ${apps.installing} '
                        '${(apps.progress * 100).round()}%',
              onTap: apps.installing == null ? onInstall : null,
            ),
          ],
        ),
      ],
    );
  }
}
