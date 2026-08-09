import 'package:flutter/material.dart';

/// Refinable SaNa color tokens.
/// Primary identity: muted lavender on near-black (not cyan/teal).
abstract final class SanaColors {
  static const Color background = Color(0xFF080A12);
  static const Color backgroundDeep = Color(0xFF0C0E18);
  static const Color surface = Color(0xFF12141F);
  static const Color surfaceElevated = Color(0xFF181A28);

  static const Color lavender = Color(0xFFB88DE0);
  static const Color lavenderLight = Color(0xFFD5B5EE);
  static const Color violetDeep = Color(0xFF7656A6);
  static const Color glow = Color(0xFFA978D0);

  static const Color textPrimary = Color(0xFFF2EEF8);
  static const Color textSecondary = Color(0xFFB7ADC8);
  static const Color textMuted = Color(0xFF7E7593);
  static const Color border = Color(0x66B88DE0);

  static const Color danger = Color(0xFFE8A0A8);
  static const Color warning = Color(0xFFE8C98A);

  /// Near-black → deep navy, nearly invisible.
  static const LinearGradient atmosphere = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0C0E18), Color(0xFF080A12), Color(0xFF07080F)],
  );

  // Backward-compatible aliases used by shell/placeholders during transition.
  static const Color voidBlack = background;
  static const Color deepNavy = backgroundDeep;
  static const Color panel = surface;
  static const Color panelElevated = surfaceElevated;
  static const Color accentTeal = lavender;
  static const Color accentCyan = lavenderLight;
  static const Color accentIndigo = violetDeep;
  static const Color softGlow = Color(0x33A978D0);
}
