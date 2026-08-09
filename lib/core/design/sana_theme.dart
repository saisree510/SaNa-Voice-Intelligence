import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'sana_colors.dart';

abstract final class SanaTheme {
  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: SanaColors.background,
      colorScheme: const ColorScheme.dark(
        surface: SanaColors.background,
        primary: SanaColors.lavender,
        secondary: SanaColors.lavenderLight,
        tertiary: SanaColors.violetDeep,
        error: SanaColors.danger,
        onPrimary: SanaColors.background,
        onSecondary: SanaColors.background,
        onSurface: SanaColors.textPrimary,
      ),
    );

    final display = GoogleFonts.soraTextTheme(base.textTheme);
    final body = GoogleFonts.ibmPlexSansTextTheme(base.textTheme);

    return base.copyWith(
      textTheme: display.copyWith(
        displayLarge: display.displayLarge?.copyWith(
          color: SanaColors.textPrimary,
          fontWeight: FontWeight.w600,
          letterSpacing: -1.2,
        ),
        displayMedium: display.displayMedium?.copyWith(
          color: SanaColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        headlineMedium: display.headlineMedium?.copyWith(
          color: SanaColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        headlineSmall: display.headlineSmall?.copyWith(
          color: SanaColors.textPrimary,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        titleLarge: display.titleLarge?.copyWith(
          color: SanaColors.lavender,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: body.titleMedium?.copyWith(
          color: SanaColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: body.bodyLarge?.copyWith(
          color: SanaColors.textPrimary,
          height: 1.4,
        ),
        bodyMedium: body.bodyMedium?.copyWith(
          color: SanaColors.textSecondary,
          height: 1.4,
        ),
        bodySmall: body.bodySmall?.copyWith(color: SanaColors.textMuted),
        labelLarge: body.labelLarge?.copyWith(
          color: SanaColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        labelMedium: body.labelMedium?.copyWith(
          color: SanaColors.textMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: SanaColors.background,
        elevation: 0,
        height: 64,
        indicatorColor: Colors.transparent,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return body.labelMedium?.copyWith(
            color: selected ? SanaColors.lavender : SanaColors.textMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 12,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? SanaColors.lavender : SanaColors.textMuted,
            size: 22,
          );
        }),
      ),
      dividerColor: SanaColors.border.withValues(alpha: 0.2),
    );
  }
}
