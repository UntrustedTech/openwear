import 'package:flutter/material.dart';
import 'package:openwear/cloud/xiaomi_cloud.dart' show cloudRegions;
import 'package:openwear/platform/android_bridge.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/services/pairing_service.dart';
import 'package:openwear/protocol/models.dart';
import 'package:openwear/ui/kit/kit.dart';
import 'package:openwear/ui/log_screen.dart';
import 'package:openwear/ui/permissions.dart';
import 'package:openwear/ui/widgets/openwear_logo.dart';

/// First-time pairing: reset the band, Bluetooth-pair it, then bind it in the app.
class PairScreen extends StatefulWidget {
  const PairScreen({super.key, required this.band});
  final BandService band;

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  late final _pairing = PairingService(
    widget.band,
    describeNetwork: networkInfo,
  );
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _key = TextEditingController();
  String _region = 'us';
  bool _useAccount = true;
  List<BondedDevice> _devices = const [];
  BondedDevice? _selected;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _pairing.dispose();
    _user.dispose();
    _password.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final denied = await requestCompanionPermissions();
    final devices = await bondedDevices();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _selected =
          devices.where((d) => d.address == _selected?.address).firstOrNull ??
          devices
              .where(
                (d) => wearModelFor(bluetoothName: d.name)?.reachable ?? false,
              )
              .firstOrNull ??
          devices.where((d) => _looksLikeWear(d.name)).firstOrNull;
      _message = denied.isEmpty
          ? null
          : 'Some permissions were denied: ${denied.join(', ')}';
    });
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

  Future<void> _attempt(Future<void> Function() action) async {
    setState(() => _message = null);
    try {
      await action();
    } on PairingException catch (e) {
      if (mounted) setState(() => _message = e.message);
    }
  }

  Future<void> _signIn() => _attempt(() async {
    await _pairing.signIn(_user.text, _password.text, _region, _askCode);
    _password.clear();
  });

  Future<void> _pair() async {
    final device = _selected;
    if (device == null) return;
    if (!_useAccount) _pairing.signOut();
    await _attempt(() => _pairing.pair(device));
  }

  Future<void> _saveKey() async {
    final device = _selected;
    if (device == null) return;
    try {
      await widget.band.savePairing(device.address, device.name, _key.text);
    } on FormatException catch (e) {
      setState(() => _message = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final message = _message;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _pairing,
          builder: (context, _) => ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.xl,
              Space.gutter,
              Space.xxl,
            ),
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: OpenWearLogo(size: 64, animate: true),
              ),
              const SizedBox(height: Space.l),
              Eyebrow('OpenWear · setup', color: p.accent),
              const SizedBox(height: Space.s),
              Text('Add your band', style: T.title),
              const SizedBox(height: Space.s),
              Text(
                'Three steps. Your band data stays between this phone and '
                'the band.',
                style: T.body.copyWith(color: p.muted),
              ),
              const SizedBox(height: Space.xl),
              _Step(
                number: 1,
                title: 'Prepare the band',
                children: [_prepareStep(context)],
              ),
              _Step(
                number: 2,
                title: 'Choose how to pair',
                children: _accountStep(context),
              ),
              _Step(
                number: 3,
                title: 'Pair',
                last: true,
                children: _bandStep(context),
              ),
              if (message != null)
                Panel(
                  borderColor: p.danger,
                  child: Text(
                    message,
                    style: T.small.copyWith(color: p.danger),
                  ),
                ),
              const SizedBox(height: Space.l),
              _Disclosure(
                title: 'Live log',
                child: SizedBox(
                  height: 360,
                  child: LogView(log: widget.band.log),
                ),
              ),
              _Disclosure(
                title: 'Advanced: enter a key manually',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'For a band already bound by the OpenWear PC tool '
                      '(32 hex digits).',
                      style: T.small.copyWith(color: p.muted),
                    ),
                    const SizedBox(height: Space.m),
                    TextField(
                      controller: _key,
                      style: T.unit.copyWith(fontSize: 14, color: p.text),
                      decoration: const InputDecoration(labelText: 'Auth key'),
                      autocorrect: false,
                      enableSuggestions: false,
                    ),
                    const SizedBox(height: Space.m),
                    ActionButton(
                      label: 'Save band with this key',
                      kind: ButtonKind.secondary,
                      onPressed: _selected == null ? null : _saveKey,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _prepareStep(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'If the band was used with another phone or computer, reset it first '
        '(on the band: Settings → System → Reset). Then pair it with this '
        'phone in Bluetooth settings and come back.',
        style: T.small.copyWith(color: Palette.of(context).muted),
      ),
      const SizedBox(height: Space.m),
      const ActionButton(
        label: 'Open Bluetooth settings',
        icon: Icons.bluetooth_rounded,
        kind: ButtonKind.secondary,
        onPressed: openBluetoothSettings,
      ),
    ],
  );

  List<Widget> _accountStep(BuildContext context) {
    final p = Palette.of(context);
    final pairing = _pairing;
    final account = pairing.account;
    return [
      Segmented<bool>(
        options: const [(true, 'Xiaomi account'), (false, 'No account')],
        value: _useAccount,
        onChanged: pairing.busy ? null : (v) => setState(() => _useAccount = v),
      ),
      const SizedBox(height: Space.m),
      if (!_useAccount)
        Text(
          'Pairs directly with the band. Some models (including Smart Band 9) '
          'only accept account pairing; the app will tell you if yours does.',
          style: T.small.copyWith(color: p.muted),
        )
      else if (account != null)
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: p.ok, size: 20),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text('Signed in · ${account.userId}', style: T.bodyStrong),
            ),
            TextButton(
              onPressed: pairing.busy ? null : pairing.signOut,
              child: const Text('Sign out'),
            ),
          ],
        )
      else ...[
        Text(
          'Your password goes only to Xiaomi and is never stored. Xiaomi '
          'approves the band once; the sign-in is then kept encrypted on this '
          'phone for watch-face pictures (Settings › Xiaomi account to sign out).',
          style: T.small.copyWith(color: p.muted),
        ),
        const SizedBox(height: Space.m),
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
        const SizedBox(height: Space.m),
        DropdownButtonFormField<String>(
          initialValue: _region,
          decoration: const InputDecoration(labelText: 'Server region'),
          dropdownColor: p.surface,
          borderRadius: BorderRadius.circular(Radii.control),
          items: [
            for (final e in cloudRegions.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (r) => setState(() => _region = r ?? 'us'),
        ),
        const SizedBox(height: Space.m),
        ActionButton(
          label: 'Sign in',
          busy: pairing.busy,
          onPressed: pairing.busy ? null : _signIn,
        ),
        const SizedBox(height: Space.s),
        ActionButton(
          label: 'Test connection',
          icon: Icons.network_check_rounded,
          kind: ButtonKind.quiet,
          onPressed: pairing.busy ? null : () => _attempt(pairing.checkNetwork),
        ),
        if (pairing.busy || pairing.status.isNotEmpty)
          Text(pairing.status, style: T.small.copyWith(color: p.muted)),
      ],
    ];
  }

  List<Widget> _bandStep(BuildContext context) {
    final p = Palette.of(context);
    final pairing = _pairing;
    final ready =
        _selected != null &&
        !pairing.busy &&
        (!_useAccount || pairing.account != null);
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              _devices.isEmpty
                  ? 'No Bluetooth-paired devices yet.'
                  : 'Choose your band',
              style: T.small.copyWith(color: p.muted),
            ),
          ),
          IconButton(
            onPressed: _refresh,
            icon: Icon(Icons.refresh_rounded, color: p.muted),
            tooltip: 'Refresh',
          ),
        ],
      ),
      for (final d in _devices) ...[
        _DeviceOption(
          device: d,
          selected: d.address == _selected?.address,
          onTap: () => setState(() => _selected = d),
        ),
        const SizedBox(height: Space.s),
      ],
      if (pairing.waitingForTap)
        Panel(
          borderColor: p.accent,
          child: Row(
            children: [
              Icon(Icons.touch_app_outlined, size: 32, color: p.accent),
              const SizedBox(width: Space.l),
              Expanded(
                child: Text(
                  'Tap ✓ on your band now to approve this phone.',
                  style: T.bodyStrong,
                ),
              ),
            ],
          ),
        ),
      if (pairing.busy || pairing.status.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s),
          child: Row(
            children: [
              if (pairing.busy)
                const Padding(
                  padding: EdgeInsets.only(right: Space.m),
                  child: SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              Expanded(
                child: Text(
                  pairing.status,
                  style: T.small.copyWith(color: p.muted),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: Space.s),
      ActionButton(
        label: 'Pair band',
        icon: Icons.link_rounded,
        onPressed: ready ? _pair : null,
      ),
    ];
  }
}

/// A numbered step with a rail joining it to the next one.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.children,
    this.last = false,
  });

  final int number;
  final String title;
  final List<Widget> children;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Text(
                number.toString().padLeft(2, '0'),
                style: T.unit.copyWith(color: p.accent, fontSize: 13),
              ),
              const SizedBox(height: Space.s),
              Expanded(
                child: last
                    ? const SizedBox.shrink()
                    : Container(width: 1, color: p.line),
              ),
            ],
          ),
          const SizedBox(width: Space.l),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? Space.l : Space.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: T.heading),
                  const SizedBox(height: Space.m),
                  ...children,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _looksLikeWear(String name) {
  final n = name.toLowerCase();
  return n.contains('band') ||
      n.contains('watch') ||
      n.startsWith('xiaomi') ||
      n.startsWith('redmi');
}

/// What OpenWear can do with the model behind a Bluetooth name.
String? modelSupportLine(String bluetoothName) {
  final m = wearModelFor(bluetoothName: bluetoothName);
  if (m == null) return null;
  return switch (m.link) {
    BandLink.bleOnly => '${m.name} · Bluetooth LE only, not supported yet',
    _ when m.verified => '${m.name} · tested with OpenWear',
    _ => '${m.name} · should work, not tested yet',
  };
}

class _DeviceOption extends StatelessWidget {
  const _DeviceOption({
    required this.device,
    required this.selected,
    required this.onTap,
  });

  final BondedDevice device;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Panel(
      onTap: onTap,
      borderColor: selected ? p.accent : null,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.l,
        vertical: Space.m,
      ),
      child: Row(
        children: [
          Icon(Icons.watch_outlined, color: selected ? p.accent : p.muted),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, style: T.bodyStrong),
                if (modelSupportLine(device.name) case final line?)
                  Text(line, style: T.small.copyWith(color: p.muted)),
                Text(device.address, style: T.unit.copyWith(color: p.muted)),
              ],
            ),
          ),
          AnimatedOpacity(
            opacity: selected ? 1 : 0,
            duration: Motion.quick,
            child: Icon(Icons.check_rounded, color: p.accent),
          ),
        ],
      ),
    );
  }
}

/// A collapsible block for secondary tools.
class _Disclosure extends StatelessWidget {
  const _Disclosure({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: Space.l),
    title: Text(title, style: T.body),
    children: [child],
  );
}
