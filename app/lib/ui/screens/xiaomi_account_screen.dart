import 'package:flutter/material.dart';
import 'package:openwear/cloud/xiaomi_cloud.dart' as cloud;
import 'package:openwear/services/band_service.dart';
import 'package:openwear/ui/common.dart';
import 'package:openwear/ui/kit/kit.dart';

/// Sign in to Xiaomi (kept encrypted) to get official face pictures.
class XiaomiAccountScreen extends StatefulWidget {
  const XiaomiAccountScreen({super.key, required this.band});
  final BandService band;

  @override
  State<XiaomiAccountScreen> createState() => _XiaomiAccountScreenState();
}

class _XiaomiAccountScreenState extends State<XiaomiAccountScreen> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  late String _region = widget.band.account.region;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<String> _askCode(String channel) async {
    final code = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Verification code'),
        content: TextField(
          controller: code,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Code Xiaomi sent to your $channel',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, code.text),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    code.dispose();
    return result ?? '';
  }

  Future<void> _signIn() async {
    if (_user.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your Xiaomi account and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final band = widget.band;
    cloud.cloudTrace = (line) => band.log.app('Xiaomi: $line');
    try {
      await band.account.signIn(_user.text, _password.text, _region, _askCode);
      _password.clear();
      if (band.connected) await band.fetchStorePictures(all: true);
    } on cloud.CloudException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      _password.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.band,
    builder: (context, _) {
      final account = widget.band.account;
      return SubPage(
        title: 'Xiaomi account',
        children: account.signedIn ? _signedIn(context) : _signInForm(context),
      );
    },
  );

  List<Widget> _signedIn(BuildContext context) {
    final band = widget.band;
    final account = band.account;
    return [
      RowGroup(
        label: 'Signed in',
        note:
            'OpenWear keeps your Xiaomi sign-in encrypted on this phone and '
            'uses it only to get pictures of the faces on your band. Your '
            'password is not stored.',
        children: [
          KitRow(
            title: 'Server region',
            value: cloud.cloudRegions[account.region] ?? account.region,
          ),
          KitRow(
            icon: Icons.image_outlined,
            title: band.fetchingStorePictures
                ? 'Getting face pictures…'
                : 'Get face pictures',
            subtitle: band.connected
                ? 'Official pictures of the faces on your band'
                : 'Connect the band first',
            onTap: band.connected && !band.fetchingStorePictures
                ? () => runAction(
                    context,
                    () => band.fetchStorePictures(all: true),
                    failure: 'Couldn’t get the pictures',
                  )
                : null,
          ),
        ],
      ),
      RowGroup(
        children: [
          KitRow(
            icon: Icons.logout_rounded,
            title: 'Sign out of Xiaomi',
            subtitle: 'Deletes the saved sign-in from this phone',
            tone: RowTone.danger,
            onTap: () => runAction(context, account.signOut),
          ),
        ],
      ),
    ];
  }

  List<Widget> _signInForm(BuildContext context) {
    final p = Palette.of(context);
    return [
      Text(
        'Sign in to get the official pictures of the faces that came with '
        'your band. Your password goes only to Xiaomi and is never stored; '
        'the sign-in is kept encrypted on this phone until you sign out.',
        style: T.small.copyWith(color: p.muted),
      ),
      const SizedBox(height: Space.m),
      AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _user,
              decoration: const InputDecoration(
                labelText: 'Email, phone or Xiaomi ID',
              ),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.username],
            ),
            const SizedBox(height: Space.m),
            TextField(
              controller: _password,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.password],
            ),
          ],
        ),
      ),
      const SizedBox(height: Space.m),
      DropdownButtonFormField<String>(
        initialValue: _region,
        decoration: const InputDecoration(labelText: 'Server region'),
        dropdownColor: p.surface,
        borderRadius: BorderRadius.circular(Radii.control),
        items: [
          for (final e in cloud.cloudRegions.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (r) => setState(() => _region = r ?? 'us'),
      ),
      const SizedBox(height: Space.m),
      ActionButton(
        label: 'Sign in',
        busy: _busy,
        onPressed: _busy ? null : _signIn,
      ),
      if (_error case final e?) ...[
        const SizedBox(height: Space.s),
        Text(e, style: T.small.copyWith(color: p.danger)),
      ],
    ];
  }
}
