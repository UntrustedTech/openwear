/// Asks how to protect a data export before it is saved to Downloads.
library;

import 'package:flutter/material.dart';
import 'package:openwear/services/data_export.dart';
import 'package:openwear/ui/kit/kit.dart';

/// The user's choice: a password (encrypted ZIP), none (plain ZIP), or
/// null when the sheet was dismissed.
typedef ExportChoice = ({String? password});

Future<ExportChoice?> showExportSheet(BuildContext context) =>
    showModalBottomSheet<ExportChoice>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (c) => Padding(
        // Keep the field above the keyboard.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
        child: const _ExportSheet(),
      ),
    );

class _ExportSheet extends StatefulWidget {
  const _ExportSheet();

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  final _password = TextEditingController();
  final _again = TextEditingController();
  bool _protect = true;
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  void _save() {
    if (!_protect) {
      Navigator.pop(context, (password: null));
      return;
    }
    final pw = _password.text;
    final error = pw.length < exportPasswordMinLength
        ? 'Use at least $exportPasswordMinLength characters.'
        : pw != _again.text
        ? 'The passwords don’t match.'
        : null;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, (password: pw));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
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
            Text('Export data', style: T.heading.copyWith(color: p.text)),
            const SizedBox(height: Space.s),
            Text(
              'The ZIP goes to Download/$exportFolder, where other apps '
              'with file access can read it. A password encrypts it with '
              'AES-256; 7-Zip, WinRAR and most file managers open it.',
              style: T.small.copyWith(color: p.muted),
            ),
            const SizedBox(height: Space.l),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _protect,
              onChanged: (v) => setState(() {
                _protect = v;
                _error = null;
              }),
              title: Text('Protect with a password', style: T.bodyStrong),
            ),
            AnimatedSize(
              duration: reduceMotion ? Duration.zero : Motion.base,
              curve: Motion.ease,
              alignment: Alignment.topCenter,
              child: _protect ? _fields(p) : const SizedBox(width: 1),
            ),
            const SizedBox(height: Space.l),
            ActionButton(
              label: _protect ? 'Encrypt and save' : 'Save without password',
              onPressed: _save,
            ),
            const SizedBox(height: Space.s),
            ActionButton(
              label: 'Cancel',
              kind: ButtonKind.secondary,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fields(Palette p) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: Space.s),
      TextField(
        controller: _password,
        obscureText: _hidden,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: 'Password',
          suffixIcon: IconButton(
            tooltip: _hidden ? 'Show password' : 'Hide password',
            icon: Icon(
              _hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            ),
            onPressed: () => setState(() => _hidden = !_hidden),
          ),
        ),
      ),
      const SizedBox(height: Space.m),
      TextField(
        controller: _again,
        obscureText: _hidden,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(labelText: 'Repeat password'),
        onSubmitted: (_) => _save(),
      ),
      if (_error case final e?) ...[
        const SizedBox(height: Space.s),
        Text(e, style: T.small.copyWith(color: p.danger)),
      ],
      const SizedBox(height: Space.s),
      Text(
        'OpenWear doesn’t keep this password. Without it the export can’t be '
        'opened.',
        style: T.small.copyWith(color: p.faint),
      ),
    ],
  );
}
