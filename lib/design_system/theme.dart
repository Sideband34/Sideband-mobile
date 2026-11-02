import 'package:flutter/material.dart';

/// Brand colours from `brand/tokens.json`. UI direction is flexible; the logo
/// and palette are approved.
abstract final class SidebandColors {
  static const primary = Color(0xFFFF8B24);
  static const accent = Color(0xFFFFB56D);
  static const ink = Color(0xFF130B12);
  static const cream = Color(0xFFFCF7EF);

  // Derived surfaces.
  static const darkSurface = Color(0xFF1E131D);
  static const darkSurfaceHigh = Color(0xFF281A26);
  static const darkOutline = Color(0xFF4A3A47);
  static const lightSurfaceHigh = Color(0xFFF5ECDF);
  static const lightOutline = Color(0xFFE2D5C6);

  /// Orange that keeps AA contrast as text on light surfaces.
  static const primaryOnLight = Color(0xFFA34700);
}

ThemeData sidebandTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? SidebandColors.primary : SidebandColors.primaryOnLight,
    onPrimary: dark ? SidebandColors.ink : Colors.white,
    primaryContainer: dark ? const Color(0xFF3A2112) : const Color(0xFFFFE3CC),
    onPrimaryContainer: dark ? SidebandColors.accent : const Color(0xFF5A2600),
    secondary: SidebandColors.accent,
    onSecondary: SidebandColors.ink,
    error: dark ? const Color(0xFFFF8A80) : const Color(0xFFB3261E),
    onError: dark ? SidebandColors.ink : Colors.white,
    surface: dark ? SidebandColors.ink : SidebandColors.cream,
    onSurface: dark ? SidebandColors.cream : SidebandColors.ink,
    onSurfaceVariant: dark ? const Color(0xFFC7B8AD) : const Color(0xFF5B4A58),
    surfaceContainerLowest: dark ? const Color(0xFF0E080D) : Colors.white,
    surfaceContainerLow: dark ? const Color(0xFF180F17) : Colors.white,
    surfaceContainer: dark ? SidebandColors.darkSurface : Colors.white,
    surfaceContainerHigh:
        dark ? SidebandColors.darkSurfaceHigh : SidebandColors.lightSurfaceHigh,
    surfaceContainerHighest:
        dark ? const Color(0xFF33222F) : const Color(0xFFEFE3D3),
    outline: dark ? SidebandColors.darkOutline : SidebandColors.lightOutline,
    outlineVariant: dark ? const Color(0xFF33242F) : const Color(0xFFEDE3D7),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
  );
  final text = base.textTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    textTheme: text.copyWith(
      headlineSmall: text.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SidebandColors.primary,
        foregroundColor: SidebandColors.ink,
        disabledBackgroundColor: scheme.surfaceContainerHighest,
        minimumSize: const Size(64, 48),
        shape: shape,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        minimumSize: const Size(64, 48),
        side: BorderSide(color: scheme.outline),
        shape: shape,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SidebandColors.primary, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          )),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
  );
}
