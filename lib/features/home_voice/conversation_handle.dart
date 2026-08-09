import 'package:flutter/material.dart';

import '../../core/design/sana_colors.dart';
import '../../core/design/sana_spacing.dart';

/// Minimal affordance: swipe/tap upward to reveal the shared transcript.
class ConversationHandle extends StatelessWidget {
  const ConversationHandle({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Reveal conversation transcript',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SanaRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SanaSpacing.lg,
            vertical: SanaSpacing.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 3,
                decoration: BoxDecoration(
                  color: SanaColors.lavender.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(SanaRadius.pill),
                ),
              ),
              const SizedBox(height: 2),
              Icon(
                Icons.keyboard_arrow_up_rounded,
                color: SanaColors.lavender.withValues(alpha: 0.9),
                size: 20,
              ),
              Text(
                'Conversation',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: SanaColors.lavender,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
