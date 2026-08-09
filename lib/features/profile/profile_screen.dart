import 'package:flutter/material.dart';

import '../../core/design/sana_colors.dart';
import '../../core/design/sana_spacing.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

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
                'Profile',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: SanaColors.textPrimary,
                ),
              ),
              const SizedBox(height: SanaSpacing.sm),
              Text(
                'Account, assistant name, and settings arrive with authentication.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
