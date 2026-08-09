import 'package:flutter/material.dart';

import '../../core/design/sana_colors.dart';
import '../../core/design/sana_spacing.dart';

class GreetingSection extends StatelessWidget {
  const GreetingSection({super.key, required this.userName});

  /// Display name from profile later; mock data is fine for this UI phase.
  final String userName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'SaNa',
              style: textTheme.titleLarge?.copyWith(
                color: SanaColors.lavender,
                fontWeight: FontWeight.w600,
                fontSize: 22,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SanaColors.surface.withValues(alpha: 0.7),
                border: Border.all(
                  color: SanaColors.border.withValues(alpha: 0.35),
                ),
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 16,
                color: SanaColors.lavender,
              ),
            ),
          ],
        ),
        const SizedBox(height: SanaSpacing.lg),
        Text(
          'Hey $userName,',
          style: textTheme.headlineSmall?.copyWith(
            color: SanaColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 28,
            height: 1.15,
          ),
        ),
        const SizedBox(height: SanaSpacing.xs),
        Text(
          'what are we working on today?',
          style: textTheme.bodyLarge?.copyWith(
            color: SanaColors.textSecondary,
            fontWeight: FontWeight.w400,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}
