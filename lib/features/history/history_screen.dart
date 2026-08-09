import 'package:flutter/material.dart';

import '../../core/design/sana_colors.dart';
import '../../core/design/sana_spacing.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

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
                'History',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: SanaColors.textPrimary,
                ),
              ),
              const SizedBox(height: SanaSpacing.sm),
              Text(
                'Past conversations will appear here after persistence is wired.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
