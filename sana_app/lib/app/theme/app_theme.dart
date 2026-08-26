import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

/// Builds SANA's light and dark [ThemeData].
///
/// Material 3, seeded from [AppColors.primary] so buttons, focus rings,
/// etc. derive automatically, with the neutral surface/text tokens
/// overridden to match SANA's palette exactly.
abstract final class AppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      surface: AppColors.surfaceLight,
      error: AppColors.error,
    );
    return _base(
      colorScheme: colorScheme,
      scaffoldBackground: AppColors.backgroundLight,
      textTheme: AppTextStyles.textTheme(
        AppColors.textPrimaryLight,
        AppColors.textSecondaryLight,
      ),
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      surface: AppColors.surfaceDark,
      error: AppColors.error,
    );
    return _base(
      colorScheme: colorScheme,
      scaffoldBackground: AppColors.backgroundDark,
      textTheme: AppTextStyles.textTheme(
        AppColors.textPrimaryDark,
        AppColors.textSecondaryDark,
      ),
    );
  }

  static ThemeData _base({
    required ColorScheme colorScheme,
    required Color scaffoldBackground,
    required TextTheme textTheme,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: textTheme.titleLarge?.color,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}
