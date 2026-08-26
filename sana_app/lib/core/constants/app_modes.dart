import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Metadata for one of SANA's three conversation modes.
///
/// [id] is also the `:mode` route parameter and — starting in Phase 8+ —
/// the key used to pick which system prompt/brain the backend applies.
/// One definition shared by the Home mode cards and the conversation
/// screen keeps them from drifting out of sync.
class AppMode {
  const AppMode({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

abstract final class AppModes {
  static const debate = AppMode(
    id: 'debate',
    title: 'Debate',
    subtitle: 'Challenge your thinking',
    icon: Icons.balance_rounded,
    color: AppColors.debate,
  );

  static const brainstorm = AppMode(
    id: 'brainstorm',
    title: 'Brainstorm',
    subtitle: 'Explore ideas with SANA',
    icon: Icons.lightbulb_rounded,
    color: AppColors.brainstorm,
  );

  static const build = AppMode(
    id: 'build',
    title: 'Build',
    subtitle: 'Turn ideas into projects',
    icon: Icons.build_rounded,
    color: AppColors.build,
  );

  static const List<AppMode> all = [debate, brainstorm, build];

  static AppMode? byId(String id) {
    for (final mode in all) {
      if (mode.id == id) return mode;
    }
    return null;
  }
}
