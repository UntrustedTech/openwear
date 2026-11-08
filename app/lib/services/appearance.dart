/// How the app looks: light/dark, accent colour, pure black, motion and
/// which cards the Today tab shows. Saved on the phone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Accent colours, each tuned for dark (ink) and light (paper) surfaces.
enum Accent {
  signal('Signal', Color(0xFFFF5B1F), Color(0xFFEC4E12)),
  volt('Volt', Color(0xFFC6EE4A), Color(0xFF5E8A00)),
  glacier('Glacier', Color(0xFF4FA8FF), Color(0xFF1F6FD1)),
  ultraviolet('Ultraviolet', Color(0xFF9C7BFF), Color(0xFF6A47E0)),
  rose('Rose', Color(0xFFFF5C8A), Color(0xFFD6336B)),
  mint('Mint', Color(0xFF3DDC97), Color(0xFF12985E));

  const Accent(this.label, this.dark, this.light);
  final String label;
  final Color dark;
  final Color light;
}

/// Cards the Today tab can show, in order.
enum TodayCard {
  band('Band'),
  goals('Today’s goals'),
  heart('Heart rate'),
  sleep('Sleep'),
  vitals('Vitals tiles'),
  weather('Weather');

  const TodayCard(this.label);
  final String label;
}

class Appearance extends ChangeNotifier {
  Appearance({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  ThemeMode mode = ThemeMode.system;
  Accent accent = Accent.signal;

  /// True black backgrounds in dark mode (saves power on OLED screens).
  bool pureBlack = false;

  /// Skip entrance animations entirely.
  bool reduceMotion = false;

  /// Today cards that are switched off.
  Set<TodayCard> hidden = {};

  bool shows(TodayCard c) => !hidden.contains(c);

  static const _kMode = 'look.mode',
      _kAccent = 'look.accent',
      _kBlack = 'look.black',
      _kMotion = 'look.motion',
      _kHidden = 'look.hidden';

  Future<void> load() async {
    try {
      final m = await _storage.read(key: _kMode);
      final a = await _storage.read(key: _kAccent);
      mode = ThemeMode.values.where((x) => x.name == m).firstOrNull ?? mode;
      accent = Accent.values.where((x) => x.name == a).firstOrNull ?? accent;
      pureBlack = await _storage.read(key: _kBlack) == 'true';
      reduceMotion = await _storage.read(key: _kMotion) == 'true';
      final h = await _storage.read(key: _kHidden) ?? '';
      hidden = {
        for (final c in TodayCard.values)
          if (h.split(',').contains(c.name)) c,
      };
    } on Exception {
      // Defaults stay; storage can be unavailable in tests.
    }
    notifyListeners();
  }

  Future<void> _save(String key, String value) async {
    notifyListeners();
    try {
      await _storage.write(key: key, value: value);
    } on Exception {
      // Not saved; the choice still applies until the app restarts.
    }
  }

  Future<void> setMode(ThemeMode m) {
    mode = m;
    return _save(_kMode, m.name);
  }

  Future<void> setAccent(Accent a) {
    accent = a;
    return _save(_kAccent, a.name);
  }

  Future<void> setPureBlack(bool on) {
    pureBlack = on;
    return _save(_kBlack, '$on');
  }

  Future<void> setReduceMotion(bool on) {
    reduceMotion = on;
    return _save(_kMotion, '$on');
  }

  Future<void> setShown(TodayCard c, bool on) {
    hidden = on ? ({...hidden}..remove(c)) : {...hidden, c};
    return _save(_kHidden, hidden.map((x) => x.name).join(','));
  }
}
