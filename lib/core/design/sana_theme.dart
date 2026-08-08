import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'sana_colors.dart';

abstract final class SanaTheme {
  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: SanaColors.deepNavy,
      colorScheme: const ColorScheme.dark(
        surface: SanaColors.deepNavy,
        primary: SanaColors.accentTeal,
        secondary: SanaColors.accentCyan,
        tertiary: SanaColors.accentIndigo,
        error: SanaColors.danger,
        onPrimary: SanaColors.voidBlack,
        onSecondary: SanaColors.voidBlack,
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
        titleLarge: display.titleLarge?.copyWith(
          color: SanaColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: body.titleMedium?.copyWith(
          color: SanaColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: body.bodyLarge?.copyWith(
          color: SanaColors.textPrimary,
          height: 1.45,
        ),
        bodyMedium: body.bodyMedium?.copyWith(
          color: SanaColors.textSecondary,
          height: 1.45,
        ),
        bodySmall: body.bodySmall?.copyWith(
          color: SanaColors.textMuted,
        ),
        labelLarge: body.labelLarge?.copyWith(
          color: SanaColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: display.titleLarge?.copyWith(
          color: SanaColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 22,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: SanaColors.panel.withValues(alpha: 0.92),
        indicatorColor: SanaColors.accentTeal.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return body.labelMedium?.copyWith(
            color: selected ? SanaColors.accentTeal : SanaColors.textMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? SanaColors.accentTeal : SanaColors.textMuted,
          );
        }),
      ),
      dividerColor: SanaColors.textMuted.withValues(alpha: 0.2),
    );
  }
}
