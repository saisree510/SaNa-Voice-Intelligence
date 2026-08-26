import 'package:flutter/material.dart';

/// Base text theme for SANA.
///
/// Uses the platform system font (no bundled/network font in V1 — keeps
/// the project buildable offline). If a brand typeface is added later,
/// only this file needs to change.
abstract final class AppTextStyles {
  static TextTheme textTheme(Color primaryText, Color secondaryText) {
    return TextTheme(
      displaySmall: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: primaryText,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: primaryText,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: primaryText,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: primaryText,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: primaryText,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: secondaryText,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: primaryText,
      ),
    );
  }
}
