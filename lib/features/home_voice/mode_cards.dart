import 'package:flutter/material.dart';

import '../../core/design/sana_colors.dart';
import '../../core/design/sana_spacing.dart';
import 'home_providers.dart';

class ModeCards extends StatelessWidget {
  const ModeCards({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final ConversationModePreview selected;
  final ValueChanged<ConversationModePreview> onSelected;

  @override
  Widget build(BuildContext context) {
    final modes = [
      (
        ConversationModePreview.debate,
        'Debate',
        'Challenge ideas and sharpen reasoning',
        Icons.balance_rounded,
      ),
      (
        ConversationModePreview.brainstorm,
        'Brainstorm',
        'Explore and shape product ideas',
        Icons.auto_awesome_rounded,
      ),
      (
        ConversationModePreview.build,
        'Build',
        'Plan software — execution needs approval',
        Icons.handyman_rounded,
      ),
    ];

    return Column(
      children: [
        for (final mode in modes) ...[
          _ModeTile(
            title: mode.$2,
            subtitle: mode.$3,
            icon: mode.$4,
            selected: selected == mode.$1,
            onTap: () => onSelected(mode.$1),
          ),
          const SizedBox(height: SanaSpacing.sm),
        ],
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: selected
                ? SanaColors.panelElevated
                : SanaColors.panel.withValues(alpha: 0.72),
            border: Border.all(
              color: selected
                  ? SanaColors.accentTeal.withValues(alpha: 0.55)
                  : SanaColors.textMuted.withValues(alpha: 0.18),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: SanaSpacing.md,
            vertical: 14,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? SanaColors.accentTeal : SanaColors.textSecondary,
              ),
              const SizedBox(width: SanaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: SanaColors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
