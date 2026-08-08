import 'package:flutter/material.dart';

/// Refinable SaNa color tokens (dark-first, calm blue/teal).
abstract final class SanaColors {
  static const Color voidBlack = Color(0xFF070B14);
  static const Color deepNavy = Color(0xFF0B1220);
  static const Color panel = Color(0xFF121A2B);
  static const Color panelElevated = Color(0xFF182338);

  static const Color textPrimary = Color(0xFFE8EEF8);
  static const Color textSecondary = Color(0xFF9AADC4);
  static const Color textMuted = Color(0xFF6B7F96);

  static const Color accentTeal = Color(0xFF2EC4B6);
  static const Color accentCyan = Color(0xFF5CC8FF);
  static const Color accentIndigo = Color(0xFF6B8CFF);
  static const Color softGlow = Color(0x662EC4B6);

  static const Color danger = Color(0xFFFF6B7A);
  static const Color warning = Color(0xFFFFC857);

  static const LinearGradient atmosphere = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF0B1220),
      Color(0xFF101A2E),
      Color(0xFF0A1624),
      Color(0xFF071018),
    ],
    stops: [0.0, 0.35, 0.7, 1.0],
  );

  static const LinearGradient orbCore = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF6B8CFF),
      Color(0xFF2EC4B6),
      Color(0xFF5CC8FF),
    ],
  );
}
