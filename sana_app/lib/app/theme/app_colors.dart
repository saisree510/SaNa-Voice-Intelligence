import 'package:flutter/material.dart';

/// SANA's brand and semantic color tokens.
///
/// Kept as one place so every feature pulls from the same palette instead
/// of hard-coding hex values. [AppTheme] turns these into a Material 3
/// [ColorScheme]; features (mode cards, voice indicator, etc.) reference
/// the semantic colors below directly.
abstract final class AppColors {
  // Brand
  static const Color primary = Color(0xFF6C5CE7); // deep violet — AI feel
  static const Color primaryDark = Color(0xFF4834D4);

  // Neutrals
  static const Color backgroundLight = Color(0xFFF7F7FB);
  static const Color backgroundDark = Color(0xFF121017);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1C1A24);
  static const Color textPrimaryLight = Color(0xFF17151F);
  static const Color textPrimaryDark = Color(0xFFF2F1F7);
  static const Color textSecondaryLight = Color(0xFF6B6876);
  static const Color textSecondaryDark = Color(0xFFA6A3B0);

  // Mode identity colors — used for mode cards, chat bubbles, and
  // mode-specific accents in the conversation screen.
  static const Color debate = Color(0xFFE84855); // challenge — crimson
  static const Color brainstorm = Color(0xFFF9A826); // ideas — amber
  static const Color build = Color(0xFF3A86FF); // structure — blue

  // Voice state colors — used by the mic button / waveform indicator.
  static const Color voiceListening = Color(0xFF00C2A8); // teal
  static const Color voiceSpeaking = Color(0xFF6C5CE7); // brand violet
  static const Color voiceIdle = Color(0xFF9B98A6);

  static const Color error = Color(0xFFE84855);
  static const Color success = Color(0xFF2ECC71);
}
