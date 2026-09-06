import 'package:flutter/material.dart';

/// Soul's card-based light workspace: neutral surfaces, crisp white cards,
/// black typography, and mint/aqua used as focused interaction signals.
class SanaColors {
  const SanaColors._();

  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color nearBlack = Color(0xFFF7F7F4);
  static const Color ink = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF0F0EC);
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  /// Primary brand signal: clean mint-teal.
  static const Color lavender = Color(0xFF58BFAE);
  static const Color lavenderSoft = Color(0xFFE4F5F2);
  static const Color lavenderDeep = Color(0xFF1F7468);

  static const Color aqua = Color(0xFFB8E4ED);
  static const Color mint = Color(0xFF7ED2BF);
  static const Color coral = Color(0xFFFFA35C);
  static const Color blush = Color(0xFFF5A4C8);

  static const Color fgPrimary = Color(0xFF1D1D1F);
  static const Color fgSecondary = Color(0xFF5F5F65);
  static const Color fgMuted = Color(0xFF898991);

  static const Color danger = Color(0xFFD9534F);
  static const Color success = Color(0xFF2E8B57);
  static const Color outline = Color(0x1F1D1D1F);
}

ThemeData buildSanaTheme() {
  const scheme = ColorScheme.light(
    primary: SanaColors.lavender,
    onPrimary: SanaColors.pureWhite,
    secondary: SanaColors.lavenderSoft,
    onSecondary: SanaColors.pureWhite,
    surface: SanaColors.pureWhite,
    onSurface: SanaColors.fgPrimary,
    onSurfaceVariant: SanaColors.fgSecondary,
    error: SanaColors.danger,
    onError: SanaColors.pureWhite,
    outline: SanaColors.fgMuted,
    surfaceContainerHighest: SanaColors.surfaceElevated,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: SanaColors.nearBlack,
    canvasColor: SanaColors.nearBlack,
    cardColor: SanaColors.pureWhite,
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
        letterSpacing: 0,
        color: SanaColors.fgPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
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
        letterSpacing: 0,
        color: SanaColors.fgPrimary,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: SanaColors.fgMuted,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SanaColors.surface,
      hintStyle: const TextStyle(color: SanaColors.fgMuted, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SanaColors.lavender,
        foregroundColor: SanaColors.pureWhite,
        disabledBackgroundColor: SanaColors.lavender.withValues(alpha: 0.35),
        disabledForegroundColor: SanaColors.pureWhite.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: SanaColors.pureWhite,
      elevation: 4,
      indicatorColor: SanaColors.lavender.withValues(alpha: 0.15),
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
