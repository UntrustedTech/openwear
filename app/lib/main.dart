import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openwear/cloud/http_backend.dart';
import 'package:openwear/platform/android_bridge.dart';
import 'package:openwear/services/band_log.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/services/appearance.dart';
import 'package:openwear/ui/home_screen.dart';
import 'package:openwear/ui/pair_screen.dart';
import 'package:openwear/ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) httpBackend = AndroidHttpBackend();
  _registerFontLicenses();
  final band = BandService();
  unawaited(band.load().then((_) => band.autoConnect()));
  _logCrashes(band.log);
  unawaited(_describeSession(band.log));
  // Access changed in Android or Health Connect settings shows up on return.
  _lifecycle = AppLifecycleListener(
    onResume: () => unawaited(band.refreshHealthConnect()),
  );
  runApp(OpenWearApp(band: band));
}

// Kept for the app's lifetime.
// ignore: unused_element
AppLifecycleListener? _lifecycle;

/// Bundled fonts (SIL OFL, DejaVu/Bitstream Vera) and ported code (MIT)
/// in the licence page.
void _registerFontLicenses() {
  for (final (family, file) in [
    ('Space Grotesk', 'assets/fonts/OFL-SpaceGrotesk.txt'),
    ('JetBrains Mono', 'assets/fonts/OFL-JetBrainsMono.txt'),
    ('Noto Serif', 'assets/fonts/OFL-NotoSerif.txt'),
    ('DejaVu Sans Condensed', 'assets/fonts/LICENSE-DejaVu.txt'),
    (
      'band10-toolkit (watch-face format)',
      'assets/licenses/MIT-band10-toolkit.txt',
    ),
  ]) {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString(file));
    });
  }
}

/// Uncaught errors go to the live log so they show up in shared reports.
void _logCrashes(BandLog log) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    log.error('UI error', details.exception, details.stack);
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log.error('Uncaught error', error, stack);
    return true;
  };
}

Future<void> _describeSession(BandLog log) async {
  try {
    log.sessionInfo.addAll(await deviceInfo());
  } on PlatformException catch (e) {
    log.warn('Could not read phone info: ${e.message}');
  }
  log.sessionInfo['time zone'] = DateTime.now().timeZoneName;
  log.app(
    'App started',
    detail: log.sessionInfo.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n'),
  );
}

class OpenWearApp extends StatelessWidget {
  const OpenWearApp({super.key, required this.band});
  final BandService band;

  @override
  Widget build(BuildContext context) {
    final look = band.appearance;
    return ListenableBuilder(
      listenable: look,
      builder: (context, _) {
        reduceMotion = look.reduceMotion;
        final accent = look.accent == Accent.signal ? null : look.accent;
        return MaterialApp(
          title: 'OpenWear',
          debugShowCheckedModeBanner: false,
          themeMode: look.mode,
          themeAnimationDuration: Motion.base,
          theme: openWearTheme(Brightness.light, accent: accent?.light),
          darkTheme: openWearTheme(
            Brightness.dark,
            accent: accent?.dark,
            pureBlack: look.pureBlack,
          ),
          home: ListenableBuilder(
            listenable: band,
            builder: (context, _) => band.state == BandState.notPaired
                ? PairScreen(band: band)
                : HomeScreen(band: band),
          ),
        );
      },
    );
  }
}
