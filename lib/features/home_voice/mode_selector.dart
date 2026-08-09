import 'package:flutter/material.dart';

import '../../core/design/sana_colors.dart';
import '../../core/design/sana_spacing.dart';
import 'home_providers.dart';

class ModeSelector extends StatelessWidget {
  const ModeSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final ConversationModePreview selected;
  final ValueChanged<ConversationModePreview> onSelected;

  @override
  Widget build(BuildContext context) {
    final modes = <(ConversationModePreview, String, IconData)>[
      (
        ConversationModePreview.debate,
        'Debate',
        Icons.chat_bubble_outline_rounded,
      ),
      (
        ConversationModePreview.brainstorm,
        'Brainstorm',
        Icons.lightbulb_outline_rounded,
      ),
      (ConversationModePreview.build, 'Build', Icons.code_rounded),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth < 360;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: tight ? 8 : 10,
          runSpacing: 8,
          children: [
            for (final mode in modes)
              ModePill(
                label: mode.$2,
                icon: mode.$3,
                selected: selected == mode.$1,
                compact: tight,
                onTap: () => onSelected(mode.$1),
              ),
          ],
        );
      },
    );
  }
}

class ModePill extends StatelessWidget {
  const ModePill({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label mode',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SanaRadius.pill),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 8 : 10,
            ),
            decoration: BoxDecoration(
              color: SanaColors.surface.withValues(
                alpha: selected ? 0.88 : 0.55,
              ),
              borderRadius: BorderRadius.circular(SanaRadius.pill),
              border: Border.all(
                color: SanaColors.lavender.withValues(
                  alpha: selected ? 0.55 : 0.28,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: compact ? 14 : 15,
                  color: selected
                      ? SanaColors.lavenderLight
                      : SanaColors.textPrimary,
                ),
                SizedBox(width: compact ? 6 : 7),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: SanaColors.textPrimary,
                    fontSize: compact ? 12.5 : 13.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
