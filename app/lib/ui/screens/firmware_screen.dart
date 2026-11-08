import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:openwear/cloud/xiaomi_cloud.dart' show compareFirmware;
import 'package:openwear/services/band_service.dart';
import 'package:openwear/services/firmware_update.dart';
import 'package:openwear/ui/common.dart';
import 'package:openwear/ui/kit/kit.dart';

/// Checks Xiaomi's servers for newer band firmware, keeps the last package
/// on the phone, and sends it (or any package file) to the band.
class FirmwareScreen extends StatelessWidget {
  const FirmwareScreen({super.key, required this.band});
  final BandService band;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: band,
    builder: (context, _) {
      final p = Palette.of(context);
      final fw = band.firmware;
      final info = band.info;
      final release = fw.release;
      final saved = fw.saved;
      final current = info?.firmware;
      final checkedNow =
          fw.checkedFirmware != null && fw.checkedFirmware == current;
      final canSend = band.connected && !fw.busy;
      return SubPage(
        title: 'Software update',
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MetricLabel('Band firmware', color: p.accent),
                const SizedBox(height: Space.s),
                Text(current ?? '—', style: T.title),
                const SizedBox(height: Space.xs),
                Text(
                  _status(fw, checkedNow, connected: band.connected),
                  style: T.small.copyWith(color: p.muted),
                ),
                if (fw.busy || fw.step == FirmwareStep.sent) ...[
                  const SizedBox(height: Space.m),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fw.step == FirmwareStep.checking
                          ? null
                          : fw.progress,
                      minHeight: 6,
                    ),
                  ),
                ],
                if (fw.error != null) ...[
                  const SizedBox(height: Space.m),
                  Text(fw.error!, style: T.small.copyWith(color: p.danger)),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.l),
          if (release != null && fw.step != FirmwareStep.sent)
            ActionButton(
              label: fw.releaseDownloaded
                  ? 'Install ${release.version}'
                  : 'Download and install ${release.version}',
              icon: Icons.system_update_alt_rounded,
              busy: fw.busy && fw.step != FirmwareStep.checking,
              onPressed: canSend && info != null
                  ? () => _confirm(
                      context,
                      'Install ${release.version}?',
                      () => fw.install(info.model),
                    )
                  : null,
            )
          else
            ActionButton(
              label: 'Check for updates',
              icon: Icons.refresh_rounded,
              kind: ButtonKind.secondary,
              busy: fw.step == FirmwareStep.checking,
              onPressed: info != null && !fw.busy
                  ? () => runAction(
                      context,
                      () => fw.check(info.model, info.firmware),
                    )
                  : null,
            ),
          if (release != null && release.changeLog.isNotEmpty) ...[
            const SectionLabel('What’s new'),
            Panel(child: Text(release.changeLog, style: T.body)),
          ],
          RowGroup(
            label: 'On this phone',
            note: saved?.publicPath != null
                ? 'A copy is in ${saved!.publicPath}. Only the latest '
                      'package is kept.'
                : 'The latest package is kept here and in '
                      'Download/$firmwareDownloadFolder after it downloads.',
            children: [
              KitRow(
                icon: Icons.inventory_2_outlined,
                title: saved == null
                    ? 'No package saved yet'
                    : 'Firmware ${saved.version}',
                subtitle: saved == null
                    ? null
                    : 'Send it again to repair or restore the band',
                onTap: saved != null && canSend
                    ? () => _confirm(
                        context,
                        'Send ${saved.version} to the band?',
                        fw.sendSaved,
                      )
                    : null,
              ),
              KitRow(
                icon: Icons.file_open_outlined,
                title: 'Install from a file',
                subtitle: 'Any package, for example an older version',
                onTap: canSend ? () => _pickFile(context, current) : null,
              ),
            ],
          ),
          const SizedBox(height: Space.l),
          Text(
            'Updates come straight from Xiaomi’s servers, the same ones Mi '
            'Fitness uses, and need your Xiaomi sign-in. Each package is '
            'downloaded and checked before anything is sent. Keep the band '
            'charged and near the phone; it restarts by itself when the '
            'install is done.',
            style: T.small.copyWith(color: p.muted),
          ),
        ],
      );
    },
  );

  String _status(
    FirmwareUpdate fw,
    bool checkedNow, {
    required bool connected,
  }) {
    final r = fw.release;
    return switch (fw.step) {
      FirmwareStep.checking => 'Checking with Xiaomi…',
      FirmwareStep.downloading =>
        'Downloading ${r?.version} · ${(fw.progress * 100).round()}%',
      FirmwareStep.sending =>
        'Sending ${fw.sending} to the band · '
            '${(fw.progress * 100).round()}%',
      FirmwareStep.sent =>
        'Sent. The band is installing ${fw.sending} and will restart; '
            'it reconnects afterwards.',
      FirmwareStep.idle when r != null =>
        'Version ${r.version} is available'
            '${fw.releaseDownloaded ? ' and downloaded' : ''}'
            '${r.size > 0 ? ' · ${_mb(r.size)}' : ''}.',
      FirmwareStep.idle when checkedNow => 'Your band is up to date.',
      FirmwareStep.idle when !connected => 'Connect the band to check.',
      FirmwareStep.idle => 'Not checked yet.',
    };
  }

  Future<void> _pickFile(BuildContext context, String? current) async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || !context.mounted) return;
    final file = picked.single;
    final bytes = await file.xFile.readAsBytes();
    if (!context.mounted) return;
    final version = await _askVersion(
      context,
      file.name,
      versionInFileName(file.name) ?? '',
      current,
    );
    if (version == null || !context.mounted) return;
    await runAction(context, () => band.firmware.sendFile(bytes, version));
  }

  Future<String?> _askVersion(
    BuildContext context,
    String name,
    String guess,
    String? current,
  ) {
    final field = TextEditingController(text: guess);
    return showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) {
          final v = field.text.trim();
          final valid = RegExp(r'^\d+\.\d+\.\d+$').hasMatch(v);
          final older =
              valid && current != null && compareFirmware(v, current) < 0;
          return AlertDialog(
            title: const Text('Install from a file'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: T.small),
                const SizedBox(height: Space.m),
                TextField(
                  controller: field,
                  decoration: const InputDecoration(
                    labelText: 'Firmware version (x.y.z)',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: Space.m),
                Text(
                  older
                      ? 'This is older than the band’s $current. The band '
                            'may refuse a downgrade. Only use packages made '
                            'for this band model.'
                      : 'Only use packages made for this band model. Keep '
                            'the band charged and near the phone.',
                  style: T.small,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: valid ? () => Navigator.pop(c, v) : null,
                child: const Text('Send'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    String title,
    Future<void> Function() action,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: const Text(
          'Keep the band on its charger or above 30% and close to the '
          'phone, and keep OpenWear open until sending finishes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) await runAction(context, action);
  }
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
