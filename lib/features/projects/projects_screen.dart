import 'package:flutter/material.dart';

import '../../core/design/sana_colors.dart';
import '../../core/design/sana_spacing.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: SanaColors.atmosphere),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SanaSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Projects',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: SanaColors.textPrimary,
                ),
              ),
              const SizedBox(height: SanaSpacing.sm),
              Text(
                'Build projects will live here once Build Mode is connected.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
