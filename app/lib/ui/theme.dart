/// OpenWear's visual language, "Signal": a precision-instrument look.
///
/// * Flat, warm surfaces (ink black in dark mode, paper in light) separated by
///   hairlines, never by blur or drop shadows.
/// * One brand accent, signal orange, used sparingly for the primary action
///   and live state. Each health metric has its own colour for its data.
/// * Two bundled typefaces: Space Grotesk for words and numbers, JetBrains
///   Mono for small uppercase labels, units and timestamps.
library;

import 'package:flutter/material.dart';

/// Display and text face (SIL OFL, bundled in assets/fonts).
const String fontFamily = 'SpaceGrotesk';

/// Label, unit and timestamp face (SIL OFL, bundled in assets/fonts).
const String monoFamily = 'JetBrainsMono';

/// Data colours, one per metric. Tuned for the dark ink background;
/// [Palette.tone] deepens them for text on paper in light mode.
abstract final class Metric {
  static const heart = Color(0xFFFF4D5E);
  static const energy = Color(0xFFFF8A3D);
  static const steps = Color(0xFFC6EE4A);
  static const stand = Color(0xFF4FC9F0);
  static const oxygen = Color(0xFF6E9BFF);
  static const stress = Color(0xFFB59CFF);
  static const sleep = Color(0xFF8C7BFF);
  static const weather = Color(0xFFF5C445);
  static const battery = Color(0xFF52D17C);
}

/// Spacing scale (4 pt base).
abstract final class Space {
  static const xs = 4.0, s = 8.0, m = 12.0, l = 16.0, xl = 24.0, xxl = 32.0;

  /// Side margin of every page.
  static const gutter = 20.0;
}

/// Corner radii.
abstract final class Radii {
  static const card = 16.0;
  static const control = 12.0;
  static const small = 6.0;
}

/// Minimum touch target.
const minTarget = 48.0;

/// Motion: quick, decelerating, no overshoot.
abstract final class Motion {
  static const ease = Cubic(0.2, 0, 0, 1);
  static const quick = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);

  /// Delay between consecutive items appearing.
  static const stagger = Duration(milliseconds: 25);

  /// Entrance animations only play this soon after a page opens; cards
  /// rebuilt later (scrolled back into view) appear at once.
  static const entranceWindow = Duration(milliseconds: 450);
}

/// Surface and text colours for one brightness.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.dark,
    required this.background,
    required this.surface,
    required this.raised,
    required this.line,
    required this.text,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.ok,
  });

  static const night = Palette(
    dark: true,
    background: Color(0xFF0C0C0E),
    surface: Color(0xFF151518),
    raised: Color(0xFF1E1E22),
    line: Color(0xFF29292E),
    text: Color(0xFFF2F0E9),
    muted: Color(0xFF99978F),
    faint: Color(0xFF5B5A55),
    accent: Color(0xFFFF5B1F),
    onAccent: Color(0xFF0C0C0E),
    danger: Color(0xFFFF4D5E),
    ok: Color(0xFF52D17C),
  );

  static const day = Palette(
    dark: false,
    background: Color(0xFFF1EFEA),
    surface: Color(0xFFFCFBF8),
    raised: Color(0xFFE8E5DE),
    line: Color(0xFFDAD6CC),
    text: Color(0xFF151514),
    muted: Color(0xFF6B6963),
    faint: Color(0xFFA8A59C),
    accent: Color(0xFFEC4E12),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFD92D43),
    ok: Color(0xFF178F4A),
  );

  final bool dark;
  final Color background, surface, raised, line;
  final Color text, muted, faint;
  final Color accent, onAccent, danger, ok;

  static Palette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<Palette>() ??
        (theme.brightness == Brightness.dark ? night : day);
  }

  /// A metric colour made readable as text on this palette's surfaces.
  Color tone(Color c) =>
      dark ? c : Color.lerp(c, const Color(0xFF000000), 0.38) ?? c;

  /// This palette with another accent (and text on it), and optionally
  /// true-black surfaces in dark mode.
  Palette styled({Color? accent, bool pureBlack = false}) {
    final a = accent ?? this.accent;
    final lightAccent = a.computeLuminance() > 0.45;
    final black = pureBlack && dark;
    return Palette(
      dark: dark,
      background: black ? const Color(0xFF000000) : background,
      surface: black ? const Color(0xFF0B0B0D) : surface,
      raised: black ? const Color(0xFF17171A) : raised,
      line: black ? const Color(0xFF222226) : line,
      text: text,
      muted: muted,
      faint: faint,
      accent: a,
      onAccent: accent == null
          ? onAccent
          : lightAccent
          ? const Color(0xFF0C0C0E)
          : const Color(0xFFFFFFFF),
      danger: danger,
      ok: ok,
    );
  }

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

/// Type scale.
abstract final class T {
  static TextStyle _sans(
    double size,
    FontWeight w,
    double tracking,
    double h,
  ) => TextStyle(
    fontFamily: fontFamily,
    fontSize: size,
    fontWeight: w,
    letterSpacing: tracking,
    height: h,
  );

  static final title = _sans(32, FontWeight.w500, -1.0, 1.1);
  static final heading = _sans(20, FontWeight.w500, -0.4, 1.2);
  static final body = _sans(15, FontWeight.w400, -0.1, 1.45);
  static final bodyStrong = _sans(15, FontWeight.w500, -0.1, 1.45);
  static final small = _sans(13, FontWeight.w400, 0, 1.4);

  /// Uppercase micro-label.
  static const label = TextStyle(
    fontFamily: monoFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.1,
    height: 1.3,
  );

  /// Units next to numbers, timestamps.
  static const unit = TextStyle(
    fontFamily: monoFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
    height: 1.2,
  );

  /// Numeric readout at [size]: tabular figures, tight tracking.
  static TextStyle numeral(double size) => TextStyle(
    fontFamily: fontFamily,
    fontSize: size,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.045 * size,
    height: 1.0,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

// Shorthands for painters that only have a BuildContext.
Color secondaryLabel(BuildContext c) => Palette.of(c).muted;
Color tertiaryLabel(BuildContext c) => Palette.of(c).faint;
Color separator(BuildContext c) => Palette.of(c).line;

/// [color] as a text or line colour in the current brightness.
Color sys(BuildContext context, Color color) => Palette.of(context).tone(color);

/// Whether entrance animations are switched off (Appearance → Reduce motion).
bool reduceMotion = false;

ThemeData openWearTheme(
  Brightness brightness, {
  Color? accent,
  bool pureBlack = false,
}) {
  final base = brightness == Brightness.dark ? Palette.night : Palette.day;
  final p = accent == null && !pureBlack
      ? base
      : base.styled(accent: accent, pureBlack: pureBlack);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.text,
    onSecondary: p.background,
    error: p.danger,
    onError: p.onAccent,
    surface: p.background,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    surfaceContainerLowest: p.background,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.raised,
    surfaceContainerHighest: p.raised,
    outline: p.faint,
    outlineVariant: p.line,
  );
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Radii.control),
  );
  OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.control),
    borderSide: BorderSide(color: c, width: w),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: fontFamily,
    extensions: [p],
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    dividerColor: p.line,
    splashFactory: NoSplash.splashFactory,
    highlightColor: p.text.withValues(alpha: 0.04),
    textTheme: TextTheme(
      bodyLarge: T.body,
      bodyMedium: T.body,
      bodySmall: T.small,
      titleLarge: T.heading,
      titleMedium: T.bodyStrong,
      labelLarge: T.bodyStrong,
      labelMedium: T.label,
    ).apply(bodyColor: p.text, displayColor: p.text),
    iconTheme: IconThemeData(color: p.text, size: 22),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: T.bodyStrong.copyWith(color: p.text, fontSize: 17),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.onAccent : p.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.raised,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.line,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        minimumSize: const Size.fromHeight(52),
        shape: controlShape,
        textStyle: T.bodyStrong,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        minimumSize: const Size(0, minTarget),
        side: BorderSide(color: p.line),
        shape: controlShape,
        textStyle: T.bodyStrong,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
        textStyle: T.bodyStrong,
        shape: controlShape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      labelStyle: T.body.copyWith(color: p.muted),
      floatingLabelStyle: T.label.copyWith(color: p.accent),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: field(p.line),
      enabledBorder: field(p.line),
      focusedBorder: field(p.accent, 1.5),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      modalBackgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.faint,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.line),
      ),
      titleTextStyle: T.heading.copyWith(color: p.text),
      contentTextStyle: T.body.copyWith(color: p.muted),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.text,
      contentTextStyle: T.body.copyWith(color: p.background),
      behavior: SnackBarBehavior.floating,
      shape: controlShape,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.text,
      side: BorderSide(color: p.line),
      labelStyle: T.label.copyWith(color: p.text),
      secondaryLabelStyle: T.label.copyWith(color: p.background),
      checkmarkColor: p.background,
      shape: const StadiumBorder(),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.faint,
      ),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: p.muted,
      collapsedIconColor: p.muted,
      textColor: p.text,
      collapsedTextColor: p.text,
      shape: const Border(),
      collapsedShape: const Border(),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}
