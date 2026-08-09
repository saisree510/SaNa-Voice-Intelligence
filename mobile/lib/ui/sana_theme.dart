import 'package:flutter/material.dart';

/// Refinable Sana brand tokens (black + muted-lavender).
class SanaColors {
  const SanaColors._();

  static const Color nearBlack = Color(0xFF000000);
  static const Color ink = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF141414);
  static const Color surfaceElevated = Color(0xFF1C1C1C);

  /// Primary brand signal — muted, not neon.
  static const Color lavender = Color(0xFFB7A8D4);
  static const Color lavenderSoft = Color(0xFF9A8BB8);
  static const Color lavenderDeep = Color(0xFF7E6FA0);

  static const Color fgPrimary = Color(0xFFF2F0F7);
  static const Color fgSecondary = Color(0xFFC4BED6);
  static const Color fgMuted = Color(0xFF8E87A3);

  static const Color danger = Color(0xFFE08A7A);
  static const Color success = Color(0xFF7DB89A);
  static const Color outline = Color(0x33B7A8D4);
}

ThemeData buildSanaTheme() {
  const scheme = ColorScheme.dark(
    primary: SanaColors.lavender,
    onPrimary: SanaColors.nearBlack,
    secondary: SanaColors.lavenderSoft,
    onSecondary: SanaColors.nearBlack,
    surface: SanaColors.ink,
    onSurface: SanaColors.fgPrimary,
    onSurfaceVariant: SanaColors.fgSecondary,
    error: SanaColors.danger,
    onError: SanaColors.nearBlack,
    outline: SanaColors.fgMuted,
    surfaceContainerHighest: SanaColors.surfaceElevated,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: SanaColors.nearBlack,
    canvasColor: SanaColors.nearBlack,
    cardColor: SanaColors.surface,
    dividerColor: SanaColors.outline,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: SanaColors.fgPrimary,
      centerTitle: true,
    ),
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: SanaColors.fgPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: SanaColors.fgPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: SanaColors.fgPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: SanaColors.fgPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: SanaColors.fgPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: SanaColors.fgSecondary,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: SanaColors.fgMuted,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: SanaColors.fgPrimary,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: SanaColors.fgMuted,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SanaColors.surface,
      hintStyle: const TextStyle(color: SanaColors.fgMuted, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SanaColors.lavender,
        foregroundColor: SanaColors.nearBlack,
        disabledBackgroundColor: SanaColors.lavender.withValues(alpha: 0.35),
        disabledForegroundColor: SanaColors.nearBlack.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: SanaColors.ink.withValues(alpha: 0.92),
      indicatorColor: SanaColors.lavender.withValues(alpha: 0.22),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? SanaColors.lavender : SanaColors.fgMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 22,
          color: selected ? SanaColors.lavender : SanaColors.fgMuted,
        );
      }),
    ),
  );
}
